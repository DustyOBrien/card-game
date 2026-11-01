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
const GOLD_COLOR := Color(1, 0.84, 0.35)
const DONE_COLOR := Color(0.55, 0.95, 0.55)

@onready var gold_label: Label = %GoldLabel
@onready var summary_label: Label = %SummaryLabel
@onready var building_row: HBoxContainer = %BuildingRow
@onready var message_label: Label = %MessageLabel
@onready var pending_label: Label = %PendingLabel
@onready var deck_button: Button = %DeckButton
@onready var next_run_button: Button = %NextRunButton


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	deck_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(DECK_BUILDER_SCENE))
	next_run_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
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
