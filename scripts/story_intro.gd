# story_intro.gd
#
# The story cutscene (scenes/story_intro.tscn), shown once at the very start of
# a new game, before the town's welcome (town.gd show_welcome()).
#
# It's a "slideshow" of panels. Each panel puts some pictures on the screen,
# animates them with tweens, and types out a line of narration at the bottom.
# Click (or press Space / Enter) to move on. A click while the text is still
# typing just finishes the text, so nobody skips a panel by accident.
# The Skip button jumps straight to the town.
#
# Everything is built in code here (like character_select.gd), so the .tscn is
# just one empty Control with this script on it.
#
# To change the story: edit the panels list and the panel_* functions below.
# Each panel_* function sets up the pictures for one panel.
extends Control

const TOWN_SCENE := "res://scenes/town.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"

const BACKGROUND := preload("res://art/town/town_background.svg")
const RUINS := preload("res://art/town/ruins.svg")
const GUILD_HALL := preload("res://art/town/guild_hall.svg")
const KING := preload("res://art/story/king.svg")
const DARK_WIZARD := preload("res://art/story/dark_wizard.svg")
const ARCHITECT := preload("res://art/story/architect.svg")
# The thriving town's buildings, left to right. The Guild Hall is in the
# middle, because it's the one that survives.
const TOWN_ROW := [
	preload("res://art/town/inn.svg"),
	preload("res://art/town/shop.svg"),
	preload("res://art/town/alchemist.svg"),
	GUILD_HALL,
	preload("res://art/town/tailor.svg"),
	preload("res://art/town/enchanter.svg"),
	preload("res://art/town/dojo.svg"),
]
const GUILD_HALL_SLOT := 3  # Where the Guild Hall is in TOWN_ROW.
const BUILDING_SIZE := 140.0
const ROW_Y := 300.0  # Top of the row of buildings.

const TYPE_SPEED := 45.0  # Letters per second for the narration.
const FADE_TIME := 0.4  # Black fade between panels (each way).

# One entry per panel: the function that sets it up, and its narration.
# (A Callable is a function stored in a variable, so it can go in a list.)
var panels: Array = []


func make_panels() -> Array:
	return [
	[panel_thriving, "Long ago, in the heart of the Kingdom, stood the greatest town of all. Its markets were loud, its halls were full, and its adventurers were the bravest in the land."],
	[panel_attack, "Then the DARK WIZARD came. In one night of storm and fire, he tore the whole area to the ground."],
	[panel_ruins, "When the smoke cleared, the town lay in ruins. Only the old Guild Hall was still standing."],
	[panel_architects, "The King sent architect after architect to rebuild it. Every single one of them failed."],
	[panel_until_you, ""],
	]

var panel_index := -1
var busy := false  # True while fading between panels: clicks are ignored.
var replay := false  # True if the story was already seen (the Story button replays it).

var background: TextureRect
var stage: Control  # Holds the current panel's pictures; emptied for each new panel.
var tint: ColorRect  # Darkens the whole picture (the wizard's night).
var flash: ColorRect  # White lightning flashes.
var fader: ColorRect  # Black, for fading between panels.
var caption_box: PanelContainer
var caption: Label
var big_text: Label  # The big centred "Until you..." line.
var hint: Label
var text_tween: Tween
var loops: Array[Tween] = []  # Looping tweens of the current panel, stopped when it ends.


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	replay = GameState.story_beats.has(GameState.STORY_INTRO)
	panels = make_panels()
	# Let clicks fall through every picture to _unhandled_input() below.
	# (Controls "eat" mouse clicks unless their mouse_filter says IGNORE.)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_screen()
	next_panel()


