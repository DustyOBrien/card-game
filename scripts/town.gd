# town.gd
#
# The town (scenes/town.tscn): where you come back to after every run.
# Its buildings start in ruins. Put gold into one to restore it a stage at a
# time; each stage opens something new (see town_building.gd and
# data/progression/town.csv). The Shop is open from the start.
#
# Like the map, the buildings are made here in code, one panel per file in
# town/, so a new row in the sheet shows up on its own.
extends Control

const SHOP_SCENE := "res://scenes/shop.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const RUINS := preload("res://art/town/ruins.svg")
const FLASK_ICON := preload("res://art/potions/flask.svg")
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
var quest_button: Button  # "Quest: Clear the Slimes", next to the flask button.
var overlay: Control  # The quest panel or the Bank while it's open.
var flask_layer: Control  # The flask screen while it's open (null when closed).


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	GameState.check_quest()
	deck_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(DECK_BUILDER_SCENE))
	next_run_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	flask_button = Button.new()
	flask_button.icon = FLASK_ICON
	flask_button.add_theme_constant_override("icon_max_width", 30)  # The svg is 64px: shrink it to fit.
	flask_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	flask_button.pressed.connect(open_flasks)
	deck_button.add_sibling(flask_button)
	quest_button = Button.new()
	quest_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	quest_button.pressed.connect(show_quest_panel.bind(false))
	flask_button.add_sibling(quest_button)
	summary_label.text = run_summary()
	message_label.text = ""
	refresh()
	# A quest that just started tells its story once (the King's letter...).
	if GameState.current_quest() and not GameState.quest_seen:
		GameState.quest_seen = true
		GameState.save_game()
		show_quest_panel(true)


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
	var inn_open := GameState.town_bonus(TownBuilding.INN) > 0
	next_run_button.disabled = not inn_open
	next_run_button.tooltip_text = "" if inn_open else "Build the Inn first: it opens the road to the Plains."
	quest_button.text = "Quest: %s%s" % [GameState.active_quest, "  ✓ Ready!" if GameState.quest_ready() else ""] \
		if GameState.current_quest() else "No quest right now"
	quest_button.disabled = GameState.current_quest() == null
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
	return panel


# The building's own button: Enter the Shop, buy an enchant / potion / map.
func make_action(building: TownBuilding, stage: int) -> Button:
	var button := Button.new()
	if building.bonus(TownBuilding.INN, stage) > 0:
		button.text = "Quest Board" + ("  ✓" if GameState.quest_ready() else "")
		button.tooltip_text = "See your quest, and hand it in when it's done."
		button.pressed.connect(show_quest_panel.bind(false))
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
	var note := "Take one flask into each run. Its charges refill when you Rest at a campfire."
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

func open_overlay() -> VBoxContainer:
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
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


# The active quest: who gives it, the story, the objective and how far along
# it is, what it gives you. `story` = the first time (no hand-in button yet).
func show_quest_panel(story: bool) -> void:
	var quest := GameState.current_quest()
	if quest == null:
		return
	var box := open_overlay()
	if not quest.giver.is_empty():
		box.add_child(make_label(quest.giver + (" writes:" if story else " says:"), 16, Color(1, 1, 1, 0.7)))
	box.add_child(make_label(quest.quest_name, 30, GOLD_COLOR))
	box.add_child(make_label(quest.text, 16, Color.WHITE))
	if story and not quest.start_gift.is_empty():
		box.add_child(make_label("You receive: " + quest_reward_text(quest.start_gift), 16, DONE_COLOR))
	var status := GameState.quest_status()
	var objective := make_label("Objective: %s  (%d / %d)" % [quest.objective_text(), status.x, status.y], 18,
		DONE_COLOR if GameState.quest_ready() else GOLD_COLOR)
	box.add_child(objective)
	if not quest.rewards.is_empty():
		box.add_child(make_label("Reward: " + quest_reward_text(quest.rewards), 15, Color(1, 1, 1, 0.8)))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var inn_open := GameState.town_bonus(TownBuilding.INN) > 0
	if GameState.quest_ready():
		var hand_in := Button.new()
		hand_in.text = "Hand In" if inn_open or quest.objective == Quest.BUILD else "Hand in at the Inn"
		hand_in.theme_type_variation = &"PrimaryButton"
		hand_in.custom_minimum_size = Vector2(180, 46)
		hand_in.pressed.connect(_on_hand_in)
		buttons.add_child(hand_in)
	var ok := Button.new()
	ok.text = "Let's go!" if story else "Close"
	ok.custom_minimum_size = Vector2(140, 46)
	ok.pressed.connect(func() -> void:
		close_overlay()
		refresh())
	buttons.add_child(ok)


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
			"pack": parts.append("%s Booster Pack" % rest)
			"gold": parts.append("%s gold" % rest)
			_: parts.append(reward)
	return ", ".join(parts)


func _on_hand_in() -> void:
	var finished := GameState.active_quest
	var lines := GameState.complete_quest()
	refresh()
	var box := open_overlay()
	box.add_child(make_label("Quest complete!", 32, GOLD_COLOR))
	box.add_child(make_label(finished, 20, Color.WHITE))
	for line in lines:
		box.add_child(make_label("+ " + line, 17, DONE_COLOR))
	var next := GameState.current_quest()
	box.add_child(make_label("New quest: %s" % next.quest_name if next else "No more quests for now. More are coming!", 17, Color(1, 1, 1, 0.8)))
	var ok := Button.new()
	ok.text = "See the new quest" if next else "Nice"
	ok.theme_type_variation = &"PrimaryButton"
	ok.custom_minimum_size = Vector2(200, 46)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		if GameState.current_quest():
			GameState.quest_seen = true
			GameState.save_game()
			show_quest_panel(true)
		else:
			close_overlay()
			refresh())
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
