# map.gd
#
# The map (scenes/map.tscn), between the deck builder and the battle.
# Pick an area to start a run there. Locked areas are shown, but greyed out.
#
# The map picture is just a background (art/map/world_map.svg). The round
# area buttons are built here in code, one per file in areas/, and placed at
# each area's map_position. So a new area shows up on its own.
extends Control

const BATTLE_SCENE := "res://scenes/battle.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
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
	gold_label.text = "Gold %d" % GameState.gold
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
	var status := make_label("Open: 5 fights" if area.unlocked else "Locked", 15)
	marker.add_child(status)

	if area.unlocked:
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
		if not area.unlocked:
			info_label.text += "  (Locked)"
	else:
		info_label.text = "Choose where to adventure."


func _on_area_chosen(area: Area) -> void:
	GameState.current_area = area
	GameState.start_run()  # Fight 1 of a new run, at full HP.
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_deck_pressed() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)
