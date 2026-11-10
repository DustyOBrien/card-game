# map.gd
#
# The map (scenes/map.tscn), between town and the Prepare Expedition screen.
# Pick an area to get ready for a run there. Locked areas are shown, but greyed out.
#
# The map picture is just a background (art/map/world_map.svg). The round
# area buttons are built here in code, one per file in areas/, and placed at
# each area's map_position. So a new area shows up on its own.
extends Control

const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"
const PREPARE_SCENE := "res://scenes/prepare.tscn"
const MAP_DECK_SCENE := "res://scenes/map_deck.tscn"
const LOCK_ICON := preload("res://art/map/lock.svg")

const BUTTON_SIZE := Vector2(110, 110)  # The round area pictures.
const HOVER_SCALE := 1.12
const INK := Color(0.23, 0.16, 0.08)  # Dark brown, like ink on the old map.
const LOCKED_TINT := Color(0.45, 0.42, 0.4)

@onready var areas_layer: Control = %AreasLayer
@onready var info_label: Label = %InfoLabel
@onready var gold_label: Label = %GoldLabel
@onready var deck_button: Button = %DeckButton


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	deck_button.pressed.connect(_on_deck_pressed)
	deck_button.visible = GameState.adventurers_here()  # No deck to edit until an adventurer arrives.
	# A Town button next to Edit Deck (restore buildings, buy potions...).
	var town_button := Button.new()
	town_button.text = "Town"
	town_button.custom_minimum_size = Vector2(120, 48)
	town_button.add_theme_font_size_override("font_size", 20)
	town_button.position = deck_button.position + (Vector2(deck_button.size.x + 12, 0) if deck_button.visible else Vector2.ZERO)
	town_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TOWN_SCENE))
	add_child(town_button)
	gold_label.text = "Coins %d" % GameState.gold
	for area in GameState.load_areas():
		areas_layer.add_child(make_area_marker(area))


# One area on the map: its round picture (a button), its name, and a line
# saying whether it's open.
func make_area_marker(area: Area) -> Control:
	var marker := VBoxContainer.new()
	marker.add_theme_constant_override("separation", 2)
	marker.alignment = BoxContainer.ALIGNMENT_CENTER

	# A TextureButton is a button made of a picture instead of a box.
	var button := TextureButton.new()
	button.texture_normal = area.icon
	button.custom_minimum_size = BUTTON_SIZE
	button.ignore_texture_size = true  # Shrink the picture to BUTTON_SIZE...
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED  # ...without squashing it.
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pivot_offset = BUTTON_SIZE / 2  # Grow from the middle when hovered.
	button.mouse_entered.connect(_on_area_hovered.bind(area, button, true))
	button.mouse_exited.connect(_on_area_hovered.bind(area, button, false))
	marker.add_child(button)

	marker.add_child(make_label(area.display_name, 26))
	var open := GameState.is_area_unlocked(area)
	var status_text := "Open"
	if open and GameState.is_guided_run(area):
		status_text = "Your first trip"
	elif GameState.cleared_areas.has(area.display_name):
		status_text = "Cleared ✓"  # You've beaten its boss (you can still go back).
	elif area.coming_later:
		status_text = "Coming later"  # Not on the new map cards yet.
	elif not open and not GameState.adventurers_here():
		status_text = "Build the Inn in town first"
	elif not open:
		status_text = "Beat the %s boss" % area.unlock_after if not area.unlock_after.is_empty() else "Locked"
	var status := make_label(status_text, 15)
	marker.add_child(status)

	if open:
		button.pressed.connect(_on_area_chosen.bind(area))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		button.disabled = true
		button.modulate = LOCKED_TINT  # Grey out the picture...
		var lock := TextureRect.new()  # ...and put a padlock on it.
		lock.texture = LOCK_ICON
		lock.custom_minimum_size = Vector2(44, 44)
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.position = BUTTON_SIZE - Vector2(44, 44)  # Bottom-right corner of the picture.
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(lock)
		status.modulate.a = 0.7

	# Centre the marker on the area's map_position. reset_size() shrinks the
	# marker to fit its contents, so we know how big it is.
	marker.reset_size()
	marker.position = area.map_position - Vector2(marker.size.x / 2, BUTTON_SIZE.y / 2)
	return marker


func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	# A light outline, like the labels on a hand-drawn map.
	label.add_theme_color_override("font_outline_color", Color(0.96, 0.9, 0.75))
	label.add_theme_constant_override("outline_size", 6)
	return label


# Pointing at an area: grow it a little, and show its description at the bottom.
func _on_area_hovered(area: Area, button: TextureButton, hovered: bool) -> void:
	var target := HOVER_SCALE if hovered and not button.disabled else 1.0
	create_tween().tween_property(button, "scale", Vector2.ONE * target, 0.1)
	if hovered:
		info_label.text = "%s: %s" % [area.display_name, area.description]
		if GameState.is_area_unlocked(area) and GameState.is_guided_run(area):
			info_label.text += "  (Your first trip: Kale's supplies. No monsters this close to town, they say...)"
		elif area.coming_later:
			pass  # Its description already says "Coming later".
		elif not GameState.adventurers_here():
			info_label.text += "  (Build the Inn in town first!)"
		elif not GameState.is_area_unlocked(area):
			info_label.text += "  (Locked: beat the %s boss to open it)" % area.unlock_after \
				if not area.unlock_after.is_empty() else "  (Locked)"
	else:
		info_label.text = "Choose where to adventure."


# The first trip (Chapter 1) goes to the map deck screen first, where Kale
# shows you the Farm's cards. Every other trip goes through Prepare Expedition.
func _on_area_chosen(area: Area) -> void:
	GameState.current_area = area
	if GameState.is_guided_run(area):
		# Chapter 1: Kale shows you the map deck first (map_deck.gd starts the trip).
		get_tree().change_scene_to_file(MAP_DECK_SCENE)
	else:
		get_tree().change_scene_to_file(PREPARE_SCENE)


func _on_deck_pressed() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)
