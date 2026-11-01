# town_road.gd
#
# The road out of town, at the bottom-right of the town screen: a dirt road
# winding off into the distance, with a wooden signpost that says
# "To the Map". Click it to head out (town.gd sends you to the map).
#
# Everything is drawn with code in _draw() (like die_view.gd), so it needs
# no art. It works like a button: it has a `pressed` signal, and it glows
# when the mouse is over it.
class_name TownRoad
extends Control

signal pressed

const ROAD_COLOR := Color(0.55, 0.42, 0.26)
const ROAD_EDGE := Color(0.38, 0.28, 0.16)
const GRASS := Color(0.32, 0.5, 0.25)
const WOOD := Color(0.5, 0.33, 0.17)
const WOOD_DARK := Color(0.33, 0.21, 0.1)
const SIGN_TEXT := Color(1, 0.93, 0.75)

var hovered := false
var is_open := true  # false = greyed out ("the road opens soon").
var sway := 0.0  # The sign rocks a tiny bit while you hover it.


func _init() -> void:
	custom_minimum_size = Vector2(300, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: hovered = true)
	mouse_exited.connect(func() -> void:
		hovered = false
		sway = 0.0
		queue_redraw())


# Open (you can go) or closed (greyed out, with a tooltip saying why).
func set_open(open: bool) -> void:
	is_open = open
	tooltip_text = "Head out to the map and pick a dungeon." if open else "Follow your quest: the road opens soon."
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_ARROW
	modulate = Color.WHITE if open else Color(0.55, 0.55, 0.55)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if is_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func _process(delta: float) -> void:
	if hovered and is_open:
		sway += delta * 4.0
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# A patch of grass for the road to run through.
	draw_rect(Rect2(0, h * 0.25, w, h * 0.75), GRASS.darkened(0.15))
	draw_rect(Rect2(0, h * 0.25, w, 3), GRASS.lightened(0.15))
	# The road: wide at the bottom-left, narrowing as it goes off to the right
	# (that's what makes it look like it's going into the distance).
	var road := PackedVector2Array([
		Vector2(w * 0.05, h), Vector2(w * 0.55, h),
		Vector2(w * 0.97, h * 0.3), Vector2(w * 0.86, h * 0.3)])
	draw_colored_polygon(road, ROAD_COLOR.lightened(0.12) if hovered and is_open else ROAD_COLOR)
	draw_polyline(PackedVector2Array([road[0], road[3]]), ROAD_EDGE, 3.0)
	draw_polyline(PackedVector2Array([road[1], road[2]]), ROAD_EDGE, 3.0)
	# Wheel ruts down the middle.
	for i in 4:
		var t := float(i) / 4.0
		var a := road[0].lerp(road[1], 0.5).lerp(road[3].lerp(road[2], 0.5), t)
		var b := road[0].lerp(road[1], 0.5).lerp(road[3].lerp(road[2], 0.5), t + 0.12)
		draw_line(a, b, ROAD_EDGE.lerp(ROAD_COLOR, 0.5), 3.0 - t * 2.0)

	# The signpost: a post and an arrow-shaped board pointing down the road.
	var post_x := w * 0.3
	draw_rect(Rect2(post_x - 4, h * 0.2, 8, h * 0.8), WOOD_DARK)
	var tilt := sin(sway) * 0.03 if hovered and is_open else 0.0
	draw_set_transform(Vector2(post_x, h * 0.32), tilt)
	var board := PackedVector2Array([
		Vector2(-70, -20), Vector2(110, -20), Vector2(132, 0), Vector2(110, 20), Vector2(-70, 20)])
	draw_colored_polygon(board, WOOD.lightened(0.1) if hovered and is_open else WOOD)
	board.append(board[0])
	draw_polyline(board, WOOD_DARK, 3.0)
	var font := get_theme_default_font()
	var text := "To the Map"
	var font_size := 22
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(20 - text_width / 2, 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SIGN_TEXT)
	draw_set_transform(Vector2.ZERO)
