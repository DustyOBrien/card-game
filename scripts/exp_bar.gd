# exp_bar.gd
#
# A class's Exp bar, drawn with code in _draw() (like the health bar).
#
#   (Lv 3)[ purple = Exp so far | dark = still to go ]  "40 / 200 Exp" on top
#
# Use it in two ways:
#   show_class(the_class)  just shows where that class is now.
#   play_gain(...)          animates Exp filling in after a fight, including
#                           wrapping round to an empty bar on a level up.
class_name ExpBar
extends Control

signal leveled_up(level: int)  # Emitted during play_gain() each time the bar fills up.

const BAR_COLOR := Color(0.62, 0.45, 0.95)
const SHINE_COLOR := Color(1, 1, 1, 0.18)  # The lighter top half of the bar.
const BACK_COLOR := Color(0.1, 0.08, 0.14, 0.9)
const EDGE_COLOR := Color(0.05, 0.05, 0.08)
const BADGE_COLOR := Color(1, 0.85, 0.3)  # The gold "Lv 3" circle.
const FONT_SIZE := 14
const FILL_TIME := 0.6  # Seconds to fill a whole bar.

var level := 1
var current := 0.0  # Exp into this level. A float so a Tween can slide it.
var needed := 1  # Exp this level needs. 0 = max level.
var gain_text := ""  # e.g. "+10 Exp", shown on the right while animating.


func show_class(character_class: CharacterClass) -> void:
	level = GameState.class_level(character_class)
	var progress := GameState.class_exp_progress(character_class)
	current = progress.x
	needed = progress.y
	queue_redraw()


# Animate from where the class WAS (before_level, before_progress) to where it
# is now. `await` this to wait for the bar to stop.
func play_gain(character_class: CharacterClass, before_level: int, before_progress: Vector2i, amount: int) -> void:
	level = before_level
	current = before_progress.x
	needed = before_progress.y
	gain_text = "+%d Exp" % amount
	var target_level := GameState.class_level(character_class)
	var target := GameState.class_exp_progress(character_class)
	while level < target_level:
		# Fill this level up to the end, then start the next one from empty.
		await _slide_to(needed)
		level += 1
		current = 0
		needed = GameState.exp_for_next_level(level) if level < GameState.CLASS_MAX_LEVEL else 0
		leveled_up.emit(level)
		_pop()
	await _slide_to(target.x)
	needed = target.y


func _slide_to(value: float) -> void:
	if needed <= 0:
		return
	var tween := create_tween()
	var time := FILL_TIME * absf(value - current) / needed
	tween.tween_method(func(v: float) -> void:
		current = v
		queue_redraw(), current, value, maxf(time, 0.05))
	await tween.finished


# A little bounce on level up.
func _pop() -> void:
	pivot_offset = size / 2
	scale = Vector2(1.06, 1.3)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _draw() -> void:
	var font := get_theme_default_font()
	var radius := size.y * 0.7  # A bit taller than the bar, like a coin on the end.
	var bar := Rect2(radius, 0, size.x - radius, size.y)

	draw_rect(bar, BACK_COLOR)
	var fraction := 1.0 if needed <= 0 else clampf(current / needed, 0, 1)
	var filled := Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y))
	draw_rect(filled, BAR_COLOR)
	draw_rect(Rect2(filled.position, Vector2(filled.size.x, filled.size.y / 2)), SHINE_COLOR)
	draw_rect(bar, EDGE_COLOR, false, 2.0)

	# The numbers, in the middle of the bar.
	var text := "Max level" if needed <= 0 else "%d / %d Exp" % [roundi(current), needed]
	if not gain_text.is_empty():
		text += "   " + gain_text
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var baseline := Vector2(bar.position.x + (bar.size.x - text_size.x) / 2, size.y / 2 + FONT_SIZE * 0.36)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, EDGE_COLOR)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)

	# The gold level badge on the left end.
	var center := Vector2(radius, size.y / 2)
	draw_circle(center, radius, BADGE_COLOR)
	draw_arc(center, radius, 0, TAU, 32, EDGE_COLOR, 2.0, true)
	var level_text := str(level)
	var level_size := 13 if level < 10 else 11
	var level_text_size := font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_size)
	draw_string(font, center + Vector2(-level_text_size.x / 2, level_size * 0.36), level_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, level_size, EDGE_COLOR)
