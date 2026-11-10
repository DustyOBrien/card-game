# chapter_card.gd
#
# A CHAPTER TITLE CARD: the screen goes black, "CHAPTER 1" fades in, then
# its name ("The Inn") underneath, like the start of a chapter in a book.
# Click (or wait a few seconds) and it fades away.
#
#   ChapterCard.show_in(self, "CHAPTER 1", "The Inn", on_done)
class_name ChapterCard
extends Control

const HOLD_TIME := 3.0  # Seconds before it goes on by itself.
const GOLD := Color(1, 0.84, 0.35)

var on_done: Callable
var leaving := false


static func show_in(parent: Node, chapter: String, title: String, done: Callable) -> ChapterCard:
	var card := ChapterCard.new()
	parent.add_child(card)
	card._build(chapter, title, done)
	return card


func _build(chapter: String, title: String, done: Callable) -> void:
	on_done = done
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var small := _label(chapter, 34, GOLD)
	var big := _label(title, 72, Color.WHITE)
	var line := ColorRect.new()  # A thin gold line between them.
	line.color = GOLD
	line.custom_minimum_size = Vector2(320, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(small)
	column.add_child(line)
	column.add_child(big)
	for part: Control in [small, line, big]:
		part.modulate.a = 0.0
	var appear := create_tween()
	appear.tween_interval(0.4)
	appear.tween_property(small, "modulate:a", 1.0, 0.8)
	appear.tween_property(line, "modulate:a", 1.0, 0.4)
	appear.tween_property(big, "modulate:a", 1.0, 1.0)
	appear.tween_interval(HOLD_TIME)
	appear.tween_callback(_leave)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_leave()


func _leave() -> void:
	if leaving:
		return
	leaving = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.6)
	fade.tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call())
	fade.tween_callback(queue_free)
