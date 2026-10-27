# game_state.gd
#
# Data that has to survive when we switch from one scene to another.
#
# Normally, when you change scenes, Godot throws the old scene away along with
# all of its variables. So how does the battle know which deck you built?
#
# Answer: an AUTOLOAD. This script is listed under Project Settings > Globals >
# Autoload with the name "GameState". Godot creates it once when the game
# starts and keeps it alive the whole time, no matter which scene is showing.
# Any script can then reach it by that name, e.g. `GameState.deck`.
# (It's a bit like a Python module with variables in it that every file imports.)
extends Node

const CARDS_FOLDER := "res://cards/"  # Every card file in here is in the card pool.
const CLASSES_FOLDER := "res://classes/"  # Every class file in here is on the Character Select screen.
const AREAS_FOLDER := "res://areas/"  # Every area file in here is on the map.
const TALENTS_FOLDER := "res://talents/"  # talents/<class>/*.tres: each class's talent tree.

# The class picked on the Character Select screen. Its rules decide which
# cards the deck builder lets you use, and how many of each.
var character_class: CharacterClass

# The deck the player built. It holds one entry per card, so two Strikes means
# Strike appears twice in the list. The battle copies this and shuffles the copy.
var deck: Array[CardData] = []

# The area picked on the map. This run's fights happen here.
var current_area: Area

# --- The run --------------------------------------------------------------
# A "run" is FIGHTS_PER_RUN battles in a row. Your HP carries over from one
# fight to the next. Win them all, or die, and you go to the shop. From the
# shop you start a new run with full HP.
const FIGHTS_PER_RUN := 5
const GOLD_MIN := 1  # Gold each enemy drops (a random amount between these).
const GOLD_MAX := 5

var gold := 0  # Kept between runs, and saved (see "Saving" below).
var fights_won := 0  # Fights won in this run.
var run_gold := 0  # Gold earned in this run, for the shop's summary.
var run_hp := -1  # Your HP between fights. -1 = start the next fight at full HP.
var run_died := false  # Did the last run end in a defeat?
# Booster packs bought in the shop and not opened yet, by name: {"Basic Booster": 2}.
var booster_packs := {}

# --- Your card collection ----------------------------------------------------
# Which cards you own, and how many: {"Strike": 3, "Punch": 1}. The deck
# builder only shows cards you own, and a deck can't hold more copies than you
# own. Cards marked Unlocked in the spreadsheet start in your collection (as
# many as their Copies column, so you own your starter deck), and you find the
# rest in booster packs.
const MAX_COPIES := 3  # The most copies of one card you can own (and put in a deck).
# The chance of each rarity for every card in a pack. They add up to 100.
const PACK_ODDS := {CardData.Rarity.COMMON: 60, CardData.Rarity.UNCOMMON: 30, CardData.Rarity.RARE: 10}
const CARDS_PER_PACK := 3
var collection := {}

# --- Card Exp ------------------------------------------------------------------
# Opening a copy of a card you already own 3 of gives that card 1 Exp instead.
# Enough Exp levels it up, and the level counts for EVERY copy of it.
# CARD_LEVEL_EXP[n] is the total Exp needed for level n + 1:
#   Level 1 at 0, Level 2 at 3, Level 3 at 3 + 5 = 8.
const CARD_LEVEL_EXP: Array[int] = [0, 3, 8]
var card_exp := {}  # {"Strike": 4}

# --- Class Exp -----------------------------------------------------------------
# Each class levels up on its own. Leveling up is how a class gets its class
# cards (see CharacterClass.level_cards and data/class_cards.csv).
const CLASS_MAX_LEVEL := 25
const EXP_PER_ENEMY := 10  # For every enemy you beat...
const EXP_PER_RUN := 25  # ...plus this for beating all of them.
const FIRST_LEVEL_EXP := 100  # Exp from level 1 to level 2...
const LEVEL_EXP_STEP := 50  # ...and each level after needs this much more.
var class_exp := {}  # Total Exp per class name: {"Knight": 140}

# Cards that Vanished this run, by their position in `deck` (so with two
# Bandages, we know WHICH one is gone). The battle leaves these out.
var vanished: Array[int] = []

