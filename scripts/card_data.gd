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

# Attack, Block and Heal can each be a plain number ("6") or dice ("d3", "2d6+1").
# See dice.gd. An empty text means the card doesn't do that.
#
# `attack` is a LIST: one entry per hit. Multi Strike is ["d3", "d3"]: two
# separate hits, each rolled on its own (and each can crit on its own).
@export var attack: PackedStringArray = []
@export var attack_modifier: int = 0  # Added to every attack die: d3 with modifier 1 = d3 + 1.
@export var block: String = ""  # Block gained by the player when played.
@export var block_modifier: int = 0  # Added to the block roll.
@export var heal: String = ""  # HP the player gets back (never above max HP).
@export var heal_modifier: int = 0  # Added to the heal roll.
@export var draw: int = 0  # Cards drawn from the draw pile.
@export var discard: int = 0  # Random cards from your hand thrown into the discard pile.
@export var draw_if_full_hp: int = 0  # Extra cards drawn if you were at full HP when you played it.
@export var next_attack_bonus: int = 0  # Your next Attack card deals this much extra damage.
@export var next_defense_bonus: int = 0  # Your next Defense card gives this much extra Block.
@export var energy: int = 0  # Energy the player gains when played.
@export var lose_hp: int = 0  # HP the player loses when played (Block doesn't stop it).
# Added to every die of the next card you play that rolls dice. A number ("1")
# or dice ("d3": Pump Up rolls how big the bonus is).
@export var next_roll_bonus: String = ""
# Advantage: roll each die twice and keep the HIGHER one. Disadvantage: keep
# the LOWER one. Having both cancels out (like in Dungeons & Dragons).
@export var advantage: bool = false  # This card's own dice roll with Advantage.
@export var disadvantage: bool = false  # This card's own dice roll with Disadvantage (Wild Swing).
@export var gain_advantage: bool = false  # The NEXT card you play that rolls gets Advantage (Insight).
@export var reroll: int = 0  # Pick this many non-Wild cards in your hand and roll their dice again (Gamble).
# Keywords:
#   Wild:   the dice roll when you PLAY the card, not when you draw it. A gamble!
#   Vanish: once played, the card is gone for the rest of the run.
@export var wild: bool = false
@export var vanish: bool = false
# What happens on a Critical: each die that reaches its top number (modifiers
# count!). Written like the spreadsheet, e.g. "+1 Damage" or "Draw 1, Gain 1 Energy".
@export var critical: String = ""
@export var copies: int = 1  # How many go in the Starter Deck (a class may allow fewer).
@export var rarity: Rarity = Rarity.COMMON  # Shown as a dropdown in the Inspector.
# true = you own 3 of it from the start. false = you have to find it in
# booster packs before it shows up in the deck builder (see GameState.collection).
@export var unlocked: bool = true
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
# The dice this card rolled, before any modifiers, e.g.
# {"attack 0": [3], "attack 1": [1], "block": [2]}. {} = not rolled yet.
# Modifiers are added when you PLAY the card (see card_roller.gd), so a bonus you
# get after drawing it still counts.
var roll_result: Dictionary = {}

# The dice the card threw away because of Advantage or Disadvantage, in the
# same shape as roll_result, e.g. {"attack 0": [1]}. Only for showing them.
var dropped_dice: Dictionary = {}

# The words a Critical can use, and the effect each one adds.
# "+1 Damage" -> {"damage": 1}, "Draw 1" -> {"draw": 1}, "Gain 2 Energy" -> {"energy": 2},
# "Draw a Card" -> {"draw": 1}, "Gain Advantage" -> {"advantage": 1}, "Dont Vanish" -> {"keep": 1}
const CRITICAL_WORDS := {"damage": "damage", "block": "block", "heal": "heal", "hp": "heal",
	"draw": "draw", "card": "draw", "cards": "draw", "energy": "energy", "advantage": "advantage",
	"vanish": "keep"}


# Does this card roll any dice?
func has_dice() -> bool:
	for formula in get_formulas().values():
		if Dice.has_dice(formula):
			return true
	return false


# Every formula on the card, by name: {"attack 0": "d3", "attack 1": "d3", "block": "d3"}.
# The names match the keys in roll_result.
func get_formulas() -> Dictionary:
	var formulas := {}
	for i in attack.size():
		formulas["attack %d" % i] = attack[i]
	if not block.is_empty():
		formulas["block"] = block
	if not heal.is_empty():
		formulas["heal"] = heal
	if not next_roll_bonus.is_empty():
		formulas["roll bonus"] = next_roll_bonus  # Pump Up's d3 rolls along with the card.
	return formulas


