# card_importer.gd
#
# Turns the card spreadsheets (data/*.csv) into Godot files.
#
# You don't run this file directly. Run tools/import_cards.gd from the Godot
# editor instead (see the instructions at the top of that file).
#
# There are up to four sheets. Only the first one is required:
#   data/cards.csv         Level 1 of every card -> cards/<name>.tres
#   data/cards_level2.csv  Level 2 versions      -> cards/levels/<name>_lv2.tres
#   data/cards_level3.csv  Level 3 versions      -> cards/levels/<name>_lv3.tres
#   data/class_cards.csv   Which card each class gets at each class level
#                          -> saved into classes/*.tres (level_cards)
#
# The level sheets have exactly the same columns as cards.csv (copy the whole
# sheet and change the numbers). A row's Name says which card it levels up.
# Leave a card out and its level 2 just plays like level 1.
#
# How a card sheet is read:
#   1. Read the CSV one row at a time. Row 1 holds the column names.
#   2. For every other row, make a new CardData and copy each column into it.
#   3. Save it as a .tres file (e.g. "Quick Strike" -> quick_strike.tres).
#   4. Delete any old .tres in that folder that isn't in the sheet any more,
#      so the spreadsheet is always the one true list of cards.
class_name CardImporter
extends RefCounted

const CSV_PATH := "res://data/cards.csv"
const CARDS_FOLDER := "res://cards/"
const LEVELS_FOLDER := "res://cards/levels/"
const LEVEL_SHEETS := {2: "res://data/cards_level2.csv", 3: "res://data/cards_level3.csv"}
const CLASS_CARDS_PATH := "res://data/class_cards.csv"
const CLASSES_FOLDER := "res://classes/"


# Reads every sheet and writes the files. Returns how many level 1 cards were made.
static func import_cards() -> int:
	var names := _import_sheet(CSV_PATH, CARDS_FOLDER, 1, [])
	if names.is_empty():
		return 0
	# Level sheets: same columns, saved next to each other in cards/levels/.
	var level_files: Array[String] = []
	for level in LEVEL_SHEETS:
		if FileAccess.file_exists(LEVEL_SHEETS[level]):
			for card_name in _import_sheet(LEVEL_SHEETS[level], LEVELS_FOLDER, level, names):
				level_files.append(level_file_name(card_name, level))
	_remove_old_cards(LEVELS_FOLDER, level_files)
	_import_class_cards(names)
	print("Done! Imported %d cards." % names.size())
	return names.size()


# The file name of a card's level 2 or 3 version: "Quick Strike", 2 -> "quick_strike_lv2.tres".
static func level_file_name(card_name: String, level: int) -> String:
	return _file_name_for(card_name).get_basename() + "_lv%d.tres" % level


