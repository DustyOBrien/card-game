# town.gd
#
# The town (scenes/town.tscn): where you come back to after every run.
# Its buildings start in ruins. Put gold into one to restore it a stage at a
# time; each stage opens something new (see town_building.gd and
# data/progression/town.csv). The Shop is open from the start.
#
# Like the map, the buildings are made here in code, one panel per file in
# town/, so a new row in the sheet shows up on its own.
#
# Click the Inn for the QUEST SCREEN (every quest you're on). The road at the
# bottom-right (town_road.gd) leads out to the map.
extends Control

const SHOP_SCENE := "res://scenes/shop.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CHARACTER_SCENE := "res://scenes/character_select.tscn"
const RUINS := preload("res://art/town/ruins.svg")
const FLASK_ICON := preload("res://art/potions/flask.svg")
const BOOSTER_ICON := preload("res://icons/booster.svg")
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
var quest_button: Button  # "The King's Letter": the quest button before the Inn exists.
var packs_button: Button  # "Your Packs (3)": open them (at the Shop, or before it's built).
var road: TownRoad  # The road out of town, with its "To the Map" sign (town_road.gd).
var overlay: Control  # The quest panel or the Bank while it's open.
var flask_layer: Control  # The flask screen while it's open (null when closed).


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
	flask_button.pressed.connect(open_flasks)
	deck_button.add_sibling(flask_button)
	quest_button = Button.new()
	quest_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	quest_button.pressed.connect(show_quest_board)
	flask_button.add_sibling(quest_button)
	# A booster pack you can click to open your packs (on the Shop screen,
	# which only opens packs until the Shop is built).
	packs_button = Button.new()
	packs_button.icon = BOOSTER_ICON
	packs_button.add_theme_constant_override("icon_max_width", 34)
	packs_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	packs_button.tooltip_text = "Open your booster packs."
	packs_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))
	quest_button.add_sibling(packs_button)
	summary_label.text = run_summary()
	message_label.text = ""
	refresh()
	# Quests that just started tell their story once (the King's letter...).
	show_next_story(false)


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
	for building in GameState.load_town():
		if GameState.has_blueprint(building):  # The rest stay hidden until a quest gives their blueprint.
			building_row.add_child(make_building(building))
	# You can head out once any area is open (before the Inn: the guided Stone run).
	var can_go := GameState.load_areas().any(func(area: Area) -> bool: return GameState.is_area_unlocked(area))
	road.set_open(can_go)
	# No adventurer yet: you're running the town, so there's no deck or flask to look at.
	deck_button.visible = GameState.adventurers_here()
	flask_button.visible = GameState.adventurers_here()
	# Before the Inn: a button for the King's quests. After: quests live at the Inn.
	quest_button.visible = not GameState.adventurers_here()
	quest_button.text = "The King's Letter" + ("  ✓ Ready!" if GameState.quests_ready_count() > 0 else "")
	quest_button.disabled = GameState.quests_active().is_empty()
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
		build_flask_screen()
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
	# Restore the next stage: gold and/or materials.
	if stage < building.max_stage():
		var cost := building.cost_of_next(stage)
		var prices: Array[String] = []
		if cost > 0:
			prices.append("%d gold" % cost)
		var needs := building.materials_for_next(stage)
		if not needs.is_empty():
			prices.append(MaterialInfo.costs_text(needs))
		var restore := Button.new()
		var verb := ("Build" if building.needs_blueprint else "Restore") if stage == 0 else "Upgrade"
		restore.text = "%s  (%s)" % [verb, ", ".join(prices) if not prices.is_empty() else "free"]
		restore.theme_type_variation = &"PrimaryButton"
		var blocked := GameState.restore_blocked(building)
		restore.disabled = not blocked.is_empty()
		restore.tooltip_text = "Next: " + building.stage_texts[stage] + ("\n" + blocked if not blocked.is_empty() else "")
		restore.pressed.connect(_on_restore_pressed.bind(building))
		box.add_child(restore)
	# Click anywhere on the built Inn to see your quests.
	if stage > 0 and building.bonus(TownBuilding.INN, stage) > 0:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "Click the Inn to see your quests."
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_quest_board())
	return panel


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
		button.text = "Open the Bank"
		button.tooltip_text = "The materials you've brought home."
		button.pressed.connect(show_bank)
	elif building.bonus(TownBuilding.SHOP, stage) > 0:
		button.text = "Enter the Shop"
		button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SHOP_SCENE))
	elif building.bonus(TownBuilding.ENCHANTER, stage) > 0:
		button.text = "Buy an Enchant  (%d gold)" % GameState.ENCHANT_PRICE
		button.tooltip_text = "A random enchant for your next run: put it on a card from the dungeon screen."
		button.disabled = GameState.gold < GameState.ENCHANT_PRICE
		button.pressed.connect(_buy_enchant)
	elif building.bonus(TownBuilding.ALCHEMIST, stage) > 0:
		button.text = "Buy a Potion  (%d gold)" % GameState.POTION_PRICE
		button.tooltip_text = "A random potion for your next run (you can carry %d)." % GameState.potion_slots()
		button.disabled = GameState.gold < GameState.POTION_PRICE or GameState.pending_potions.size() >= GameState.potion_slots()
		button.pressed.connect(_buy_potion)
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


