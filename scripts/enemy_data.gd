# enemy_data.gd
#
# An EnemyData describes ONE kind of enemy: its name, HP, attacks and picture.
# Like cards, classes and areas, each one is a .tres file, in the enemies/
# folder. To ADD AN ENEMY, duplicate enemies/slime.tres in Godot's FileSystem
# panel and change it in the Inspector. Then put it in an area's encounters
# (see area.gd) so it shows up in fights.
class_name EnemyData
extends Resource

@export var display_name: String = "Enemy"
@export var max_hp: int = 20
@export var armor: int = 0  # Saves up to this much leftover Block each turn (see combatant.gd).
@export var attack_min: int = 2  # Each turn it attacks for a random amount between these.
@export var attack_max: int = 5
@export var texture: Texture2D  # Its picture.
@export var sprite_size: Vector2 = Vector2(160, 120)  # How big the picture is drawn, in pixels.
@export var name_color: Color = Color(0.55, 0.95, 0.55)  # Colour of its name on screen.
