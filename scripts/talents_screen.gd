# talents_screen.gd
#
# The Talents screen (scenes/talents.tscn): the chosen class's talent trees.
# Like World of Warcraft, a class can have several trees, one tab each, and
# your points are shared between them. Click a talent to spend a point on it.
# Hover one to read what it does.
#
# Like Character Select, the tree is built here in code from the talent
# files, so a new talent in the spreadsheet shows up on its own. Each talent's
# Tier (row) and Column (left to right) say where its box goes.
extends Control

const BOX_SIZE := Vector2(156, 72)
const COLUMN_SPACING := 176.0  # Pixels from one column to the next.
const ROW_SPACING := 112.0  # Pixels from one tier to the next.
const TIER_LABEL_WIDTH := 150.0  # Room on the left for "Tier 2" labels.
const LEARNED_COLOR := Color(1, 0.82, 0.3)  # Gold border: you have it.
const OPEN_COLOR := Color(1, 1, 1, 0.85)  # White border: you can learn it now.
const LOCKED_COLOR := Color(1, 1, 1, 0.15)  # Faint border: not yet.
const REASON_COLOR := Color(1, 0.55, 0.45)
const SPEC_SCENE := "res://scenes/spec_select.tscn"

@onready var title_label: Label = %TitleLabel
@onready var points_label: Label = %PointsLabel
@onready var tree_tabs: HBoxContainer = %TreeTabs
@onready var tree_area: Control = %TreeArea
@onready var detail_name: Label = %DetailName
@onready var detail_text: Label = %DetailText
@onready var detail_reason: Label = %DetailReason
@onready var back_button: Button = %BackButton
@onready var reset_button: Button = %ResetButton

var character_class: CharacterClass
var boxes := {}  # Talent -> its Button (only the tree on show).
var current_tree := ""  # The tree whose tab is open.
var tab_buttons := {}  # Tree name -> its tab Button.
var hovered: Talent = null  # Shown in the details panel.
var tree_note: Label  # Under the tabs: whose tree this is.


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	character_class = GameState.character_class
	title_label.text = "%s Talents" % character_class.display_name
	back_button.pressed.connect(_on_back_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	# The lines between talents are drawn by the tree area itself. draw.connect()
	# lets this script do the drawing, whenever Godot redraws that node.
	tree_area.draw.connect(_draw_lines)
	build_spec_banner()
	build_tabs()
	build_tree()
	refresh()


# ---------------------------------------------------------------------------
# Building the tree (once)
# ---------------------------------------------------------------------------

# The banner at the top that says which Spec you picked and what it does,
# so it's clear how the Spec and the trees fit together. Built in code and
# slotted in above the tabs.
func build_spec_banner() -> void:
	var specs := GameState.specs_for(character_class)
	if specs.is_empty():
		return  # This class has no specs yet.
	var spec_name := GameState.spec_of(character_class)
	var spec: Talent = null
	for talent in specs:
		if talent.tree == spec_name:
			spec = talent

	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.17, 0.07, 0.9)
	style.border_color = LEARNED_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	style.content_margin_left = 16
	banner.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	banner.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)
	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", LEARNED_COLOR)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 15)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if spec == null:
		heading.text = "No Spec chosen"
		info.text = "Pick a Spec to choose how your %s plays. Your Spec is free, and its tree is marked ★ below." % character_class.display_name
	else:
		heading.text = "Your Spec: ★ %s" % spec_name
		info.text = spec.rank_text(1)
	text_box.add_child(heading)
	text_box.add_child(info)

	var change := Button.new()
	change.text = "Change Spec" if spec != null else "Choose a Spec"
	change.tooltip_text = "Changing Spec gives back all your talent points."
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	change.custom_minimum_size = Vector2(170, 40)
	change.pressed.connect(func() -> void: get_tree().change_scene_to_file(SPEC_SCENE))
	row.add_child(change)

	tree_tabs.add_sibling(banner)
	tree_tabs.get_parent().move_child(banner, tree_tabs.get_index())  # Above the tabs.

	# And a line under the tabs saying whose tree is on show.
	tree_note = Label.new()
	tree_note.add_theme_font_size_override("font_size", 15)
	tree_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tree_tabs.add_sibling(tree_note)


