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

var gold := 0  # Kept between runs (for now: it resets when you close the game).
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


func _ready() -> void:
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
	result.owned = owned(card)
	return result


# Open one booster pack: CARDS_PER_PACK cards, each one added to your
# collection with add_card(). Returns what you got, for the shop to show.
# Any card can come out, even one you already own 3 of (that's how cards get Exp).
func open_pack() -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	for i in CARDS_PER_PACK:
		opened.append(add_card(_pick_pack_card()))
	return opened


# One random card for a pack. First roll its rarity (60 / 30 / 10), then pick
# any card of that rarity. If the spreadsheet has no cards of some rarity, its
# odds are shared out among the rarities that do have cards.
# Cards in the class cards sheet never come from packs: classes get those by
# leveling up. (Other class-only cards, like Master of None, can.)
func _pick_pack_card() -> CardData:
	var level_rewards := _level_reward_names()
	var by_rarity := {}  # Rarity -> the cards of that rarity.
	for card in load_all_cards():
		if level_rewards.has(card.card_name):
			continue
		if not by_rarity.has(card.rarity):
			by_rarity[card.rarity] = []
		by_rarity[card.rarity].append(card)
	# Add up the odds of the rarities that have cards, and pick one.
	var total := 0
	for rarity in by_rarity:
		total += PACK_ODDS[rarity]
	var roll := randi_range(1, total)
	for rarity in by_rarity:
		roll -= PACK_ODDS[rarity]
		if roll <= 0:
			return by_rarity[rarity].pick_random()
	return null


# The names of every card some class gets by leveling up (class_cards.csv).
func _level_reward_names() -> Array[String]:
	var names: Array[String] = []
	for character_class in load_classes():
		for level in character_class.level_cards:
			for card_name in character_class.level_cards[level]:
				names.append(card_name)
	return names


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
	for card in load_all_cards():
		if card.card_name == card_name:
			return card
	return null


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
	deck = make_starter_deck()


# Every class, loaded from the classes/ folder, in their sort_order.
func load_classes() -> Array[CharacterClass]:
	var classes: Array[CharacterClass] = []
	for file_name in ResourceLoader.list_directory(CLASSES_FOLDER):
		if file_name.ends_with(".tres"):
			classes.append(load(CLASSES_FOLDER + file_name))
	classes.sort_custom(func(a: CharacterClass, b: CharacterClass) -> bool:
		return a.sort_order < b.sort_order)
	return classes


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
func load_all_cards() -> Array[CardData]:
	var cards: Array[CardData] = []
	for file_name in ResourceLoader.list_directory(CARDS_FOLDER):
		if file_name.ends_with(".tres"):
			cards.append(load(CARDS_FOLDER + file_name))
	return cards


# Every card you OWN that the chosen class is allowed to build with (one of each).
# Sorted by school, then name, so schools sit together.
func load_card_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in load_all_cards():
		if owned(card) > 0 and (character_class == null or character_class.can_use(card)):
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
