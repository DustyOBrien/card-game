# enemy_data.gd
#
# An EnemyData describes ONE kind of enemy: its name, HP, moves and picture.
# Like cards, each one is a .tres file, in the enemies/ folder.
#
# Enemies come from spreadsheets, like cards do (see card_importer.gd):
#   data/enemies/enemies.csv     one row per enemy: HP, Armor, art, boss...
#   data/enemies/moves.csv       one row per MOVE: which enemy, what it does
#   data/enemies/encounters.csv  which enemies are in each fight of each area
# Run tools/import_cards.gd after changing them.
class_name EnemyData
extends Resource

enum MoveOrder { RANDOM, IN_ORDER }

@export var display_name: String = "Enemy"
@export var max_hp: int = 20
@export var armor: int = 0  # Saves up to this much leftover Block each turn (see combatant.gd).
@export var texture: Texture2D  # Its picture.
@export var sprite_size: Vector2 = Vector2(160, 120)  # How big the picture is drawn, in pixels.
@export var name_color: Color = Color(0.55, 0.95, 0.55)  # Colour of its name on screen.

@export_group("Moves")
@export var moves: Array[EnemyMove] = []
# RANDOM: pick a move by weight each turn. IN_ORDER: move 1, 2, 3, then
# back to 1 (bosses: you can learn the pattern).
@export var move_order: MoveOrder = MoveOrder.RANDOM
# Used only if it has no moves: a plain attack between these.
@export var attack_min: int = 2
@export var attack_max: int = 5

@export_group("Split")
# When it drops to half HP or less, it splits on its next turn into
# split_count of these enemies, each with the HP it had left.
@export var split_into: String = ""  # An enemy name, e.g. "Slime". Blank = never splits.
@export var split_count: int = 2

@export_group("Rewards")
@export var is_boss: bool = false  # Beating an area's boss opens the next area.
@export var exp: int = 10  # Class Exp for beating it.
@export var bonus_gold: int = 0  # Extra gold on top of the usual 1-5.


# The plain attack for enemies with no moves (and for old enemy files).
func default_move() -> EnemyMove:
	var move := EnemyMove.new()
	move.move_name = "Attack"
	move.attack_min = attack_min
	move.attack_max = attack_max
	return move
