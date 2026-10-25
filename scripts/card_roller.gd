# card_roller.gd
#
# Works out what a card does when it's played: rolls its dice, adds the
# modifiers, and checks for Criticals.
#
# THE CRITICAL RULE: a die that reaches its top number is a Critical, and
# modifiers count. So on a d3, a 3 is a crit, and with +1 a 2 is a crit too
# (2 + 1 = 3). Every die checks on its own: Multi Strike rolls two d3s, so it
# can crit twice, and each crit applies the card's Critical effect once.
#
# Rolling happens in two steps, so "roll when drawn" works:
#   1. roll()     rolls the bare dice, e.g. {"attack 0": [2]}. Saved on the card.
#   2. resolve()  adds modifiers and crits at the moment you PLAY the card.
#      A bonus you got after drawing (like Master of None's +1) still counts.
class_name CardRoller
extends RefCounted


# Step 1: roll every die on the card, with no modifiers.
# {"attack 0": [3], "attack 1": [1], "block": [2]}
# `mode` is ADVANTAGE (roll each die twice, keep the higher), DISADVANTAGE
# (keep the lower) or NORMAL. The dice thrown away go in card.dropped_dice,
# so the dice tray can show them.
const NORMAL := 0
const ADVANTAGE := 1
const DISADVANTAGE := -1

static func roll(card: CardData, mode: int = NORMAL) -> Dictionary:
	var raw := {}
	card.dropped_dice = {}
	var formulas := card.get_formulas()
	for key in formulas:
		raw[key] = Dice.roll_dice(formulas[key])
		if mode != NORMAL and not raw[key].is_empty():
			_keep_best(card, raw, key, Dice.roll_dice(formulas[key]), mode)
	return raw


# Advantage or Disadvantage for this card right now? `pending_advantage` is
# true if an earlier card (Insight) gave your next roll Advantage.
# Advantage and Disadvantage together cancel out.
static func mode_for(card: CardData, pending_advantage: bool) -> int:
	var has_advantage := card.advantage or pending_advantage
	if has_advantage and not card.disadvantage:
		return ADVANTAGE
	if card.disadvantage and not has_advantage:
		return DISADVANTAGE
	return NORMAL


# Advantage gained AFTER a card already rolled (it rolled when you drew it):
# roll a second set of dice now and keep the higher of each pair.
static func add_advantage(card: CardData) -> void:
	var formulas := card.get_formulas()
	card.dropped_dice = {}
	for key in card.roll_result:
		if not card.roll_result[key].is_empty():
			_keep_best(card, card.roll_result, key, Dice.roll_dice(formulas[key]), ADVANTAGE)


# Compare two rolls of the same dice, die by die. Keep the higher (Advantage)
# or lower (Disadvantage) in `raw`, and remember the other in dropped_dice.
static func _keep_best(card: CardData, raw: Dictionary, key: String, second: Array[int], mode: int) -> void:
	var kept: Array[int] = []
	var dropped: Array[int] = []
	for i in raw[key].size():
		var a: int = raw[key][i]
		var b: int = second[i]
		var a_wins := a >= b if mode == ADVANTAGE else a <= b
		kept.append(a if a_wins else b)
		dropped.append(b if a_wins else a)
	raw[key] = kept
	card.dropped_dice[key] = dropped


# Every die showing its lowest (1) or highest number. Used to preview a card's
# range before it rolls: resolve() this and you get the worst / best case.
static func fixed_roll(card: CardData, highest: bool) -> Dictionary:
	var raw := {}
	var formulas := card.get_formulas()
	for key in formulas:
		var dice := Dice.parse(formulas[key])
		var values: Array[int] = []
		if not dice.is_empty():
			for i in dice.count:
				values.append(dice.sides if highest else 1)
		raw[key] = values
	return raw


