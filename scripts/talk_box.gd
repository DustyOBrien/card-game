# talk_box.gd
#
# A person TALKING to you: a speech box along the bottom of the screen, with
# their picture and name, their words typed out, and a button to go on.
# Dusty's playtest: the start had too many big "UNLOCKED!" banners. Now the
# story is told by the people in it (Kale), and the big banners
# (unlock_banner.gd) are kept for the really big moments.
#
#   TalkBox.show_in(self, "Kale", INN_ICON, ["Line one.", "Line two."], "Okay!", on_done)
#
# Each line is one "page": the button says "..." until the last page, which
# gets button_text. A click while the words are still typing just finishes
# them, so nobody skips a line by accident.
class_name TalkBox
extends Control

const TYPE_SPEED := 60.0  # Letters per second.
const NAME_COLOR := Color(1, 0.84, 0.35)

var pages: Array = []
var page := 0
var last_button := "OK"
var on_done: Callable
var words: Label
var button: Button
var typing: Tween


static func show_in(parent: Node, speaker: String, picture: Texture2D, lines: Array, button_text: String,
		done: Callable) -> TalkBox:
	var box := TalkBox.new()
	parent.add_child(box)
	box._build(speaker, picture, lines, button_text, done)
	return box


func _build(speaker: String, picture: Texture2D, lines: Array, button_text: String, done: Callable) -> void:
	pages = lines
	last_button = button_text
	on_done = done
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing behind it can be clicked while someone's talking.
	var shade := ColorRect.new()  # Darken the screen a little, so the words stand out.
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.1, 0.07, 0.97)
	style.border_color = Color(0.62, 0.46, 0.24)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	# Along the bottom of the screen, 900 wide.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -450
	panel.offset_right = 450
	panel.offset_top = -230
	panel.offset_bottom = -24
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	if picture:
		var face := TextureRect.new()
		face.texture = picture
		face.custom_minimum_size = Vector2(120, 120)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(face)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)
	var name_label := Label.new()
	name_label.text = speaker
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	column.add_child(name_label)
	words = Label.new()
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_vertical = Control.SIZE_EXPAND_FILL
	words.add_theme_font_size_override("font_size", 19)
	column.add_child(words)
	button = Button.new()
	button.custom_minimum_size = Vector2(170, 42)
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.theme_type_variation = &"PrimaryButton"
	button.pressed.connect(_on_button)
	column.add_child(button)

	# Slide up from below.
	panel.modulate.a = 0.0
	panel.position.y += 40
	var slide := create_tween().set_parallel()
	slide.tween_property(panel, "modulate:a", 1.0, 0.2)
	slide.tween_property(panel, "position:y", panel.position.y - 40, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_page()


func _show_page() -> void:
	var line: String = pages[page] if page < pages.size() else ""
	words.text = line
	words.visible_ratio = 0.0
	button.text = last_button if page >= pages.size() - 1 else "..."
	typing = create_tween()
	typing.tween_property(words, "visible_ratio", 1.0, maxf(line.length() / TYPE_SPEED, 0.1))


func _on_button() -> void:
	if typing and typing.is_running():
		typing.kill()  # Still typing: just show the whole line.
		words.visible_ratio = 1.0
		return
	page += 1
	if page < pages.size():
		_show_page()
		return
	queue_free()
	if on_done.is_valid():
		on_done.call()
