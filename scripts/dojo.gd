# dojo.gd
#
# The Dojo (scenes/dojo.tscn), opened from its building in town.
#
# Two things live here:
#   1. Your TALENT POINTS, with a button to the Talents screen.
#   2. The MONSTER BOOK: every monster you've met in a fight. Click one to see
#      its picture, its stats and moves, where you saw it, how many you've
#      beaten, and its Monster Exp (each kill is worth some). Monsters you
#      haven't met yet are dark "???" silhouettes, so you can see how many are
#      left to find.
#
# The book itself is GameState.bestiary (saved). battle.gd fills it: every
# monster that shows up in a fight is "seen" there, and every kill counts.
# Monster Levels don't DO anything yet: that's the next step for the Dojo.
#
# Like the town, the whole screen is built here in code; the .tscn is just
# this script on an empty Control.
extends Control

const TOWN_SCENE := "res://scenes/town.tscn"
const TALENTS_SCENE := "res://scenes/talents.tscn"
const GOLD_COLOR := Color(1, 0.84, 0.35)
const DIM_COLOR := Color(1, 1, 1, 0.6)
const PANEL_COLOR := Color(0.12, 0.1, 0.09, 0.95)
const BORDER_COLOR := Color(0.45, 0.36, 0.25)
const ATTACK_COLOR := Color(1, 0.6, 0.5)

var monsters: Array[EnemyData] = []  # Every monster in the game, met ones first.
var list_box: VBoxContainer  # The buttons on the left.
var detail_box: VBoxContainer  # The chosen monster's page on the right.
var selected: EnemyData = null


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	monsters = book_order()
	build_screen()
	# Open the first monster you've met (if any).
	if not monsters.is_empty() and GameState.bestiary.has(monsters[0].display_name):
		show_monster(monsters[0])
	else:
		show_empty_page()


# Every monster file, except the training dummies. The ones in your book come
# first (A to Z), then the ones still to find (weakest first, so the list
# doesn't give away which is the boss).
func book_order() -> Array[EnemyData]:
	var met: Array[EnemyData] = []
	var unknown: Array[EnemyData] = []
	for enemy: EnemyData in GameState.load_enemies():
		if enemy.display_name.ends_with("Dummy"):
			continue  # Training dummies aren't monsters.
		if GameState.bestiary.has(enemy.display_name):
			met.append(enemy)
		else:
			unknown.append(enemy)
	met.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.display_name < b.display_name)
	unknown.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.max_hp < b.max_hp)
	return met + unknown


# ---------------------------------------------------------------------------
# Building the screen (once)
# ---------------------------------------------------------------------------

func build_screen() -> void:
	var background := ColorRect.new()
	background.color = Color(0.13, 0.1, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	# Title row: name on the left, Back on the right.
	var title_row := HBoxContainer.new()
	page.add_child(title_row)
	var title := make_label("The Dojo", 36, GOLD_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(170, 44)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(TOWN_SCENE))
	title_row.add_child(back)

	page.add_child(build_talent_bar())

	# The book: the list on the left, the page on the right.
	var book := HBoxContainer.new()
	book.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book.add_theme_constant_override("separation", 16)
	page.add_child(book)

	var list_panel := make_panel()
	list_panel.custom_minimum_size = Vector2(330, 0)
	book.add_child(list_panel)
	var list_column := VBoxContainer.new()
	list_column.add_theme_constant_override("separation", 8)
	list_panel.add_child(list_column)
	var met := GameState.bestiary.size()
	list_column.add_child(make_label("Monster Book  ·  %d / %d met" % [mini(met, monsters.size()), monsters.size()], 20, GOLD_COLOR))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_column.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(list_box)
	for enemy in monsters:
		list_box.add_child(make_monster_button(enemy))

	var detail_panel := make_panel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book.add_child(detail_panel)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(detail_scroll)
	detail_box = VBoxContainer.new()
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(detail_box)


# The strip at the top: this class's talent points, and the way to the Talents screen.
func build_talent_bar() -> Control:
	var bar := make_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var hero := GameState.character_class
	var text := make_label("%s talent points to spend: %d   (Class: %d from levels  ·  Legacy: %d, every class gets these)" % [
		hero.display_name, GameState.talent_points_left(hero),
		GameState.class_talent_points(hero), GameState.legacy_talent_points], 18, Color.WHITE)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var talents := Button.new()
	talents.text = "Talents"
	talents.theme_type_variation = &"PrimaryButton"
	talents.custom_minimum_size = Vector2(150, 44)
	talents.tooltip_text = "Spend your talent points (the Talents screen)."
	talents.pressed.connect(func() -> void:
		GameState.talents_return_scene = scene_file_path  # Its Back button comes back here.
		get_tree().change_scene_to_file(TALENTS_SCENE))
	row.add_child(talents)
	return bar


# One row of the list: picture, name, kills. A "???" shadow if you haven't met it.
func make_monster_button(enemy: EnemyData) -> Button:
	var met := GameState.bestiary.has(enemy.display_name)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 52)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = enemy.texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 56)
	button.toggle_mode = true
	button.set_meta("enemy", enemy)
	if met:
		var kills := int(GameState.bestiary[enemy.display_name].kills)
		button.text = "%s   ·   %d beaten" % [enemy.display_name, kills]
		if enemy.is_boss:
			button.text += "   ★"
		button.pressed.connect(show_monster.bind(enemy))
	else:
		button.text = "???"
		button.disabled = true
		# A black silhouette: the shape gives a hint, nothing else.
		button.add_theme_color_override("icon_disabled_color", Color(0, 0, 0, 0.85))
		button.tooltip_text = "Meet it in a fight to add it to the book."
	return button