# Read one card sheet and save a .tres for every row. `known_names` is the
# list of level 1 cards: a level sheet's rows must match one of them.
# Returns the names of the cards it made.
static func _import_sheet(csv_path: String, folder: String, level: int, known_names: Array[String]) -> Array[String]:
	var made_names: Array[String] = []
	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_error("Couldn't open %s" % csv_path)
		return made_names

	DirAccess.make_dir_recursive_absolute(folder)  # Make the folder if it's missing.

	# --- Row 1: the column names ---------------------------------------------
	# We remember which position each column is in, e.g. {"cost": 3, ...}.
	# That way the columns can be in any order in your spreadsheet.
	var columns := {}
	var header := file.get_csv_line()
	for i in header.size():
		columns[_clean_column_name(header[i])] = i

	# --- Every other row: one card -----------------------------------------
	var made_files: Array[String] = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		var card_name := _cell(row, columns, "name")
		if card_name.is_empty():
			continue  # Skip blank rows.
		if level > 1 and not known_names.has(card_name):
			push_warning("%s: there's no card called \"%s\" in cards.csv, skipped" % [csv_path.get_file(), card_name])
			continue

		var card := CardData.new()
		card.card_name = card_name
		card.level = level
		card.copies = _to_int(_cell(row, columns, "copies"), 1)
		card.cost = _to_int(_cell(row, columns, "cost"))
		card.schools = _parse_flags(_cell(row, columns, "school"), CardData.School)
		card.types = _parse_flags(_cell(row, columns, "type"), CardData.CardType)
		card.attack = _read_attacks(row, columns, card_name)
		card.attack_modifier = _to_int(_cell(row, columns, "attack modifier"))
		card.block = _read_formula_list(_cell(row, columns, "block"), card_name)
		card.block_modifier = _to_int(_cell(row, columns, "block modifier"))
		card.heal = _read_formula_list(_cell(row, columns, "heal"), card_name)
		card.heal_modifier = _to_int(_cell(row, columns, "heal modifier"))
		card.draw = _to_int(_cell(row, columns, "draw"))
		card.discard = _to_int(_cell(row, columns, "discard"))
		card.draw_if_full_hp = _to_int(_yes_no_as_number(_cell(row, columns, "draw if full hp")))
		var roll_bonus := _cell(row, columns, "next die roll bonus")
		if roll_bonus.is_empty():
			roll_bonus = _cell(row, columns, "next roll bonus")  # Either name works.
		card.next_roll_bonus = _read_formula(roll_bonus, card_name)  # "1" or dice like "d3".
		card.next_attack_bonus = _to_int(_cell(row, columns, "next attack bonus"))
		card.next_defense_bonus = _to_int(_cell(row, columns, "next defense bonus"))
		card.energy = _to_int(_cell(row, columns, "energy"))
		card.lose_hp = _to_int(_cell(row, columns, "lose hp"))
		# Wild can be a TRUE/FALSE "Wild" column, or a "Roll" column saying Play (Draw = normal).
		card.wild = _parse_yes_no(_cell(row, columns, "wild"), false) \
				or _cell(row, columns, "roll").to_lower() == "play"
		card.vanish = _parse_yes_no(_cell(row, columns, "vanish"), false)
		card.advantage = _parse_yes_no(_cell(row, columns, "advantage"), false)
		card.disadvantage = _parse_yes_no(_cell(row, columns, "disadvantage"), false)
		card.gain_advantage = _parse_yes_no(_cell(row, columns, "gain advantage"), false)
		card.reroll = _to_int(_cell(row, columns, "reroll"), _to_int(_cell(row, columns, "re-roll")))
		card.class_only = _parse_list(_cell(row, columns, "class"))
		card.rarity = _parse_rarity(_cell(row, columns, "rarity"))
		card.unlocked = _parse_yes_no(_cell(row, columns, "unlocked"), true)
		card.color = _pick_color(card.schools)
		var critical := _cell(row, columns, "critical effect")
		if critical.is_empty():
			critical = _cell(row, columns, "critical")  # The older name works too.
		card.critical = _read_critical(critical, card_name)
		# The Description is optional: a blank one is written for you from the numbers.
		card.effect = _cell(row, columns, "description")
		if card.effect.is_empty():
			card.effect = card.make_description()

		var path := folder + (_file_name_for(card_name) if level == 1 else level_file_name(card_name, level))
		var error := ResourceSaver.save(card, path)
		if error != OK:
			push_error("Couldn't save %s (error %d)" % [path, error])
			continue
		made_files.append(path.get_file())
		made_names.append(card_name)
		print("Imported ", card_name, " -> ", path)

	if level == 1:
		_remove_old_cards(folder, made_files)
	return made_names


