# town.gd
#
# The town (scenes/town.tscn): where you come back to after every run.
# Only the GUILD HALL stands when you arrive. The other buildings appear (in
# ruins) once you have their blueprint, and you build and upgrade them from
# inside the Guild Hall, with materials and gold (see town_building.gd and
# data/progression/town.csv). Each stage opens something new.
#
# Like the map, the buildings are made here in code, one panel per file in
# town/, so a new row in the sheet shows up on its own.
#
# Click the Inn for the QUEST SCREEN (every quest you're on). The road at the
# bottom-right (town_road.gd) leads out to the map.
#
# THE START OF THE GAME is a few one-time STORY BEATS, played here in order
# (play_story()). Each is remembered in GameState.story_beats once seen:
#   1. Welcome      The King's welcome, then the Inn blueprint pops up like
#                   an unlock. "Read Blueprint" shows the Inn's ruins, and a
#                   guide explains building and points at the Guild Hall.
#   2. King's Stone Your first visit to the Guild Hall: 5 Stone pops up in
#                   the Bank, and a guide shows you how to build the Inn.
#   3. Inn Built    The Innkeeper thanks you and asks for help: the QUEST
#                   tutorial, then his first two quests (Gather Stone, Need Hops).
#   4. Adventurer Trained   Back from the Adventurer's training and the deck
#                   builder: the Innkeeper's slime news, and the next quests.
extends Control

const SHOP_SCENE := "res://scenes/shop.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CHARACTER_SCENE := "res://scenes/character_select.tscn"
const RUINS := preload("res://art/town/ruins.svg")
const FLASK_ICON := preload("res://art/potions/flask.svg")
const POTION_ICON := preload("res://art/potions/potion.svg")
const BOOSTER_ICON := preload("res://icons/booster.svg")
const BLUEPRINT_ICON := preload("res://art/town/blueprint.svg")
const QUEST_ICON := preload("res://art/town/quest.svg")
const GUILD_HALL_ICON := preload("res://art/town/guild_hall.svg")
const INN_ICON := preload("res://art/town/inn.svg")
const SLIME_ART := preload("res://art/enemies/slime.svg")
# Story beats (see the top of this file). The milestones live in GameState
# because quests.csv can name them in Starts After.
const WELCOME := "Welcome"
const KINGS_STONE := "King's Stone"
const KINGS_STONE_AMOUNT := 5
const GOLD_COLOR := Color(1, 0.84, 0.35)
const DONE_COLOR := Color(0.55, 0.95, 0.55)

@onready var gold_label: Label = %GoldLabel
@onready var summary_label: Label = %SummaryLabel
@onready var building_row: HBoxContainer = %BuildingRow
@onready var message_label: Label = %MessageLabel
@onready var pending_label: Label = %PendingLabel
@onready var deck_button: Button = %DeckButton
@onready var next_run_button: Button = %NextRunButton

var flask_button: Button  # "Flask: Health Flask", next to Edit Deck.
var packs_button: Button  # "Your Packs (3)": open them (at the Shop, or before it's built).
var road: TownRoad  # The road out of town, with its "To the Map" sign (town_road.gd).
var overlay: Control  # The quest panel or the Guild Hall while it's open.
var panels := {}  # Building name -> its panel on the street (for guides to point at).
# Parts of the Guild Hall screen, for its first-visit guide.
var bank_box: Control
var build_rows := {}  # Building name -> its row in the Build list.
var flask_layer: Control  # The Alchemist screen while it's open (null when closed).
var alchemist_tab := "Flasks"  # Which tab of the Alchemist screen: "Flasks" or "Potions".


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	GameState.check_quest()
	deck_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(DECK_BUILDER_SCENE))
	# The road to the map replaces the old "Start Next Run" button.
	next_run_button.visible = false
	road = TownRoad.new()
	road.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	next_run_button.add_sibling(road)
	flask_button = Button.new()
	flask_button.icon = FLASK_ICON
	flask_button.add_theme_constant_override("icon_max_width", 30)  # The svg is 64px: shrink it to fit.
	flask_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	flask_button.pressed.connect(open_alchemist.bind("Flasks"))
	deck_button.add_sibling(flask_button)
	# A booster pack you can click to open your packs (on the Shop screen,
	# which only opens packs until the Shop is built).
	packs_button = Button.new()
	packs_button.icon = BOOSTER_ICON
	packs_button.add_theme_constant_override("icon_max_width", 34)
	packs_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	packs_button.tooltip_text = "Open your booster packs."
	packs_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))
	flask_button.add_sibling(packs_button)
	summary_label.text = run_summary()
	message_label.text = ""
	refresh()
	# The welcome, the Innkeeper... or just any new quests' stories.
	play_story()


# How the last run went (empty if you haven't been on one yet).
func run_summary() -> String:
	var dungeon := GameState.dungeon
	var area_name := GameState.current_area.display_name if GameState.current_area else ""
	match dungeon.result if dungeon else "":
		"won":
			return "You beat the %s boss after %d fight(s), and took home %s!" % [area_name, dungeon.fights_won, dungeon.loot_text()]
		"left":
			return "You left the %s after %d fight(s), with %s." % [area_name, dungeon.fights_won, dungeon.loot_text()]
		"died":
			if not GameState.sack_open():
				return "You fell after %d fight(s), and lost what you found." % dungeon.fights_won
			return "You fell after %d fight(s). Your Save Sack brought home %s." % [dungeon.fights_won, dungeon.loot_text()]
	return "Build up the town with the gold and materials you bring home from the dungeons."