func _on_restore_pressed(building: TownBuilding) -> void:
	if GameState.restore(building):
		var stage := GameState.town_stage(building)
		message_label.text = "The %s is %s: %s!" % [building.building_name,
			"built" if stage == 1 and building.needs_blueprint else "restored", building.stage_texts[stage - 1]]
	refresh()
	# Building what a quest asked for: straight to the quests, to hand it in.
	if GameState.quests_active().any(func(q: Quest) -> bool: return q.objective == Quest.BUILD and GameState.quest_ready(q)):
		show_quest_board()


func _buy_enchant() -> void:
	var enchant := Enchant.pick_random(GameState.load_enchants())
	if enchant == null or GameState.gold < GameState.ENCHANT_PRICE:
		return
	GameState.gold -= GameState.ENCHANT_PRICE
	GameState.pending_enchants.append(enchant.enchant_name)
	GameState.save_game()
	message_label.text = "The Enchanter hands you %s: %s" % [enchant.enchant_name, enchant.description]
	refresh()


func _buy_potion() -> void:
	var potion := Potion.pick_random(GameState.load_potions())
	if potion == null or GameState.gold < GameState.POTION_PRICE:
		return
	GameState.gold -= GameState.POTION_PRICE
	GameState.pending_potions.append(potion.potion_name)
	GameState.save_game()
	message_label.text = "The Alchemist brews a %s: %s" % [potion.potion_name, potion.effect_text()]
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


# --- Flasks ------------------------------------------------------------------
# A screen on top of the town: one panel per flask (flasks/*.tres). Pick the
# one you take on your next run; unlock and upgrade them with gold once the
# Alchemist is restored.

func open_flasks() -> void:
	flask_layer = ColorRect.new()
	flask_layer.color = Color(0, 0, 0, 0.8)
	flask_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flask_layer)
	build_flask_screen()


func close_flasks() -> void:
	flask_layer.queue_free()
	flask_layer = null


func build_flask_screen() -> void:
	for old in flask_layer.get_children():
		old.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flask_layer.add_child(center)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	center.add_child(layout)
	layout.add_child(make_label("Flasks", 34, Color.WHITE))
	var note := "Take one flask into each run. Its charges refill at the start of every run."
	if not GameState.alchemist_open():
		note += "\nRestore the Alchemist to unlock and upgrade flasks."
	layout.add_child(make_label(note, 15, Color(1, 1, 1, 0.75)))
	layout.add_child(make_label("Gold %d" % GameState.gold, 18, GOLD_COLOR))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(row)
	for flask in GameState.load_flasks():
		row.add_child(make_flask_panel(flask))
	var close := Button.new()
	close.text = "Done"
	close.custom_minimum_size = Vector2(160, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_flasks)
	layout.add_child(close)


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
		box.add_child(make_label(quest.giver + (" writes:" if not GameState.adventurers_here() else " says:") + kind, 16, Color(1, 1, 1, 0.7)))
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
	# The Inn just opened: the first Adventurer arrives, and Character Select
	# and the deck builder open up. Off to meet them (and their training, the
	# tutorial). The new quests' stories show when you're back in town.
	if GameState.adventurers_here() and not GameState.tutorial_done:
		var adventurer: CharacterClass = GameState.load_classes()[0]
		UnlockBanner.show_in(self, "A NEW ADVENTURER!", "The %s has arrived" % adventurer.display_name, adventurer.emblem,
			"Word of your Inn spread, and the first Adventurer has checked in! You've got a town to run, so leave the fighting to them.\n\nNEW: Character Select and the Deck Builder.  Quest rewards: %s" % ", ".join(lines),
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
	ok.pressed.connect(show_next_story.bind(GameState.adventurers_here()))
	box.add_child(ok)


# The Guild Hall's Bank: every material you've brought home.
func show_bank() -> void:
	var box := open_overlay()
	box.add_child(make_label("The Bank", 30, GOLD_COLOR))
	box.add_child(make_label("What you've brought home is safe here. Materials you find in the dungeon only count once you get out (or if they're in your Save Sack).", 15, Color(1, 1, 1, 0.75)))
	var any := false
	for info in GameState.load_materials():
		var count := GameState.material_count(info.material_name)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var picture := TextureRect.new()
		picture.texture = info.icon
		picture.self_modulate = info.color if info.icon and info.icon.resource_path.ends_with("ooze.svg") else Color.WHITE
		picture.custom_minimum_size = Vector2(40, 40)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		var label := make_label("%s:  %d" % [info.material_name, count], 20, info.color if count > 0 else Color(1, 1, 1, 0.4))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = info.description
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		box.add_child(row)
		any = any or count > 0
	if not any:
		box.add_child(make_label("Empty for now.", 16, Color(1, 1, 1, 0.6)))
	var ok := Button.new()
	ok.text = "Close"
	ok.custom_minimum_size = Vector2(140, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close_overlay)
	box.add_child(ok)