# --- Talents -------------------------------------------------------------------
# Each class has its own talent tree (talent.gd, from data/talents/<class>.csv).
# You get 1 talent point per class level after level 1, plus any bonus points
# (later: clearing areas, quests, bosses), and spend them on talents.
var talent_ranks := {}  # Class name -> {talent name -> rank}: {"Adventurer": {"Jack of All Trades": 1}}
var bonus_talent_points := 0  # Extra points every class gets (none yet).
var talents_return_scene := "res://scenes/character_select.tscn"  # Where the Talents screen's Back goes.

# The last deck you built for each class, as card names: {"Knight": ["Strike", ...]}.
# Picking that class again gives you this deck back instead of the starter deck.
var saved_decks := {}

# Remembered lists, so the cards/ folder is only read once (see load_all_cards()).
var _all_cards: Array[CardData] = []
var _cards_by_name := {}  # "Strike" -> its CardData, for find_card().
var _classes: Array[CharacterClass] = []  # For load_classes().
var _talents := {}  # Class name -> its Array[Talent], for talents_for().


func _ready() -> void:
	start_fresh()
	load_game()  # If there's a save file, it replaces the fresh start.


# A brand new player: the starter cards, no gold, no Exp.
# Used when the game starts, and by the Reset Save button (reset_save()).
func start_fresh() -> void:
	gold = 0
	collection.clear()
	card_exp.clear()
	class_exp.clear()
	booster_packs.clear()
	saved_decks.clear()
	talent_ranks.clear()
	bonus_talent_points = 0
	character_class = null
	deck.clear()
	start_run()
	for card in load_all_cards():
		if card.unlocked:
			collection[card.card_name] = clampi(card.copies, 1, MAX_COPIES)
	# Every class starts at level 1, so it gets its level 1 class cards now.
	for character_class in load_classes():
		_give_level_cards(character_class, 1)


# How many copies of this card do you own? (0 = you haven't found it yet.)
func owned(card: CardData) -> int:
	return collection.get(card.card_name, 0)


# Add one copy of a card to your collection. Once you own 3, it gives the
# card 1 Exp instead. Returns what happened, for the screen to show:
#   {"card": CardData, "new": true/false, "owned": 2, "exp": false, "level_up": false}
func add_card(card: CardData) -> Dictionary:
	var result := {"card": card, "new": owned(card) == 0, "exp": false, "level_up": false}
	if owned(card) < MAX_COPIES:
		collection[card.card_name] = owned(card) + 1
	else:
		var level_before := card_level(card)
		card_exp[card.card_name] = card_exp.get(card.card_name, 0) + 1
		result.exp = true
		result.level_up = card_level(card) > level_before
	# Write down the numbers NOW. If the same card comes out twice in one pack,
	# the shop shows each one with the numbers it had at that moment, not the
	# final numbers after the whole pack was opened.
	result.owned = owned(card)
	result.level = card_level(card)
	result.exp_text = card_exp_text(card)
	return result


# Open one booster pack: CARDS_PER_PACK cards, each one added to your
# collection with add_card(). Returns what you got, for the shop to show.
# Any card can come out, even one you already own 3 of (that's how cards get Exp).
func open_pack() -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	for i in CARDS_PER_PACK:
		var card := _pick_pack_card()
		if card:  # null only if there are no cards that can come from packs at all.
			opened.append(add_card(card))
	save_game()
	return opened


# One random card for a pack. First roll its rarity (60 / 30 / 10), then pick
# any card of that rarity. If the spreadsheet has no cards of some rarity, its
# odds are shared out among the rarities that do have cards.
# Class cards never come from packs: classes get them by leveling up.
func _pick_pack_card() -> CardData:
	var by_rarity := {}  # Rarity -> the cards of that rarity.
	for card in load_all_cards():
		if card.is_class_card():
			continue
		if not by_rarity.has(card.rarity):
			by_rarity[card.rarity] = []
		by_rarity[card.rarity].append(card)
	# Add up the odds of the rarities that have cards, and pick one.
	var total := 0
	for rarity in by_rarity:
		total += PACK_ODDS[rarity]
	if total == 0:
		return null  # No pack cards in the spreadsheet (randi_range(1, 0) would go wrong).
	var roll := randi_range(1, total)
	for rarity in by_rarity:
		roll -= PACK_ODDS[rarity]
		if roll <= 0:
			return by_rarity[rarity].pick_random()
	return null


