# encounter.gd
#
# An Encounter is the group of enemies in ONE fight, e.g. two Slimelings.
# Areas hold a list of them (see area.gd): fight 1 uses the first one,
# fight 2 the second, and so on. Click an area in Godot (areas/plains.tres)
# to see and change its encounters in the Inspector.
class_name Encounter
extends Resource

# The enemies, left to right. The same enemy can be in the list more than once.
@export var enemies: Array[EnemyData] = []
