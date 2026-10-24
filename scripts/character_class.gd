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
@export_multiline var description: String = ""  # A line of flavour text.
@export var color: Color = Color(0.4, 0.4, 0.42)  # Panel colour on the select screen.
@export var sort_order: int = 0  # Lower numbers are shown further left.

@export_group("Deck rules")
# Which schools' cards this class may put in its deck. Same checkboxes as on cards.
@export_flags("Strength", "Agility", "Intellect", "Wisdom") var allowed_schools: int = 15  # 15 = all four.
@export var allow_neutral: bool = true  # Can it use cards with no school?
@export var max_copies: int = 2  # Most copies of each card that HAS a school.
@export var max_copies_neutral: int = 2  # Most copies of each neutral card.
@export var min_deck_size: int = 10  # Can't start a battle with fewer cards.
@export var max_deck_size: int = 20  # Can't add cards beyond this.


# How many copies of this card may the deck hold? 0 means "not allowed at all".
func max_copies_of(card: CardData) -> int:
	if card.is_neutral():
		return max_copies_neutral if allow_neutral else 0
	# A card with several schools is allowed if ANY of them is allowed.
	# `&` keeps the schools the card and the class have in common.
	if (card.schools & allowed_schools) == 0:
		return 0
	return max_copies


func can_use(card: CardData) -> bool:
	return max_copies_of(card) > 0


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
		lines.append("%s cards: up to %d each" % [", ".join(school_names), max_copies])
	if allow_neutral:
		lines.append("Neutral cards: up to %d each" % max_copies_neutral)
	lines.append("Deck size: %d to %d cards" % [min_deck_size, max_deck_size])
	return "\n".join(lines)