# The class cards sheet: one row per card a class gets when it levels up.
#   Class   | Level | Card         | Copies
#   Knight  | 2     | Shield Bash  | 1
# Copies is optional (1 if blank). Each class's list is saved into its .tres
# file (CharacterClass.level_cards), so you can also see it in the Inspector.
static func _import_class_cards(known_names: Array[String]) -> void:
	var file := FileAccess.open(CLASS_CARDS_PATH, FileAccess.READ)
	if file == null:
		return  # The sheet is optional.
	var columns := {}
	var header := file.get_csv_line()
	for i in header.size():
		columns[_clean_column_name(header[i])] = i

	# Class name -> {level: ["Shield Bash", ...]}
	var by_class := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		var class_text := _cell(row, columns, "class")
		var card_name := _cell(row, columns, "card")
		if class_text.is_empty() or card_name.is_empty():
			continue
		if not known_names.has(card_name):
			push_warning("class_cards.csv: there's no card called \"%s\" in cards.csv, skipped" % card_name)
			continue
		var level := _to_int(_cell(row, columns, "level"), 1)
		if not by_class.has(class_text):
			by_class[class_text] = {}
		if not by_class[class_text].has(level):
			by_class[class_text][level] = PackedStringArray()
		# Two copies = the name twice in the list.
		for i in maxi(_to_int(_cell(row, columns, "copies"), 1), 1):
			by_class[class_text][level].append(card_name)

	# Write each class's list into its file. A class missing from the sheet
	# gets an empty list.
	for file_name in DirAccess.get_files_at(CLASSES_FOLDER):
		if not file_name.ends_with(".tres"):
			continue
		var character_class: CharacterClass = load(CLASSES_FOLDER + file_name)
		character_class.level_cards.clear()
		for level in by_class.get(character_class.display_name, {}):
			character_class.level_cards[level] = by_class[character_class.display_name][level]
		ResourceSaver.save(character_class)
		print("Class cards for ", character_class.display_name, ": ", character_class.level_cards)


# Get one cell from a row by its column name, e.g. _cell(row, columns, "cost").
static func _cell(row: PackedStringArray, columns: Dictionary, column: String) -> String:
	if not columns.has(column) or columns[column] >= row.size():
		return ""  # Column missing from the sheet: treat it as blank.
	return row[columns[column]].strip_edges()


# "School · Card School" -> "school",  "NAME" -> "name"
# (Some spreadsheet apps add " · something" to column names, so we cut that off.)
static func _clean_column_name(column_name: String) -> String:
	column_name = column_name.replace("﻿", "")  # Invisible marker some apps add.
	return column_name.get_slice("·", 0).strip_edges().to_lower()


# The Attack column, plus Attack (2), Attack (3)... for extra hits, plus an
# optional Hits column that repeats the attack. Each entry is one hit.
#   Attack "d3, d3"               -> ["d3", "d3"]   (a comma between hits)
#   Attack "d3", Attack (2) "d3"  -> ["d3", "d3"]
#   Attack "d3", Hits 3           -> ["d3", "d3", "d3"]
static func _read_attacks(row: PackedStringArray, columns: Dictionary, card_name: String) -> PackedStringArray:
	var hits := PackedStringArray()
	for part in _cell(row, columns, "attack").split(",", false):
		var hit := _read_formula(part, card_name)
		if not hit.is_empty():
			hits.append(hit)
	var first: String = hits[0] if not hits.is_empty() else ""
	for number in range(2, 10):
		var extra := _read_formula(_cell(row, columns, "attack (%d)" % number), card_name)
		if not extra.is_empty():
			hits.append(extra)
	var repeat := _to_int(_cell(row, columns, "hits"), 1)
	if repeat > 1 and hits.size() == 1:
		for i in repeat - 1:
			hits.append(first)
	return hits


# A cell that can hold a number or dice ("6", "d3", "2d6+1").
# 0 and blank both mean "nothing", so they give "".
static func _read_formula(text: String, card_name: String) -> String:
	text = text.strip_edges().replace(" ", "")
	if text.is_empty() or text == "0" or text == "-":
		return ""
	if not Dice.is_valid(text):
		push_warning("%s: can't read '%s' (use a number or dice like d6+2)" % [card_name, text])
		return ""
	return text


# Block and Heal are ONE roll, so a list like "d3, d3" is added up into "2d3".
# (Different dice, like "d3, d6", can't be one roll yet: we keep the first.)
static func _read_formula_list(text: String, card_name: String) -> String:
	var parts := PackedStringArray()
	for part in text.split(",", false):
		var formula := _read_formula(part, card_name)
		if not formula.is_empty():
			parts.append(formula)
	if parts.size() <= 1:
		return parts[0] if not parts.is_empty() else ""
	var first := Dice.parse(parts[0])
	var count := 0
	for part in parts:
		var dice := Dice.parse(part)
		if dice.sides != first.sides or dice.bonus != 0 or first.sides == 0:
			push_warning("%s: can't add '%s' together, using %s" % [card_name, text, parts[0]])
			return parts[0]
		count += dice.count
	return "%dd%d" % [count, first.sides]


