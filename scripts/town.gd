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
var flask_layer: Control  # The flask screen while it's open (null when closed).


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	deck_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(DECK_BUILDER_SCENE))
	next_run_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	flask_button = Button.new()
	flask_button.icon = FLASK_ICON
	flask_button.add_theme_constant_override("icon_max_width", 30)  # The svg is 64px: shrink it to fit.
	flask_button.custom_minimum_size = Vector2(0, deck_button.custom_minimum_size.y)
	flask_button.pressed.connect(open_flasks)
	deck_button.add_sibling(flask_button)
	summary_label.text = run_summary()
	message_label.text = ""
	refresh()


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
	return "Restore the town with the gold you bring home from the dungeons."


# Build every building's panel again (after restoring or buying something).
func refresh() -> void:
	gold_label.text = "Gold %d" % GameState.gold
	for old in building_row.get_children():
		old.queue_free()
	for building in GameState.load_town():
		building_row.add_child(make_building(building))
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
	# Restore the next stage.
	if stage < building.max_stage():
		var cost := building.cost_of_next(stage)
		var restore := Button.new()
		restore.text = "%s  (%d gold)" % ["Restore" if stage == 0 else "Upgrade", cost]
		restore.theme_type_variation = &"PrimaryButton"
		restore.disabled = GameState.gold < cost
		restore.tooltip_text = "Next: " + building.stage_texts[stage]
		restore.pressed.connect(_on_restore_pressed.bind(building))
		box.add_child(restore)
	return panel


# The building's own button: Enter the Shop, buy an enchant / potion / map.
func make_action(building: TownBuilding, stage: int) -> Button:
	var button := Button.new()
	if building.bonus(TownBuilding.SHOP, stage) > 0:
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
		message_label.text = "The %s is restored: %s!" % [building.building_name, building.stage_texts[stage - 1]]
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
		main.text = "Unlock  (%d gold)" % flask.unlock_cost
		main.theme_type_variation = &"PrimaryButton"
		main.disabled = not GameState.alchemist_open() or GameState.gold < flask.unlock_cost
		main.tooltip_text = "Unlocked at the Alchemist." if GameState.alchemist_open() else "Restore the Alchemist first."
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