# Build every building's panel again (after restoring or buying something).
func refresh() -> void:
	gold_label.text = "Gold %d" % GameState.gold
	for material_name in GameState.materials:
		if GameState.materials[material_name] > 0:
			gold_label.text += "   %s %d" % [material_name, GameState.materials[material_name]]
	for old in building_row.get_children():
		old.queue_free()
	panels.clear()
	for building in GameState.load_town():
		if GameState.has_blueprint(building):  # The rest stay hidden until a quest gives their blueprint.
			panels[building.building_name] = make_building(building)
			building_row.add_child(panels[building.building_name])
	# While the Inn waits to be built, the Guild Hall glows: go in there!
	if inn_waiting() and panels.has("Guild Hall"):
		var glow: Control = panels["Guild Hall"]
		var tween := glow.create_tween().set_loops()
		tween.tween_property(glow, "modulate", Color(1.35, 1.25, 0.9), 0.6)
		tween.tween_property(glow, "modulate", Color.WHITE, 0.6)
	# You can head out once any area is open (after the Inn: the Architect's guided run first).
	var can_go := GameState.load_areas().any(func(area: Area) -> bool: return GameState.is_area_unlocked(area))
	road.set_open(can_go)
	# No adventurer yet: you're running the town, so there's no deck or flask to look at.
	deck_button.visible = GameState.adventurers_here()
	flask_button.visible = GameState.adventurers_here()
	packs_button.visible = GameState.pack_count() > 0
	packs_button.text = "Open Packs (%d)" % GameState.pack_count()
	packs_button.theme_type_variation = &"PrimaryButton"  # Gold: there's something to open!
	var ready_for_run: Array[String] = []
	if not GameState.pending_enchants.is_empty():
		ready_for_run.append("Enchants: " + ", ".join(GameState.pending_enchants))
	if not GameState.pending_potions.is_empty():
		ready_for_run.append("Potions: " + ", ".join(GameState.pending_potions))
	var flask := GameState.current_flask()
	if flask:
		flask_button.text = "Flask: %s" % flask.flask_name
		flask_button.add_theme_color_override("icon_normal_color", flask.color)
		flask_button.add_theme_color_override("icon_hover_color", flask.color)
		flask_button.tooltip_text = "Choose and upgrade the flask you take into the dungeon."
	else:
		flask_button.text = "Flask: none yet"
		flask_button.tooltip_text = "Brew your first flask at the Alchemist."
	if flask_layer:
		build_alchemist_screen()
	pending_label.text = ("Ready for your next run:  " + "   ·   ".join(ready_for_run)) if not ready_for_run.is_empty() else ""


func make_building(building: TownBuilding) -> PanelContainer:
	var stage := GameState.town_stage(building)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(228, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.09, 0.95)
	style.border_color = GOLD_COLOR if stage > 0 else Color(0.4, 0.36, 0.32)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	# The picture: greyed out with rubble on top while it's in ruins.
	var picture := TextureRect.new()
	picture.texture = building.icon
	picture.custom_minimum_size = Vector2(0, 110)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(picture)
	if stage == 0:
		picture.modulate = Color(0.45, 0.42, 0.4)
		var rubble := TextureRect.new()
		rubble.texture = RUINS
		rubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rubble.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.add_child(rubble)

	box.add_child(make_label(building.building_name, 22, Color.WHITE))
	var status := "In ruins" if stage == 0 else "Stage %d / %d" % [stage, building.max_stage()]
	if stage >= building.max_stage():
		status = "Fully restored ✓"
	box.add_child(make_label(status, 15, DONE_COLOR if stage > 0 else Color(1, 1, 1, 0.6)))
	box.add_child(make_label(building.description, 13, Color(1, 1, 1, 0.75)))

	# Each stage: done (green ✓) or still to come (grey).
	for i in building.max_stage():
		var line := make_label(("✓ " if i < stage else "○ ") + building.stage_texts[i], 13,
			DONE_COLOR if i < stage else Color(1, 1, 1, 0.45))
		box.add_child(line)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	# What you can do here, once it's open.
	var action := make_action(building, stage)
	if action:
		box.add_child(action)
	# Building and upgrading happen inside the Guild Hall: just say what's next.
	if stage < building.max_stage():
		var verb := "Build" if stage == 0 else "Upgrade"
		var can := GameState.restore_blocked(building).is_empty()
		box.add_child(make_label("%s it at the Guild Hall  (%s)" % [verb, price_text(building, stage)], 13,
			GOLD_COLOR if can else Color(1, 1, 1, 0.5)))
	# Click anywhere on the built Inn to see your quests, or on the Guild Hall to go in.
	var on_click := Callable()
	if stage > 0 and building.bonus(TownBuilding.INN, stage) > 0:
		panel.tooltip_text = "Click the Inn to see your quests."
		on_click = show_quest_board
	elif stage > 0 and building.bonus(TownBuilding.BANK, stage) > 0:
		panel.tooltip_text = "Click the Guild Hall to build, upgrade and see your Bank."
		on_click = show_guild_hall
	if on_click.is_valid():
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	return panel


# "5 Stone" / "40 gold" / "15 gold, 5 Green Ooze" / "free": the next stage's price.
func price_text(building: TownBuilding, stage: int) -> String:
	var prices: Array[String] = []
	if building.cost_of_next(stage) > 0:
		prices.append("%d gold" % building.cost_of_next(stage))
	var needs := building.materials_for_next(stage)
	if not needs.is_empty():
		prices.append(MaterialInfo.costs_text(needs))
	return ", ".join(prices) if not prices.is_empty() else "free"


# You have the Inn's blueprint but haven't built it yet.
func inn_waiting() -> bool:
	var inn := GameState.find_building("Inn")
	return inn != null and GameState.has_blueprint(inn) and GameState.town_stage(inn) == 0