# A card's level (1 to 3), from its Exp.
func card_level(card: CardData) -> int:
	var exp_total: int = card_exp.get(card.card_name, 0)
	var level := 1
	for i in CARD_LEVEL_EXP.size():
		if exp_total >= CARD_LEVEL_EXP[i]:
			level = i + 1
	return level


# e.g. "Exp 1 / 3" (towards the next level), or "Max level".
func card_exp_text(card: CardData) -> String:
	var level := card_level(card)
	if level >= CARD_LEVEL_EXP.size():
		return "Max level"
	return "Exp %d / %d" % [card_exp.get(card.card_name, 0), CARD_LEVEL_EXP[level]]


# The version of a card you actually play with: its level 2 or 3 file from
# cards/levels/ once it's leveled up. If that level isn't in the level sheet
# yet, it falls back to the highest level that is (or the level 1 card).
func leveled(card: CardData) -> CardData:
	var base_name := card.resource_path.get_file().get_basename()  # "strike"
	for level in range(card_level(card), 1, -1):  # e.g. 3, then 2
		var path := CardImporter.LEVELS_FOLDER + "%s_lv%d.tres" % [base_name, level]
		if ResourceLoader.exists(path):
			return load(path)
	return card


# How much Exp it takes to go from `level` to the next one: 100, 150, 200...
func exp_for_next_level(level: int) -> int:
	return FIRST_LEVEL_EXP + LEVEL_EXP_STEP * (level - 1)


# A class's level, worked out from its total Exp.
func class_level(character_class: CharacterClass) -> int:
	var exp_left: int = class_exp.get(character_class.display_name, 0)
	var level := 1
	while level < CLASS_MAX_LEVEL and exp_left >= exp_for_next_level(level):
		exp_left -= exp_for_next_level(level)
		level += 1
	return level


# Progress towards the next level, for the Exp bar: Vector2i(40, 150) means
# "40 of the 150 Exp needed". At the max level it's Vector2i(0, 0).
func class_exp_progress(character_class: CharacterClass) -> Vector2i:
	var level := class_level(character_class)
	if level >= CLASS_MAX_LEVEL:
		return Vector2i.ZERO
	var exp_left: int = class_exp.get(character_class.display_name, 0)
	for i in range(1, level):
		exp_left -= exp_for_next_level(i)
	return Vector2i(exp_left, exp_for_next_level(level))


# Give the chosen class some Exp. Returns one entry per level gained, with the
# class cards it unlocked: [{"level": 2, "cards": [add_card() results]}]
func add_class_exp(amount: int) -> Array[Dictionary]:
	var level_ups: Array[Dictionary] = []
	var level_before := class_level(character_class)
	class_exp[character_class.display_name] = class_exp.get(character_class.display_name, 0) + amount
	for level in range(level_before + 1, class_level(character_class) + 1):
		level_ups.append({"level": level, "cards": _give_level_cards(character_class, level)})
	save_game()
	return level_ups


# Add the class cards a class gets at `level` to your collection.
func _give_level_cards(character_class: CharacterClass, level: int) -> Array[Dictionary]:
	var given: Array[Dictionary] = []
	for card_name in character_class.level_cards.get(level, PackedStringArray()):
		var card := find_card(card_name)
		if card:
			given.append(add_card(card))
	return given


# The level 1 card with this name, or null.
func find_card(card_name: String) -> CardData:
	if _cards_by_name.is_empty():
		for card in load_all_cards():
			_cards_by_name[card.card_name] = card
	return _cards_by_name.get(card_name)


# The enemies for the current fight: the area's encounters in order (fight 1
# = the first encounter...), starting over if there are fewer than 5.
# An empty list means the area has no encounters yet.
func current_encounter() -> Array[EnemyData]:
	var enemies: Array[EnemyData] = []
	var encounters := current_area.encounters
	if not encounters.is_empty():
		enemies.assign(encounters[(current_fight() - 1) % encounters.size()].enemies)
	return enemies


# Called when you pick an area on the map: a fresh run there.
func start_run() -> void:
	fights_won = 0
	run_gold = 0
	run_hp = -1
	run_died = false
	vanished.clear()  # Vanished cards come back for a new run.


