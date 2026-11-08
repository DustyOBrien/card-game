# class_track.gd
#
# THE CLASS TRACK (scenes/class_track.tscn): how your class grows.
#
#   - Top: each SPEC with its level (1 to 10, or 0 while locked), its Exp bar,
#     and the spec reward its next level gives (a class card and/or a pack,
#     from data/progression/class_cards.csv).
#   - Bottom: the CLASS TRACK, like a season pass. The class level is all the
#     spec levels added up (the Adventurer: 3 specs x 10 = 30), and every class
#     level gives a reward from data/progression/class_track.csv plus 1 talent
#     point. Rewards you've had are ticked; the next one glows.
#
# The rules are in GameState (spec_level, class_level, claim_class_track);
# this screen only draws them. Built in code, like the Binder.
extends Control

const GOLD := Color(1, 0.84, 0.35)
const DIM := Color(1, 1, 1, 0.6)
const TILE_SIZE := Vector2(150, 150)

var hero: CharacterClass


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	hero = GameState.character_class
	build_screen()


func build_screen() -> void:
	var background := ColorRect.new()
	background.color = hero.color.darkened(0.75)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	page.add_child(title_row)
	var emblem := TextureRect.new()
	emblem.texture = hero.emblem
	emblem.custom_minimum_size = Vector2(48, 48)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(emblem)
	var title := make_label("%s  ·  Class Track" % hero.display_name, 32, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(make_label("Class level %d / %d" % [GameState.class_level(hero), GameState.class_max_level(hero)], 24, Color.WHITE))
	var back := Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(120, 42)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(GameState.screen_return_scene))
	title_row.add_child(back)

	page.add_child(make_label("Class Exp goes into the spec you're playing. Each spec goes up to level %d, and your class level is all your spec levels added up. Every spec level gives a SPEC REWARD (a class card or a pack) AND the next CLASS TRACK reward (with a talent point)." % GameState.SPEC_MAX_LEVEL, 16, DIM, true))

	# --- The specs ---
	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 8)
	page.add_child(specs)
	var spec_names: Array[String] = []
	for spec in GameState.specs_for(hero):
		spec_names.append(spec.tree)
	if spec_names.is_empty():
		spec_names.append("")  # A class with no specs levels by itself.
	for spec_name in spec_names:
		specs.add_child(make_spec_row(spec_name))

	# --- The track ---
	page.add_child(make_label("Class Track", 24, GOLD))
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, TILE_SIZE.y + 24)
	page.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)
	var rewards := {}  # Level -> its row from the sheet.
	for entry in GameState.class_track(hero):
		rewards[entry.level] = entry
	var level := GameState.class_level(hero)
	var next_tile: Control = null
	for track_level in range(1, GameState.class_max_level(hero) + 1):
		var tile := make_tile(track_level, rewards.get(track_level, {}), level)
		row.add_child(tile)
		if track_level == level + 1:
			next_tile = tile
	if next_tile:
		# Start scrolled so the next reward is in view.
		(func() -> void: scroll.ensure_control_visible(next_tile)).call_deferred()


# One spec: name, level, Exp bar and what its next level gives.
func make_spec_row(spec_name: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	var playing := spec_name == GameState.exp_spec(hero)
	if playing:
		style.border_color = GOLD
		style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var level := GameState.spec_level(hero, spec_name)
	var name_label := make_label("%s%s" % [spec_name if not spec_name.is_empty() else hero.display_name, "  ★ playing" if playing else ""], 20, Color.WHITE)
	name_label.custom_minimum_size = Vector2(300, 0)
	row.add_child(name_label)
	if level == 0:
		row.add_child(make_label("🔒 Locked  ·  level 0. Unlock it to start levelling it (and your class goes up a level).", 16, DIM, true))
		return panel
	row.add_child(make_label("Lv %d / %d" % [level, GameState.SPEC_MAX_LEVEL], 20, GOLD))
	var progress := GameState.spec_exp_progress(hero, spec_name)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = maxi(progress.y, 1)
	bar.value = progress.x if progress.y > 0 else 1
	bar.show_percentage = false
	bar.tooltip_text = "%d / %d Exp" % [progress.x, progress.y] if progress.y > 0 else "Max level"
	row.add_child(bar)
	var next := "Max level!" if level >= GameState.SPEC_MAX_LEVEL else "Next (Lv %d): %s" % [level + 1,
		_reward_words(GameState.spec_reward_text(hero, spec_name, level + 1))]
	row.add_child(make_label(next, 16, DIM, true))
	return panel


# One level on the track. Had = gold with a tick, next = bright, later = dim.
func make_tile(track_level: int, entry: Dictionary, level: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = TILE_SIZE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	var had := track_level <= level
	style.bg_color = Color(0.25, 0.2, 0.08, 0.9) if had else Color(0.08, 0.08, 0.1, 0.9)
	style.border_color = GOLD if had else (Color.WHITE if track_level == level + 1 else Color(1, 1, 1, 0.15))
	style.set_border_width_all(2 if track_level != level + 1 else 3)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(make_label("%sLv %d" % ["✓ " if had else "", track_level], 20, GOLD if had else Color.WHITE))
	var words := "Where you start" if track_level == 1 else ""
	if not entry.is_empty():
		words = entry.text if not entry.text.is_empty() else _reward_words(entry.rewards)
	var reward := make_label(words, 14, Color.WHITE if had or track_level == level + 1 else DIM, true)
	reward.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(reward)
	if track_level > 1:
		box.add_child(make_label("+1 talent point", 13, Color(0.6, 0.85, 1)))
	return panel


# Reward text from a sheet ("Pack Small 1; Card Trail Rations 1") in plain words.
static func _reward_words(text: String) -> String:
	if text.strip_edges().is_empty():
		return "nothing set yet"
	var parts: Array[String] = []
	for part in text.split(";", false):
		var words := part.strip_edges().split(" ", false)
		if words.is_empty():
			continue
		var rest := part.strip_edges().substr(words[0].length()).strip_edges()
		match words[0].to_lower():
			"pack":
				var count := rest.get_slice(" ", rest.get_slice_count(" ") - 1)
				parts.append("%s × %s pack" % [count if count.is_valid_int() else "1", rest.get_slice(" ", 0)])
			"card":
				parts.append("class card: " + rest)
			"material":
				parts.append(rest)
			"essence":
				var amount := rest.get_slice(" ", rest.get_slice_count(" ") - 1)
				parts.append("%s %s Essence" % [amount, rest.get_slice(" ", 0) if rest.get_slice_count(" ") > 1 else "Neutral"])
			_:
				parts.append(part.strip_edges())
	return ", ".join(parts)


func make_label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
