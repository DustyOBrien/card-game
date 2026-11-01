# encounter.gd
#
# An Encounter is the group of enemies in ONE fight, e.g. two Slimelings.
# Fight room cards (room_card.gd) hold a list of them and pick one at random.
class_name Encounter
extends Resource

# The enemies, left to right. The same enemy can be in the list more than once.
@export var enemies: Array[EnemyData] = []
