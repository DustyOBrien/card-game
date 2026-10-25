# card_data.gd
#
# A CardData describes ONE kind of card: its name, cost, and what it does.
# It extends Resource, which is Godot's word for "a chunk of data you can
# save as a file". Each card type lives in its own .tres file in the
# cards/ folder (strike.tres, defend.tres). Open one in the Godot editor
# and you can change its numbers in the Inspector without touching code.
#
# `class_name CardData` gives this type a global name, so any other script
# can write `CardData` (like using a class you imported in Python).
class_name CardData
extends Resource

# --- Card types and schools ---------------------------------------------------
# A card can have SEVERAL types and SEVERAL schools (or none), so each is
# stored as "bit flags": every option gets its own power of two (1, 2, 4, 8),
# and a card's value is the options added together.
#   Attack only            -> 1
#   Attack + Ability       -> 1 + 4 = 5
#   Strength + Wisdom      -> 1 + 8 = 9
#   Neutral (no school)    -> 0
# You never have to do this maths yourself: the Inspector shows a checkbox for
# each option, and the has_type() / has_school() helpers below do the checking.
#
# IMPORTANT: the numbers here must match the order of the names in the
# @export_flags(...) lines further down (first name = 1, second = 2, ...).
# To add a new option, add it to the END of both lists with the next power of two.
enum CardType { ATTACK = 1, DEFENSE = 2, ABILITY = 4 }
enum School { STRENGTH = 1, AGILITY = 2, INTELLECT = 4, WISDOM = 8 }

# Each school's colour, used for cards and for the deck builder's school chips.
const SCHOOL_COLORS := {
	School.STRENGTH: Color(0.6, 0.22, 0.22),
	School.AGILITY: Color(0.25, 0.5, 0.3),
	School.INTELLECT: Color(0.22, 0.35, 0.65),
	School.WISDOM: Color(0.5, 0.4, 0.65),
}
const NEUTRAL_COLOR := Color(0.4, 0.4, 0.42)

# Rarity is just one value per card, so it's a normal enum (0, 1, 2), not flags.
enum Rarity { COMMON, UNCOMMON, RARE }
const RARITY_COLORS := {
	Rarity.COMMON: Color(0.85, 0.85, 0.85),
	Rarity.UNCOMMON: Color(0.45, 0.75, 1.0),
	Rarity.RARE: Color(1.0, 0.8, 0.3),
}

# @export makes a variable show up in the Inspector so you can edit it there.
@export var card_name: String = "New Card"
@export var cost: int = 1  # Energy needed to play the card.

# @export_flags shows one checkbox per name in the Inspector.
@export_flags("Attack", "Defense", "Ability") var types: int = 0
@export_flags("Strength", "Agility", "Intellect", "Wisdom") var schools: int = 0

@export var damage: int = 0  # Damage dealt to the enemy when played.
# Dice damage, e.g. "2d3+2" (see dice.gd). When set, it's used INSTEAD of `damage`.
@export var dice: String = ""
@export var block: int = 0  # Block gained by the player when played.
@export var heal: int = 0  # HP the player gets back (never above max HP).
@export var draw: int = 0  # Cards drawn from the draw pile.
@export var discard: int = 0  # Random cards from your hand thrown into the discard pile.
@export var draw_if_full_hp: int = 0  # Extra cards drawn if you were at full HP when you played it.
@export var next_attack_bonus: int = 0  # Your next Attack card deals this much extra damage.
@export var next_defense_bonus: int = 0  # Your next Defense card gives this much extra Block.
@export var energy: int = 0  # Energy the player gains when played.
@export var lose_hp: int = 0  # HP the player loses when played (Block doesn't stop it).
@export var copies: int = 1  # How many go in the Starter Deck (a class may allow fewer).
@export var rarity: Rarity = Rarity.COMMON  # Shown as a dropdown in the Inspector.
@export var unlocked: bool = true  # Locked cards show in the deck builder but can't be added.
# Classes allowed to use this card, e.g. ["Knight"]. Empty means every class.
@export var class_only: PackedStringArray = []
@export_multiline var effect: String = ""  # Rules text shown on the card.
@export var color: Color = Color.WHITE  # Tint used when drawing the card.


# Does this card have the given type? Example: card.has_type(CardData.CardType.ATTACK)
func has_type(type: CardType) -> bool:
	# `&` (bitwise AND) keeps only the bits both numbers share.
	# If the result isn't 0, the card has that type ticked.
	return (types & type) != 0


# Does this card belong to the given school? Example: card.has_school(CardData.School.STRENGTH)
func has_school(school: School) -> bool:
	return (schools & school) != 0


# --- Battle-only values ----------------------------------------------------------
# These are NOT @export, so they aren't saved in the .tres file. The battle
# gives every card in your deck its own copy (duplicate()), so two Strikes can
# each have their own roll.
var roll_result: Dictionary = {}  # The last roll, e.g. {"dice": [2, 3], "bonus": 2, "total": 7}. {} = not rolled.


func has_dice() -> bool:
	return not dice.is_empty()


func is_rolled() -> bool:
	return not roll_result.is_empty()


# Does playing this card hurt the enemy? (Then it must be dropped on the enemy.)
func deals_damage() -> bool:
	return damage > 0 or has_dice()


# Effects that have no symbol on the card get a short line of text instead,
# e.g. "Next Attack +3" or "Lose 2 HP". (Attack, Block, Draw, Discard and Heal
# are shown as symbols by card.gd.)
func get_extra_text() -> String:
	var lines: Array[String] = []
	if next_attack_bonus > 0:
		lines.append("Next Attack +%d" % next_attack_bonus)
	if next_defense_bonus > 0:
		lines.append("Next Defense +%d" % next_defense_bonus)
	if energy > 0:
		lines.append("+%d Energy" % energy)
	if draw_if_full_hp > 0:
		lines.append("Full HP: Draw %d" % draw_if_full_hp)
	if lose_hp > 0:
		lines.append("Lose %d HP" % lose_hp)
	return "\n".join(lines)


# "Common", "Uncommon" or "Rare".
func get_rarity_text() -> String:
	return Rarity.keys()[rarity].capitalize()  # keys() gives ["COMMON", "UNCOMMON", "RARE"].


# Can only some classes use this card?
func is_class_card() -> bool:
	return not class_only.is_empty()


# Is this card neutral (no school ticked at all)?
func is_neutral() -> bool:
	return schools == 0


# Text for the card's type line, e.g. "Attack" or "Attack / Ability".
func get_type_text() -> String:
	var names: Array[String] = []
	# CardType.keys() gives the names as text: ["ATTACK", "DEFENSE", "ABILITY"]
	for type_name in CardType.keys():
		if has_type(CardType[type_name]):
			names.append(type_name.capitalize())  # "ATTACK" -> "Attack"
	return " / ".join(names)


# Short text for the card's schools, e.g. "STR" or "STR WIS".
# This is a placeholder until we have proper symbols for each school.
func get_school_text() -> String:
	if is_neutral():
		return "Neutral"
	var names: Array[String] = []
	for school_name in School.keys():
		if has_school(School[school_name]):
			names.append(school_name.substr(0, 3))  # "STRENGTH" -> "STR"
	return " ".join(names)
