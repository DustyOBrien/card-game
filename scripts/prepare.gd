# prepare.gd
#
# PREPARE EXPEDITION (scenes/prepare.tscn): the one stop between picking a
# place on the map and setting out. Everything you choose before a trip is
# on this screen, in four columns:
#   0. Quest:     the trip's MAIN QUEST (a Story quest: its Seed Cards go on the
#                 board, and only it counts this trip), the side quests that
#                 always count, and your KEY ITEMS.
#   1. Hero:      your class, spec and deck (buttons hop to their screens and come back here).
#   2. Map Cards: which of YOUR map cards go into the place's map deck.
#   3. Pack:      your flask, how many torches and tools, and the potions/enchants you bought in town.
# Chapter 1's first trip (the Architect: no class, no deck) only shows the
# Quest column and your torches.
# Along the bottom: LOADOUTS (save this whole setup by name, load it again
# later), "Same as last time", Back to the Map and Set Out!
#
# The rules live in GameState (loadouts, map_cards_off, packed_torches) and
# DungeonRun (how the map deck is built). This script only draws them.
# Like the Dojo, the whole screen is built in code: the .tscn is just this
# script on an empty Control.
extends Control

const MAP_SCENE := "res://scenes/map.tscn"
const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CHARACTER_SCENE := "res://scenes/character_select.tscn"
const SPEC_SCENE := "res://scenes/spec_select.tscn"
const TALENTS_SCENE := "res://scenes/talents.tscn"
const PERKS_SCENE := "res://scenes/area_perks.tscn"
const BINDER_SCENE := "res://scenes/binder.tscn"
const TRACK_SCENE := "res://scenes/class_track.tscn"
const TORCH_ICON := preload("res://art/map_cards/torch.svg")
const TOOL_ICONS := {
	DungeonRun.CROWBAR: preload("res://art/map_cards/crowbar.svg"),
	DungeonRun.BOMB: preload("res://art/map_cards/bomb.svg"),
}
const FLASK_ICON := preload("res://art/potions/flask.svg")

const GOLD_COLOR := Color(1, 0.84, 0.35)
const DIM_COLOR := Color(1, 1, 1, 0.6)
const PANEL_COLOR := Color(0.12, 0.1, 0.09, 0.94)
const BORDER_COLOR := Color(0.45, 0.36, 0.25)
const BAD_COLOR := Color(1, 0.5, 0.45)

var area: Area
var guided := false  # Chapter 1's first trip: only the quest and torches.
var quest_box: VBoxContainer
var hero_box: VBoxContainer
var cards_box: VBoxContainer
var pack_box: VBoxContainer
var loadout_row: HBoxContainer
var name_edit: LineEdit
var status_label: Label  # A line under the columns: "Loaded Slime Hunt." / why you can't set out.
var set_out_button: Button
var perks_button: Button


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	GameState.preparing = false
	area = GameState.current_area
	guided = GameState.is_guided_run(area) or GameState.character_class == null
	build_screen()
	refresh()
	start_guide.call_deferred()


# The first visit: a short guide around the screen (screen_guide.gd).
func start_guide() -> void:
	if guided:
		ScreenGuide.start(self, "prepare first trip", [
			{"target": panel_of(quest_box), "text": "PREPARE EXPEDITION: before every trip you pick what you're going for. This is your QUEST for the trip: Kale's supplies. Your KEY ITEMS are here too: Kale's Cellar Key and that strange orb."},
			{"target": set_out_button, "text": "Ready? Set Out!"},
		])
		return
	ScreenGuide.start(self, "prepare", [
		{"target": panel_of(quest_box), "text": "QUEST: pick this trip's MAIN QUEST. It can put its own map cards on the board (like the Dark Cellar), and only it counts this trip. SIDE quests (defeat X monsters...) always count."},
		{"target": panel_of(hero_box), "text": "PREPARE EXPEDITION: everything you pick before a trip, in one place. HERO: your class, spec and deck. Edit Deck (or Change Class/Spec) and you come straight back here."},
		{"target": panel_of(cards_box), "text": "MAP CARDS: your own map cards. Ticked ones go into the map deck with the place's base cards. Untick fights for a safer trip, or keep them for more drops."},
		{"target": panel_of(pack_box), "text": "PACK: your flask, how many torches you bring, and tools (crowbars, bombs) made from your Bank materials. Each kind takes a backpack slot, so packing less = more room for loot."},
		{"target": loadout_row.get_parent(), "text": "LOADOUTS: Save this whole setup by name and load it again with one click. Same as last time puts back what you last set out with."},
		{"target": perks_button, "text": "PERKS: every trip here gives the place Exp. Each level up gives an Explorer point to spend on this place's perks, and a booster pack."},
		{"target": set_out_button, "text": "Ready? Set Out!"},
	])