# Step 2: what the card does with these dice.
# `bonuses` holds the bonuses waiting in the battle right now:
#   {"roll": next roll bonus, "attack": next attack bonus, "defense": next defense bonus}
# Returns:
#   hits:   damage of each hit, e.g. [4, 1]
#   block, heal, draw, energy: totals, crits included
#   crits:  how many dice crit
#   lines:  the working as text, for the battle log, e.g. "Hit 1: [3] + 1 = 4  CRIT!"
#   roll_bonus: the bonus for your next roll (Pump Up, Master of None)
#   advantage:  crits that say "Gain Advantage";  keep: crits that say "Dont Vanish"
#   rolls:  the same working as data, for the dice tray (dice_tray.gd), one per roll:
#           {name, sides, dice, dropped, crit_dice, modifier, crit_bonus, total, crits}
static func resolve(card: CardData, raw: Dictionary, bonuses: Dictionary) -> Dictionary:
	var result := {"hits": [], "block": 0, "heal": 0, "draw": 0, "energy": 0, "crits": 0,
		"roll_bonus": 0, "advantage": 0, "keep": 0, "lines": [], "rolls": []}
	var crit_effects := card.get_critical_effects()
	var formulas := card.get_formulas()
	var extra_damage := 0  # Crit damage from a die that isn't an attack die.

	for key: String in formulas:
		var dice := Dice.parse(formulas[key])
		if dice.is_empty():
			continue
		var values: Array = raw.get(key, [])

		# Everything added to this roll. All of it counts towards a crit.
		var modifier: int = dice.bonus + _modifier_for(card, key, bonuses)

		var total := modifier
		var crits := 0
		var crit_dice: Array[bool] = []  # Which of the dice crit, for the dice tray.
		for value: int in values:
			total += value
			var is_crit: bool = value + modifier >= dice.sides  # Top number reached (modifiers count).
			crit_dice.append(is_crit)
			if is_crit:
				crits += 1

		# Crit effects that add to THIS roll: +Damage on an attack, +Block on a block...
		var crit_bonus := 0
		var kind := key.get_slice(" ", 0)  # "attack 0" -> "attack"
		if kind == "attack":
			crit_bonus = crits * crit_effects.get("damage", 0)
		else:
			crit_bonus = crits * crit_effects.get(kind, 0)
			extra_damage += crits * crit_effects.get("damage", 0)
		total = maxi(total + crit_bonus, 0)

		# ...and effects that go to the whole card (or to a different kind of roll).
		result.crits += crits
		result.draw += crits * crit_effects.get("draw", 0)
		result.energy += crits * crit_effects.get("energy", 0)
		result.advantage += crits * crit_effects.get("advantage", 0)  # "Gain Advantage"
		result.keep += crits * crit_effects.get("keep", 0)  # "Dont Vanish"
		if kind != "block":
			result.block += crits * crit_effects.get("block", 0)
		if kind != "heal":
			result.heal += crits * crit_effects.get("heal", 0)

		match kind:
			"attack":
				result.hits.append(total)
			"block":
				result.block += total
			"heal":
				result.heal += total
			"roll":
				result.roll_bonus += total  # Pump Up: the bonus for your next roll.

		if not values.is_empty():
			var name := _roll_name(card, key)
			result.lines.append(_describe(name, values, modifier, crit_bonus, total, crits))
			result.rolls.append({"name": name, "kind": kind, "sides": dice.sides, "dice": values,
				"dropped": card.dropped_dice.get(key, []),
				"crit_dice": crit_dice, "modifier": modifier, "crit_bonus": crit_bonus,
				"total": total, "crits": crits})

	if extra_damage > 0 and not result.hits.is_empty():
		result.hits[0] += extra_damage
	return result


# Total damage of all hits.
static func total_damage(result: Dictionary) -> int:
	var total := 0
	for hit: int in result.hits:
		total += hit
	return total


# The bonuses that apply to one roll on the card.
static func _modifier_for(card: CardData, key: String, bonuses: Dictionary) -> int:
	var modifier := 0
	if card.has_dice():
		modifier += bonuses.get("roll", 0)  # Next roll bonus: every die of a card that rolls.
	if key.begins_with("attack"):
		modifier += card.attack_modifier
		if card.has_type(CardData.CardType.ATTACK):
			modifier += bonuses.get("attack", 0)  # Rage-style bonus, on every hit.
	elif key == "block":
		modifier += card.block_modifier
		if card.has_type(CardData.CardType.DEFENSE):
			modifier += bonuses.get("defense", 0)
	elif key == "heal":
		modifier += card.heal_modifier
	return modifier


# "attack 1" -> "Hit 2" (or just "Attack" for a single hit), "block" -> "Block".
static func _roll_name(card: CardData, key: String) -> String:
	if key == "roll bonus":
		return "Next roll"
	if key.begins_with("attack") and card.attack.size() > 1:
		return "Hit %d" % (key.get_slice(" ", 1).to_int() + 1)
	return key.get_slice(" ", 0).capitalize()


# "Hit 1: [3] + 1 + 1 crit = 5  CRIT!"
static func _describe(name: String, values: Array, modifier: int,
		crit_bonus: int, total: int, crits: int) -> String:
	var text := "%s: %s" % [name, " ".join(values.map(func(v): return "[%d]" % v))]
	if modifier > 0:
		text += " + %d" % modifier
	elif modifier < 0:
		text += " - %d" % -modifier
	if crit_bonus > 0:
		text += " + %d crit" % crit_bonus
	text += " = %d" % total
	if crits > 0:
		text += "  CRIT!" if crits == 1 else "  CRIT x%d!" % crits
	return text