func build_screen() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	background = TextureRect.new()
	background.texture = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	tint = make_overlay(Color(0.12, 0.02, 0.2, 0.0))
	flash = make_overlay(Color(1, 1, 1, 0.0))

	# The narration box along the bottom.
	caption_box = PanelContainer.new()
	caption_box.custom_minimum_size = Vector2(900, 0)
	caption_box.position = Vector2((1280 - 900) / 2.0, 560)
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.05, 0.04, 0.08, 0.85)
	box_style.border_color = Color(0.85, 0.7, 0.35)
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(10)
	box_style.set_content_margin_all(18)
	caption_box.add_theme_stylebox_override("panel", box_style)
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption_box)
	caption = Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 22)
	caption.custom_minimum_size = Vector2(864, 66)
	caption_box.add_child(caption)

	big_text = Label.new()
	big_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_text.offset_bottom = -300
	big_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	big_text.add_theme_font_size_override("font_size", 64)
	big_text.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	big_text.add_theme_color_override("font_outline_color", Color.BLACK)
	big_text.add_theme_constant_override("outline_size", 10)
	big_text.visible = false
	add_child(big_text)

	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	add_child(hint)

	fader = make_overlay(Color(0, 0, 0, 1.0))  # Starts black, fades in on the first panel.

	var skip := Button.new()
	skip.text = "Skip  >>"
	skip.tooltip_text = "Skip the story and go to the town."
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip.pressed.connect(finish)
	add_child(skip)


