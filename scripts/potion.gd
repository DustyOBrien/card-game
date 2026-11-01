# potion.gd
#
# A POTION is a one-use item you drink during a fight (click it, on your
# turn). Fights sometimes drop one, and the Alchemist in town sells them.
# You can carry a few (DungeonRun.potion_slots()); they're gone when the run ends.
#
# Potions come from data/progression/potions.csv -> potions/*.tres.
class_name Potion
extends Resource

@export var potion_name: String = "Potion"
@export_multiline var description: String = ""
@export var rarity: CardData.Rarity = CardData.Rarity.COMMON
@export var color: Color = Color(0.9, 0.3, 0.3)  # The liquid's colour.

@export_group("What it does")
@export var heal: int = 0  # HP back.
@export var block: int = 0  # Block for you.
@export var energy: int = 0  # Energy this turn.
@export var draw: int = 0  # Cards drawn.
@export var damage: int = 0  # Damage to EVERY enemy.
@export var advantage: bool = false  # Your next roll has Advantage.
@export var roll_bonus: int = 0  # +this to your next roll.


# "Heal 8 · Block 5": what it does, short (for its tooltip).
func effect_text() -> String:
	var parts: Array[String] = []
	if heal > 0: parts.append("Heal %d" % heal)
	if block > 0: parts.append("Block %d" % block)
	if energy > 0: parts.append("+%d Energy" % energy)
	if draw > 0: parts.append("Draw %d" % draw)
	if damage > 0: parts.append("%d damage to every enemy" % damage)
	if advantage: parts.append("Next roll has Advantage")
	if roll_bonus > 0: parts.append("Next roll +%d" % roll_bonus)
	return " · ".join(parts)


static func pick_random(from: Array[Potion]) -> Potion:
	if from.is_empty():
		return null
	var total := 0
	for potion in from:
		total += Enchant.RARITY_WEIGHTS[potion.rarity]
	var roll := randi_range(1, total)
	for potion in from:
		roll -= Enchant.RARITY_WEIGHTS[potion.rarity]
		if roll <= 0:
			return potion
	return from[-1]
