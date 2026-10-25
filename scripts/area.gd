# area.gd
#
# An Area is one place on the map (Plains, Forest, Cave...). Each run is
# fought in the area you pick on the map screen.
#
# Like cards and classes, an area is a Resource: one .tres file per area in
# the areas/ folder. To ADD AN AREA, duplicate areas/forest.tres in Godot's
# FileSystem panel and change it in the Inspector. The map shows every
# area it finds in that folder.
class_name Area
extends Resource

@export var display_name: String = "New Area"
@export_multiline var description: String = ""  # Shown when you point at it on the map.
@export var unlocked: bool = false  # Locked areas show on the map but can't be picked.
@export var sort_order: int = 0  # The order along the road: 0 first.
@export var icon: Texture2D  # The round picture on the map.
@export var background: Texture2D  # The picture behind the fight.
# Where the area's button sits on the map, in pixels from the top-left of the
# 1280 x 720 screen. Its centre goes here.
@export var map_position: Vector2 = Vector2(640, 360)
