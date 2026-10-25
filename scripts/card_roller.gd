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
static func roll(card: CardData) -> Dictionary:
	var raw := {}
	var formulas := card.get_formulas()
	for key in formulas:
		raw[key] = Dice.roll_dice(formulas[key])
	return raw


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
#   lines:  the working, for the dice display, e.g. "Hit 1: [3] + 1 = 4  CRIT!"
static func resolve(card: CardData, raw: Dictionary, bonuses: Dictionary) -> Dictionary:
	var result := {"hits": [], "block": 0, "heal": 0, "draw": 0, "energy": 0, "crits": 0, "lines": []}
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
		for value: int in values:
			total += value
			if value + modifier >= dice.sides:  # Top number reached (modifiers count).
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

		if not values.is_empty():
			result.lines.append(_describe(card, key, values, modifier, crit_bonus, total, crits))

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
	return modifier


# "Hit 1: [3] + 1 + 1 crit = 5  CRIT!"
static func _describe(card: CardData, key: String, values: Array, modifier: int,
		crit_bonus: int, total: int, crits: int) -> String:
	var name := "Attack"
	if key.begins_with("attack") and card.attack.size() > 1:
		name = "Hit %d" % (key.get_slice(" ", 1).to_int() + 1)
	elif key == "block":
		name = "Block"
	elif key == "heal":
		name = "Heal"
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