# A full-screen coloured sheet that clicks go straight through.
func make_overlay(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


# Clicks and keys anywhere (except on the Skip button, which takes its own click).
func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton  # null if it isn't a mouse button.
	var clicked := mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if clicked or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		advance()


func advance() -> void:
	if busy:
		return
	# Still typing? Show the whole line first.
	if text_tween and text_tween.is_running():
		text_tween.kill()
		caption.visible_ratio = 1.0
		big_text.visible_ratio = 1.0
		text_done()
		return
	next_panel()


func next_panel() -> void:
	panel_index += 1
	if panel_index >= panels.size():
		finish()
		return
	busy = true
	hint.text = ""
	# Fade to black (not on the first panel: the screen starts black).
	if panel_index > 0:
		await create_tween().tween_property(fader, "color:a", 1.0, FADE_TIME).finished
	clear_stage()
	var setup: Callable = panels[panel_index][0]
	setup.call()
	await create_tween().tween_property(fader, "color:a", 0.0, FADE_TIME).finished
	busy = false
	var line: String = panels[panel_index][1]
	caption_box.visible = line != ""
	if line != "":
		type_out(caption, line)


# Type a line out letter by letter: tween visible_ratio from 0 to 1.
func type_out(label: Label, line: String, speed := TYPE_SPEED) -> void:
	label.text = line
	label.visible_ratio = 0.0
	text_tween = create_tween()
	text_tween.tween_property(label, "visible_ratio", 1.0, line.length() / speed)
	text_tween.finished.connect(text_done)


func text_done() -> void:
	var last := panel_index == panels.size() - 1
	hint.text = "Click to begin" if last else "Click to continue"


# Empty the stage and reset the overlays for a new panel.
func clear_stage() -> void:
	for loop in loops:
		loop.kill()
	loops.clear()
	for child in stage.get_children():
		child.queue_free()
	tint.color.a = 0.0
	flash.color.a = 0.0
	background.modulate = Color.WHITE
	background.visible = true
	big_text.visible = false


# A picture on the stage, with its bottom-middle at `foot` (so pictures of
# different heights all stand on the same ground).
func add_picture(texture: Texture2D, size: Vector2, foot: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size = size
	picture.position = foot - Vector2(size.x / 2.0, size.y)
	picture.pivot_offset = Vector2(size.x / 2.0, size.y)  # Scale and turn from the feet.
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(picture)
	return picture


# A tween that repeats until the panel ends.
func make_loop() -> Tween:
	var loop := create_tween().set_loops()
	loops.append(loop)
	return loop


# The row of buildings. `ruined` swaps all but the Guild Hall for ruins.
func add_town_row(ruined: bool) -> Array[TextureRect]:
	var row: Array[TextureRect] = []
	var gap := 1280.0 / TOWN_ROW.size()
	for i in TOWN_ROW.size():
		var texture: Texture2D = TOWN_ROW[i]
		if ruined and i != GUILD_HALL_SLOT:
			texture = RUINS
		var foot := Vector2(gap * (i + 0.5), ROW_Y + BUILDING_SIZE)
		row.append(add_picture(texture, Vector2(BUILDING_SIZE, BUILDING_SIZE), foot))
	return row


# PANEL 1: the town in its glory. The buildings bob gently, like it's busy.
func panel_thriving() -> void:
	var row := add_town_row(false)
	for i in row.size():
		var building := row[i]
		var bob := make_loop()
		bob.tween_interval(i * 0.15)  # Each one starts a little later: a wave.
		bob.tween_property(building, "scale", Vector2(1.04, 0.97), 0.5).set_trans(Tween.TRANS_SINE)
		bob.tween_property(building, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
		bob.tween_interval(0.6)


# PANEL 2: night falls, the Dark Wizard rises, lightning, the buildings shake.
func panel_attack() -> void:
	var row := add_town_row(false)
	create_tween().tween_property(tint, "color:a", 0.55, 1.5)
	var wizard := add_picture(DARK_WIZARD, Vector2(200, 245), Vector2(640, 300))
	wizard.modulate.a = 0.0
	wizard.position.y += 40
	var rise := create_tween().set_parallel()
	rise.tween_property(wizard, "modulate:a", 1.0, 1.2)
	rise.tween_property(wizard, "position:y", wizard.position.y - 40, 1.2).set_trans(Tween.TRANS_SINE)
	# He hovers up and down.
	var hover := make_loop()
	hover.tween_interval(1.2)
	hover.tween_property(wizard, "position:y", 16.0, 1.0).as_relative().set_trans(Tween.TRANS_SINE)
	hover.tween_property(wizard, "position:y", -16.0, 1.0).as_relative().set_trans(Tween.TRANS_SINE)
	# Lightning: a white flash, and every building jumps.
	var storm := make_loop()
	storm.tween_interval(1.0)
	storm.tween_callback(func() -> void: strike(row))
	storm.tween_property(flash, "color:a", 0.0, 0.35).from(0.75)
	storm.tween_interval(0.7)
	storm.tween_callback(func() -> void: strike(row))
	storm.tween_property(flash, "color:a", 0.0, 0.25).from(0.5)
	storm.tween_interval(1.2)


# One lightning strike: a jagged bolt on a random building, and they all shake.
func strike(row: Array[TextureRect]) -> void:
	var target := row[randi() % row.size()]
	var bolt := Line2D.new()
	bolt.width = 6
	bolt.default_color = Color(0.85, 0.75, 1.0)
	var x := target.position.x + target.size.x / 2.0
	var y := 0.0
	while y < target.position.y + 40:
		bolt.add_point(Vector2(x, y))
		x += randf_range(-30, 30)
		y += randf_range(30, 60)
	stage.add_child(bolt)
	var fade := create_tween()
	fade.tween_property(bolt, "modulate:a", 0.0, 0.4)
	fade.tween_callback(bolt.queue_free)
	for building in row:
		var start := building.position
		var shake := create_tween()
		for i in 4:
			shake.tween_property(building, "position", start + Vector2(randf_range(-6, 6), randf_range(-3, 3)), 0.04)
		shake.tween_property(building, "position", start, 0.04)


# PANEL 3: the morning after. Ruins and smoke; the Guild Hall still stands.
func panel_ruins() -> void:
	background.modulate = Color(0.45, 0.42, 0.45)
	var row := add_town_row(true)
	for i in row.size():
		if i != GUILD_HALL_SLOT:
			row[i].modulate = Color(0.75, 0.7, 0.7)
			add_smoke(row[i], i * 0.4)
	# A soft golden glow behind the Guild Hall, so the eye goes to it.
	var hall := row[GUILD_HALL_SLOT]
	var glow := make_loop()
	glow.tween_property(hall, "modulate", Color(1.25, 1.15, 0.85), 1.2).set_trans(Tween.TRANS_SINE)
	glow.tween_property(hall, "modulate", Color.WHITE, 1.2).set_trans(Tween.TRANS_SINE)


# Grey puffs that rise out of a ruin and fade away, over and over.
func add_smoke(ruin: TextureRect, delay: float) -> void:
	var puff := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.55, 0.58, 0.6)
	style.set_corner_radius_all(30)
	puff.add_theme_stylebox_override("panel", style)
	puff.size = Vector2(40, 40)
	puff.pivot_offset = puff.size / 2.0
	puff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start := ruin.position + Vector2(ruin.size.x / 2.0 - 20, 40)
	puff.position = start
	puff.modulate.a = 0.0
	stage.add_child(puff)
	var rise := make_loop()
	rise.tween_interval(delay)
	rise.tween_callback(func() -> void:
		puff.position = start
		puff.scale = Vector2(0.6, 0.6)
		puff.modulate.a = 0.8)
	rise.set_parallel()
	rise.tween_property(puff, "position:y", start.y - 120, 2.4)
	rise.tween_property(puff, "scale", Vector2(1.8, 1.8), 2.4)
	rise.tween_property(puff, "modulate:a", 0.0, 2.4)
	rise.set_parallel(false)
	rise.tween_interval(0.01)


# PANEL 4: the King sends architects. One by one they walk up to the ruins...
# and give up: they go grey, slump and fade away.
func panel_architects() -> void:
	background.modulate = Color(0.45, 0.42, 0.45)
	var ruin := add_picture(RUINS, Vector2(220, 220), Vector2(880, 520))
	ruin.modulate = Color(0.75, 0.7, 0.7)
	add_smoke(ruin, 0.0)
	add_picture(KING, Vector2(170, 230), Vector2(200, 520))
	for i in 3:
		send_architect(i * 1.6)


func send_architect(delay: float) -> void:
	var walker := add_picture(ARCHITECT, Vector2(110, 165), Vector2(330, 520))
	walker.modulate.a = 0.0
	var walk := create_tween()
	walk.tween_interval(delay)
	walk.tween_property(walker, "modulate:a", 1.0, 0.2)
	# Walk towards the ruins, with a little hop on each step.
	for step in 6:
		walk.tween_property(walker, "position", Vector2(36, -10), 0.14).as_relative()
		walk.tween_property(walker, "position", Vector2(36, 10), 0.14).as_relative()
	walk.tween_interval(0.3)
	# They fail: grey, slumped, gone.
	walk.set_parallel()
	walk.tween_property(walker, "modulate", Color(0.4, 0.4, 0.4, 1.0), 0.4)
	walk.tween_property(walker, "rotation_degrees", -14.0, 0.4)
	walk.set_parallel(false)
	walk.tween_property(walker, "modulate:a", 0.0, 0.8)


# PANEL 5: darkness, then "Until you..." and the new architect, in gold.
func panel_until_you() -> void:
	background.visible = false
	# A soft golden glow for the new architect to stand in: a RADIAL gradient
	# (gold in the middle, see-through at the edge) drawn as a picture.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 0.8, 0.35, 0.45))
	gradient.set_color(1, Color(1, 0.8, 0.35, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 0.0)
	var glow := add_picture(glow_texture, Vector2(360, 360), Vector2(640, 700))
	glow.modulate.a = 0.0
	glow.pivot_offset = glow.size / 2.0
	var shine := make_loop()
	shine.tween_interval(1.4)
	shine.tween_property(glow, "modulate:a", 1.0, 1.0)
	shine.tween_property(glow, "scale", Vector2(1.08, 1.08), 1.2).set_trans(Tween.TRANS_SINE)
	shine.tween_property(glow, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE)
	var you := add_picture(ARCHITECT, Vector2(150, 225), Vector2(640, 620))
	you.modulate = Color(1, 0.9, 0.5, 0.0)
	var appear := create_tween()
	appear.tween_interval(1.4)
	appear.tween_property(you, "modulate", Color(1.2, 1.1, 0.8, 1.0), 1.0)
	appear.tween_property(you, "modulate", Color.WHITE, 0.6)
	big_text.visible = true
	type_out(big_text, "Until you...", 6.0)


# The end (or Skip): remember the story was seen, and go to the town.
# (Replaying it with the Story button goes back to Character Select.)
func finish() -> void:
	GameState.reach_milestone(GameState.STORY_INTRO)
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE if replay else TOWN_SCENE)
