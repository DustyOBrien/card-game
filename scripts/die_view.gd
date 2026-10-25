# die_view.gd
#
# One die on screen. There's no picture file: the die draws itself in
# _draw(), Godot's way of letting a node paint shapes and text with code.
#
# The shape tells you the die at a glance, like real tabletop dice:
#   d3 = triangle,  d4 = diamond,  d6 = square,  anything else = hexagon.
# A die that crits turns gold and gets a glowing ring.
#
# Godot calls _draw() once, and again whenever we call queue_redraw()
# (for example after changing the number). Drawing commands like
# draw_colored_polygon() only work inside _draw().
class_name DieView
extends Control

const SIZE := 60.0  # Normal width and height in pixels (the dice tray).
const FACE_COLOR := Color(0.96, 0.93, 0.86)  # Ivory, like a real die.
const EDGE_COLOR := Color(0.12, 0.1, 0.14)
const TEXT_COLOR := Color(0.12, 0.1, 0.14)
const CRIT_FACE_COLOR := Color(1.0, 0.8, 0.3)  # Gold.
const CRIT_EDGE_COLOR := Color(0.85, 0.3, 0.1)
const GLOW_COLOR := Color(1.0, 0.6, 0.2, 0.35)

# @export so that duplicate() copies them too (the dragged card is a copy).
@export var sides := 6
@export var value := 1
@export var is_crit := false
@export var die_size := SIZE  # Smaller dice sit on the cards in your hand.


# DieView.new(30) makes a 30 pixel die. Leave the number out for a normal one.
func _init(new_size: float = SIZE) -> void:
	die_size = new_size
	custom_minimum_size = Vector2(die_size, die_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(die_size, die_size) / 2  # Spin around the middle, not the corner.


# Change what the die shows, then ask Godot to draw it again.
func show_value(new_value: int, crit: bool = false) -> void:
	value = new_value
	is_crit = crit
	queue_redraw()


func _draw() -> void:
	var center := Vector2(die_size, die_size) / 2
	var points := _shape_points(center, die_size * 0.46)
	if is_crit:
		draw_circle(center, die_size * 0.56, GLOW_COLOR)  # Soft glow behind the die.

	draw_colored_polygon(points, CRIT_FACE_COLOR if is_crit else FACE_COLOR)
	# A closed outline: the polyline goes round the shape and back to the start.
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, CRIT_EDGE_COLOR if is_crit else EDGE_COLOR, maxf(die_size / 20, 1.5), true)

	# The number in the middle. A triangle's middle is lower down, so nudge it.
	var font := get_theme_default_font()
	var font_size := roundi(die_size * 0.43)  # 26 on a normal die.
	var text := str(value)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var nudge := die_size * 0.1 if sides == 3 else 0.0
	var baseline := center + Vector2(-text_size.x / 2, font_size * 0.36 + nudge)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)


# The corners of the die's shape, going round the centre.
func _shape_points(center: Vector2, radius: float) -> PackedVector2Array:
	var corners := 6  # Hexagon for d8, d10, d12, d20...
	var start_angle := -PI / 2  # First corner straight up.
	match sides:
		3:
			corners = 3
		4:
			corners = 4
		6:
			corners = 4
			start_angle = -PI / 4  # Turn the diamond 45° so it's a square.
			radius *= 1.3  # A square looks small next to a triangle, so grow it a bit.
	var points := PackedVector2Array()
	for i in corners:
		var angle := start_angle + TAU * i / corners  # TAU = a full turn (2 × PI).
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	if sides == 3:
		# Triangles look high up in the box, so move it down a little.
		for i in points.size():
			points[i].y += radius * 0.18
	return points
