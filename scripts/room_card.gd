# room_card.gd
#
# One card in an area's ROOM DECK. When you step onto a blank square in the
# dungeon, you draw a room card, and that's what the square turns out to be:
# a fight, a locked chest, a campfire...
#
# Room cards come from the spreadsheet data/dungeons/rooms.csv, which the
# importer saves into each area's file (areas/plains.tres -> Rooms).
class_name RoomCard
extends Resource

# (New types go on the END: room files store the number, so the order must not change.)
enum Type { FIGHT, HARD_FIGHT, LOCKED_CHEST, TREASURE, CAMPFIRE, MINI_BOSS, BOSS, EMPTY, EVENT }

# What each type is called in the sheet's Type column, and on screen.
const TYPE_NAMES := {
	Type.FIGHT: "Fight",
	Type.HARD_FIGHT: "Hard Fight",
	Type.LOCKED_CHEST: "Locked Chest",
	Type.TREASURE: "Treasure",
	Type.CAMPFIRE: "Campfire",
	Type.MINI_BOSS: "Mini Boss",
	Type.BOSS: "Boss",
	Type.EMPTY: "Empty",
	Type.EVENT: "Event",  # A random event from data/dungeons/events.csv (see dungeon_event.gd).
}

@export var room_name: String = "Room"
@export var type: Type = Type.EMPTY
# Which tier of the dungeon it belongs to. Tier 1 cards are in the deck from
# the start; beating a Mini Boss shuffles in the next tier. 0 = the Boss room,
# which only goes in after the last tier's Mini Boss.
@export var tier: int = 1
@export var copies: int = 1  # How many of this card go in the deck.
# false = you need to find a Map in a chest before this card goes in the deck.
@export var unlocked: bool = true
# Fights only. true = an AMBUSH: the fight starts the moment you find it, no
# backing off. Other fights show you the enemies first, and you choose to
# Fight or Back off to the square you came from.
@export var ambush: bool = false
# Fights: the enemy groups it can be. One is picked at random each time.
@export var encounters: Array[Encounter] = []
# What you find: one entry is picked at random, e.g. ["Gold 5-10", "Card", "Pack"].
# Chests and Treasure always have loot. A fight's loot is a bonus for winning.
# Words the game knows: Gold N-M, Card, Pack, Map, Key.
@export var loot: PackedStringArray = []


func is_fight() -> bool:
	return type in [Type.FIGHT, Type.HARD_FIGHT, Type.MINI_BOSS, Type.BOSS]


func type_name() -> String:
	return TYPE_NAMES[type]


# A random enemy group for this fight (empty if it isn't a fight).
func pick_encounter() -> Array[EnemyData]:
	var enemies: Array[EnemyData] = []
	if not encounters.is_empty():
		enemies.assign(encounters.pick_random().enemies)
	return enemies
