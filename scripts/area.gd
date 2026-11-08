# area.gd
#
# An Area is one PLACE on the map (the Abandoned Farm, the Forest, the
# Cave...). Each run is an expedition into the place you pick on the map screen.
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
# The area whose boss opens this one, e.g. "Abandoned Farm" for the Forest. Blank = only `unlocked` counts.
@export var unlock_after: String = ""
# true = shown on the map, but not open yet whatever you do: it's still being
# built (the Forest waits until the Farm's new map cards feel right).
@export var coming_later: bool = false
# This area's own material ("Stone"). The map cards' Loot and the monsters'
# Drops (enemies.csv) are what really hand it out.
@export var material: String = ""
@export var sort_order: int = 0  # The order along the road: 0 first.
@export var icon: Texture2D  # The round picture on the map.
@export var background: Texture2D  # The picture behind the fight.
# Where the area's button sits on the map, in pixels from the top-left of the
# 1280 x 720 screen. Its centre goes here.
@export var map_position: Vector2 = Vector2(640, 360)
# The place's MAP CARD sheet (map_cards.gd), e.g.
# "res://data/dungeons/farm_cards.csv". Read when the game runs.
@export var map_card_sheet: String = ""
# The place's PERKS sheet (area_perk.gd): what its Explorer points buy, e.g.
# "res://data/dungeons/farm_perks.csv". Blank = no perks yet.
@export var perk_sheet: String = ""
# BOOSTER: the name on this place's booster packs and cards ("Farm"). A place
# with one has a BINDER of every card its packs can hold (GameState.binder_cards()).
@export var booster: String = ""
# The old room deck (rooms.csv, saved in here by the importer), for places
# without a map card sheet yet.
@export var rooms: Array[RoomCard] = []


# Every map card this place has (each one once; Copies says how many go in the deck).
func cards() -> Array[RoomCard]:
	if not map_card_sheet.is_empty():
		return MapCards.load_sheet(map_card_sheet)
	return rooms