# Keeps the Critical text, but warns about parts the game can't understand.
# "-" or blank means no critical.
static func _read_critical(text: String, card_name: String) -> String:
	if text == "-" or text.is_empty():
		return ""
	var card := CardData.new()
	for part in text.split(",", false):
		card.critical = part
		if card.get_critical_effects().is_empty():
			push_warning("%s: Critical '%s' isn't understood. Try +1 Damage, +1 Block, +1 Heal, Draw 1, Gain 1 Energy, Gain Advantage or Dont Vanish" % [card_name, part.strip_edges()])
	return text


# TRUE -> "1", FALSE -> "0", anything else unchanged. For columns that
# used to hold a number but are now ticked like a checkbox.
static func _yes_no_as_number(text: String) -> String:
	match text.strip_edges().to_lower():
		"true", "yes":
			return "1"
		"false", "no":
			return "0"
	return text


# "6" -> 6. A blank cell gives `default` instead.
static func _to_int(text: String, default: int = 0) -> int:
	return text.to_int() if text.is_valid_int() else default


# "Strength, Wisdom" -> STRENGTH + WISDOM (as bit flags, see card_data.gd).
# Several values can be separated by commas, slashes, semicolons or "|".
# A blank cell means none (e.g. a Neutral card).
static func _parse_flags(text: String, options: Dictionary) -> int:
	var result := 0
	for separator in ["/", ";", "|"]:
		text = text.replace(separator, ",")
	for part in text.split(",", false):
		var key := part.strip_edges().to_upper()
		if key in ["NEUTRAL", "NONE"]:
			continue  # Neutral = no school ticked, same as a blank cell.
		if options.has(key):
			result |= options[key]  # |= means "turn this flag on".
		elif not key.is_empty():
			push_warning("Unknown value '%s' in the spreadsheet" % part)
	return result


# "Knight, Adventurer" -> ["Knight", "Adventurer"]. Blank -> [] (every class).
static func _parse_list(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for separator in ["/", ";", "|"]:
		text = text.replace(separator, ",")
	for part in text.split(",", false):
		if not part.strip_edges().is_empty():
			result.append(part.strip_edges())
	return result


# "Rare" -> Rarity.RARE. Blank means Common.
static func _parse_rarity(text: String) -> CardData.Rarity:
	var key := text.strip_edges().to_upper()
	if key.is_empty():
		return CardData.Rarity.COMMON
	if not CardData.Rarity.has(key):
		push_warning("Unknown rarity '%s', using Common" % text)
		return CardData.Rarity.COMMON
	return CardData.Rarity[key]


# "Yes" / "Y" / "True" / "1" -> true, "No" / "N" / "False" / "0" -> false.
# A blank cell gives `default` instead.
static func _parse_yes_no(text: String, default: bool) -> bool:
	var value := text.strip_edges().to_lower()
	if value in ["yes", "y", "true", "1"]:
		return true
	if value in ["no", "n", "false", "0"]:
		return false
	return default


static func _pick_color(schools: int) -> Color:
	# The card's colour comes from its first school (colours are in card_data.gd).
	for school in CardData.SCHOOL_COLORS:
		if schools & school:
			return CardData.SCHOOL_COLORS[school]
	return CardData.NEUTRAL_COLOR


# "Quick Strike" -> "quick_strike.tres"
static func _file_name_for(card_name: String) -> String:
	return card_name.to_lower().replace(" ", "_").validate_filename() + ".tres"


# Delete card files in `folder` that are no longer in the spreadsheet.
static func _remove_old_cards(folder: String, keep: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(folder):
		if file_name.ends_with(".tres") and not keep.has(file_name):
			DirAccess.remove_absolute(folder + file_name)
			# Godot also keeps a matching .uid file next to some files.
			if FileAccess.file_exists(folder + file_name + ".uid"):
				DirAccess.remove_absolute(folder + file_name + ".uid")
			print("Removed ", file_name, " (not in the spreadsheet)")