# Which fight of the run is next (or now): 1 to FIGHTS_PER_RUN.
func current_fight() -> int:
	return fights_won + 1


func is_run_over() -> bool:
	return run_died or fights_won >= FIGHTS_PER_RUN


# Called by the Character Select screen. A new class means a new deck,
# so we throw the old one away and start from that class's starter deck.
func choose_class(new_class: CharacterClass) -> void:
	character_class = new_class
	deck = _load_saved_deck(new_class)
	if deck.is_empty():
		deck = make_starter_deck()


# The deck you last built for this class, from saved_decks. Any card the class
# can't use any more (or that you don't own enough of) is left out.
func _load_saved_deck(for_class: CharacterClass) -> Array[CardData]:
	var loaded: Array[CardData] = []
	for card_name in saved_decks.get(for_class.display_name, []):
		var card := find_card(card_name)
		if card and for_class.can_add_to(loaded, card):
			loaded.append(card)
	return loaded


# ---------------------------------------------------------------------------
# Talents
# ---------------------------------------------------------------------------

# Every talent in this class's tree, from talents/<class>/. Read once, then remembered.
func talents_for(for_class: CharacterClass) -> Array[Talent]:
	if for_class == null:
		var none: Array[Talent] = []
		return none
	if not _talents.has(for_class.display_name):
		var list: Array[Talent] = []
		var folder := TALENTS_FOLDER + for_class.resource_path.get_file().get_basename() + "/"
		for file_name in ResourceLoader.list_directory(folder):
			if file_name.ends_with(".tres"):
				list.append(load(folder + file_name))
		# Top row first, then left to right.
		list.sort_custom(func(a: Talent, b: Talent) -> bool:
			return a.tier < b.tier if a.tier != b.tier else a.column < b.column)
		_talents[for_class.display_name] = list
	return _talents[for_class.display_name]


func find_talent(for_class: CharacterClass, talent_name: String) -> Talent:
	for talent in talents_for(for_class):
		if talent.talent_name == talent_name:
			return talent
	return null


# How many ranks of this talent the class has learned (0 = none).
func talent_rank(talent: Talent) -> int:
	return talent_ranks.get(talent.class_display_name, {}).get(talent.talent_name, 0)


# Points: 1 per level after level 1, plus bonus points, minus what's spent.
func talent_points_earned(for_class: CharacterClass) -> int:
	return class_level(for_class) - 1 + bonus_talent_points


func talent_points_spent(for_class: CharacterClass, only_tier: int = 0) -> int:
	var spent := 0
	for talent in talents_for(for_class):
		if only_tier == 0 or talent.tier == only_tier:
			spent += talent_rank(talent) * talent.cost
	return spent


func talent_points_left(for_class: CharacterClass) -> int:
	return talent_points_earned(for_class) - talent_points_spent(for_class)


# Why can't you learn the next rank of this talent? A short reason for the
# talent screen, or "" if you can. Checks every rule from the sheet.
func why_cant_learn(talent: Talent) -> String:
	var for_class := _class_named(talent.class_display_name)
	var rank := talent_rank(talent)
	if rank >= talent.max_ranks:
		return "Max rank"
	# Choice Group and Locks Out: has another talent shut this one out?
	for other in talents_for(for_class):
		if other == talent or talent_rank(other) == 0:
			continue
		var same_group := not talent.choice_group.is_empty() and other.choice_group == talent.choice_group
		if same_group or other.locks_out.has(talent.talent_name) or talent.locks_out.has(other.talent_name):
			return "You picked %s" % other.talent_name
	if talent.tier_unlock > 0 and talent.tier > 1:
		var in_tier_above := talent_points_spent(for_class, talent.tier - 1)
		if in_tier_above < talent.tier_unlock:
			return "Spend %d point(s) in Tier %d first" % [talent.tier_unlock, talent.tier - 1]
	if talent.points_in_tree > 0 and talent_points_spent(for_class) < talent.points_in_tree:
		return "Spend %d point(s) in this tree first" % talent.points_in_tree
	if not talent.needs.is_empty():
		var have: Array[String] = []
		for needed in talent.needs:
			var needed_talent := find_talent(for_class, needed)
			if needed_talent and talent_rank(needed_talent) > 0:
				have.append(needed)
		var enough := not have.is_empty() if talent.needs_any else have.size() == talent.needs.size()
		if not enough:
			return "Needs %s" % (" or " if talent.needs_any else " and ").join(talent.needs)
	if talent_points_left(for_class) < talent.cost:
		return "No talent points left"
	return ""


