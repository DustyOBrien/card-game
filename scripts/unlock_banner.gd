# unlock_banner.gd
#
# A big, celebratory "You unlocked something!" screen: the screen dims,
# golden light rays spin behind a picture that pops in, sparkles burst, and
# the title drops in. Used when the first Adventurer arrives and when
# Talents open up.
#
# Use it from any screen:
#   UnlockBanner.show_in(self, "A NEW ADVENTURER!", "The Adventurer", emblem,
#       "Some text...", "Meet the Adventurer", func() -> void: ...)
#
# It draws the rays itself in _draw() (Godot calls _draw() when the node
# needs painting; queue_redraw() asks for it again), so no extra art is needed.
class_name UnlockBanner
extends ColorRect

const GOLD := Color(1, 0.84, 0.35)
const RAY_COUNT := 14
const PICTURE_SIZE := 190.0

var picture_center := Vector2.ZERO  # Where the rays and glow are drawn.
var spin := 0.0  # The rays' angle, turned a little every frame.
var glow := 0.0  # 0 -> 1 as the banner appears.


# Make the banner, add it on top of `parent`, and play the animation.
# `on_done` runs when the button is pressed (after the banner is removed).
# `extra` (optional) goes above the button, e.g. a row of cards. With an
# extra and no picture, there's no star: the words move up to make room.
static func show_in(parent: Node, title: String, subtitle: String, picture: Texture2D,
		text: String, button_text: String, on_done: Callable, extra: Control = null) -> UnlockBanner:
	var banner := UnlockBanner.new()
	parent.add_child(banner)
	banner._build(title, subtitle, picture, text, button_text, on_done, extra)
	return banner


func _build(title: String, subtitle: String, picture: Texture2D, text: String,
		button_text: String, on_done: Callable, extra: Control) -> void:
	color = Color(0, 0, 0, 0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing behind it can be clicked.
	var screen := get_viewport_rect().size
	picture_center = Vector2(screen.x / 2, 250)
	var no_art := picture == null and extra != null
	if no_art:
		picture_center.y = 90  # The light shines behind the title instead.

	# The picture: the class emblem, or a big star if there's no picture.
	var art: Control
	if picture:
		var rect := TextureRect.new()
		rect.texture = picture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art = rect
	else:
		var star := Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", 150)
		star.add_theme_color_override("font_color", GOLD)
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art = star
	art.size = Vector2.ONE * PICTURE_SIZE
	art.position = picture_center - art.size / 2
	art.pivot_offset = art.size / 2
	art.scale = Vector2.ZERO
	art.visible = not no_art
	add_child(art)

	# Sparkles: lots of little gold dots bursting out at once.
	var sparkles := CPUParticles2D.new()
	sparkles.position = picture_center
	sparkles.amount = 70
	sparkles.one_shot = true
	sparkles.explosiveness = 0.95
	sparkles.lifetime = 1.6
	sparkles.direction = Vector2.UP
	sparkles.spread = 180
	sparkles.initial_velocity_min = 180
	sparkles.initial_velocity_max = 420
	sparkles.gravity = Vector2(0, 260)
	sparkles.scale_amount_min = 3
	sparkles.scale_amount_max = 7
	sparkles.color = GOLD
	sparkles.emitting = false
	add_child(sparkles)

	# The words, in a column under the picture.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.position = Vector2(screen.x / 2 - 360, 40 if no_art else picture_center.y + PICTURE_SIZE / 2 + 16)
	column.custom_minimum_size = Vector2(720, 0)
	column.modulate.a = 0
	add_child(column)
	var heading := _label(title, 46, GOLD)
	heading.add_theme_color_override("font_outline_color", Color(0.35, 0.2, 0))
	heading.add_theme_constant_override("outline_size", 10)
	column.add_child(heading)
	if not subtitle.is_empty():
		column.add_child(_label(subtitle, 24, Color.WHITE))
	column.add_child(_label(text, 17, Color(1, 1, 1, 0.85)))
	if extra:
		column.add_child(extra)
	var button := Button.new()
	button.text = button_text
	button.theme_type_variation = &"PrimaryButton"
	button.custom_minimum_size = Vector2(260, 50)
	button.add_theme_font_size_override("font_size", 20)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void:
		queue_free()
		on_done.call())
	column.add_child(button)

	# The animation, step by step. A Tween changes a property smoothly over time.
	var tween := create_tween()
	tween.tween_property(self, "color:a", 0.85, 0.35)  # Dim the screen...
	tween.parallel().tween_property(self, "glow", 1.0, 0.6)  # ...while the light grows.
	# The picture pops in, overshooting a little (TRANS_BACK) so it bounces.
	tween.tween_property(art, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_callback(func() -> void: sparkles.emitting = true)
	# Then the words slide up into place.
	column.position.y += 30
	tween.tween_property(column, "modulate:a", 1.0, 0.4)
	tween.parallel().tween_property(column, "position:y", column.position.y - 30, 0.4)
	# The picture keeps gently "breathing" afterwards.
	var breathe := art.create_tween().set_loops()
	breathe.tween_property(art, "scale", Vector2.ONE * 1.06, 0.9).set_delay(1.0)
	breathe.tween_property(art, "scale", Vector2.ONE, 0.9)


func _label(text: String, font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _process(delta: float) -> void:
	spin += delta * 0.4  # Slowly turn the rays.
	queue_redraw()


# The spinning rays and the glow behind the picture.
func _draw() -> void:
	if glow <= 0.0:
		return
	var length := 520.0 * glow
	for i in RAY_COUNT:
		var angle := spin + TAU * i / RAY_COUNT
		var half := TAU / RAY_COUNT / 4  # Each ray is a thin wedge.
		var points := PackedVector2Array([picture_center,
			picture_center + Vector2.from_angle(angle - half) * length,
			picture_center + Vector2.from_angle(angle + half) * length])
		draw_colored_polygon(points, Color(GOLD, 0.13 * glow))
	# A soft glow: circles that get fainter as they get bigger.
	for ring in 6:
		draw_circle(picture_center, (60 + ring * 28) * glow, Color(GOLD, 0.07 * glow))
