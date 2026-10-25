# health_bar.gd
#
# The enemy's health bar, drawn with code in _draw() (like the dice).
#
#   [ red = HP left | dark = HP lost ]   "17 / 20" written on top
#
# Extras:
#   - When the enemy takes damage, the lost part flashes yellow and then
#     shrinks away, so you can see how big the hit was.
#   - While you drag an attack, set_preview() shows what it would do:
#       bright, blinking = HP the attack will surely take
#       striped          = HP it MIGHT take, depending on the dice
#   - Block shows as a blue shield with its number on the left.
class_name HealthBar
extends Control

const BAR_COLOR := Color(0.85, 0.2, 0.2)
const BACK_COLOR := Color(0.1, 0.08, 0.1, 0.85)
const EDGE_COLOR := Color(0.05, 0.05, 0.08)
const TRAIL_COLOR := Color(1.0, 0.8, 0.3)  # The bit just lost, before it shrinks away.
const SURE_COLOR := Color(1, 0.95, 0.55)  # Preview: damage the attack will surely do.
const MAYBE_COLOR := Color(1, 0.6, 0.6)  # Preview: damage it might do.
const BLOCK_COLOR := Color(0.45, 0.65, 1.0)
const FONT_SIZE := 18

var max_value := 1
var value := 1
var block := 0
var trail_value := 1.0  # Where the yellow "just lost" part ends. Shrinks down to `value`.
var preview_low := -1  # HP left after the BIGGEST possible hit. -1 = no preview.
var preview_high := -1  # HP left after the smallest possible hit.
var preview_text := ""  # e.g. "17 → 12–15"
var trail_tween: Tween


# Update the numbers. Losing HP starts the yellow trail animation.
func set_values(new_value: int, new_max: int, new_block: int) -> void:
	var lost := new_value < value
	if new_max != max_value or new_value > value:
		trail_value = new_value  # New fight or healing: no trail.
	max_value = maxi(new_max, 1)
	value = new_value
	block = new_block
	if lost:
		if trail_tween:
			trail_tween.kill()
		trail_tween = create_tween()
		# Wait a moment, then shrink the trail down to the new HP.
		trail_tween.tween_interval(0.25)
		trail_tween.tween_property(self, "trail_value", float(value), 0.4)
		trail_tween.tween_callback(queue_redraw)
	queue_redraw()


# Show what an attack would do: the HP left after the biggest and the
# smallest hit (the same number if the dice already rolled).
func set_preview(low: int, high: int, text: String) -> void:
	preview_low = low
	preview_high = high
	preview_text = text
	queue_redraw()


func clear_preview() -> void:
	if preview_low == -1:
		return
	preview_low = -1
	preview_high = -1
	queue_redraw()


func _process(_delta: float) -> void:
	# Keep redrawing while something moves: the blinking preview or the trail.
	if preview_low != -1 or trail_value > value:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BACK_COLOR)

	# The trail first, so the red bar draws over its left part.
	if trail_value > value:
		draw_rect(_part(value, trail_value), TRAIL_COLOR)

	if preview_low == -1:
		draw_rect(_part(0, value), BAR_COLOR)
	else:
		# Red for the HP that's safe whatever the dice roll...
		draw_rect(_part(0, preview_low), BAR_COLOR)
		# ...stripes for the HP it might take...
		var maybe := _part(preview_low, preview_high)
		draw_rect(maybe, BAR_COLOR.darkened(0.3))
		var x := maybe.position.x - size.y
		while x < maybe.end.x:
			var a := Vector2(maxf(x, maybe.position.x), size.y)
			var b := Vector2(minf(x + size.y, maybe.end.x), 0)
			draw_line(a, b, MAYBE_COLOR, 3.0)
			x += 9
		# ...and a bright blinking part for the HP it will surely take.
		var blink := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 120.0)
		draw_rect(_part(preview_high, value), Color(SURE_COLOR, blink))

	draw_rect(rect, EDGE_COLOR, false, 3.0)  # Outline.

	# The numbers, in the middle.
	var text := preview_text if preview_low != -1 else "%d / %d" % [value, max_value]
	var font := get_theme_default_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var baseline := Vector2((size.x - text_size.x) / 2, size.y / 2 + FONT_SIZE * 0.36)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 5, EDGE_COLOR)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)

	if block > 0:
		_draw_block(Vector2(-4, size.y / 2))


# The part of the bar between two HP values, as a rectangle.
func _part(from: float, to: float) -> Rect2:
	var x1 := size.x * clampf(from / max_value, 0, 1)
	var x2 := size.x * clampf(to / max_value, 0, 1)
	return Rect2(x1, 0, maxf(x2 - x1, 0), size.y)


# A little shield with the Block number, sitting on the bar's left end.
func _draw_block(center: Vector2) -> void:
	var r := size.y * 0.75
	var shield := PackedVector2Array([
		center + Vector2(-r, -r), center + Vector2(r, -r),
		center + Vector2(r, 0.1 * r), center + Vector2(0, r * 1.1), center + Vector2(-r, 0.1 * r)])
	draw_colored_polygon(shield, BLOCK_COLOR)
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_polyline(outline, EDGE_COLOR, 2.5, true)
	var font := get_theme_default_font()
	var text := str(block)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(font, center + Vector2(-text_size.x / 2, FONT_SIZE * 0.3), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, EDGE_COLOR)