# The column panel around one of the boxes (box -> scroll -> column -> panel).
func panel_of(box: Control) -> Control:
	return box.get_parent().get_parent().get_parent()


# ---------------------------------------------------------------------------
# Building the screen (once)
# ---------------------------------------------------------------------------

func build_screen() -> void:
	# The place's own picture behind everything, darkened so the text reads.
	var background := TextureRect.new()
	background.texture = area.background
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.55)
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

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	page.add_child(title_row)
	var title := make_label("Prepare Expedition  ·  %s" % area.display_name, 34, GOLD_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	# The place's level, and its perks (if it has any).
	var progress := GameState.area_exp_progress(area)
	var level_label := make_label("Level %d%s" % [GameState.area_level(area),
		"  ·  %d / %d Exp" % [progress.x, progress.y] if progress.y > 0 else ""], 18, Color.WHITE)
	level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	level_label.add_theme_constant_override("outline_size", 4)
	title_row.add_child(level_label)
	perks_button = make_button("", func() -> void: get_tree().change_scene_to_file(PERKS_SCENE))
	perks_button.custom_minimum_size = Vector2(0, 44)
	var points := GameState.explorer_points(area)
	perks_button.text = "%s Perks" % area.display_name.get_slice(" ", area.display_name.get_slice_count(" ") - 1) + \
		("  ★ %d" % points if points > 0 else "")
	if points > 0:
		perks_button.theme_type_variation = &"PrimaryButton"
	perks_button.visible = not guided and not GameState.area_perk_list(area).is_empty()
	title_row.add_child(perks_button)
	# The place's binder (its cards, found and not), if it has booster packs.
	if not area.booster.is_empty() and not guided:
		var binder_button := make_button("Binder  %d%%" % GameState.binder_percent(area), _show_screen.bind(BINDER_SCENE))
		binder_button.custom_minimum_size = Vector2(0, 44)
		title_row.add_child(binder_button)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	page.add_child(columns)
	quest_box = add_column(columns, "Quest")
	hero_box = add_column(columns, "Hero")
	cards_box = add_column(columns, "Map Cards")
	pack_box = add_column(columns, "Pack")


	status_label = make_label("", 16, DIM_COLOR)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	page.add_child(status_label)

	# Bottom bar: loadouts on the left, Back and Set Out on the right.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	bar.add_child(make_label("Loadouts:", 18, GOLD_COLOR))
	var same := Button.new()
	same.text = "Same as last time"
	same.tooltip_text = "Put back the class, deck, flask, torches, tools and map cards you last set out with."
	same.disabled = GameState.last_loadout.is_empty()
	same.pressed.connect(_on_load.bind(GameState.last_loadout, "your last setup"))
	bar.add_child(same)
	loadout_row = HBoxContainer.new()
	loadout_row.add_theme_constant_override("separation", 4)
	bar.add_child(loadout_row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Loadout name"
	name_edit.custom_minimum_size = Vector2(150, 0)
	name_edit.max_length = 20
	bar.add_child(name_edit)
	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Save this whole setup (class, spec, talents, deck, flask, torches, tools, map cards) to load again later."
	save.pressed.connect(_on_save_loadout)
	bar.add_child(save)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var back := Button.new()
	back.text = "Back to Map"
	back.custom_minimum_size = Vector2(140, 48)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	bar.add_child(back)
	set_out_button = Button.new()
	set_out_button.text = "Set Out!"
	set_out_button.theme_type_variation = &"PrimaryButton"
	set_out_button.custom_minimum_size = Vector2(170, 48)
	set_out_button.add_theme_font_size_override("font_size", 22)
	set_out_button.pressed.connect(_on_set_out)
	bar.add_child(set_out_button)
	if guided:  # The Architect: no hero to pick, the first trip's board is set, no loadouts.
		panel_of(hero_box).visible = false
		panel_of(cards_box).visible = false
		for part in bar.get_children():
			if part not in [spacer, back, set_out_button]:
				part.visible = false


# A column: a dark panel with a gold heading, holding a box we fill in refresh().
func add_column(parent: Control, heading: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var label := make_label(heading, 24, GOLD_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


# ---------------------------------------------------------------------------
# Filling it in (again after every change)
# ---------------------------------------------------------------------------

func refresh() -> void:
	for box in [quest_box, hero_box, cards_box, pack_box, loadout_row]:
		for old in box.get_children():
			old.queue_free()
	fill_quest()
	if guided:
		fill_torches()
	else:
		fill_hero()
		fill_map_cards()
		fill_pack()
		fill_loadouts()
	var problem := set_out_problem()
	set_out_button.disabled = not problem.is_empty()
	set_out_button.tooltip_text = problem if not problem.is_empty() else "Head out to the %s." % area.display_name
	if not problem.is_empty():
		show_status(problem, BAD_COLOR)


# Why you can't set out yet ("" = you can).
func set_out_problem() -> String:
	if guided:
		return ""
	var rules := GameState.character_class
	if GameState.deck.size() < rules.min_deck_size:
		return "Your deck needs at least %d cards (it has %d). Press Edit Deck." % [rules.min_deck_size, GameState.deck.size()]
	return ""


# The trip's MAIN QUEST (one of your Story quests for this place), the side
# quests that count on every trip, and your key items.
func fill_quest() -> void:
	var mains := GameState.main_quests_for(area)
	var current := GameState.current_run_quest(area)
	GameState.run_quest = current.quest_name if current else ""
	quest_box.add_child(make_label("Main quest", 18, GOLD_COLOR))
	if mains.is_empty():
		quest_box.add_child(make_label("No story quest out here right now.", 15, DIM_COLOR, true))
	var group := ButtonGroup.new()
	for quest in mains:
		var pick := CheckBox.new()
		pick.button_group = group
		pick.text = quest.quest_name
		pick.focus_mode = Control.FOCUS_NONE
		pick.button_pressed = quest == current
		pick.add_theme_font_size_override("font_size", 18)
		pick.disabled = guided  # The first trip is always Kale's supplies.
		pick.toggled.connect(func(on: bool) -> void:
			if on and GameState.run_quest != quest.quest_name:
				GameState.run_quest = quest.quest_name
				GameState.save_game()
				refresh())
		quest_box.add_child(pick)
		var status := GameState.quest_status(quest)
		quest_box.add_child(make_label("%s  (%d/%d)" % [quest.objective_text(), status.x, status.y], 15,
			Color.WHITE if quest == current else DIM_COLOR, true))
		if not quest.seed_cards.is_empty():
			quest_box.add_child(make_label("Puts on your board: " + quest.seed_cards.replace(";", ","), 15, Color(0.6, 0.9, 1), true))
	# Side quests: they always count.
	var sides: Array[Quest] = []
	for quest in GameState.quests_active():
		if quest.quest_type != "Story" and (quest.area.is_empty() or quest.area == area.display_name):
			sides.append(quest)
	if not sides.is_empty():
		quest_box.add_child(make_label("Side quests (always count)", 18, GOLD_COLOR))
		for quest in sides:
			var status := GameState.quest_status(quest)
			quest_box.add_child(make_label("%s: %s  (%d/%d)" % [quest.quest_name, quest.objective_text(), status.x, status.y], 15, DIM_COLOR, true))
	# Key items: story things, never used up or lost.
	quest_box.add_child(make_label("Key items", 18, GOLD_COLOR))
	quest_box.add_child(make_label(", ".join(GameState.key_items) if not GameState.key_items.is_empty() else "None yet.", 15,
		Color(0.62, 0.85, 1) if not GameState.key_items.is_empty() else DIM_COLOR, true))


# The first trip's Pack: just your torches (from the Bank).
func fill_torches() -> void:
	var in_bank := GameState.material_count(DungeonRun.TORCH)
	pack_box.add_child(make_label("Torches: %d" % in_bank, 18, Color.WHITE))
	pack_box.add_child(make_label("You take every torch in your Bank. Torches light up DARK places." if in_bank > 0 \
		else "No torches yet. You won't need one today: Kale's key opens the cellar.", 15, DIM_COLOR, true))


func fill_hero() -> void:
	var rules := GameState.character_class
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var emblem := TextureRect.new()
	emblem.texture = rules.emblem
	emblem.custom_minimum_size = Vector2(56, 56)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(emblem)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(make_label(rules.display_name, 24, Color.WHITE))
	var spec := GameState.spec_of(rules)
	var spec_name := GameState.exp_spec(rules)
	names.add_child(make_label("Class level %d / %d  ·  %s %s" % [GameState.class_level(rules), GameState.class_max_level(rules),
		spec if not spec.is_empty() else "no spec yet",
		"Lv %d" % GameState.spec_level(rules, spec_name) if not spec_name.is_empty() else ""], 16, DIM_COLOR))
	row.add_child(names)
	hero_box.add_child(row)
	# Class Exp only goes to the spec you play. Already at the top? Say so
	# BEFORE the trip, so the Exp isn't thrown away by surprise (card doc).
	if GameState.spec_maxed(rules) and not spec_name.is_empty():
		hero_box.add_child(make_label("⚠ %s is max level (%d): this trip's class Exp is lost. Change Spec to level another one." % [
			spec_name, GameState.SPEC_MAX_LEVEL], 15, BAD_COLOR, true))
	hero_box.add_child(make_label("%d HP%s" % [GameState.player_max_hp(), "  ·  %d Armor" % rules.armor if rules.armor > 0 else ""], 16, Color(1, 0.6, 0.6), true))

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	buttons.add_child(make_button("Change Class", _go_to.bind(CHARACTER_SCENE)))
	buttons.add_child(make_button("Class Track", _show_screen.bind(TRACK_SCENE)))
	if GameState.specs_open() and not GameState.specs_for(rules).is_empty():
		buttons.add_child(make_button("Change Spec", _go_to.bind(SPEC_SCENE)))
	if GameState.talents_open():
		var points := GameState.talent_points_left(rules)
		var talents := make_button("Talents" + (" (%d)" % points if points > 0 else ""), func() -> void:
			GameState.talents_return_scene = scene_file_path
			get_tree().change_scene_to_file(TALENTS_SCENE))
		buttons.add_child(talents)
	hero_box.add_child(buttons)

	# The deck: how big, and what's in it.
	var deck := GameState.deck
	var deck_line := make_label("Deck: %d cards (%d to %d)" % [deck.size(), rules.min_deck_size, rules.deck_size_limit()], 18,
		GOLD_COLOR if deck.size() >= rules.min_deck_size else BAD_COLOR, true)
	hero_box.add_child(deck_line)
	var counts := {}
	for card in deck:
		counts[card.card_name] = counts.get(card.card_name, 0) + 1
	var parts: Array[String] = []
	for card_name in counts:
		parts.append(card_name + (" ×%d" % counts[card_name] if counts[card_name] > 1 else ""))
	hero_box.add_child(make_label(", ".join(parts) if not parts.is_empty() else "(empty)", 15, DIM_COLOR, true))
	hero_box.add_child(make_button("Edit Deck", _go_to.bind(DECK_BUILDER_SCENE)))


func fill_map_cards() -> void:
	# Your own map cards for this place ("Yours" in the sheet), unlocked ones only.
	var yours: Array[RoomCard] = []
	var locked := 0
	for card in area.cards():
		if card.deck_part != RoomCard.DECK_YOURS:
			continue
		if GameState.is_room_unlocked(area, card):
			yours.append(card)
		else:
			locked += 1
	var taken := 0
	for card in yours:
		if not GameState.is_map_card_off(area, card):
			taken += card.copies
	var in_deck := mini(taken, DungeonRun.YOUR_SLOTS)
	cards_box.add_child(make_label("The map deck is %d cards: the %s's base cards, your cards (%d / %d), and Filler for the rest." % [
		DungeonRun.DECK_SIZE, area.display_name, in_deck, DungeonRun.YOUR_SLOTS], 15, DIM_COLOR, true))
	if taken > DungeonRun.YOUR_SLOTS:
		cards_box.add_child(make_label("Only %d fit: some of yours are left out at random." % DungeonRun.YOUR_SLOTS, 15, BAD_COLOR, true))
	if yours.is_empty():
		cards_box.add_child(make_label("You have no map cards of your own yet. Quests and Maps give you some.", 16, Color.WHITE, true))
	for card in yours:
		cards_box.add_child(make_map_card_row(card))
	if locked > 0:
		cards_box.add_child(make_label("%d more to find (quests, Maps from the Mapmaker or chests)." % locked, 15, DIM_COLOR, true))
	cards_box.add_child(make_label("Fewer fights = a safer trip. More fights = more drops and Exp, but more Danger.", 14, DIM_COLOR, true))


# One of your map cards, with a tick box: ticked = it goes in the deck.
func make_map_card_row(card: RoomCard) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tick := CheckBox.new()
	tick.button_pressed = not GameState.is_map_card_off(area, card)
	tick.focus_mode = Control.FOCUS_NONE
	tick.toggled.connect(func(on: bool) -> void:
		GameState.set_map_card_off(area, card, not on)
		GameState.save_game()
		refresh())
	row.add_child(tick)
	var picture := TextureRect.new()
	picture.texture = card.art
	picture.custom_minimum_size = Vector2(34, 34)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(make_label("%s  ×%d" % [card.room_name, card.copies], 17, Color.WHITE, true))
	var tile := make_label("%s  ·  %s" % [card.tile_name(), card.type_name()], 14, RoomCard.TILE_COLORS[card.tile], true)
	text.add_child(tile)
	row.add_child(text)
	row.tooltip_text = card.text
	row.modulate.a = 1.0 if tick.button_pressed else 0.55
	return row


func fill_pack() -> void:
	# The flask: pick one of the flasks you've brewed.
	var flask_row := HBoxContainer.new()
	flask_row.add_theme_constant_override("separation", 8)
	var flask_icon := TextureRect.new()
	flask_icon.texture = FLASK_ICON
	flask_icon.custom_minimum_size = Vector2(32, 32)
	flask_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var current := GameState.current_flask()
	if current:
		flask_icon.self_modulate = current.color
	flask_row.add_child(flask_icon)
	var choice := OptionButton.new()
	choice.focus_mode = Control.FOCUS_NONE
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var unlocked: Array[Flask] = []
	for flask in GameState.load_flasks():
		if GameState.is_flask_unlocked(flask):
			unlocked.append(flask)
			choice.add_item(flask.flask_name)
			if flask == current:
				choice.select(unlocked.size() - 1)
	choice.item_selected.connect(func(index: int) -> void:
		GameState.chosen_flask = unlocked[index].flask_name
		GameState.save_game()
		refresh())
	if unlocked.is_empty():  # No flask brewed yet (a quest gives you the first).
		current = null
		flask_icon.modulate.a = 0.4
		flask_row.add_child(make_label("No flask yet", 18, DIM_COLOR))
	else:
		flask_row.add_child(choice)
	pack_box.add_child(flask_row)
	if current:
		var stats := GameState.flask_stats(current)
		pack_box.add_child(make_label("%d charge%s: %s" % [stats[Flask.CHARGES], "" if stats[Flask.CHARGES] == 1 else "s",
			Flask.effect_text(stats)], 15, DIM_COLOR, true))

	# Torches: for DARK places, but they take backpack space.
	var torch_row := HBoxContainer.new()
	torch_row.add_theme_constant_override("separation", 6)
	var torch_icon := TextureRect.new()
	torch_icon.texture = TORCH_ICON
	torch_icon.custom_minimum_size = Vector2(32, 32)
	torch_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	torch_row.add_child(torch_icon)
	# Torches come from your Bank: craft them at the Guild Hall's crafting bench.
	var in_bank := GameState.material_count(DungeonRun.TORCH)
	var packed := mini(GameState.packed_torches, in_bank)
	var torch_label := make_label("Torches: %d  (Bank %d)" % [packed, in_bank], 18, Color.WHITE)
	torch_label.custom_minimum_size = Vector2(170, 0)
	torch_label.tooltip_text = "Torches light up DARK places. Craft more at the Guild Hall's crafting bench."
	torch_row.add_child(torch_label)
	var fewer := make_button("−", _change_torches.bind(-1))
	fewer.disabled = packed <= 0
	torch_row.add_child(fewer)
	var more := make_button("+", _change_torches.bind(1))
	more.disabled = packed >= mini(GameState.MAX_PACKED_TORCHES, in_bank)
	torch_row.add_child(more)
	pack_box.add_child(torch_row)
	# Tools: crowbars and bombs to use on map cards. Made from Bank materials
	# when you set out (as many as you can afford then).
	var tool_slots := 0
	for tool_name: String in DungeonRun.TOOLS:
		var packed: int = GameState.packed_tools.get(tool_name, 0)
		tool_slots += DungeonRun.stacks(packed)
		var cost: Dictionary = GameState.TOOL_COSTS.get(tool_name, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = TOOL_ICONS[tool_name]
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon)
		var label := make_label("%ss: %d" % [tool_name, packed], 18, Color.WHITE)
		label.custom_minimum_size = Vector2(110, 0)
		row.add_child(label)
		var less := make_button("−", _change_tool.bind(tool_name, -1))
		less.disabled = packed <= 0
		row.add_child(less)
		var plus := make_button("+", _change_tool.bind(tool_name, 1))
		plus.disabled = packed >= GameState.MAX_PACKED_TOOLS
		row.add_child(plus)
		var all_of_them := {}  # What all the packed ones cost together.
		for material_name: String in cost:
			all_of_them[material_name] = cost[material_name] * maxi(packed, 1)
		var afford := GameState.has_materials(all_of_them)
		var price := make_label("each: %s" % MaterialInfo.costs_text(cost), 14, DIM_COLOR if afford or packed == 0 else Color(1, 0.55, 0.45))
		price.tooltip_text = "Made from the Bank's materials when you set out.%s" % (
			"" if afford or packed == 0 else " You can't afford all %d right now: you'll take as many as you can." % packed)
		price.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(price)
		pack_box.add_child(row)
	var slots := DungeonRun.BACKPACK_SLOTS + GameState.town_bonus(TownBuilding.BACKPACK_SLOTS)
	var torch_slots := DungeonRun.stacks(packed)
	pack_box.add_child(make_label("Backpack: %d slots, %d free for loot. Torches share one slot, and each kind of tool another (up to %d of one thing in a slot)." % [
		slots, slots - torch_slots - tool_slots, DungeonRun.BACKPACK_STACK], 15, DIM_COLOR, true))

	# What you bought in town for this trip.
	pack_box.add_child(make_label("Bought in town:", 18, GOLD_COLOR))
	var bought: Array[String] = []
	for potion_name in GameState.pending_potions:
		bought.append(potion_name)
	for enchant_name in GameState.pending_enchants:
		bought.append("Enchant: " + enchant_name)
	pack_box.add_child(make_label(", ".join(bought) if not bought.is_empty() else "Nothing. (Potions at the Alchemist, enchants at the Enchanter.)", 15, DIM_COLOR, true))


func fill_loadouts() -> void:
	for i in GameState.loadouts.size():
		var loadout: Dictionary = GameState.loadouts[i]
		var load_button := make_button(str(loadout.get("name", "?")), _on_load.bind(loadout, str(loadout.get("name", ""))))
		load_button.tooltip_text = "%s · %s · %d cards. Click to load it." % [loadout.get("class", "?"),
			loadout.get("spec", "") if not str(loadout.get("spec", "")).is_empty() else "no spec", loadout.get("deck", []).size()]
		loadout_row.add_child(load_button)
		var delete := make_button("×", _on_delete_loadout.bind(i))
		delete.tooltip_text = "Delete this loadout."
		delete.custom_minimum_size = Vector2(28, 0)
		loadout_row.add_child(delete)


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

# Edit the deck / class / spec, then come back here (GameState.preparing).
func _go_to(scene: String) -> void:
	GameState.save_game()
	GameState.preparing = true
	get_tree().change_scene_to_file(scene)


# A screen that only looks (Binder, Class Track): its Back comes straight here.
func _show_screen(scene: String) -> void:
	GameState.save_game()
	GameState.screen_return_scene = scene_file_path
	get_tree().change_scene_to_file(scene)


func _change_tool(tool_name: String, by: int) -> void:
	var packed: int = clampi(GameState.packed_tools.get(tool_name, 0) + by, 0, GameState.MAX_PACKED_TOOLS)
	if packed > 0:
		GameState.packed_tools[tool_name] = packed
	else:
		GameState.packed_tools.erase(tool_name)
	GameState.save_game()
	refresh()


func _change_torches(by: int) -> void:
	var in_bank := GameState.material_count(DungeonRun.TORCH)
	GameState.packed_torches = clampi(mini(GameState.packed_torches, in_bank) + by, 0, mini(GameState.MAX_PACKED_TORCHES, in_bank))
	GameState.save_game()
	refresh()


func _on_load(loadout: Dictionary, what: String) -> void:
	var skipped := GameState.apply_loadout(loadout)
	refresh()
	if skipped.is_empty():
		show_status("Loaded %s." % what, GOLD_COLOR)
	else:
		show_status("Loaded %s, but skipped %s." % [what, ", ".join(skipped)], BAD_COLOR)


func _on_save_loadout() -> void:
	var loadout_name := name_edit.text.strip_edges()
	if loadout_name.is_empty():
		loadout_name = "%s %d" % [GameState.character_class.display_name, GameState.loadouts.size() + 1]
	if GameState.save_loadout(loadout_name):
		name_edit.text = ""
		refresh()
		show_status("Saved loadout: %s." % loadout_name, GOLD_COLOR)
	else:
		show_status("You can keep %d loadouts. Delete one (×) to make room." % GameState.MAX_LOADOUTS, BAD_COLOR)


func _on_delete_loadout(index: int) -> void:
	GameState.delete_loadout(index)
	refresh()


func _on_set_out() -> void:
	if not set_out_problem().is_empty():
		return
	if not guided:
		GameState.last_loadout = GameState.current_loadout("Last time")
	GameState.save_game()
	GameState.start_run()  # A fresh dungeon, at full HP.
	get_tree().change_scene_to_file(DUNGEON_SCENE)


func show_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# Little helpers
# ---------------------------------------------------------------------------

func make_label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func make_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button
