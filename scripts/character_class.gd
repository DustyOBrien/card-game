# character_class.gd
#
# A CharacterClass describes ONE class you can pick on the Character Select
# screen (Adventurer, Knight...), mainly its deck-building rules.
#
# Just like CardData, it's a Resource: each class is a .tres file in the
# classes/ folder. To ADD A CLASS, you don't need to write any code:
#   1. In Godot's FileSystem panel, right-click classes/knight.tres > Duplicate.
#   2. Click the new file and change its name, rules and colour in the Inspector.
# The Character Select screen shows every .tres file it finds in classes/.
#
# (We can't call this script "Class" because `class` is a GDScript keyword.)
class_name CharacterClass
extends Resource

@export var display_name: String = "New Class"  # Name shown on screen.
@export var emblem: Texture2D  # The class's symbol. Drag an image from emblems/ onto this in the Inspector.
@export_multiline var description: String = ""  # A line of flavour text.
@export var color: Color = Color(0.4, 0.4, 0.42)  # Panel colour on the select screen.
@export var sort_order: int = 0  # Lower numbers are shown further left.
@export var max_hp: int = 50  # The player's HP in battle.
# Armor: how much leftover Block carries over to your next turn, instead of
# dropping to 0 (see combatant.gd).
@export var armor: int = 0

@export_group("Unlocking")
@export var starts_unlocked: bool = false  # true = playable from the start (the Adventurer).
# Otherwise the class unlocks once you own this many different cards of this
# school (cards marked Unlocked in the spreadsheet, plus ones from packs).
@export_enum("Strength:1", "Agility:2", "Intellect:4", "Wisdom:8") var unlock_school: int = 1
@export var unlock_card_count: int = 12

@export_group("Levels")
# The cards this class gets when it reaches each level, e.g.
#   {2: ["Shield Bash"], 5: ["Shield Wall", "Shield Wall"]}  (twice = 2 copies)
# Filled in from data/class_cards.csv by the card importer.
@export var level_cards: Dictionary[int, PackedStringArray] = {}

@export_group("Deck rules")
# Which schools' cards this class may put in its deck. Same checkboxes as on cards.
@export_flags("Strength", "Agility", "Intellect", "Wisdom") var allowed_schools: int = 15  # 15 = all four.
@export var allow_neutral: bool = true  # Can it use cards with no school?
# Every class can use up to 3 copies of a card (GameState.MAX_COPIES), so
# that isn't a class setting. Classes differ in WHICH cards they may use.
# Most cards from any ONE school in the deck (all its cards added up). 0 = no limit.
@export var max_cards_per_school: int = 0
@export var min_deck_size: int = 12  # Can't start a battle with fewer cards.
@export var max_deck_size: int = 20  # Can't add cards beyond this.


# How many copies of this card may the deck hold? 0 means "not allowed at all".
func max_copies_of(card: CardData) -> int:
	# Class cards (the Class column) are only for the classes they name.
	if card.is_class_card() and not card.class_only.has(display_name):
		return 0
	if card.is_neutral():
		return GameState.MAX_COPIES if allow_neutral else 0
	# A card with several schools is allowed if ANY of them is allowed.
	# `&` keeps the schools the card and the class have in common.
	if (card.schools & allowed_schools) == 0:
		return 0
	return GameState.MAX_COPIES


func can_use(card: CardData) -> bool:
	return max_copies_of(card) > 0


# Could this card go into `deck` right now? Checks every rule in one place,
# so the deck builder and the starter deck follow exactly the same rules.
func can_add_to(deck: Array[CardData], card: CardData) -> bool:
	return why_not(deck, card).is_empty()


# Why can't this card go into `deck`? A short reason for the deck builder to
# show, or "" if it can.
func why_not(deck: Array[CardData], card: CardData) -> String:
	var count := deck.count(card)
	if count >= max_copies_of(card):
		return "All copies in deck" if count > 0 else "Not for this class"
	if count >= GameState.owned(card):
		# You can't put in more copies than you own.
		return "You own %d" % GameState.owned(card)
	if deck.size() >= max_deck_size:
		return "Deck is full"
	if max_cards_per_school > 0:
		# Every school on the card must still have room.
		for school in CardData.School.values():
			if card.has_school(school) and count_school(deck, school) >= max_cards_per_school:
				var school_name: String = CardData.School.find_key(school).capitalize()
				return "%d %s card max" % [max_cards_per_school, school_name]
	return ""


# How many cards in `deck` belong to `school`? (A STR + WIS card counts for both.)
static func count_school(deck: Array[CardData], school: int) -> int:
	var total := 0
	for card in deck:
		if card.has_school(school):
			total += 1
	return total


# ---------------------------------------------------------------------------
# Unlocking
# ---------------------------------------------------------------------------

# How many different cards of our unlock school do you own?
func unlock_progress(all_cards: Array[CardData]) -> int:
	var total := 0
	for card in all_cards:
		if GameState.owned(card) > 0 and card.has_school(unlock_school):
			total += 1
	return total


func is_unlocked(all_cards: Array[CardData]) -> bool:
	return starts_unlocked or unlock_progress(all_cards) >= unlock_card_count


# e.g. "Unlock 12 Strength cards (6 / 12)"
func get_unlock_text(all_cards: Array[CardData]) -> String:
	var school_name: String = CardData.School.find_key(unlock_school).capitalize()
	return "Unlock %d %s cards (%d / %d)" % [
		unlock_card_count, school_name, unlock_progress(all_cards), unlock_card_count]


# A short summary of the rules, built from the numbers above so it never goes
# out of date. Shown on the Character Select screen.
func get_rules_text() -> String:
	var school_names: Array[String] = []
	for school_name in CardData.School.keys():
		if (allowed_schools & CardData.School[school_name]) != 0:
			school_names.append(school_name.capitalize())

	var lines: Array[String] = []
	if school_names.is_empty():
		lines.append("No school cards")
	else:
		lines.append("%s cards" % ", ".join(school_names))
	if max_cards_per_school > 0:
		lines.append("At most %d card(s) from each school" % max_cards_per_school)
	if allow_neutral:
		lines.append("Neutral cards")
	lines.append("Up to %d copies of each card" % GameState.MAX_COPIES)
	lines.append("Deck size: %d to %d cards" % [min_deck_size, max_deck_size])
	lines.append("HP: %d" % max_hp)
	if armor > 0:
		lines.append("Armor: %d (keeps up to %d leftover Block)" % [armor, armor])
	return "\n".join(lines)
