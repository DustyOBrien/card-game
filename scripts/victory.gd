# victory.gd
#
# The WIN screen (scenes/victory.tscn): you beat an area's final Boss! It
# celebrates, shows how the run went, and shows the area you just opened
# up on the map. Everything is built here in code.
#
# battle.gd fills in GameState.last_victory before coming here:
#   {"area": Area, "boss": "Slime King", "opened": [Area, ...], "exp": 85}
extends Control

const TOWN_SCENE := "res://scenes/town.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const GOLD := Color(1, 0.84, 0.35)
const CONFETTI_COLORS: Array[Color] = [Color(1, 0.84, 0.35), Color(0.45, 0.75, 1), Color(1, 0.45, 0.45),
	Color(0.55, 0.95, 0.55), Color(0.85, 0.55, 1)]

var title: Label
var panel: PanelContainer


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	var info: Dictionary = GameState.last_victory
	var area: Area = info.get("area", GameState.current_area)
	var dungeon := GameState.dungeon

	# The area's picture behind everything, darkened.
	var background := TextureRect.new()
	background.texture = area.background if area else null
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.modulate = Color(0.45, 0.45, 0.5)
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	center.add_child(layout)

	title = make_label("VICTORY!", 72, GOLD)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.18, 0.02))
	layout.add_child(title)
	var area_name := area.display_name if area else "The dungeon"
	layout.add_child(make_label("You beat %s. The %s is cleared!" % [info.get("boss", "the Boss"), area_name], 24, Color.WHITE))

	# How the run went.
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.92)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	style.shadow_color = Color(1, 0.8, 0.3, 0.35)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(560, 0)
	layout.add_child(panel)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	panel.add_child(stats)
	if dungeon:
		stats.add_child(make_stat("Fights won", str(dungeon.fights_won)))
		stats.add_child(make_stat("Steps walked", str(dungeon.total_steps)))
		stats.add_child(make_stat("Taken home", dungeon.loot_text()))
		if not dungeon.super_cards.is_empty():
			var names: Array[String] = []
			for card in dungeon.super_cards:
				names.append(card.card_name)
			stats.add_child(make_stat("Super cards used", ", ".join(names)))
	stats.add_child(make_stat("Exp", "+%d" % info.get("exp", 0)))

	# The new area: its picture, pulsing.
	var opened: Array = info.get("opened", [])
	var unlock_box := VBoxContainer.new()
	unlock_box.add_theme_constant_override("separation", 4)
	layout.add_child(unlock_box)
	if opened.is_empty():
		unlock_box.add_child(make_label("No new area opened this time. More are coming!", 18, Color(1, 1, 1, 0.7)))
	for new_area: Area in opened:
		unlock_box.add_child(make_label("New area unlocked!", 22, Color(0.55, 0.95, 0.55)))
		var picture := TextureRect.new()
		picture.texture = new_area.icon
		picture.custom_minimum_size = Vector2(0, 96)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		unlock_box.add_child(picture)
		unlock_box.add_child(make_label(new_area.display_name, 28, Color.WHITE))
		unlock_box.add_child(make_label(new_area.description, 15, Color(1, 1, 1, 0.75)))
		picture.pivot_offset = Vector2(picture.size.x / 2, 48)
		var pulse := create_tween().set_loops()
		pulse.bind_node(picture)
		pulse.tween_property(picture, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(picture, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	layout.add_child(buttons)
	var town := Button.new()
	town.text = "Back to Town →"
	town.theme_type_variation = &"PrimaryButton"
	town.custom_minimum_size = Vector2(220, 50)
	town.pressed.connect(func() -> void: get_tree().change_scene_to_file(TOWN_SCENE))
	buttons.add_child(town)
	if not opened.is_empty():
		var map := Button.new()
		map.text = "See the Map"
		map.custom_minimum_size = Vector2(180, 50)
		map.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
		buttons.add_child(map)

	celebrate()


# The title pops in, then confetti rains for a few seconds.
func celebrate() -> void:
	await get_tree().process_frame  # Wait for the layout, so the title knows its size.
	title.pivot_offset = title.size / 2
	title.scale = Vector2(0.2, 0.2)
	title.modulate.a = 0.0
	var pop := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(title, "scale", Vector2.ONE, 0.6)
	pop.tween_property(title, "modulate:a", 1.0, 0.3)
	# A gentle golden glow that keeps breathing.
	var glow := create_tween().set_loops()
	glow.bind_node(title)
	glow.tween_property(title, "self_modulate", Color(1.2, 1.15, 0.9), 0.8)
	glow.tween_property(title, "self_modulate", Color.WHITE, 0.8)
	for color in CONFETTI_COLORS:
		add_child(make_confetti(color))


# One colour of confetti, falling from the whole top edge.
func make_confetti(color: Color) -> CPUParticles2D:
	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(size.x / 2, -20)
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(size.x / 2, 4)
	confetti.amount = 40
	confetti.lifetime = 4.0
	confetti.direction = Vector2(0, 1)
	confetti.spread = 25.0
	confetti.gravity = Vector2(0, 120)
	confetti.initial_velocity_min = 60.0
	confetti.initial_velocity_max = 160.0
	confetti.angular_velocity_min = -360.0
	confetti.angular_velocity_max = 360.0
	confetti.scale_amount_min = 4.0
	confetti.scale_amount_max = 8.0
	confetti.color = color
	confetti.preprocess = 1.5  # Already falling when the screen appears.
	return confetti


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(560, 0)
	return label


# "Fights won ............ 12"
func make_stat(what: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = what
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", GOLD)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.custom_minimum_size = Vector2(300, 0)
	row.add_child(value_label)
	return row