# The building's own button: Enter the Shop, buy an enchant / potion / map.
func make_action(building: TownBuilding, stage: int) -> Button:
	var button := Button.new()
	if building.bonus(TownBuilding.INN, stage) > 0:
		var ready := GameState.quests_ready_count()
		button.text = "Quests" + ("  ✓ %d ready!" % ready if ready > 0 else "  (%d)" % GameState.quests_active().size())
		button.tooltip_text = "Every quest you're on, how far along it is, and what it gives you."
		if ready > 0:
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(show_quest_board)
	elif building.bonus(TownBuilding.BANK, stage) > 0:
		button.text = "Enter the Guild Hall"
		button.tooltip_text = "Build and upgrade the town, and see the materials in your Bank."
		if inn_waiting():
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(show_guild_hall)
	elif building.bonus(TownBuilding.SHOP, stage) > 0:
		button.text = "Enter the Shop"
		button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))
	elif building.bonus(TownBuilding.ENCHANTER, stage) > 0:
		button.text = "Buy an Enchant  (%d gold)" % GameState.ENCHANT_PRICE
		button.tooltip_text = "A random enchant for your next run: put it on a card from the dungeon screen."
		button.disabled = GameState.gold < GameState.ENCHANT_PRICE
		button.pressed.connect(_buy_enchant)
	elif building.bonus(TownBuilding.ALCHEMIST, stage) > 0:
		button.text = "Enter the Alchemist"
		button.tooltip_text = "Brew and upgrade flasks, and unlock potions so they drop in the dungeon."
		button.pressed.connect(open_alchemist.bind("Flasks"))
	elif building.bonus(TownBuilding.MAPMAKER, stage) > 0:
		button.text = "Buy a Map  (%d gold)" % GameState.MAP_PRICE
		button.tooltip_text = "Unlocks a new room card in a dungeon you can visit."
		button.disabled = GameState.gold < GameState.MAP_PRICE or map_area() == null
		button.pressed.connect(_buy_map)
	else:
		return null
	return button


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# The Build button in the Guild Hall.
func _on_restore_pressed(building: TownBuilding) -> void:
	if not GameState.restore(building):
		return
	var stage := GameState.town_stage(building)
	message_label.text = "The %s is %s: %s!" % [building.building_name,
		"built" if stage == 1 and building.needs_blueprint else "upgraded", building.stage_texts[stage - 1]]
	close_overlay()
	refresh()
	# A brand new building pops up on the street.
	if stage == 1 and panels.has(building.building_name):
		pop_in(panels[building.building_name])
	# The Inn: the Innkeeper comes out to thank you (play_story() does the rest).
	if not GameState.story_beats.has(GameState.INN_BUILT) and building.bonus(TownBuilding.INN, stage) > 0:
		get_tree().create_timer(0.7).timeout.connect(play_story)
		return
	# Building what a quest asked for: straight to the quests, to hand it in.
	if GameState.quests_active().any(func(q: Quest) -> bool: return q.objective == Quest.BUILD and GameState.quest_ready(q)):
		show_quest_board()
	else:
		show_guild_hall()


# Grow a panel in from nothing with a little bounce (a new building!).
func pop_in(control: Control) -> void:
	await get_tree().process_frame  # Wait until it has a size, so it grows from its middle.
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size / 2
	control.scale = Vector2(0.2, 0.2)
	control.create_tween().tween_property(control, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _buy_enchant() -> void:
	var enchant := Enchant.pick_random(GameState.load_enchants())
	if enchant == null or GameState.gold < GameState.ENCHANT_PRICE:
		return
	GameState.gold -= GameState.ENCHANT_PRICE
	GameState.pending_enchants.append(enchant.enchant_name)
	GameState.save_game()
	message_label.text = "The Enchanter hands you %s: %s" % [enchant.enchant_name, enchant.description]
	refresh()


# The area a map is for: the one you were last in, or any other open area
# that still has locked rooms. null if there's none.
func map_area() -> Area:
	var areas: Array[Area] = [GameState.current_area]  # The last one you were in first...
	areas.append_array(GameState.load_areas())  # ...then the rest.
	for area in areas:
		if area and GameState.is_area_unlocked(area) and area.rooms.any(
				func(card: RoomCard) -> bool: return not GameState.is_room_unlocked(area, card)):
			return area
	return null


func _buy_map() -> void:
	var area := map_area()
	if area == null or GameState.gold < GameState.MAP_PRICE:
		return
	GameState.gold -= GameState.MAP_PRICE
	var room := GameState.unlock_random_room(area)  # Also saves.
	message_label.text = "A new room for the %s: %s!" % [area.display_name, room.room_name]
	refresh()


# --- The Alchemist -------------------------------------------------------------
# A screen on top of the town with two tabs:
#   Flasks  - one panel per flask (flasks/*.tres). Pick the one you take on
#             your next run, brew the ones you don't have, upgrade the rest.
#   Potions - one panel per potion (potions/*.tres). Unlock a potion so it
#             can drop in the dungeon, then make it Stronger or More Common.
# The town's Flask button opens it on the Flasks tab too.

func open_alchemist(tab: String = "Flasks") -> void:
	alchemist_tab = tab
	flask_layer = ColorRect.new()
	flask_layer.color = Color(0, 0, 0, 0.85)
	flask_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flask_layer)
	build_alchemist_screen()


func close_alchemist() -> void:
	flask_layer.queue_free()
	flask_layer = null


func build_alchemist_screen() -> void:
	for old in flask_layer.get_children():
		old.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flask_layer.add_child(center)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	center.add_child(layout)
	layout.add_child(make_label("The Alchemist", 32, Color.WHITE))

	# The two tabs: plain buttons, the open one gold and pressed in.
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	layout.add_child(tabs)
	for tab in ["Flasks", "Potions"]:
		var tab_button := Button.new()
		tab_button.text = tab
		tab_button.icon = FLASK_ICON if tab == "Flasks" else POTION_ICON
		tab_button.add_theme_constant_override("icon_max_width", 24)
		tab_button.custom_minimum_size = Vector2(170, 42)
		if tab == alchemist_tab:
			tab_button.theme_type_variation = &"PrimaryButton"
		tab_button.pressed.connect(func() -> void:
			alchemist_tab = tab
			build_alchemist_screen())
		tabs.add_child(tab_button)

	var wallet := "Gold %d" % GameState.gold
	if GameState.material_count(GameState.POTION_UNLOCK_MATERIAL) > 0 or alchemist_tab == "Potions":
		wallet += "   ·   %s %d" % [GameState.POTION_UNLOCK_MATERIAL, GameState.material_count(GameState.POTION_UNLOCK_MATERIAL)]
	layout.add_child(make_label(wallet, 18, GOLD_COLOR))
	if alchemist_tab == "Flasks":
		build_flasks_tab(layout)
	else:
		build_potions_tab(layout)

	var close := Button.new()
	close.text = "Done"
	close.custom_minimum_size = Vector2(160, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_alchemist)
	layout.add_child(close)


