# area_perks_screen.gd
#
# A PLACE'S PERKS (scenes/area_perks.tscn), opened from Prepare Expedition.
# Trips to a place give it Exp; each level up gives an Explorer point (and a
# booster pack). Spend the points here on that place's own flat list of perks
# (data/dungeons/farm_perks.csv for the Farm). Perks are for good.
#
# The rules are in GameState (area_level, explorer_points, buy_area_perk) and
# area_perk.gd. Like the Dojo, the whole screen is built in code.
extends Control

const PREPARE_SCENE := "res://scenes/prepare.tscn"
const GOLD_COLOR := Color(1, 0.84, 0.35)
const DIM_COLOR := Color(1, 1, 1, 0.6)
const OWNED_COLOR := Color(0.55, 0.9, 0.55)
const PANEL_COLOR := Color(0.12, 0.1, 0.09, 0.94)
const OWNED_PANEL := Color(0.12, 0.2, 0.12, 0.94)
const BORDER_COLOR := Color(0.45, 0.36, 0.25)

var area: Area
var header: Label
var points_label: Label
var exp_bar: ProgressBar
var grid: GridContainer


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	area = GameState.current_area
	build_screen()
	refresh()


func build_screen() -> void:
	var background := TextureRect.new()
	background.texture = area.background
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	# Title row: the place and its level, then Back.
	var title_row := HBoxContainer.new()
	page.add_child(title_row)
	header = make_label("", 32, GOLD_COLOR)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(header)
	var back := Button.new()
	back.text = "Back to Prepare"
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(PREPARE_SCENE))
	title_row.add_child(back)

	# The Exp bar and the points to spend.
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 12)
	page.add_child(bar_row)
	exp_bar = ProgressBar.new()
	exp_bar.custom_minimum_size = Vector2(420, 26)
	exp_bar.show_percentage = false
	bar_row.add_child(exp_bar)
	points_label = make_label("", 20, Color.WHITE)
	bar_row.add_child(points_label)
	page.add_child(make_label("Every trip here gives %s Exp: 1 per card you flip, 3 per fight won, 10 per floor deeper, and 10 for getting home (half if you don't). Each level up gives an Explorer point and a %s." % [
		area.display_name, GameState.AREA_LEVEL_PACK], 15, DIM_COLOR, true))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)


func refresh() -> void:
	var level := GameState.area_level(area)
	header.text = "%s Perks  ·  Level %d" % [area.display_name, level]
	var progress := GameState.area_exp_progress(area)
	exp_bar.max_value = maxi(progress.y, 1)
	exp_bar.value = progress.x if progress.y > 0 else 1
	exp_bar.tooltip_text = "%d / %d Exp to level %d" % [progress.x, progress.y, level + 1] if progress.y > 0 else "Top level!"
	var points := GameState.explorer_points(area)
	points_label.text = ("%d / %d Exp" % [progress.x, progress.y] if progress.y > 0 else "Top level!") + \
		"     ★ %d Explorer point%s" % [points, "" if points == 1 else "s"]
	points_label.add_theme_color_override("font_color", GOLD_COLOR if points > 0 else Color.WHITE)
	for old in grid.get_children():
		old.queue_free()
	# Only the perks for things you've unlocked (GameState.shown_area_perks):
	# the rest wait, hidden, until you have what they're about.
	var perks := GameState.shown_area_perks(area)
	if perks.is_empty():
		grid.add_child(make_label("No perks here yet.", 18, DIM_COLOR))
	for perk in perks:
		grid.add_child(make_perk_panel(perk))
	var hidden := GameState.area_perk_list(area).size() - perks.size()
	if hidden > 0:
		grid.add_child(make_hidden_panel(hidden))


# A dim "?" panel at the end: there are more perks, for things you haven't
# found yet. (It doesn't say what, so it's a little surprise when they show.)
func make_hidden_panel(count: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 128)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.7)
	style.border_color = BORDER_COLOR.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var mark := make_label("?", 40, DIM_COLOR)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mark)
	var text := make_label("%d more perk%s will show up as you unlock new things in town." % [count, "" if count == 1 else "s"], 15, DIM_COLOR, true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	return panel


func make_perk_panel(perk: AreaPerk) -> Control:
	var owned := GameState.has_area_perk(area, perk)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 128)
	var style := StyleBoxFlat.new()
	style.bg_color = OWNED_PANEL if owned else PANEL_COLOR
	style.border_color = OWNED_COLOR if owned else BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var top := HBoxContainer.new()
	var name_label := make_label(perk.perk_name, 19, OWNED_COLOR if owned else Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(make_label("★ %d" % perk.cost, 18, GOLD_COLOR))
	box.add_child(top)
	var text := make_label(perk.text, 15, DIM_COLOR, true)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var why := GameState.why_cant_buy_perk(area, perk)
	if owned:
		button.text = "✓ Yours"
		button.disabled = true
	elif why.is_empty():
		button.text = "Learn (★ %d)" % perk.cost
		button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(_on_buy.bind(perk))
	else:
		button.text = why
		button.disabled = true
	box.add_child(button)
	return panel


func _on_buy(perk: AreaPerk) -> void:
	if GameState.buy_area_perk(area, perk):
		refresh()


func make_label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
