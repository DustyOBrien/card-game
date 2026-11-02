# enemy_move.gd
#
# One thing an enemy can do on its turn: "Bite: attack for 2-3, twice" or
# "Harden: gain 5 Block". An enemy has a list of moves (see enemy_data.gd)
# and picks one at the start of your turn, so you can see it coming: that's
# its INTENT, shown under its health bar.
#
# Moves come from the spreadsheet data/enemies/moves.csv (one row per move),
# which the importer turns into these. A move can do several things at once:
# "Attack 4 + Block 3" is one move with both an attack and a block.
class_name EnemyMove
extends Resource

@export var move_name: String = "Attack"
# How likely this move is, compared with the enemy's other moves. Weights
# 2 and 1 mean the first move is picked twice as often. (Only for enemies
# that pick at random. Bosses usually go In Order instead.)
@export var weight: int = 1
# The most times in a row it may pick this move. 0 = no limit.
# 1 = never twice in a row (good for Block and buff moves).
@export var max_in_a_row: int = 0

@export_group("What it does")
@export var attack_min: int = 0  # Damage per hit: a random amount between these.
@export var attack_max: int = 0  # (0 and 0 = no attack.)
@export var hits: int = 1  # Attacks this many times (each hit goes through your Block on its own).
@export var block: int = 0  # Block for itself.
@export var strength: int = 0  # +this to all its attacks for the rest of the fight (a buff).
@export var heal: int = 0  # HP back for itself.
@export var ally_block: int = 0  # Block for every OTHER enemy.
@export var ally_strength: int = 0  # Strength for EVERY enemy, itself included (a war cry).
@export var summon: String = ""  # The name of an enemy it calls in ("Slimeling").
@export var summon_count: int = 0  # How many it calls in (never more than MAX_ENEMIES on screen).


func attacks() -> bool:
	return attack_max > 0


# What kind of intent this is, for its colour on screen.
func kind() -> String:
	if attacks():
		return "attack"
	if block > 0 or ally_block > 0:
		return "block"
	if not summon.is_empty():
		return "summon"
	return "buff"


# The move written out with its ranges, for the Dojo's monster book:
# "Attack 5-7 x2 + Block 3". (In a fight, enemy_view.gd shows the exact roll.)
func describe() -> String:
	var parts: Array[String] = []
	if attacks():
		var damage := str(attack_min) if attack_min == attack_max else "%d-%d" % [attack_min, attack_max]
		parts.append("Attack " + damage + (" x%d" % hits if hits > 1 else ""))
	if block > 0:
		parts.append("Block %d" % block)
	if ally_block > 0:
		parts.append("Shield allies %d" % ally_block)
	if strength > 0:
		parts.append("Strength +%d" % strength)
	if ally_strength > 0:
		parts.append("All Strength +%d" % ally_strength)
	if heal > 0:
		parts.append("Heal %d" % heal)
	if not summon.is_empty():
		parts.append("Summon %s" % summon + (" x%d" % summon_count if summon_count > 1 else ""))
	return " + ".join(parts) if not parts.is_empty() else "Does nothing"
