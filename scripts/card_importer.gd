# card_importer.gd
#
# Turns the card spreadsheet (data/cards.csv) into card files (cards/*.tres).
#
# You don't run this file directly. Run tools/import_cards.gd from the Godot
# editor instead (see the instructions at the top of that file).
#
# How it works:
#   1. Read the CSV one row at a time. Row 1 holds the column names.
#   2. For every other row, make a new CardData and copy each column into it.
#   3. Save it as cards/<card_name>.tres (e.g. "Quick Strike" -> quick_strike.tres).
#   4. Delete any old .tres in cards/ that isn't in the sheet any more,
#      so the spreadsheet is always the one true list of cards.
class_name CardImporter
extends RefCounted

const CSV_PATH := "res://data/cards.csv"
const CARDS_FOLDER := "res://cards/"

# Card colour, picked from the card's first school.
const SCHOOL_COLORS := {
	CardData.School.STRENGTH: Color(0.6, 0.22, 0.22),
	CardData.School.AGILITY: Color(0.25, 0.5, 0.3),
	CardData.School.INTELLECT: Color(0.22, 0.35, 0.65),
	CardData.School.WISDOM: Color(0.5, 0.4, 0.65),
}
const NEUTRAL_COLOR := Color(0.4, 0.4, 0.42)


# Reads the CSV and writes the card files. Returns how many cards were made.
static func import_cards() -> int:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_error("Couldn't open %s" % CSV_PATH)
		return 0

	DirAccess.make_dir_recursive_absolute(CARDS_FOLDER)  # Make cards/ if it's missing.

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

		var card := CardData.new()
		card.card_name = card_name
		card.copies = _to_int(_cell(row, columns, "copies"), 1)
		card.cost = _to_int(_cell(row, columns, "cost"))
		card.schools = _parse_flags(_cell(row, columns, "school"), CardData.School)
		card.types = _parse_flags(_cell(row, columns, "type"), CardData.CardType)
		card.effect = _cell(row, columns, "description")
		card.damage = _to_int(_cell(row, columns, "attack"))
		card.block = _to_int(_cell(row, columns, "block"))
		card.draw = _to_int(_cell(row, columns, "draw"))
		card.discard = _to_int(_cell(row, columns, "discard"))
		card.heal = _to_int(_cell(row, columns, "heal"))
		card.draw_if_full_hp = _to_int(_cell(row, columns, "draw if full hp"))
		card.next_attack_bonus = _to_int(_cell(row, columns, "next attack bonus"))
		card.next_defense_bonus = _to_int(_cell(row, columns, "next defense bonus"))
		card.color = _pick_color(card.schools)

		var path := CARDS_FOLDER + _file_name_for(card_name)
		var error := ResourceSaver.save(card, path)
		if error != OK:
			push_error("Couldn't save %s (error %d)" % [path, error])
			continue
		made_files.append(path.get_file())
		print("Imported ", card_name, " -> ", path)

	_remove_old_cards(made_files)
	print("Done! Imported %d cards." % made_files.size())
	return made_files.size()


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
		if options.has(key):
			result |= options[key]  # |= means "turn this flag on".
		elif not key.is_empty():
			push_warning("Unknown value '%s' in the spreadsheet" % part)
	return result


static func _pick_color(schools: int) -> Color:
	for school in SCHOOL_COLORS:
		if schools & school:
			return SCHOOL_COLORS[school]
	return NEUTRAL_COLOR


# "Quick Strike" -> "quick_strike.tres"
static func _file_name_for(card_name: String) -> String:
	return card_name.to_lower().replace(" ", "_").validate_filename() + ".tres"


# Delete card files that are no longer in the spreadsheet.
static func _remove_old_cards(keep: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(CARDS_FOLDER):
		if file_name.ends_with(".tres") and not keep.has(file_name):
			DirAccess.remove_absolute(CARDS_FOLDER + file_name)
			# Godot also keeps a matching .uid file next to some files.
			if FileAccess.file_exists(CARDS_FOLDER + file_name + ".uid"):
				DirAccess.remove_absolute(CARDS_FOLDER + file_name + ".uid")
			print("Removed ", file_name, " (not in the spreadsheet)")