# One tab per tree. A ButtonGroup makes them work like radio buttons.
func build_tabs() -> void:
	var trees := GameState.trees_for(character_class)
	if trees.is_empty():
		return
	# Open on your spec's tree.
	current_tree = GameState.spec_of(character_class) if trees.has(GameState.spec_of(character_class)) else trees[0]
	var group := ButtonGroup.new()
	for tree_name in trees:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = tree_name == current_tree
		tab.custom_minimum_size = Vector2(220, 40)
		tab.add_theme_font_size_override("font_size", 18)
		tab.pressed.connect(_on_tab_pressed.bind(tree_name))
		tree_tabs.add_child(tab)
		tab_buttons[tree_name] = tab
	tree_tabs.visible = trees.size() > 1  # One tree doesn't need tabs.


# Build the boxes for the tree on show (again, when you switch tabs).
func build_tree() -> void:
	for child in tree_area.get_children():
		tree_area.remove_child(child)
		child.queue_free()
	boxes.clear()
	# Specs live in the same list, but they're picked on the Spec screen.
	var talents := GameState.talents_for(character_class).filter(
		func(talent: Talent) -> bool: return talent.tree == current_tree and not talent.is_spec)
	if talents.is_empty():
		var empty := Label.new()
		empty.text = "No talents for the %s yet.\nAdd a sheet: data/talents/%s.csv" % [
			character_class.display_name, character_class.resource_path.get_file().get_basename()]
		tree_area.add_child(empty)
		return

	# One label per tier, on the left, with what it takes to open it
	# (the smallest requirement of any talent in that tier).
	var tiers := {}  # Tier -> [points in this tree, points in the tier above]
	for talent in talents:
		var needs: Array = tiers.get(talent.tier, [9999, 9999])  # 9999 = "no talent seen yet"
		tiers[talent.tier] = [mini(needs[0], talent.points_in_tree), mini(needs[1], talent.tier_unlock)]
	for tier: int in tiers:
		var label := Label.new()
		label.text = "Tier %d" % tier
		if tiers[tier][0] > 0:
			label.text += "\n%d point(s) in tree" % tiers[tier][0]
		if tier > 1 and tiers[tier][1] > 0:
			label.text += "\n%d point(s) in Tier %d" % [tiers[tier][1], tier - 1]
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		label.position = Vector2(0, row_y(tier) + 16)
		tree_area.add_child(label)

	for talent in talents:
		var box := Button.new()
		box.custom_minimum_size = BOX_SIZE
		box.size = BOX_SIZE
		box.position = Vector2(TIER_LABEL_WIDTH + (talent.column - 1) * COLUMN_SPACING, row_y(talent.tier))
		box.add_theme_font_size_override("font_size", 15)
		box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.pressed.connect(_on_talent_pressed.bind(talent))
		box.mouse_entered.connect(_on_talent_hovered.bind(talent))
		tree_area.add_child(box)
		boxes[talent] = box
	# Tell the containers how big the tree is, so it can be centred.
	var right := 0.0
	var bottom := 0.0
	for box: Button in boxes.values():
		right = maxf(right, box.position.x + BOX_SIZE.x)
		bottom = maxf(bottom, box.position.y + BOX_SIZE.y)
	tree_area.custom_minimum_size = Vector2(right, bottom)


func row_y(tier: int) -> float:
	return (tier - 1) * ROW_SPACING


# ---------------------------------------------------------------------------
# Updating (after every click)
# ---------------------------------------------------------------------------

