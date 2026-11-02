# area.gd
#
# An Area is one place on the map (Plains, Forest, Cave...). Each run is a
# trip into the dungeon of the area you pick on the map screen.
#
# Like cards and classes, an area is a Resource: one .tres file per area in
# the areas/ folder. To ADD AN AREA, duplicate areas/forest.tres in Godot's
# FileSystem panel and change it in the Inspector. The map shows every
# area it finds in that folder.
class_name Area
extends Resource

@export var display_name: String = "New Area"
@export_multiline var description: String = ""  # Shown when you point at it on the map.
@export var unlocked: bool = false  # Open from the start? Locked areas show on the map but can't be picked.
# The area whose boss opens this one, e.g. "Plains" for the Forest. Blank = only `unlocked` counts.
@export var unlock_after: String = ""
# This area's own material ("Stone"): it turns up on explored squares now
# and then (see dungeon_run.gd). Monsters can drop it too (enemies.csv Drops).
@export var material: String = ""
@export var sort_order: int = 0  # The order along the road: 0 first.
@export var icon: Texture2D  # The round picture on the map.
@export var background: Texture2D  # The picture behind the fight.
# Where the area's button sits on the map, in pixels from the top-left of the
# 1280 x 720 screen. Its centre goes here.
@export var map_position: Vector2 = Vector2(640, 360)
# The area's room cards (see room_card.gd and dungeon_run.gd), from the
# spreadsheet data/dungeons/rooms.csv. Every tier's cards are in here.
@export var rooms: Array[RoomCard] = []