# ---------------------------------------------------------------------------
# The monster's page
# ---------------------------------------------------------------------------

func show_monster(enemy: EnemyData) -> void:
	selected = enemy
	for button in list_box.get_children():
		button.button_pressed = button.get_meta("enemy") == enemy
	clear_page()
	var entry: Dictionary = GameState.bestiary.get(enemy.display_name, {"seen": [], "kills": 0})

	# Picture and name.
	var picture := TextureRect.new()
	picture.texture = enemy.texture
	picture.custom_minimum_size = Vector2(0, 170)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_box.add_child(picture)
	detail_box.add_child(make_label(enemy.display_name, 30, enemy.name_color))
	if enemy.is_boss:
		detail_box.add_child(make_label("★ Boss", 18, GOLD_COLOR))

	# Monster Exp: kills, level, and a bar to the next level.
	var monster := enemy.display_name
	var level := GameState.monster_level(monster)
	var monster_exp := GameState.monster_exp(monster)
	var next := GameState.monster_next_level_exp(monster)
	detail_box.add_child(make_label("Beaten %d time%s  ·  Monster Level %d" % [
		entry.kills, "" if entry.kills == 1 else "s", level], 20, GOLD_COLOR))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	bar.max_value = next if next > 0 else 1
	bar.value = monster_exp if next > 0 else 1
	detail_box.add_child(bar)
	detail_box.add_child(make_label(
		("Monster Exp %d / %d  (+%d per kill)" % [monster_exp, next, GameState.MONSTER_EXP_PER_KILL]) if next > 0
			else "Monster Exp %d: max level!" % monster_exp, 15, DIM_COLOR))

	# Stats.
	add_heading("Stats")
	var stats: Array[String] = ["HP %d" % enemy.max_hp]
	if enemy.armor > 0:
		stats.append("Armor %d" % enemy.armor)
	stats.append("%d Exp" % enemy.exp)
	if enemy.bonus_gold > 0:
		stats.append("+%d gold" % enemy.bonus_gold)
	add_line("  ·  ".join(stats), Color.WHITE)
	if not enemy.split_into.is_empty():
		add_line("At half HP it splits into %d %s." % [enemy.split_count, enemy.split_into], Color(0.6, 1, 0.6))
	if not enemy.drops.is_empty():
		add_line("Drops: " + ", ".join(drop_texts(enemy)), Color(0.75, 0.9, 1))

	# Moves.
	var order := "in order, then back to the first" if enemy.move_order == EnemyData.MoveOrder.IN_ORDER \
		else "picked at random each turn"
	add_heading("Moves  (%s)" % order)
	var moves := enemy.moves if not enemy.moves.is_empty() else [enemy.default_move()] as Array[EnemyMove]
	for move in moves:
		add_line("%s:  %s" % [move.move_name, move.describe()],
			ATTACK_COLOR if move.attacks() else Color(0.6, 0.8, 1))

	# Where you've met it.
	add_heading("Where you saw it")
	var seen: Array = entry.seen
	if seen.is_empty():
		add_line("Somewhere... you don't remember.", DIM_COLOR)
	for place in seen:
		add_line("• " + str(place), Color.WHITE)


# "Green Ooze 100" -> "Green Ooze (100%)". The same drop listed 3 times
# (the Slime King's "Stone 100%; Stone 100%; Stone 100%") -> "3x Stone (100%)".
func drop_texts(enemy: EnemyData) -> Array[String]:
	var counts := {}  # Each different drop -> how many times it's listed (in order).
	for drop in enemy.drops:
		counts[drop] = counts.get(drop, 0) + 1
	var texts: Array[String] = []
	for drop: String in counts:
		var words := drop.rsplit(" ", true, 1)
		var text := "%s (%s%%)" % [words[0], words[1]] if words.size() == 2 and words[1].is_valid_int() else drop
		texts.append(text if counts[drop] == 1 else "%dx %s" % [counts[drop], text])
	return texts


func show_empty_page() -> void:
	clear_page()
	detail_box.add_child(make_label("Your monster book is empty.", 24, GOLD_COLOR))
	detail_box.add_child(make_label("Every monster you meet in the dungeons goes in here: where you saw it, its stats and moves, and how many you've beaten. Each one you beat gives Monster Exp for that monster.", 17, DIM_COLOR))


func clear_page() -> void:
	for child in detail_box.get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

func add_heading(text: String) -> void:
	var label := make_label(text, 20, GOLD_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail_box.add_child(HSeparator.new())
	detail_box.add_child(label)


func add_line(text: String, color: Color) -> void:
	var label := make_label(text, 17, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail_box.add_child(label)


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	return panel