func build_flasks_tab(layout: VBoxContainer) -> void:
	var note := "Here you brew flasks you don't have, or upgrade the ones you do.\nTake one flask into each run: its charges refill when you Rest at a campfire."
	if not GameState.alchemist_open():
		note += "\nBuild the Alchemist to brew and upgrade flasks."
	layout.add_child(make_label(note, 15, Color(1, 1, 1, 0.75)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(row)
	for flask in GameState.load_flasks():
		row.add_child(make_flask_panel(flask))


func build_potions_tab(layout: VBoxContainer) -> void:
	var note := "Unlock a potion and it can drop in the dungeon. Then make it Stronger, or More Common so it drops more often."
	if not GameState.potions_open():
		note = "Build the Alchemist first: no potions drop in the dungeon until then."
	layout.add_child(make_label(note, 15, Color(1, 1, 1, 0.75)))
	# 7 potions: 4 on the first row, 3 on the second.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var holder := CenterContainer.new()
	holder.add_child(grid)
	layout.add_child(holder)
	var total_weight := 0  # For "drops X% of the time".
	for potion in GameState.unlocked_potion_list():
		total_weight += GameState.potion_drop_weight(potion)
	var potions := GameState.load_potions().duplicate()
	potions.sort_custom(func(a: Potion, b: Potion) -> bool:
		return a.rarity < b.rarity if a.rarity != b.rarity else a.potion_name < b.potion_name)
	for potion in potions:
		grid.add_child(make_potion_panel(potion, total_weight))


func make_potion_panel(potion: Potion, total_weight: int) -> PanelContainer:
	var unlocked := GameState.is_potion_unlocked(potion)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.09, 0.97)
	style.border_color = potion.color.darkened(0.2) if unlocked else Color(0.35, 0.32, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	# Bottle + name + rarity in one line, to keep the panel short.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	var picture := TextureRect.new()
	picture.texture = POTION_ICON
	picture.self_modulate = potion.color if unlocked else Color(0.4, 0.4, 0.4)
	picture.custom_minimum_size = Vector2(40, 40)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(picture)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var title := make_label(potion.potion_name, 18, Color.WHITE if unlocked else Color(1, 1, 1, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(title)
	var rarity_name: String = CardData.Rarity.keys()[potion.rarity].capitalize()
	var rarity := make_label(rarity_name + ("" if unlocked else "  ·  Locked"), 12, CardData.RARITY_COLORS.get(potion.rarity, Color.WHITE))
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(rarity)

	# What it does right now (with your Stronger upgrade).
	box.add_child(make_label(GameState.strengthened(potion).effect_text(), 15, potion.color.lightened(0.4)))

	if not unlocked:
		var unlock := Button.new()
		unlock.custom_minimum_size = Vector2(0, 36)
		unlock.text = "Unlock  (%d gold, %s)" % [GameState.potion_unlock_gold(potion),
			MaterialInfo.costs_text(GameState.potion_unlock_materials(potion))]
		unlock.theme_type_variation = &"PrimaryButton"
		unlock.disabled = not GameState.can_unlock_potion(potion)
		if not GameState.potions_open():
			unlock.tooltip_text = "Build the Alchemist first."
		elif not GameState.has_materials(GameState.potion_unlock_materials(potion)):
			unlock.tooltip_text = "Green Slimes drop Green Ooze."
		else:
			unlock.tooltip_text = "Once unlocked, it can drop in the dungeon."
		unlock.pressed.connect(_unlock_potion.bind(potion))
		box.add_child(unlock)
		return panel

	var chance := 100.0 * GameState.potion_drop_weight(potion) / maxf(total_weight, 1)
	box.add_child(make_label("%d%% of potion drops" % roundi(chance), 13, Color(1, 1, 1, 0.65)))
	# The two upgrades, one line each.
	for upgrade in [GameState.STRONGER, GameState.MORE_COMMON]:
		var stage := GameState.potion_upgrade_stage(potion, upgrade)
		var cost := GameState.potion_upgrade_cost(potion, upgrade)
		var stages: int = GameState.POTION_UPGRADES[upgrade].size()
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var text := make_label("", 13, DONE_COLOR if cost < 0 else Color.WHITE)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(84, 30)
		if cost < 0:
			text.text = "✓ %s (%d/%d)" % [upgrade, stage, stages]
			buy.text = "Done"
			buy.disabled = true
		else:
			# What the next stage gives: "Stronger (0/2): Heal 12".
			var next := GameState.strengthened(potion, stage + 1).effect_text() if upgrade == GameState.STRONGER \
				else "drops %dx as often" % (stage + 2)
			text.text = "%s (%d/%d): %s" % [upgrade, stage, stages, next]
			buy.text = "%d gold" % cost
			buy.disabled = GameState.gold < cost
			buy.pressed.connect(_buy_potion_upgrade.bind(potion, upgrade))
		line.add_child(text)
		line.add_child(buy)
		box.add_child(line)
	return panel


func _unlock_potion(potion: Potion) -> void:
	if GameState.unlock_potion(potion):
		message_label.text = "%s unlocked: it can drop in the dungeon now!" % potion.potion_name
	refresh()


func _buy_potion_upgrade(potion: Potion, upgrade: String) -> void:
	if GameState.buy_potion_upgrade(potion, upgrade):
		message_label.text = "%s upgraded: %s" % [potion.potion_name, upgrade]
	refresh()


func make_flask_panel(flask: Flask) -> PanelContainer:
	var unlocked := GameState.is_flask_unlocked(flask)
	var chosen := unlocked and GameState.current_flask() == flask
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.09, 0.97)
	style.border_color = GOLD_COLOR if chosen else (flask.color.darkened(0.3) if unlocked else Color(0.35, 0.32, 0.3))
	style.set_border_width_all(3 if chosen else 2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var picture := TextureRect.new()
	picture.texture = FLASK_ICON
	picture.self_modulate = flask.color if unlocked else Color(0.4, 0.4, 0.4)
	picture.custom_minimum_size = Vector2(0, 72)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(picture)
	box.add_child(make_label(flask.flask_name, 22, Color.WHITE))
	box.add_child(make_label(flask.description, 13, Color(1, 1, 1, 0.7)))
	var stats := GameState.flask_stats(flask)
	var charges: int = stats[Flask.CHARGES]
	box.add_child(make_label("%s\n%d charge%s" % [Flask.effect_text(stats), charges, "" if charges == 1 else "s"],
		17, flask.color.lightened(0.35)))

	# Take it / taken / unlock.
	var main := Button.new()
	main.custom_minimum_size = Vector2(0, 40)
	if chosen:
		main.text = "✓ Taking this one"
		main.disabled = true
	elif unlocked:
		main.text = "Take this flask"
		main.theme_type_variation = &"PrimaryButton"
		main.pressed.connect(_choose_flask.bind(flask))
	else:
		# The price can be gold, materials, or both ("Brew  (3 Green Ooze)").
		var needs := MaterialInfo.parse_costs(flask.unlock_materials)
		var price: Array[String] = []
		if flask.unlock_cost > 0:
			price.append("%d gold" % flask.unlock_cost)
		if not needs.is_empty():
			price.append(MaterialInfo.costs_text(needs))
		main.text = "Brew  (%s)" % ", ".join(price)
		main.theme_type_variation = &"PrimaryButton"
		main.disabled = not GameState.alchemist_open() or GameState.gold < flask.unlock_cost \
			or not GameState.has_materials(needs)
		if not GameState.alchemist_open():
			main.tooltip_text = "Build the Alchemist first."
		elif not GameState.has_materials(needs):
			main.tooltip_text = "You need %s (you have what's in the Bank)." % MaterialInfo.costs_text(needs)
		else:
			main.tooltip_text = "Brewed at the Alchemist."
		main.pressed.connect(_unlock_flask.bind(flask))
	box.add_child(main)

	# Upgrades: one line each, with its next stage and a Buy button.
	box.add_child(make_label("Upgrades", 16, Color(1, 1, 1, 0.85)))
	for upgrade in flask.upgrades():
		var stages := flask.stages_of(upgrade)
		var stage := GameState.flask_upgrade_stage(flask, upgrade)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var text := make_label("", 14, DONE_COLOR if stage >= stages.size() else Color.WHITE)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(96, 32)
		if stage >= stages.size():
			text.text = "✓ %s: %s" % [upgrade, flask.stage_texts[stages[-1]]]
			buy.text = "Done"
			buy.disabled = true
		else:
			var next_row: int = stages[stage]
			text.text = "%s (%d/%d): %s" % [upgrade, stage, stages.size(), flask.stage_texts[next_row]]
			buy.text = "%d gold" % flask.costs[next_row]
			buy.disabled = not unlocked or not GameState.alchemist_open() or GameState.gold < flask.costs[next_row]
			if not GameState.alchemist_open():
				buy.tooltip_text = "Restore the Alchemist first."
			elif not unlocked:
				buy.tooltip_text = "Unlock this flask first."
			buy.pressed.connect(_buy_flask_upgrade.bind(flask, upgrade))
		line.add_child(text)
		line.add_child(buy)
		box.add_child(line)
	return panel


func _choose_flask(flask: Flask) -> void:
	GameState.chosen_flask = flask.flask_name
	GameState.save_game()
	refresh()


func _unlock_flask(flask: Flask) -> void:
	if GameState.unlock_flask(flask):
		GameState.chosen_flask = flask.flask_name  # You probably want to try it.
		GameState.save_game()
		message_label.text = "The Alchemist hands you a %s!" % flask.flask_name
	refresh()


func _buy_flask_upgrade(flask: Flask, upgrade: String) -> void:
	if GameState.buy_flask_upgrade(flask, upgrade):
		var stage := GameState.flask_upgrade_stage(flask, upgrade)
		message_label.text = "%s upgraded: %s" % [flask.flask_name, flask.stage_texts[flask.stages_of(upgrade)[stage - 1]]]
	refresh()


# --- Quests and the Bank -----------------------------------------------------------
# Both open as a panel on top of the town, like the flask screen.

func open_overlay(width: float = 620) -> VBoxContainer:
	close_overlay()
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.09, 0.98)
	style.border_color = GOLD_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


# --- Quests --------------------------------------------------------------------
# The QUEST SCREEN (the Inn's Quests button): every quest you're on, grouped
# by type (Story / Adventurer / Side), each with its objective, a progress
# bar, its rewards and a Hand In button once it's done. Quests you've finished
# are listed at the bottom. A quest's story shows once, when it starts
# (show_next_story).

const QUEST_TYPE_ORDER := ["Story", "Adventurer", "Side"]
const QUEST_TYPE_TITLES := {"Story": "Story", "Adventurer": "Adventurer Quests", "Side": "Side Quests"}


func show_quest_board() -> void:
	var box := open_overlay(820)
	box.add_child(make_label("Quests", 32, GOLD_COLOR))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var active := GameState.quests_active()
	# Quests that are done go at the top, so you see them first.
	var ready := active.filter(GameState.quest_ready)
	if not ready.is_empty():
		list.add_child(_left(make_label("Ready to Hand In!", 20, DONE_COLOR)))
		for quest: Quest in ready:
			list.add_child(make_quest_card(quest))
	# The rest, grouped: Story first, then Adventurer, Side, and any other type.
	var types: Array[String] = []
	types.assign(QUEST_TYPE_ORDER)
	for quest in active:
		if not types.has(quest.quest_type):
			types.append(quest.quest_type)
	for quest_type in types:
		var of_type := active.filter(func(q: Quest) -> bool: return q.quest_type == quest_type and not ready.has(q))
		if of_type.is_empty():
			continue
		var heading := make_label(QUEST_TYPE_TITLES.get(quest_type, quest_type + " Quests"), 20, Color(1, 1, 1, 0.75))
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(heading)
		for quest: Quest in of_type:
			list.add_child(make_quest_card(quest))
	if active.is_empty():
		list.add_child(make_label("No quests right now. More are coming!", 17, Color(1, 1, 1, 0.7)))
	if not GameState.quests_done.is_empty():
		var done := make_label("Finished:  " + ",  ".join(GameState.quests_done), 14, Color(1, 1, 1, 0.45))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(done)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		close_overlay()
		refresh())
	box.add_child(close)


# One quest on the quest screen: name and giver, objective with a progress
# bar, rewards, the story (smaller), and Hand In when it's done.
func make_quest_card(quest: Quest) -> PanelContainer:
	var ready := GameState.quest_ready(quest)
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.13) if not ready else Color(0.16, 0.24, 0.14)
	style.border_color = DONE_COLOR if ready else Color(1, 1, 1, 0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	var title := _left(make_label(quest.quest_name + ("   from " + quest.giver if not quest.giver.is_empty() else ""), 20, GOLD_COLOR))
	info.add_child(title)
	var status := GameState.quest_status(quest)
	info.add_child(_left(make_label("%s   %d / %d" % [quest.objective_text(), status.x, status.y], 17,
		DONE_COLOR if ready else Color.WHITE)))
	var bar := ProgressBar.new()
	bar.max_value = status.y
	bar.value = status.x
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = DONE_COLOR if ready else GOLD_COLOR
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.4)
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", back)
	info.add_child(bar)
	if not quest.rewards.is_empty():
		info.add_child(_left(make_label("Reward: " + quest_reward_text(quest.rewards), 15, Color(0.95, 0.85, 0.6))))
	var story := _left(make_label(quest.text, 13, Color(1, 1, 1, 0.55)))
	info.add_child(story)
	if ready:
		var hand_in := Button.new()
		hand_in.text = "Hand In"
		hand_in.theme_type_variation = &"PrimaryButton"
		hand_in.custom_minimum_size = Vector2(130, 46)
		hand_in.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hand_in.pressed.connect(_on_hand_in.bind(quest))
		row.add_child(hand_in)
	return card


func _left(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


# A quest's story, the first time (who gives it, what to do, any start gift).
# Then the next new quest's story, until there are none left.
func show_next_story(back_to_board: bool) -> void:
	var quest: Quest = null
	while quest == null and not GameState.unseen_quests.is_empty():
		quest = GameState.find_quest(GameState.unseen_quests[0])
		if quest == null or not GameState.active_quests.has(quest.quest_name):
			GameState.unseen_quests.pop_front()  # Gone from the sheet, or already done.
			quest = null
	if quest == null:
		if back_to_board:
			show_quest_board()
		else:
			close_overlay()
			refresh()
		return
	var box := open_overlay()
	var kind := "" if quest.quest_type == "Story" else "  (%s quest)" % quest.quest_type
	if not quest.giver.is_empty():
		box.add_child(make_label(quest.giver + (" writes:" if quest.giver == "The King" else " says:") + kind, 16, Color(1, 1, 1, 0.7)))
	box.add_child(make_label("New quest: " + quest.quest_name, 30, GOLD_COLOR))
	box.add_child(make_label(quest.text, 16, Color.WHITE))
	if not quest.start_gift.is_empty():
		box.add_child(make_label("You receive: " + quest_reward_text(quest.start_gift), 16, DONE_COLOR))
	box.add_child(make_label("Objective: " + quest.objective_text(), 18, GOLD_COLOR))
	if not quest.rewards.is_empty():
		box.add_child(make_label("Reward: " + quest_reward_text(quest.rewards), 15, Color(1, 1, 1, 0.8)))
	var ok := Button.new()
	ok.text = "Let's go!" if GameState.unseen_quests.size() <= 1 else "Next quest →"
	ok.theme_type_variation = &"PrimaryButton"
	ok.custom_minimum_size = Vector2(180, 46)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		GameState.unseen_quests.erase(quest.quest_name)
		GameState.save_game()
		show_next_story(back_to_board))
	box.add_child(ok)


# "Material Lumber 5; Blueprint Inn" -> "5 Lumber, Inn blueprint".
func quest_reward_text(text: String) -> String:
	var parts: Array[String] = []
	for part in text.split(";", false):
		var reward := part.strip_edges()
		var word := reward.get_slice(" ", 0).to_lower()
		var rest := reward.substr(word.length()).strip_edges()
		match word:
			"material": parts.append(MaterialInfo.costs_text(MaterialInfo.parse_costs(rest)))
			"blueprint": parts.append("%s blueprint" % rest)
			"room": parts.append("new room: " + rest.get_slice(":", 1).strip_edges())
			"pack":  # "Small 2" -> "2 Small Plains Booster Packs"
				var count := maxi(rest.get_slice(" ", rest.get_slice_count(" ") - 1).to_int(), 1)
				var pack := GameState.find_pack(rest.get_slice(" ", 0))
				parts.append("%d %s%s" % [count, pack.name, "s" if count > 1 else ""])
			"gold": parts.append("%s gold" % rest)
			"unlock": parts.append("%s unlocked" % rest)
			_: parts.append(reward)
	return ", ".join(parts)


func _on_hand_in(quest: Quest) -> void:
	var talents_before := GameState.talents_open()
	var features_before := GameState.unlocked_features.duplicate()
	var lines := GameState.complete_quest(quest)
	close_overlay()
	refresh()
	# Big moments get the big banner (unlock_banner.gd).
	# "Unlock Adventurer" (the Need Hops quest): the first Adventurer arrives,
	# and Character Select and the deck builder open up. Off to meet them (and
	# their training, the tutorial). Back in town, the Innkeeper has news.
	if GameState.adventurers_here() and not features_before.has(GameState.ADVENTURER_FEATURE):
		var adventurer: CharacterClass = GameState.load_classes()[0]
		UnlockBanner.show_in(self, "A NEW ADVENTURER!", "The %s has arrived" % adventurer.display_name, adventurer.emblem,
			"The Inn's ale is flowing again, and word has spread: the first Adventurer has checked in! From now on, they do the fighting. You keep building the town.\n\nNEW: Character Select and the Deck Builder.  Quest rewards: %s" % ", ".join(lines),
			"Meet the Adventurer", func() -> void: get_tree().change_scene_to_file(CHARACTER_SCENE))
		return
	if GameState.talents_open() and not talents_before:
		UnlockBanner.show_in(self, "TALENTS UNLOCKED!", "Your adventurers can grow", null,
			"Every class levels up from the Exp it earns in fights. Each level gives a TALENT POINT: spend it in your spec's talent tree (or the others) for lasting bonuses.\n\nFind the Talents button on Character Select and in the Deck Builder.",
			"Got it!", _show_quest_complete.bind(quest.quest_name, lines))
		return
	# A quest reward opened a new spec (Pack Rat...).
	for feature in GameState.unlocked_features:
		var spec := _spec_named(feature)
		if spec and not features_before.has(feature):
			UnlockBanner.show_in(self, "NEW SPEC UNLOCKED!", spec.talent_name, null,
				spec.rules + "\n\nPick it from Change Spec in the Deck Builder.",
				"Got it!", _show_quest_complete.bind(quest.quest_name, lines))
			return
	_show_quest_complete(quest.quest_name, lines)


func _spec_named(spec_name: String) -> Talent:
	for character_class in GameState.load_classes():
		for spec in GameState.specs_for(character_class):
			if spec.talent_name == spec_name:
				return spec
	return null


# "Quest complete!" with what you got, then any new quests' stories, then
# back to the quest screen.
func _show_quest_complete(finished: String, lines: Array[String]) -> void:
	var box := open_overlay()
	box.add_child(make_label("Quest complete!", 32, GOLD_COLOR))
	box.add_child(make_label(finished, 20, Color.WHITE))
	for line in lines:
		box.add_child(make_label("+ " + line, 17, DONE_COLOR))
	var ok := Button.new()
	ok.text = "See the new quest" if not GameState.unseen_quests.is_empty() else "Nice"
	ok.theme_type_variation = &"PrimaryButton"
	ok.custom_minimum_size = Vector2(200, 46)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		close_overlay()
		announce_quests(true))
	box.add_child(ok)


