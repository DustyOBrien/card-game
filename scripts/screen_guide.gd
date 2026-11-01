# screen_guide.gd
#
# A step-by-step GUIDE for a screen: it dims the screen, draws a glowing gold
# box around one part of it, and explains that part in a small panel with a
# Next button. Used the first time you open the Deck Builder.
#
#   ScreenGuide.start(self, "deck_builder", [
#       {"target": title_label, "text": "This is your class..."},
#       {"target": pool_grid, "text": "These are your cards..."},
#   ])
#
# Each guide only shows once: its name goes into GameState.seen_guides.
class_name ScreenGuide
extends Control

const GOLD := Color(1, 0.84, 0.35)
const PANEL_WIDTH := 400.0

var steps: Array = []
var step := 0
var guide_name := ""
var panel: PanelContainer
var text_label: Label
var next_button: Button
var glow := 0.0  # Pulses the box's brightness (see _process).


# Show the guide on `screen` unless it was seen before. Returns it (or null).
static func start(screen: Control, name: String, guide_steps: Array) -> ScreenGuide:
	if GameState.seen_guides.has(name) or guide_steps.is_empty():
		return null
	var guide := ScreenGuide.new()
	guide.guide_name = name
	guide.steps = guide_steps
	screen.add_child(guide)
	guide._build.call_deferred()  # After the screen has laid itself out (sizes are known).
	return guide


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # Read first, then play.
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.07, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 17)
	# A wrapping Label has no width of its own, so give it one; otherwise it
	# wraps every word onto its own line and the panel grows very tall.
	text_label.custom_minimum_size.x = PANEL_WIDTH - 28
	box.add_child(text_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var skip := Button.new()
	skip.text = "Skip guide"
	skip.pressed.connect(_finish)
	buttons.add_child(skip)
	next_button = Button.new()
	next_button.theme_type_variation = &"PrimaryButton"
	next_button.custom_minimum_size = Vector2(120, 40)
	next_button.pressed.connect(_on_next)
	buttons.add_child(next_button)
	_show_step()


func _show_step() -> void:
	var info: Dictionary = steps[step]
	text_label.text = "%s\n\n(%d / %d)" % [info.text, step + 1, steps.size()]
	next_button.text = "Next →" if step < steps.size() - 1 else "Got it!"
	panel.modulate.a = 0
	# Wait one frame so the panel knows its new height, then place it.
	await get_tree().process_frame
	panel.size = Vector2(PANEL_WIDTH, 0)
	panel.reset_size()
	# Put the panel next to the box: below it if there's room, else above,
	# kept on screen.
	var box_rect := target_rect()
	var screen := get_viewport_rect().size
	var where := Vector2(box_rect.position.x, box_rect.end.y + 14)
	if where.y + panel.size.y > screen.y - 10:
		where.y = box_rect.position.y - panel.size.y - 14
	if where.y < 10:  # A tall target: sit inside it, at the top.
		where.y = box_rect.position.y + 20
	where.x = clampf(where.x, 10, screen.x - panel.size.x - 10)
	panel.position = where
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)
	queue_redraw()


# The part of the screen this step is about, a little bigger than it.
func target_rect() -> Rect2:
	var target: Control = steps[step].target
	return target.get_global_rect().grow(6) if is_instance_valid(target) else Rect2(get_viewport_rect().size / 2, Vector2.ZERO)


func _on_next() -> void:
	step += 1
	if step >= steps.size():
		_finish()
	else:
		_show_step()


func _finish() -> void:
	if not GameState.seen_guides.has(guide_name):
		GameState.seen_guides.append(guide_name)
		GameState.save_game()
	queue_free()


func _process(delta: float) -> void:
	glow += delta * 3.0
	queue_redraw()


# Dim everything except the box, then draw the glowing gold border.
func _draw() -> void:
	if steps.is_empty() or panel == null:
		return
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var hole := target_rect()
	var dim := Color(0, 0, 0, 0.55)
	# Four dark rectangles around the hole (above, below, left, right).
	draw_rect(Rect2(0, 0, screen.size.x, hole.position.y), dim)
	draw_rect(Rect2(0, hole.end.y, screen.size.x, screen.size.y - hole.end.y), dim)
	draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), dim)
	draw_rect(Rect2(hole.end.x, hole.position.y, screen.size.x - hole.end.x, hole.size.y), dim)
	var pulse := 0.6 + 0.4 * sin(glow)
	draw_rect(hole, Color(GOLD, pulse), false, 3.0)
	draw_rect(hole.grow(4), Color(GOLD, pulse * 0.35), false, 4.0)
