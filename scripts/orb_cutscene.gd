# orb_cutscene.gd
#
# The end of the first trip (Chapter 1): a short cutscene on the road home.
#   1. The Architect walks home along the road at dusk.
#   2. Slimes ooze in from the right and cut them off. The Architect backs away.
#   3. The orb rises out of their pack, glowing brighter and brighter...
#   4. FLASH! The slimes slither away, and the Architect runs home.
# A caption types along the bottom for each step. Click to skip ahead to the
# end; on_done is called when it's over (dungeon.gd goes back to town).
#
#   OrbCutscene.play(self, noisy, on_done)
class_name OrbCutscene
extends Control

const ARCHITECT := preload("res://art/story/architect.svg")
const SLIME := preload("res://art/enemies/slime.svg")
const ORB := preload("res://art/story/orb.svg")
const GROUND_Y := 470.0  # Where everyone's feet are.

var on_done: Callable
var caption: Label
var stage: Control
var flash: ColorRect
var finished := false


static func play(parent: Node, noisy: bool, done: Callable) -> OrbCutscene:
	var scene := OrbCutscene.new()
	parent.add_child(scene)
	scene._run(noisy, done)
	return scene


func _run(noisy: bool, done: Callable) -> void:
	on_done = done
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sky := ColorRect.new()  # Dusk.
	sky.color = Color(0.16, 0.12, 0.22)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	var road := ColorRect.new()
	road.color = Color(0.32, 0.25, 0.16)
	road.position = Vector2(0, GROUND_Y)
	road.size = Vector2(2000, 400)
	road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(road)
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	flash = ColorRect.new()
	flash.color = Color(1, 0.97, 0.85, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 24)
	caption.anchor_left = 0.1
	caption.anchor_right = 0.9
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = -150
	caption.offset_bottom = -40
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	var hint := Label.new()
	hint.text = "(click to skip)"
	hint.modulate.a = 0.5
	hint.position = Vector2(20, 16)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	# The cast.
	var you := _picture(ARCHITECT, Vector2(110, 165), Vector2(-80, GROUND_Y))
	var slimes: Array[TextureRect] = []
	for i in 3:
		var slime := _picture(SLIME, Vector2(90, 70), Vector2(1400 + i * 110, GROUND_Y))
		slime.modulate = Color(0.6, 1, 0.6)
		slimes.append(slime)
	var orb := _picture(ORB, Vector2(70, 70), Vector2(520, GROUND_Y - 90))
	orb.modulate.a = 0.0
	orb.pivot_offset = orb.size / 2

	var film := create_tween()
	# 1. Walking home.
	film.tween_callback(_say.bind("The road home. Your pack is full, and Kale is going to be so happy..."))
	film.tween_property(you, "position:x", 420.0, 2.6)
	# 2. Slimes!
	film.tween_callback(_say.bind(("All that noise brought them: " if noisy else "Then the ground starts to squelch. ") +
		"SLIMES! They ooze out of the ditches and block the road."))
	for i in slimes.size():
		film.parallel().tween_property(slimes[i], "position:x", 700.0 + i * 110, 1.6).set_trans(Tween.TRANS_SINE)
	film.tween_interval(0.6)
	film.tween_callback(_say.bind("You're an Architect, not a fighter! You back away..."))
	film.tween_property(you, "position:x", 340.0, 0.8)
	film.parallel().tween_property(you, "rotation_degrees", -8.0, 0.8)
	for i in slimes.size():
		film.parallel().tween_property(slimes[i], "position:x", 610.0 + i * 100, 0.8)
	# 3. The orb.
	film.tween_callback(_say.bind("Your pack is getting warm. The mysterious orb floats up out of it... GLOWING."))
	film.tween_property(orb, "modulate:a", 1.0, 0.6)
	film.parallel().tween_property(orb, "position:y", GROUND_Y - 260.0, 1.4).set_trans(Tween.TRANS_SINE)
	film.tween_property(orb, "scale", Vector2(1.8, 1.8), 1.0).set_trans(Tween.TRANS_SINE)
	film.parallel().tween_property(orb, "modulate", Color(1.8, 1.7, 1.2), 1.0)
	# 4. FLASH!
	film.tween_property(flash, "color:a", 1.0, 0.15)
	film.tween_callback(func() -> void:
		for slime in slimes:
			slime.flip_h = true)
	film.tween_property(flash, "color:a", 0.0, 1.0)
	film.tween_callback(_say.bind("The slimes shriek and slither back into the ditches. You don't wait to find out why. RUN!"))
	for i in slimes.size():
		film.parallel().tween_property(slimes[i], "position:x", 1500.0 + i * 100, 1.2).set_ease(Tween.EASE_IN)
	film.parallel().tween_property(orb, "scale", Vector2.ONE, 1.0)
	film.parallel().tween_property(orb, "modulate", Color(1, 1, 1, 0.0), 1.2)
	film.parallel().tween_property(you, "rotation_degrees", 0.0, 0.3)
	film.tween_property(you, "position:x", -200.0, 1.4).set_ease(Tween.EASE_IN)
	film.tween_interval(1.0)
	film.tween_callback(_finish)


# A picture with its feet at `foot`.
func _picture(texture: Texture2D, picture_size: Vector2, foot: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size = picture_size
	picture.position = foot - Vector2(picture_size.x / 2.0, picture_size.y)
	picture.pivot_offset = Vector2(picture_size.x / 2.0, picture_size.y)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(picture)
	return picture


func _say(text: String) -> void:
	caption.text = text
	caption.visible_ratio = 0.0
	create_tween().tween_property(caption, "visible_ratio", 1.0, text.length() / 50.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	if on_done.is_valid():
		on_done.call()
	queue_free()