# --- The Guild Hall ---------------------------------------------------------------
# Your home base, standing from the start. Inside: the BANK (every material
# you've brought home) and the BUILD list (every building you have a
# blueprint for: build it, or upgrade it to its next stage).

func show_guild_hall() -> void:
	# Your first visit, with the Inn still to build: the King's Stone arrives.
	var first_visit := inn_waiting() and not GameState.story_beats.has(KINGS_STONE)
	if first_visit:
		GameState.add_material("Stone", KINGS_STONE_AMOUNT)
		GameState.story_beats.append(KINGS_STONE)
		GameState.save_game()
		refresh()
	var box := open_overlay(780)
	box.add_child(make_label("The Guild Hall", 32, GOLD_COLOR))
	box.add_child(make_label("Plan and build the town from here. Its Bank keeps everything you bring home safe.", 15, Color(1, 1, 1, 0.75)))

	# The Bank: one chip per material you have, plus your gold.
	box.add_child(_left(make_label("The Bank", 20, Color.WHITE)))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 10)
	chips.add_theme_constant_override("v_separation", 8)
	chips.add_child(make_chip(null, "Gold %d" % GameState.gold, GOLD_COLOR, "Gold: from monsters, chests and quests."))
	for info in GameState.load_materials():
		var count := GameState.material_count(info.material_name)
		if count > 0:
			chips.add_child(make_chip(info, "%s %d" % [info.material_name, count], info.color, info.description))
	bank_box = chips
	box.add_child(chips)

	# The Build list.
	box.add_child(_left(make_label("Build & Upgrade", 20, Color.WHITE)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	build_rows.clear()
	for building in GameState.load_town():
		var stage := GameState.town_stage(building)
		if GameState.has_blueprint(building) and stage < building.max_stage():
			build_rows[building.building_name] = make_build_row(building, stage)
			list.add_child(build_rows[building.building_name])
	if build_rows.is_empty():
		list.add_child(make_label("Nothing to build right now. Quests (and the dungeons) give you new blueprints.", 15, Color(1, 1, 1, 0.6)))

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		close_overlay()
		refresh())
	box.add_child(close)

	if first_visit:
		_kings_stone_arrives()


# A material in the Bank: its picture and "Stone 5".
func make_chip(info: MaterialInfo, text: String, color: Color, tooltip: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.border_color = color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 8
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	chip.tooltip_text = tooltip
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	if info and info.icon:
		var picture := TextureRect.new()
		picture.texture = info.icon
		picture.self_modulate = info.color if info.icon.resource_path.ends_with("ooze.svg") else Color.WHITE
		picture.custom_minimum_size = Vector2(28, 28)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
	var label := make_label(text, 17, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF  # Short text: keep it on one line.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return chip


# One building in the Build list: its picture, what the next stage gives,
# the price, and the Build / Upgrade button.
func make_build_row(building: TownBuilding, stage: int) -> PanelContainer:
	var row_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.13)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	row_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_panel.add_child(row)
	var picture := TextureRect.new()
	picture.texture = building.icon
	picture.custom_minimum_size = Vector2(56, 56)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if stage == 0:
		picture.modulate = Color(0.55, 0.52, 0.5)  # Still in ruins.
	row.add_child(picture)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var verb := "Build" if stage == 0 else "Upgrade"
	info.add_child(_left(make_label(building.building_name + ("" if stage == 0 else "  (stage %d → %d)" % [stage, stage + 1]), 18, GOLD_COLOR)))
	info.add_child(_left(make_label(building.stage_texts[stage], 14, Color(1, 1, 1, 0.8))))
	var blocked := GameState.restore_blocked(building)
	info.add_child(_left(make_label("Costs " + price_text(building, stage) + ("" if blocked.is_empty() else "   ·   " + blocked), 14,
		DONE_COLOR if blocked.is_empty() else Color(1, 0.6, 0.5))))
	var button := Button.new()
	button.text = verb
	button.custom_minimum_size = Vector2(120, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.theme_type_variation = &"PrimaryButton"
	button.disabled = not blocked.is_empty()
	button.tooltip_text = blocked
	button.pressed.connect(_on_restore_pressed.bind(building))
	row.add_child(button)
	return row_panel


# STORY BEAT 2: the King's Stone pops up in the Bank, then a guide shows how
# to build the Inn.
func _kings_stone_arrives() -> void:
	var stone := GameState.find_material("Stone")
	var pop := HBoxContainer.new()
	pop.alignment = BoxContainer.ALIGNMENT_CENTER
	pop.add_theme_constant_override("separation", 10)
	if stone and stone.icon:
		var picture := TextureRect.new()
		picture.texture = stone.icon
		picture.custom_minimum_size = Vector2(96, 96)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pop.add_child(picture)
	var amount := make_label("+%d Stone!" % KINGS_STONE_AMOUNT, 54, GOLD_COLOR)
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount.add_theme_color_override("font_outline_color", Color.BLACK)
	amount.add_theme_constant_override("outline_size", 10)
	pop.add_child(amount)
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pop)
	# Centre it on the screen, grow it in, hold, then float it up into the Bank.
	pop.reset_size()
	pop.position = (get_viewport_rect().size - pop.size) / 2
	pop.pivot_offset = pop.size / 2
	pop.scale = Vector2(0.1, 0.1)
	var tween := pop.create_tween()
	tween.tween_property(pop, "scale", Vector2(1.15, 1.15), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(pop, "scale", Vector2.ONE, 0.15)
	tween.tween_interval(0.8)
	tween.tween_property(pop, "position:y", pop.position.y - 160, 0.5)
	tween.parallel().tween_property(pop, "modulate:a", 0.0, 0.5)
	tween.tween_callback(pop.queue_free)
	tween.tween_callback(func() -> void:
		var steps := [
			{"target": bank_box, "text": "This is the Guild Hall. Up here is the BANK: everything you bring home is kept safe in it. The King's builders left you 5 Stone to get started."},
		]
		if build_rows.has("Inn"):
			steps.append({"target": build_rows["Inn"], "text": "Down here is the BUILD list: every building you have a blueprint for, and what it costs. The Inn needs 5 Stone, and you have it. Press Build!"})
		ScreenGuide.start(self, "guild_hall", steps))


# --- The start of the game: story beats ------------------------------------------

# Play the next story beat that's due, or else any new quests' stories.
func play_story() -> void:
	if not GameState.story_beats.has(WELCOME):
		show_welcome()
	elif GameState.town_bonus(TownBuilding.INN) > 0 and not GameState.story_beats.has(GameState.INN_BUILT):
		show_innkeeper_thanks()
	elif GameState.adventurers_here() and GameState.tutorial_done and not GameState.story_beats.has(GameState.ADVENTURER_TRAINED):
		show_slime_news()
	elif inn_waiting():
		message_label.text = "Click the Guild Hall to build the Inn."
		show_next_story(false)
	else:
		announce_quests(false)


# STORY BEAT 1: welcome to town, and the Inn blueprint.
func show_welcome() -> void:
	UnlockBanner.show_in(self, "WELCOME TO TOWN!", "A mission from the King", GUILD_HALL_ICON,
		"The King has named you his ARCHITECT. Your mission: bring this old town back to its glory.\n\nOnly the Guild Hall still stands. Everything else lies in ruins, but the King gave you something to start with...",
		"What did he give me?", show_blueprint_unlock)


func show_blueprint_unlock() -> void:
	UnlockBanner.show_in(self, "NEW BLUEPRINT!", "The Inn", BLUEPRINT_ICON,
		"A BLUEPRINT is the plan for a building. Every building needs one: once you have its blueprint, the building shows up in town (in ruins), ready to be built.\n\nYou'll earn more blueprints from quests, and find some out in the dungeons.",
		"Read Blueprint", _on_read_blueprint)


func _on_read_blueprint() -> void:
	GameState.give_rewards("Blueprint Inn")
	GameState.story_beats.append(WELCOME)
	GameState.save_game()
	refresh()
	if panels.has("Inn"):
		pop_in(panels["Inn"])
	message_label.text = "Click the Guild Hall to build the Inn."
	await get_tree().create_timer(0.6).timeout  # Let the Inn finish popping in first.
	# How building works: point at the Inn's ruins, then at the Guild Hall.
	var steps := []
	if panels.has("Inn"):
		steps.append({"target": panels["Inn"], "text": "The blueprint shows you the Inn's ruins. To BUILD it you need MATERIALS: the Inn takes 5 Stone. Some buildings cost gold too. You find materials in the dungeons, and each area has its own (the Plains have Stone)."})
	if panels.has("Guild Hall"):
		steps.append({"target": panels["Guild Hall"], "text": "Everything is built from the GUILD HALL. It also holds your Bank, where your materials are kept. Click the Guild Hall to take a look inside."})
	ScreenGuide.start(self, "town_building", steps)


# STORY BEAT 3: the Innkeeper thanks you, then the quest tutorial, then his
# first two quests (quests.csv: Starts After "Inn Built").
func show_innkeeper_thanks() -> void:
	close_overlay()
	UnlockBanner.show_in(self, "THE INN IS OPEN!", "The Innkeeper comes out to meet you", INN_ICON,
		"\"You rebuilt my Inn! I never thought I'd see the day. Thank you, Architect!\"\n\nHe wipes his hands on his apron. \"Truth is, there are still a few things I need help with around here. Could you lend me a hand?\"",
		"Happy to help!", show_quest_tutorial)


func show_quest_tutorial() -> void:
	UnlockBanner.show_in(self, "QUESTS UNLOCKED!", "How quests work", QUEST_ICON,
		"People in town will ask you for help. Each QUEST has an objective (bring something home, build something, beat some monsters) and a REWARD.\n\n•  Your quests live at the INN: click it any time to see them, and how far along you are.\n•  When one is done, come back to the Inn and press HAND IN to get the reward.\n•  You can be on several quests at once.",
		"See the Innkeeper's quests", func() -> void:
			GameState.reach_milestone(GameState.INN_BUILT)
			refresh()
			show_next_story(true))


# STORY BEAT 4: back from the Adventurer's training. Slimes!
func show_slime_news() -> void:
	UnlockBanner.show_in(self, "TROUBLE ON THE PLAINS!", "The Innkeeper has news", SLIME_ART,
		"\"Now that we've got a real Adventurer, I can tell you: slimes are taking over the Plains! Folk are too scared to travel, and nobody comes to an Inn that nobody can reach.\"\n\n\"I've put up some new jobs, and your Adventurer has a favour to ask too.\"",
		"Let's hear it", func() -> void:
			GameState.reach_milestone(GameState.ADVENTURER_TRAINED)
			refresh()
			announce_quests(true))


# NEW QUESTS! A big banner listing the quests that just started (so you don't
# miss them), then each one's story. Nothing new: straight on.
func announce_quests(back_to_board: bool) -> void:
	var fresh: Array[Quest] = []
	for quest_name in GameState.unseen_quests:
		var quest := GameState.find_quest(quest_name)
		if quest and GameState.active_quests.has(quest_name):
			fresh.append(quest)
	if fresh.is_empty():
		show_next_story(back_to_board)
		return
	var lines: Array[String] = []
	for quest in fresh:
		var kind := "" if quest.quest_type == "Story" else "  (%s quest)" % quest.quest_type
		lines.append("•  %s%s:  %s" % [quest.quest_name, kind, quest.objective_text()])
	var title := "NEW QUEST!" if fresh.size() == 1 else "%d NEW QUESTS!" % fresh.size()
	UnlockBanner.show_in(self, title, "Find them at the Inn any time", QUEST_ICON,
		"\n".join(lines), "Read them" if fresh.size() > 1 else "Read it", show_next_story.bind(back_to_board))
