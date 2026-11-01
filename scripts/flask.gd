# flask.gd
#
# A FLASK is like a potion you always own. You pick ONE to take into each
# run (in town), it has charges (sips) that come back when you Rest at a
# campfire, and you can upgrade it at the Alchemist.
#
# Flasks come from data/progression/flasks.csv -> flasks/*.tres. The sheet
# has one row per STAGE:
#   - "Base" rows say what the flask does before any upgrades (Heal Die 3,
#     Charges 1...). The first Base row's Cost is what unlocking it costs
#     (0 = you start with it).
#   - Every other row is one stage of an upgrade. Rows with the same Upgrade
#     name are one upgrade, bought in order (Bigger Die: d6, then d8).
#
# What a flask does right now is worked out by stats(): start from the Base
# rows, then add every stage you've bought.
class_name Flask
extends Resource

# Effect names, as written in the sheet's Effect column.
const HEAL_DIE := "heal die"  # Heal one die of this size (3 = d3). Bigger stages REPLACE it.
const ENERGY := "energy"  # Gain this much Energy.
const CHARGES := "charges"  # Sips per rest.
const ROLL_BONUS := "roll bonus"  # +this to the heal roll.
const SAVE_CHANCE := "save chance"  # % chance a sip doesn't use up a charge.
const EFFECTS := [HEAL_DIE, ENERGY, CHARGES, ROLL_BONUS, SAVE_CHANCE]
const BASE := "Base"

@export var flask_name: String = "Flask"
@export_multiline var description: String = ""
@export var color: Color = Color(0.9, 0.3, 0.3)  # The liquid's colour.
@export var sort_order: int = 0
@export var unlock_cost: int = 0  # Gold to brew it.
@export var unlock_materials: String = ""  # Materials to brew it: "Green Ooze 3".


# Free to unlock (no gold, no materials) = you start with it.
func starts_unlocked() -> bool:
	return unlock_cost == 0 and unlock_materials.strip_edges().is_empty()

# One entry per sheet row (Base rows included), in sheet order.
@export var upgrade_names: PackedStringArray = []  # "Base", "Bigger Die"...
@export var costs: Array[int] = []
@export var effects: PackedStringArray = []
@export var amounts: Array[int] = []
@export var stage_texts: PackedStringArray = []


# The upgrade names, in sheet order, without "Base": ["Bigger Die", "Extra Charge"...].
func upgrades() -> PackedStringArray:
	var names := PackedStringArray()
	for upgrade in upgrade_names:
		if upgrade != BASE and not names.has(upgrade):
			names.append(upgrade)
	return names


# The rows (indexes into the arrays above) of one upgrade's stages, in order.
func stages_of(upgrade: String) -> Array[int]:
	var rows: Array[int] = []
	for i in upgrade_names.size():
		if upgrade_names[i] == upgrade:
			rows.append(i)
	return rows


# What the flask does, given the stages you've bought: {"Bigger Die": 2, ...}.
# Returns {"heal die": 6, "energy": 0, "charges": 2, "roll bonus": 1, "save chance": 0}.
func stats(bought: Dictionary) -> Dictionary:
	var result := {HEAL_DIE: 0, ENERGY: 0, CHARGES: 0, ROLL_BONUS: 0, SAVE_CHANCE: 0}
	for i in upgrade_names.size():
		var upgrade := upgrade_names[i]
		if upgrade != BASE and stages_of(upgrade).find(i) >= int(bought.get(upgrade, 0)):
			continue  # Not bought (yet).
		var effect := effects[i]
		if effect == HEAL_DIE:
			result[HEAL_DIE] = maxi(result[HEAL_DIE], amounts[i])  # d6 replaces d3.
		elif result.has(effect):
			result[effect] += amounts[i]  # Everything else adds up.
	result[CHARGES] = maxi(result[CHARGES], 1)
	return result


# "Heal d6+1 · Gain 1 Energy · 10% chance to keep the charge" (no charges: they're shown apart).
static func effect_text(stats: Dictionary) -> String:
	var parts: Array[String] = []
	if stats[HEAL_DIE] > 0:
		parts.append("Heal d%d%s" % [stats[HEAL_DIE], ("+%d" % stats[ROLL_BONUS]) if stats[ROLL_BONUS] > 0 else ""])
	if stats[ENERGY] > 0:
		parts.append("Gain %d Energy" % stats[ENERGY])
	if stats[SAVE_CHANCE] > 0:
		parts.append("%d%% chance to keep the charge" % stats[SAVE_CHANCE])
	return " · ".join(parts)