func refresh() -> void:
	var points := GameState.talent_points_left(character_class)
	points_label.text = "Talent points: %d" % points
	# Each tab shows the points spent in it, e.g. "Pack Rat  (3)".
	for tree_name: String in tab_buttons:
		var star := "★ " if tree_name == GameState.spec_of(character_class) else ""  # Your spec's tree.
		tab_buttons[tree_name].text = "%s%s  (%d)" % [star, tree_name,
			GameState.talent_points_spent(character_class, tree_name)]
	points_label.add_theme_color_override("font_color", LEARNED_COLOR if points > 0 else Color(1, 1, 1, 0.6))
	if tree_note:
		var spec_name := GameState.spec_of(character_class)
		if current_tree == spec_name:
			tree_note.text = "★ Your Spec's tree: the talents made for %s. (Your points can go in any tree.)" % spec_name
			tree_note.add_theme_color_override("font_color", LEARNED_COLOR)
		else:
			tree_note.text = "The %s tree (not your Spec). Its talents still work if you learn them." % current_tree
			tree_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	for talent: Talent in boxes:
		var box: Button = boxes[talent]
		var rank := GameState.talent_rank(talent)
		var reason := GameState.why_cant_learn(talent)
		box.text = "%s\n%d / %d" % [talent.talent_name, rank, talent.max_ranks]
		var border := LOCKED_COLOR
		if rank > 0:
			border = LEARNED_COLOR
		elif reason.is_empty():
			border = OPEN_COLOR
		for state in ["normal", "hover", "pressed", "focus"]:
			box.add_theme_stylebox_override(state, make_box_style(border, rank > 0, state == "hover"))
		# Faded until you could learn it (or already have it).
		box.modulate.a = 1.0 if rank > 0 or reason.is_empty() else 0.55
	show_details(hovered)
	tree_area.queue_redraw()  # Redraw the lines (learned paths turn gold).


func make_box_style(border: Color, learned: bool, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = character_class.color.darkened(0.2 if learned else 0.6)
	if hover:
		style.bg_color = style.bg_color.lightened(0.15)
	style.border_color = border
	style.set_border_width_all(3 if learned else 2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(6)
	return style


# A line from each talent up to the talents it Needs.
func _draw_lines() -> void:
	for talent: Talent in boxes:
		for needed_name in talent.needs:
			var needed := GameState.find_talent(character_class, needed_name)
			if needed == null or not boxes.has(needed):
				continue
			var from: Button = boxes[needed]
			var to: Button = boxes[talent]
			var color := LEARNED_COLOR if GameState.talent_rank(needed) > 0 else LOCKED_COLOR
			tree_area.draw_line(from.position + Vector2(BOX_SIZE.x / 2, BOX_SIZE.y),
				to.position + Vector2(BOX_SIZE.x / 2, 0), color, 3.0, true)


func show_details(talent: Talent) -> void:
	if talent == null:
		detail_name.text = "Hover a talent to see what it does"
		detail_text.text = "You get 1 talent point each time your class levels up. Click a talent to spend a point on it."
		detail_reason.text = ""
		return
	var rank := GameState.talent_rank(talent)
	detail_name.text = "%s  (%d / %d)" % [talent.talent_name, rank, talent.max_ranks]
	var lines: Array[String] = []
	if rank > 0:
		lines.append("Now: " + talent.rank_text(rank))
	if rank < talent.max_ranks:
		lines.append(("Next: " if rank > 0 else "") + talent.rank_text(rank + 1))
	if not talent.choice_group.is_empty():
		lines.append("Pick only one talent from \"%s\"." % talent.choice_group)
	if talent.effect.is_empty():
		lines.append("(This talent doesn't do anything yet.)")
	detail_text.text = "\n".join(lines)
	var reason := GameState.why_cant_learn(talent)
	detail_reason.text = "" if reason.is_empty() or reason == "Max rank" else reason
	if reason.is_empty():
		detail_reason.text = "Click to learn (%d point%s)" % [talent.cost, "" if talent.cost == 1 else "s"]
		detail_reason.add_theme_color_override("font_color", LEARNED_COLOR)
	else:
		detail_reason.add_theme_color_override("font_color", REASON_COLOR)


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_talent_pressed(talent: Talent) -> void:
	hovered = talent
	if GameState.learn_talent(talent):
		# A little pop, like cards in the deck builder.
		var box: Button = boxes[talent]
		box.pivot_offset = BOX_SIZE / 2
		box.scale = Vector2(1.1, 1.1)
		create_tween().tween_property(box, "scale", Vector2.ONE, 0.15)
	refresh()


func _on_tab_pressed(tree_name: String) -> void:
	current_tree = tree_name
	tab_buttons[tree_name].button_pressed = true
	hovered = null
	build_tree()
	refresh()


func _on_talent_hovered(talent: Talent) -> void:
	hovered = talent
	show_details(talent)


func _on_reset_pressed() -> void:
	GameState.reset_talents(character_class)
	refresh()


# Back to wherever you came from (Character Select or the deck builder).
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameState.talents_return_scene)