# Spend points on the next rank. Returns false if a rule says no.
func learn_talent(talent: Talent) -> bool:
	if not why_cant_learn(talent).is_empty():
		return false
	if not talent_ranks.has(talent.class_display_name):
		talent_ranks[talent.class_display_name] = {}
	talent_ranks[talent.class_display_name][talent.talent_name] = talent_rank(talent) + 1
	save_game()
	return true


# Take back every point in this class's tree (free, for now).
func reset_talents(for_class: CharacterClass) -> void:
	talent_ranks.erase(for_class.display_name)
	if for_class == character_class:
		# Cards a talent let into the deck might not be allowed any more.
		deck = _keep_allowed(deck)
	save_game()


# The total of one effect from every talent the class has learned, e.g.
# talent_bonus(knight, Talent.ENERGY). Pass a card to only count talents whose
# School matches it, or a school to only count talents for that school
# ("All" talents always count).
func talent_bonus(for_class: CharacterClass, effect: String, card: CardData = null, school: int = -1) -> int:
	var total := 0
	for talent in talents_for(for_class):
		if talent.effect != effect:
			continue
		if card and not talent.matches_card(card):
			continue
		if school >= 0 and not (talent.school in ["all", "any", ""]) and talent.school_flag() != school:
			continue
		total += talent.amount_at(talent_rank(talent))
	return total


# The first talent in this class's tree that opens up a school, for the deck
# builder to say "Needs talent: Jack of All Trades". null if there isn't one.
func talent_that_opens(for_class: CharacterClass, school: int) -> Talent:
	for talent in talents_for(for_class):
		if talent.effect == Talent.SCHOOL_LIMIT and (talent.school in ["all", "any", ""] or talent.school_flag() == school):
			return talent
	return null


func _talent_could_open(card: CardData) -> bool:
	if card.is_class_card() and not card.class_only.has(character_class.display_name):
		return false
	for school in CardData.School.values():
		if card.has_school(school) and talent_that_opens(character_class, school):
			return true
	return false


func _class_named(display_name: String) -> CharacterClass:
	for each_class in load_classes():
		if each_class.display_name == display_name:
			return each_class
	return null


# The cards of `cards` that still follow every deck rule, in the same order.
func _keep_allowed(cards: Array[CardData]) -> Array[CardData]:
	var kept: Array[CardData] = []
	for card in cards:
		if character_class.can_add_to(kept, card):
			kept.append(card)
	return kept


# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------
# Everything you keep between runs is written to one small JSON file.
# "user://" is a folder Godot gives every game for its own files. On Windows
# it's %APPDATA%\Godot\app_userdata\Card Game\ (Project > Open User Data
# Folder in the editor takes you there). JSON is the same format Python's
# json module reads and writes.
#
# What's saved: gold, your collection, card Exp, class Exp, unopened packs,
# talents and the last deck you built for each class. NOT saved: a run in progress.
# Quit in the middle of a run and you start a new one next time.
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1  # Bump this if the save format ever changes.