func is_rolled() -> bool:
	return not roll_result.is_empty()


# Does playing this card hurt the enemy? (Then it must be dropped on the enemy.)
func deals_damage() -> bool:
	return not attack.is_empty()


# Reads the Critical text into numbers: "+1 Damage, Draw 1" -> {"damage": 1, "draw": 1}.
# Anything it doesn't understand is skipped (the importer warns about it).
func get_critical_effects() -> Dictionary:
	var effects := {}
	for part in critical.split(",", false):
		var amount := 1  # No number ("Gain Advantage", "Draw a Card") means 1.
		var effect := ""
		for word in part.strip_edges().to_lower().split(" ", false):
			if word.replace("+", "").is_valid_int():
				amount = word.replace("+", "").to_int()
			elif CRITICAL_WORDS.has(word) and effect.is_empty():
				effect = CRITICAL_WORDS[word]
		if amount > 0 and not effect.is_empty():
			effects[effect] = effects.get(effect, 0) + amount
	return effects


# The attack as short text for the card: "d3", "d3+1", or "d3 x2" for two equal hits.
func get_attack_text() -> String:
	if attack.is_empty():
		return ""
	var hits: Array[String] = []
	for formula in attack:
		hits.append(_with_modifier(formula, attack_modifier))
	if hits.count(hits[0]) == hits.size() and hits.size() > 1:
		return "%s x%d" % [hits[0], hits.size()]  # All hits the same.
	return " + ".join(hits)


func get_block_text() -> String:
	return _with_modifier(block, block_modifier)


func get_heal_text() -> String:
	return _with_modifier(heal, heal_modifier)


# "d3" with modifier 1 -> "d3+1". A plain number just gets added: "6" + 1 -> "7".
static func _with_modifier(formula: String, modifier: int) -> String:
	if formula.is_empty() or modifier == 0:
		return formula
	if formula.is_valid_int():
		return str(formula.to_int() + modifier)
	return "%s%+d" % [formula, modifier]  # %+d always shows the sign: +1, -2.


# A sentence describing the card, for cards whose Description cell is blank.
# e.g. "Deal d3 damage twice. Discard 1 at random. Critical: Draw 1."
func make_description() -> String:
	var parts: Array[String] = []
	if not attack.is_empty():
		var text := "Deal %s damage" % _with_modifier(attack[0], attack_modifier)
		if attack.size() > 1 and get_attack_text().contains(" x"):
			text += " %d times" % attack.size() if attack.size() > 2 else " twice"
		elif attack.size() > 1:
			text = "Deal %s damage" % get_attack_text()
		parts.append(text)
	if not block.is_empty():
		parts.append("Gain %s Block" % get_block_text())
	if not heal.is_empty():
		parts.append("Heal %s HP" % get_heal_text())
	if draw > 0:
		parts.append("Draw %d" % draw)
	if discard > 0:
		parts.append("Discard %d at random" % discard)
	var extra := get_extra_text()
	if not extra.is_empty():
		parts.append_array(extra.split("\n"))
	var sentence := ". ".join(parts)
	if not critical.is_empty():
		sentence += ". Critical: " + critical
	if not get_keyword_text().is_empty():
		sentence = get_keyword_text() + ". " + sentence  # e.g. "Wild. Deal d6 damage."
	return sentence + "." if not sentence.is_empty() else ""


# Effects that have no symbol on the card get a short line of text instead,
# e.g. "Next Attack +3" or "Lose 2 HP". (Attack, Block, Draw, Discard and Heal
# are shown as symbols by card.gd. The Critical gets its own line on the card.)
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
	if not next_roll_bonus.is_empty():
		lines.append("Next roll +%s" % next_roll_bonus)
	if gain_advantage:
		lines.append("Gain Advantage")
	if reroll > 0:
		lines.append("Re-roll %d card%s" % [reroll, "" if reroll == 1 else "s"])
	return "\n".join(lines)


# The card's keywords as text, e.g. "Wild · Vanish". "" if it has none.
func get_keyword_text() -> String:
	var words: Array[String] = []
	if wild and has_dice():
		words.append("Wild")  # Wild only means something on a card with dice.
	if advantage and not disadvantage:
		words.append("Adv")
	if disadvantage and not advantage:
		words.append("Disadv")
	if vanish:
		words.append("Vanish")
	return " · ".join(words)


# Does this card roll its dice as soon as you draw it?
# Every dice card does, except Wild ones, which roll when played.
func rolls_on_draw() -> bool:
	return has_dice() and not wild


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