func save_game() -> void:
	if character_class:
		saved_decks[character_class.display_name] = deck.map(func(card: CardData) -> String: return card.card_name)
	var data := {
		"version": SAVE_VERSION,
		"gold": gold,
		"collection": collection,
		"card_exp": card_exp,
		"class_exp": class_exp,
		"booster_packs": booster_packs,
		"decks": saved_decks,
		"talents": talent_ranks,
		"bonus_talent_points": bonus_talent_points,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Couldn't save the game: %s" % error_string(FileAccess.get_open_error()))
		return
	# "\t" indents it, so you can open the file and read it yourself.
	file.store_string(JSON.stringify(data, "\t"))


# Read the save file, if there is one. Returns false if there isn't (or it's broken).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		push_warning("The save file couldn't be read, so you start fresh.")
		return false
	# JSON stores every number as a float (3.0), so int() turns them back.
	gold = int(data.get("gold", 0))
	collection = _whole_numbers(data.get("collection", {}))
	card_exp = _whole_numbers(data.get("card_exp", {}))
	class_exp = _whole_numbers(data.get("class_exp", {}))
	booster_packs = _whole_numbers(data.get("booster_packs", {}))
	saved_decks = data.get("decks", {})
	talent_ranks.clear()
	var saved_talents: Dictionary = data.get("talents", {})
	for class_name_key in saved_talents:
		talent_ranks[class_name_key] = _whole_numbers(saved_talents[class_name_key])
	bonus_talent_points = int(data.get("bonus_talent_points", 0))
	# A card added to the spreadsheet as Unlocked after you saved still
	# shows up in your collection.
	for card in load_all_cards():
		if card.unlocked and owned(card) == 0:
			collection[card.card_name] = clampi(card.copies, 1, MAX_COPIES)
	return true


# {"Strike": 3.0} -> {"Strike": 3}
func _whole_numbers(numbers: Dictionary) -> Dictionary:
	var result := {}
	for key in numbers:
		result[key] = int(numbers[key])
	return result


# The Reset Save button: delete the save file and start over as a new player.
func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	start_fresh()


# Godot sends this when you close the game window: one last save on the way out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


# Every class, loaded from the classes/ folder, in their sort_order.
# Read once and remembered, like load_all_cards().
func load_classes() -> Array[CharacterClass]:
	if _classes.is_empty():
		for file_name in ResourceLoader.list_directory(CLASSES_FOLDER):
			if file_name.ends_with(".tres"):
				_classes.append(load(CLASSES_FOLDER + file_name))
		_classes.sort_custom(func(a: CharacterClass, b: CharacterClass) -> bool:
			return a.sort_order < b.sort_order)
	return _classes


# Every area, loaded from the areas/ folder, in their sort_order (the order along the road).
func load_areas() -> Array[Area]:
	var areas: Array[Area] = []
	for file_name in ResourceLoader.list_directory(AREAS_FOLDER):
		if file_name.ends_with(".tres"):
			areas.append(load(AREAS_FOLDER + file_name))
	areas.sort_custom(func(a: Area, b: Area) -> bool: return a.sort_order < b.sort_order)
	return areas


# Every card in the game (one of each), loaded from the cards/ folder.
# Character Select uses this to count owned cards for class unlocks.
# The cards don't change while the game runs, so the folder is only read the
# first time; after that the same list is handed back. Don't change the list
# you get (loop over it, or make your own list from it).
func load_all_cards() -> Array[CardData]:
	if _all_cards.is_empty():
		for file_name in ResourceLoader.list_directory(CARDS_FOLDER):
			if file_name.ends_with(".tres"):
				_all_cards.append(load(CARDS_FOLDER + file_name))
	return _all_cards


# Every card you OWN that the chosen class is allowed to build with (one of each),
# plus ones a talent could open up (the deck builder shows them as "Needs talent").
# Sorted by school, then name, so schools sit together.
func load_card_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in load_all_cards():
		if owned(card) > 0 and (character_class == null or character_class.can_use(card) or _talent_could_open(card)):
			pool.append(card)
	# sort_custom() takes a function that answers "should a come before b?".
	# `func(a, b): ...` is a lambda: a small function with no name (like Python's lambda).
	pool.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.schools != b.schools:
			return a.schools < b.schools
		return a.card_name < b.card_name)
	return pool


# The suggested starting deck for the chosen class: every card it can use,
# as many times as the Copies column says, but never more than the class
# allows (so a Copies of 3 still gives the Adventurer just 1).
# Used when you pick a class, and by the deck builder's Starter Deck button.
func make_starter_deck() -> Array[CardData]:
	var starter: Array[CardData] = []
	for card in load_card_pool():
		for i in mini(card.copies, character_class.max_copies_of(card)):
			# can_add_to() checks every deck rule, including "locked cards
			# can't be added" and the deck-size and per-school limits.
			if character_class.can_add_to(starter, card):
				starter.append(card)
	return starter


# For testing a scene on its own (F6): if nothing was picked yet, use the
# first class and its starter deck, so the scene still has something to show.
func ensure_ready() -> void:
	if character_class == null:
		choose_class(load_classes()[0])
	elif deck.is_empty():
		deck = make_starter_deck()
	if current_area == null:
		current_area = load_areas()[0]  # The first area on the road (the Plains).
