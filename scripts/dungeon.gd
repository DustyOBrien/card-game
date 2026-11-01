# dungeon.gd
#
# The dungeon screen (scenes/dungeon.tscn): the 5 x 5 grid you explore
# between fights. Click a square next to the explored area to step into the
# unknown (a room card is drawn), or click any explored room to walk back.
#
# All the RULES live in dungeon_run.gd (GameState.dungeon). This script only
# draws them and turns clicks into calls like dungeon.move_to(square). So
# when we come back here after a fight, nothing is lost: the scene is built
# again from GameState.dungeon.
#
# Almost everything here is built in code (like the map's area buttons),
# because 25 squares are easier to make in a loop than by hand in the editor.
extends Control

const BATTLE_SCENE := "res://scenes/battle.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"
const CARD_SCENE := preload("res://scenes/card.tscn")
const ENCHANT_ICON := preload("res://art/potions/enchant.svg")
const SACK_ICON := preload("res://art/potions/sack.svg")
const POTION_ICON := preload("res://art/potions/potion.svg")
const FLASK_ICON := preload("res://art/potions/flask.svg")

const SQUARE_SIZE := Vector2(108, 108)
const GAP := 6

# One picture per kind of room. (Empty rooms have no picture, just a name.)
const ICONS := {
	RoomCard.Type.FIGHT: preload("res://art/rooms/fight.svg"),
	RoomCard.Type.HARD_FIGHT: preload("res://art/rooms/hard_fight.svg"),
	RoomCard.Type.LOCKED_CHEST: preload("res://art/rooms/chest.svg"),
	RoomCard.Type.TREASURE: preload("res://art/rooms/treasure.svg"),
	RoomCard.Type.CAMPFIRE: preload("res://art/rooms/campfire.svg"),
	RoomCard.Type.MINI_BOSS: preload("res://art/rooms/mini_boss.svg"),
	RoomCard.Type.BOSS: preload("res://art/rooms/boss.svg"),
	RoomCard.Type.EVENT: preload("res://art/rooms/event.svg"),
}
const OPEN_CHEST_ICON := preload("res://art/rooms/open_chest.svg")
const KEY_ICON := preload("res://art/rooms/key.svg")
const START_ICON := preload("res://art/rooms/start.svg")
const PLAYER_ICON := preload("res://art/rooms/player.svg")

# Square colours.
const FOG_COLOR := Color(0.08, 0.09, 0.12, 0.85)  # Not explored, can't reach yet.
const REACHABLE_COLOR := Color(0.2, 0.24, 0.32, 0.92)  # Not explored, one step away: click to explore.
const ROOM_COLOR := Color(0.32, 0.27, 0.2, 0.95)  # An explored room.
const DANGER_ROOM_COLOR := Color(0.45, 0.16, 0.14, 0.95)  # A fight you haven't won yet.
const CAMPFIRE_COLOR := Color(0.5, 0.32, 0.1, 0.95)
const WALL_COLOR := Color(0.03, 0.03, 0.04, 0.95)  # A dead end (the room deck ran out).
const HOVER_BORDER := Color(1.0, 0.85, 0.35)
const HERE_BORDER := Color(0.55, 0.9, 1.0)

@onready var background: TextureRect = %Background
@onready var grid: GridContainer = %Grid
@onready var title_label: Label = %TitleLabel
@onready var stats_label: RichTextLabel = %StatsLabel
@onready var info_label: Label = %InfoLabel
@onready var log_label: RichTextLabel = %LogLabel
@onready var popup: PanelContainer = %Popup
@onready var popup_title: Label = %PopupTitle
@onready var popup_text: Label = %PopupText
@onready var popup_buttons: HBoxContainer = %PopupButtons

var dungeon: DungeonRun
var squares := {}  # Vector2i -> the Button drawn for that square.
var reach := {}  # Where you can step to: dungeon.reachable(), worked out once per refresh().
var _boxes := {}  # Square styles we've already made, so a redraw reuses them.
# The Save Sack, Found and enchant/potion rows in the side panel (built in code).
var sack_row: HBoxContainer
var found_row: HFlowContainer
var enchant_button: Button
var potion_row: HBoxContainer
var picker: ColorRect  # The "put an enchant on a card" screen, while it's open.
var guide_label: Label  # The guided first run's tip box (null on normal runs).
# The popup's picture (a key, a chest...) and its little animation.
var popup_holder: Control
var popup_picture: TextureRect
var popup_sparkles: CPUParticles2D
var popup_tween: Tween
var popup_loot_texture: Texture2D  # What pops out of a chest you just opened.


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	dungeon = GameState.dungeon
	background.texture = dungeon.area.background
	grid.columns = DungeonRun.SIZE
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	for y in DungeonRun.SIZE:
		for x in DungeonRun.SIZE:
			var square := Vector2i(x, y)
			var button := make_square(square)
			grid.add_child(button)
			squares[square] = button
	build_legend()
	build_sack_panel()
	if dungeon.guided:
		build_guide()
	popup.hide()
	refresh()
	# Back from beating a Mini Boss: its room is a campfire now. Offer it
	# straight away (you can still say Not now and keep exploring: the next
	# tier waits until you rest at a campfire).
	if dungeon.tier_up_waiting and dungeon.rooms[dungeon.position].campfire:
		show_campfire()


# --- Drawing ----------------------------------------------------------------

# A row of the room pictures and their names, under the grid.
func build_legend() -> void:
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 10)
	legend.position = grid.position + Vector2(0, grid.size.y + 10)
	legend.size = Vector2(grid.size.x, 36)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	for type in [RoomCard.Type.FIGHT, RoomCard.Type.HARD_FIGHT, RoomCard.Type.LOCKED_CHEST,
			RoomCard.Type.TREASURE, RoomCard.Type.EVENT, RoomCard.Type.CAMPFIRE, RoomCard.Type.MINI_BOSS, RoomCard.Type.BOSS]:
		var picture := TextureRect.new()
		picture.texture = ICONS[type]
		picture.custom_minimum_size = Vector2(26, 26)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		legend.add_child(picture)
		var name_label := Label.new()
		name_label.text = RoomCard.TYPE_NAMES[type]
		name_label.add_theme_font_size_override("font_size", 13)
		legend.add_child(name_label)
	add_child(legend)


func make_square(square: Vector2i) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SQUARE_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	button.pressed.connect(_on_square_pressed.bind(square))
	button.mouse_entered.connect(_on_square_hovered.bind(square))
	button.mouse_exited.connect(func() -> void: info_label.text = default_info())
	# Inside each square: a picture in the middle and a name at the bottom.
	# They ignore the mouse, so clicks go through to the button.
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 22
	icon.offset_right = -22
	icon.offset_top = 10
	icon.offset_bottom = -30
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var label := Label.new()
	label.name = "Name"
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -28
	label.offset_bottom = -4
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	# The player's marker, in the top-left corner of the square you're on.
	var marker := TextureRect.new()
	marker.name = "Player"
	marker.texture = PLAYER_ICON
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.size = Vector2(38, 38)
	marker.position = Vector2(4, 4)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(marker)
	return button


# Draw every square and every label again from the DungeonRun.
func refresh() -> void:
	reach = dungeon.reachable() if dungeon.result.is_empty() else {}
	for square: Vector2i in squares:
		draw_square(square)
	var hp := GameState.run_hp if GameState.run_hp > 0 else GameState.player_max_hp()
	title_label.text = "%s  ·  Tier %d / %d" % [dungeon.area.display_name, dungeon.tier, dungeon.max_tier] \
		if not dungeon.guided else "%s  ·  Gathering Stone" % dungeon.area.display_name
	var lines: Array[String] = []
	lines.append("[color=#ff8080]HP %d / %d[/color]" % [hp, GameState.player_max_hp()])
	lines.append("[color=#ffd75a]Keys: %d[/color]" % dungeon.keys)
	var danger_color := "#ffffff" if dungeon.danger() == 0 else "#ff9050"
	if not dungeon.guided:  # No enemies on the guided run, so no Danger either.
		lines.append("[color=%s]Danger %d[/color]  (enemies +%d Strength; +1 more in %d steps)" % [
			danger_color, dungeon.danger(), dungeon.danger(), dungeon.steps_to_next_danger()])
	lines.append("Rooms left in the deck: %d" % dungeon.deck.size())
	if dungeon.boss_unlocked:
		lines.append("[color=#ff6060]The Boss is somewhere in the deck![/color]")
	elif dungeon.tier_up_waiting:
		lines.append("[color=#ffd75a]Go Deeper at the campfire.[/color]")
	stats_label.text = "\n".join(lines)
	stats_label.tooltip_text = "\n".join([
		"HP: carries over from fight to fight. Resting at a campfire heals %d%%." % roundi(DungeonRun.REST_HEAL * 100),
		"Keys: fights drop a small key %d%% of the time. A key opens one Locked Chest." % DungeonRun.KEY_CHANCE,
		"Danger: every %d steps since your last rest, every enemy gets +1 Strength. Resting resets it." % dungeon.steps_per_danger(),
		"Found: only yours once you get out (Leave at a campfire, or beat the Boss). Die and it's lost.",
		"Rooms left: blank squares draw from this deck. When it's empty, the rest are dead ends until you rest.",
	])
	info_label.text = default_info()
	log_label.text = "\n".join(dungeon.history.slice(-14))
	refresh_sack()


func draw_square(square: Vector2i) -> void:
	var button: Button = squares[square]
	var icon: TextureRect = button.get_node("Icon")
	var label: Label = button.get_node("Name")
	button.get_node("Player").visible = square == dungeon.position
	icon.texture = null
	icon.modulate = Color.WHITE
	label.text = ""
	button.tooltip_text = describe_square(square)  # Shown when you hover the square for a moment.
	var color := FOG_COLOR
	var reachable := reach.has(square)
	if dungeon.walls.has(square):
		color = WALL_COLOR
	elif dungeon.is_explored(square):
		var room: Dictionary = dungeon.rooms[square]
		var card: RoomCard = room.card
		color = ROOM_COLOR
		if card == null:
			icon.texture = START_ICON
			label.text = "Entrance"
		else:
			label.text = card.room_name
			icon.texture = ICONS.get(card.type)
			if card.is_fight():
				if room.cleared:
					icon.modulate = Color(1, 1, 1, 0.35)  # Beaten: faded out.
				else:
					color = DANGER_ROOM_COLOR
			elif card.type == RoomCard.Type.LOCKED_CHEST and room.get("opened", false):
				icon.texture = OPEN_CHEST_ICON
			elif card.type == RoomCard.Type.TREASURE and room.cleared:
				icon.modulate = Color(1, 1, 1, 0.35)
			elif card.type == RoomCard.Type.EVENT and room.get("event") != null:
				label.text = room.event.event_name  # Once you've found out what it is.
				if room.done:
					icon.modulate = Color(1, 1, 1, 0.35)
		if room.campfire:
			icon.texture = ICONS[RoomCard.Type.CAMPFIRE]
			icon.modulate = Color.WHITE
			color = CAMPFIRE_COLOR
			if card != null and card.type == RoomCard.Type.MINI_BOSS:
				label.text = "Campfire"
		elif card != null and card.type == RoomCard.Type.CAMPFIRE:
			icon.modulate = Color(1, 1, 1, 0.35)  # Used: the fire is out.
	elif reachable:
		color = REACHABLE_COLOR
		label.text = "?"
	var border := HERE_BORDER if square == dungeon.position else Color(0, 0, 0, 0.6)
	button.add_theme_stylebox_override("normal", make_box(color, border, 2 if square != dungeon.position else 4))
	button.add_theme_stylebox_override("hover", make_box(color.lightened(0.12), HOVER_BORDER if reachable else border, 4 if reachable else 2))
	button.add_theme_stylebox_override("pressed", make_box(color.lightened(0.2), HOVER_BORDER, 4))
	button.add_theme_stylebox_override("disabled", make_box(color, border, 2 if square != dungeon.position else 4))
	# You can click a square you can walk to, and the square you're on (to use
	# its campfire or chest again).
	button.disabled = not (reachable or (square == dungeon.position and has_action_here()))
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND


# The tooltip for a square: what it is and what you can do with it.
func describe_square(square: Vector2i) -> String:
	if dungeon.walls.has(square):
		return "Dead end: the room deck ran out."
	if not dungeon.is_explored(square):
		var distance: int = reach[square].steps if reach.has(square) else -1
		if distance > 0:
			return "Unexplored (%d step%s away).\nStep here to draw a room from the deck." % [distance, "s" if distance > 1 else ""]
		return "Unexplored.\nExplore a square next to it first."
	var room: Dictionary = dungeon.rooms[square]
	var card: RoomCard = room.card
	if card == null:
		return "The entrance."
	var lines: Array[String] = ["%s (%s)" % [card.room_name, card.type_name()]]
	if room.campfire:
		lines.append("A lit campfire. Stand here and click it to Rest or Leave the dungeon.")
		if dungeon.tier_up_waiting:
			lines.append("Resting here takes you deeper.")
		return "\n".join(lines)
	if card.is_fight():
		if room.cleared:
			lines.append("Beaten. Safe to walk through.")
			return "\n".join(lines)
		var groups: Array[String] = []
		for encounter in card.encounters:
			var names: Array[String] = []
			for enemy in encounter.enemies:
				names.append(enemy.display_name)
			groups.append(", ".join(names))
		lines.append(("Could be: " if groups.size() > 1 else "Enemies: ") + "  /  ".join(groups))
		match card.type:
			RoomCard.Type.MINI_BOSS:
				lines.append("Beat it to light a campfire. Resting there opens %s." % (
					"Tier %d" % (dungeon.tier + 1) if dungeon.tier < dungeon.max_tier else "the Boss room"))
			RoomCard.Type.BOSS:
				lines.append("Beat it to clear the %s and take your loot home." % dungeon.area.display_name)
		lines.append("Blocks the way until you beat it. Click it to fight.")
	elif card.type == RoomCard.Type.LOCKED_CHEST:
		if room.get("opened", false):
			lines.append("Opened.")
		else:
			lines.append("Needs a small key (you have %d)." % dungeon.keys)
	elif card.type == RoomCard.Type.TREASURE:
		lines.append("Taken." if room.cleared else "")
	elif card.type == RoomCard.Type.CAMPFIRE:
		lines.append("The fire is out (each campfire can be used once).")
	elif card.type == RoomCard.Type.EMPTY:
		lines.append("Nothing here.")
	elif card.type == RoomCard.Type.EVENT:
		if room.get("event") != null:
			lines[0] = "%s (Event)" % room.event.event_name
		lines.append("Done." if room.done else "Something strange happens here. Step in to find out.")
	if not card.loot.is_empty() and not room.get("opened", false) and not (card.type == RoomCard.Type.TREASURE and room.cleared):
		lines.append("Loot: one of " + ", ".join(Array(card.loot)))
	return "\n".join(lines.filter(func(line: String) -> bool: return not line.is_empty()))


func make_box(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var key := "%s %s %d" % [color.to_html(), border.to_html(), width]
	if _boxes.has(key):
		return _boxes[key]
	var box := StyleBoxFlat.new()
	_boxes[key] = box
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	return box


func default_info() -> String:
	if not dungeon.result.is_empty():
		return ""
	return "Click a ? square to explore, or a room to walk back to it."


# Is there something to do on the square you're standing on?
func has_action_here() -> bool:
	var room: Dictionary = dungeon.rooms[dungeon.position]
	if room.campfire:
		return true
	return room.card != null and room.card.type == RoomCard.Type.LOCKED_CHEST and not room.get("opened", false)


# --- Clicking ---------------------------------------------------------------

func _on_square_hovered(square: Vector2i) -> void:
	if not reach.has(square):
		return
	var distance: int = reach[square].steps
	var what := "explore" if not dungeon.is_explored(square) else "walk there"
	var text := "%d step%s to %s." % [distance, "s" if distance > 1 else "", what]
	if dungeon.steps_to_next_danger() <= distance:
		text += " Danger goes up!"
	info_label.text = text


func _on_square_pressed(square: Vector2i) -> void:
	if popup.visible or picker:
		return
	var what := "chest" if square == dungeon.position else dungeon.move_to(square)
	if square == dungeon.position and dungeon.rooms[square].campfire:
		what = "campfire"
	refresh()
	if guide_label:
		show_guide_tip(what, square)
	match what:
		"fight", "ambush":
			var card: RoomCard = dungeon.rooms[square].card
			var heading := "Boss!" if card.type == RoomCard.Type.BOSS else card.type_name() + "!"
			var text := "%s\n%s" % [card.room_name, enemy_list(dungeon.fight_enemies)]
			if what == "ambush":
				show_popup("Ambush!", text + "\nThey jump out at you. There's no backing off!", [["Fight!", start_fight]])
			else:
				text += "\nBacking off takes you to the square you came from (1 step). This room will block the way until you beat it."
				show_popup(heading, text, [["Fight!", start_fight], ["Back off", _on_back_off]])
		"chest":
			show_chest()
		"campfire":
			show_campfire()
		"event":
			show_event()
		"treasure":
			var found := dungeon.history[-1].trim_prefix("Treasure! ")
			var card: RoomCard = dungeon.rooms[square].card
			var text := "You find %s." % found
			if dungeon.guided and dungeon.guide_goal_met():
				text += "\n" + guide_goal_text()
			if card.loot.has("Key"):
				show_popup("A Key!", text, [["Nice", close_popup]], KEY_ICON, "key")
			else:
				show_popup("Treasure!", text, [["Nice", close_popup]], loot_picture(card), "pop")


# --- The guided first run ------------------------------------------------------
# Before the Inn, the Plains trip has no enemies: a box under the stats
# explains each new thing the first time you meet it. Its campfire only offers
# Return to Town, and only once you have the Stone the Inn needs.

const GUIDE_START := "Welcome to the Plains! The grid is the dungeon. Click a ? square next to you to explore it: each new square draws a card from the area's room deck. You need 5 Stone for the Inn."

func build_guide() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.08, 0.95)
	style.border_color = Color(1, 0.84, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	guide_label = Label.new()
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.add_theme_font_size_override("font_size", 16)
	guide_label.text = "Guide:  " + GUIDE_START
	panel.add_child(guide_label)
	var box := info_label.get_parent()
	box.add_child(panel)
	box.move_child(panel, info_label.get_index() + 1)


# "Stone 3 / 5" for the guide, from what the Inn needs.
func guide_progress() -> String:
	var parts: Array[String] = []
	var needs := dungeon.guide_needs()
	for material_name in needs:
		parts.append("%s %d / %d" % [material_name, mini(dungeon.material_total(material_name), needs[material_name]), needs[material_name]])
	return "  ".join(parts)


# Once you have enough Stone: find the campfire, or go back to the one you found.
func guide_goal_text() -> String:
	var found_fire := dungeon.rooms.values().any(func(room: Dictionary) -> bool:
		return room.card != null and room.card.type == RoomCard.Type.CAMPFIRE)
	return "You have all the Stone you need! Walk back to the campfire and Return to Town." if found_fire \
		else "You have all the Stone you need! Find a campfire to Return to Town."


# A tip for what just happened.
func show_guide_tip(what: String, square: Vector2i) -> void:
	var card: RoomCard = dungeon.rooms[square].card if dungeon.rooms.has(square) else null
	var tip := ""
	match what:
		"treasure":
			if card and card.loot.has("Key"):
				tip = "A small key! Each key opens one Locked Chest. You can walk back through rooms you've explored for free."
			else:
				tip = "Stone! What you find shows on the right under Found. It's only yours once you get home: if you fall, you lose it, except what's in your Save Sack. Try dragging the Stone into the sack."
		"chest":
			tip = "A Locked Chest. Open it with a key." if dungeon.keys > 0 \
				else "A Locked Chest, and no key yet. Keep exploring, then come back: chests wait for you."
		"empty":
			tip = "Nothing here, just a quiet meadow. Explored rooms stay on the map."
		"campfire":
			tip = "A campfire! Campfires are your way back to town." if not dungeon.guide_goal_met() else guide_goal_text()
		"opened":
			tip = "The key opened it!"
		"walk":
			if dungeon.deck.is_empty():
				tip = "The room deck is empty, so the dark squares are dead ends."
	if dungeon.guide_goal_met() and what != "campfire":
		tip = guide_goal_text()
	if not tip.is_empty():
		guide_label.text = "Guide:  %s\n(%s)" % [tip, guide_progress()]


# The guided run's campfire: Return to Town is the only choice, greyed out
# until you have the Stone.
func show_guided_campfire() -> void:
	var text := "Campfires let you return to town with everything you found."
	var blocked := ""
	if dungeon.guide_goal_met():
		text += "\nYou have the Stone. Time to go home and build the Inn!"
	else:
		blocked = "You need 5 Stone first (%s)." % guide_progress()
		text += "\n" + blocked
	show_popup("Campfire", text, [["Return to Town", _on_leave, blocked], ["Keep exploring", close_popup]],
		ICONS[RoomCard.Type.CAMPFIRE], "pop")


# An event: its story and a button per choice. Choices you can't pick yet
# (not enough gold, no flask) are greyed out with the reason as a tooltip.
func show_event() -> void:
	var event: DungeonEvent = dungeon.rooms[dungeon.position].event
	var choices := []
	for i in event.choice_labels.size():
		var label := event.choice_labels[i]
		for effect in DungeonEvent.split_effects(event.effects[i]):
			if effect.to_lower().begins_with("pay "):
				label += " (%s gold)" % effect.substr(4)  # Show the price.
		if event.chances[i] < 100:
			label += " (%d%%)" % event.chances[i]
		var blocked := dungeon.choice_blocked(event, i)
		choices.append([label, _on_event_choice.bind(i), blocked])
	show_popup(event.event_name, event.text, choices)


func _on_event_choice(index: int) -> void:
	var event: DungeonEvent = dungeon.rooms[dungeon.position].event
	if not dungeon.choice_blocked(event, index).is_empty():
		return  # Greyed out (not enough gold...).
	var outcome := dungeon.choose(index)
	refresh()
	if outcome.fight:
		show_popup(event.event_name, outcome.text + "\n" + enemy_list(dungeon.fight_enemies), [["Fight!", start_fight]])
	else:
		show_popup(event.event_name, outcome.text if not outcome.text.is_empty() else "...", [["OK", close_popup]])


func enemy_list(enemies: Array[EnemyData]) -> String:
	var names: Array[String] = []
	for enemy in enemies:
		names.append(enemy.display_name)
	return ", ".join(names)


func _on_back_off() -> void:
	dungeon.back_off()
	close_popup()


func start_fight() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


func show_chest() -> void:
	var card: RoomCard = dungeon.rooms[dungeon.position].card
	if dungeon.keys > 0:
		show_popup(card.room_name, "A locked chest. Use a small key? (You have %d.)" % dungeon.keys,
			[["Open it", _on_open_chest], ["Leave it", close_popup]], ICONS[RoomCard.Type.LOCKED_CHEST], "chest")
	else:
		show_popup(card.room_name, "A locked chest. You need a small key: %s" % ("look around for one." if dungeon.guided else "fights sometimes drop one."),
			[["OK", close_popup]], ICONS[RoomCard.Type.LOCKED_CHEST], "chest")


func _on_open_chest() -> void:
	var card: RoomCard = dungeon.rooms[dungeon.position].card
	var loot := dungeon.open_chest(dungeon.position)
	refresh()
	if guide_label:
		show_guide_tip("opened", dungeon.position)
	var text := "Inside: %s" % loot
	if dungeon.guided and dungeon.guide_goal_met():
		text += "\n" + guide_goal_text()
	# The chest rattles, then bursts open (see play_picture).
	show_popup("Opened!", text, [["Nice", close_popup]], ICONS[RoomCard.Type.LOCKED_CHEST], "unlock")
	popup_loot_texture = loot_picture(card)


func show_campfire() -> void:
	if dungeon.guided:
		show_guided_campfire()
		return
	# For now a campfire is the way home. (Rest is switched off: see rest() in
	# dungeon_run.gd.) After a Mini Boss it can also take you deeper.
	var text := "Return to Town with what you found (%s)." % dungeon.loot_text()
	var choices := [["Return to Town", _on_leave]]
	if dungeon.tier_up_waiting:
		text = ("The Mini Boss is beaten! Go Deeper to Tier %d: harder rooms, better loot. (No healing: the map goes blank and the rooms shift.)" % (dungeon.tier + 1)
			if dungeon.tier < dungeon.max_tier else "The Mini Boss is beaten! Go Deeper to find the way to the Boss. (No healing: the map goes blank.)") + "\nOr " + text
		choices.push_front(["Go Deeper", _on_go_deeper])
	choices.append(["Not now", close_popup])
	show_popup("Campfire", text, choices, ICONS[RoomCard.Type.CAMPFIRE], "pop")


func _on_go_deeper() -> void:
	dungeon.rest(false)
	close_popup()
	refresh()
	info_label.text = "Tier %d! New rooms are in the deck." % dungeon.tier if not dungeon.boss_unlocked else "The Boss is somewhere in the deck now!"


func _on_rest() -> void:
	var healed := dungeon.rest()
	close_popup()
	refresh()
	info_label.text = "You rest and heal %d HP.%s" % [healed, " Your flask is full again." if dungeon.flask else ""]


# Drink the flask between fights: heal your run HP.
func _on_flask_pressed() -> void:
	if not dungeon.can_sip_on_map():
		return
	var max_hp := GameState.player_max_hp()
	var hp_before := GameState.run_hp if GameState.run_hp > 0 else max_hp
	var sip := dungeon.sip_flask()
	GameState.run_hp = mini(hp_before + sip.heal, max_hp)
	var text := "You drink from your %s: d%d rolled %d, heal %d (HP %d/%d)." % [dungeon.flask.flask_name,
		dungeon.flask_stats[Flask.HEAL_DIE], sip.roll, GameState.run_hp - hp_before, GameState.run_hp, max_hp]
	if sip.kept:
		text += " Lucky, the flask is still full!"
	dungeon.add_log(text)
	refresh()
	info_label.text = text  # After refresh(), which sets its own hint.


func _on_leave() -> void:
	dungeon.leave()
	dungeon.claim_loot()
	get_tree().change_scene_to_file(TOWN_SCENE)


# --- The popup ----------------------------------------------------------------

# choices: a list of [button text, function to call], or [text, function,
# why it's blocked] to grey a button out (with the reason as its tooltip).
func show_popup(heading: String, text: String, choices: Array, picture: Texture2D = null, animation := "") -> void:
	play_picture(picture, animation)
	popup_title.text = heading
	popup_text.text = text
	for old in popup_buttons.get_children():
		old.queue_free()
	for choice in choices:
		var button := Button.new()
		button.text = choice[0]
		button.custom_minimum_size = Vector2(150, 44)
		button.pressed.connect(choice[1])
		if choice.size() > 2 and not str(choice[2]).is_empty():
			button.disabled = true
			button.tooltip_text = choice[2]
		if choice == choices[0]:
			button.theme_type_variation = &"PrimaryButton"  # The first choice is the main one (gold).
		popup_buttons.add_child(button)
	popup.show()


func close_popup() -> void:
	popup.hide()
	if popup_tween:
		popup_tween.kill()
	refresh()


# --- Popup pictures and animations ------------------------------------------------
# A picture above the popup's title, animated with Tweens:
#   "key"    spins in and sparkles
#   "chest"  drops in and bounces
#   "unlock" rattles, then swaps to an open chest with a burst (and the loot pops out)
#   "pop"    grows in with a little bounce

const PICTURE_SIZE := Vector2(110, 110)

func make_popup_picture() -> void:
	popup_holder = Control.new()  # A plain Control, so we can move the picture freely inside it.
	popup_holder.custom_minimum_size = Vector2(0, PICTURE_SIZE.y + 10)
	popup_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_title.get_parent().add_child(popup_holder)
	popup_title.get_parent().move_child(popup_holder, 0)
	popup_picture = TextureRect.new()
	popup_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	popup_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Anchored to the middle of the holder, so it stays centred whatever the popup's width.
	popup_picture.anchor_left = 0.5
	popup_picture.anchor_right = 0.5
	popup_picture.offset_left = -PICTURE_SIZE.x / 2
	popup_picture.offset_right = PICTURE_SIZE.x / 2
	popup_picture.offset_bottom = PICTURE_SIZE.y
	popup_picture.pivot_offset = PICTURE_SIZE / 2
	popup_holder.add_child(popup_picture)
	popup_sparkles = CPUParticles2D.new()
	popup_sparkles.amount = 40
	popup_sparkles.one_shot = true
	popup_sparkles.explosiveness = 0.9
	popup_sparkles.lifetime = 0.9
	popup_sparkles.spread = 180
	popup_sparkles.initial_velocity_min = 120
	popup_sparkles.initial_velocity_max = 260
	popup_sparkles.gravity = Vector2(0, 300)
	popup_sparkles.scale_amount_min = 3
	popup_sparkles.scale_amount_max = 6
	popup_sparkles.color = Color(1, 0.85, 0.35)
	popup_sparkles.emitting = false
	popup_sparkles.position = PICTURE_SIZE / 2  # The picture's middle.
	popup_picture.add_child(popup_sparkles)


# The loot's picture: a material's icon, a key, or the treasure gem.
func loot_picture(card: RoomCard) -> Texture2D:
	for entry in card.loot:
		var words := entry.split(" ", false)
		var info := GameState.find_material(" ".join(words.slice(0, -1)) if words.size() > 1 else entry)
		if info and info.icon:
			return info.icon
	return ICONS[RoomCard.Type.TREASURE]


func play_picture(picture: Texture2D, animation: String) -> void:
	if popup_holder == null:
		make_popup_picture()
	if popup_tween:
		popup_tween.kill()
	popup_loot_texture = null
	for old in popup_holder.get_children():  # Loot still floating out of the last chest.
		if old != popup_picture:
			old.queue_free()
	popup_holder.visible = picture != null
	if picture == null:
		return
	popup_picture.texture = picture
	popup_picture.position.y = 0
	popup_picture.rotation = 0
	popup_picture.scale = Vector2.ONE
	popup_picture.modulate = Color.WHITE
	popup_tween = create_tween()
	match animation:
		"key":
			popup_picture.scale = Vector2.ZERO
			popup_picture.rotation = -PI
			popup_tween.tween_property(popup_picture, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			popup_tween.parallel().tween_property(popup_picture, "rotation", 0.0, 0.45).set_ease(Tween.EASE_OUT)
			popup_tween.tween_callback(func() -> void: popup_sparkles.restart())
			popup_tween.tween_property(popup_picture, "rotation", 0.25, 0.15)
			popup_tween.tween_property(popup_picture, "rotation", 0.0, 0.15)
		"chest":
			var rest_y := popup_picture.position.y
			popup_picture.position.y = rest_y - 80
			popup_picture.modulate.a = 0
			popup_tween.tween_property(popup_picture, "modulate:a", 1.0, 0.15)
			popup_tween.parallel().tween_property(popup_picture, "position:y", rest_y, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		"unlock":
			# Rattle: tip left and right a few times...
			for i in 3:
				popup_tween.tween_property(popup_picture, "rotation", 0.18, 0.06)
				popup_tween.tween_property(popup_picture, "rotation", -0.18, 0.06)
			popup_tween.tween_property(popup_picture, "rotation", 0.0, 0.05)
			# ...then the lid flies open: swap the picture, pop, sparkle...
			popup_tween.tween_callback(func() -> void:
				popup_picture.texture = OPEN_CHEST_ICON
				popup_sparkles.restart())
			popup_tween.tween_property(popup_picture, "scale", Vector2.ONE * 1.25, 0.1)
			popup_tween.tween_property(popup_picture, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
			# ...and the loot jumps out and floats up.
			popup_tween.tween_callback(_pop_out_loot)
		_:  # "pop"
			popup_picture.scale = Vector2.ZERO
			popup_tween.tween_property(popup_picture, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			popup_tween.tween_callback(func() -> void: popup_sparkles.restart())


# The loot's picture jumps out of the opened chest and fades away.
func _pop_out_loot() -> void:
	if popup_loot_texture == null:
		return
	var loot := TextureRect.new()
	loot.texture = popup_loot_texture
	loot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	loot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	loot.size = PICTURE_SIZE * 0.55
	loot.position = popup_picture.position + PICTURE_SIZE / 2 - loot.size / 2  # Starts in the chest.
	loot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_holder.add_child(loot)
	var tween := loot.create_tween()
	tween.tween_property(loot, "position:x", loot.position.x + 90, 0.5)
	tween.parallel().tween_property(loot, "position:y", loot.position.y - 20, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.6)
	tween.tween_property(loot, "modulate:a", 0.0, 0.4)
	tween.tween_callback(loot.queue_free)


# --- Save Sack, Found loot, enchants and potions --------------------------------
# The side panel shows what you've found as little chips. Drag one into a
# Save Sack slot (or just click it) to keep it safe if you die; click a sack
# slot to take it back out. The rules are in dungeon_run.gd (put_in_sack...).

func build_sack_panel() -> void:
	var box := info_label.get_parent()
	var at := info_label.get_index() + 1
	var nodes: Array[Control] = []

	var sack_title := HBoxContainer.new()
	var sack_picture := TextureRect.new()
	sack_picture.texture = SACK_ICON
	sack_picture.custom_minimum_size = Vector2(24, 24)
	sack_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sack_title.add_child(sack_picture)
	sack_title.add_child(make_small_label("Save Sack: kept even if you die", Color(1, 0.85, 0.5)))
	sack_title.tooltip_text = "Drag what you've found into a slot (or click it). If you die, you keep what's in the sack.\nEach slot holds a pack, a card, or up to %d gold. The Tailor in town makes it bigger." % GameState.gold_stack()
	nodes.append(sack_title)
	sack_row = HBoxContainer.new()
	sack_row.add_theme_constant_override("separation", 6)
	nodes.append(sack_row)

	nodes.append(make_small_label("Found (lost if you die):", Color(0.85, 0.82, 0.76)))
	found_row = HFlowContainer.new()
	found_row.add_theme_constant_override("h_separation", 6)
	found_row.add_theme_constant_override("v_separation", 4)
	nodes.append(found_row)

	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 8)
	enchant_button = Button.new()
	enchant_button.icon = ENCHANT_ICON
	enchant_button.expand_icon = true
	enchant_button.custom_minimum_size = Vector2(190, 40)
	enchant_button.pressed.connect(show_enchant_picker)
	enchant_button.tooltip_text = "Put an enchant on a card in your deck. It lasts for this run, and each card holds one."
	gear.add_child(enchant_button)
	potion_row = HBoxContainer.new()
	potion_row.add_theme_constant_override("separation", 2)
	gear.add_child(potion_row)
	nodes.append(gear)

	for node in nodes:
		box.add_child(node)
		box.move_child(node, at)
		at += 1


func make_small_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	return label


func refresh_sack() -> void:
	if sack_row == null:
		return
	for old in sack_row.get_children() + found_row.get_children() + potion_row.get_children():
		old.queue_free()
	# The sack's slots: filled ones (click to take out) and empty ones.
	for i in GameState.sack_slots():
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(120, 34)
		slot.add_theme_font_size_override("font_size", 14)
		slot.focus_mode = Control.FOCUS_NONE
		slot.clip_text = true
		if i < dungeon.sack.size():
			slot.text = DungeonRun.sack_item_text(dungeon.sack[i])
			slot.tooltip_text = "Click to take it out of the sack."
			slot.pressed.connect(_on_sack_slot_pressed.bind(i))
		else:
			slot.text = "(empty)"
			slot.modulate.a = 0.6
			slot.tooltip_text = "Drag something you found here."
		# set_drag_forwarding(): this slot accepts drops (the chips below are
		# what you drag). Callable() = "nothing" for the part we don't need.
		slot.set_drag_forwarding(Callable(), _can_drop_in_sack, _drop_in_sack)
		sack_row.add_child(slot)
	# What you've found, as chips you can drag.
	if dungeon.found_gold > 0:
		found_row.add_child(make_chip("%d gold" % dungeon.found_gold, {"kind": "gold"},
			"Drag into the sack: a slot holds up to %d gold." % GameState.gold_stack()))
	if dungeon.found_packs > 0:
		found_row.add_child(make_chip("Small Plains Pack x%d" % dungeon.found_packs, {"kind": "pack"}, ""))
	for card in dungeon.found_cards:
		found_row.add_child(make_chip(card.card_name, {"kind": "card", "card": card}, ""))
	for material_name in dungeon.found_materials:
		var chip := make_chip("%s x%d" % [material_name, dungeon.found_materials[material_name]],
			{"kind": "material", "name": material_name},
			"Drag into the sack: a slot holds up to %d of one material." % GameState.gold_stack())
		var info := GameState.find_material(material_name)
		if info:
			chip.add_theme_color_override("font_color", info.color)
			chip.icon = info.icon
			chip.add_theme_constant_override("icon_max_width", 18)
		found_row.add_child(chip)
	if found_row.get_child_count() == 0:
		found_row.add_child(make_small_label("nothing yet", Color(1, 1, 1, 0.5)))
	# Enchants waiting, and potions.
	enchant_button.text = "Use Enchant (%d)" % dungeon.enchant_drops.size()
	enchant_button.disabled = dungeon.enchant_drops.is_empty()
	if dungeon.flask:  # Your flask first, with its charges left. A healing flask can be drunk right here.
		var flask_icon := Button.new()
		flask_icon.icon = FLASK_ICON
		flask_icon.add_theme_constant_override("icon_max_width", 30)  # The svg is 64px: shrink it to fit.
		flask_icon.flat = true
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			flask_icon.add_theme_color_override(state, dungeon.flask.color)
		flask_icon.custom_minimum_size = Vector2(36, 36)
		flask_icon.disabled = not dungeon.can_sip_on_map()
		var how := "Click to drink it now, or in a fight." if dungeon.flask_stats[Flask.HEAL_DIE] > 0 else "Drink it during a fight."
		if dungeon.flask_charges <= 0:
			how = "Empty: it refills on your next run."
		flask_icon.tooltip_text = "%s (%d / %d charges): %s\n%s" % [dungeon.flask.flask_name, dungeon.flask_charges,
			dungeon.flask_stats[Flask.CHARGES], Flask.effect_text(dungeon.flask_stats), how]
		flask_icon.pressed.connect(_on_flask_pressed)
		potion_row.add_child(flask_icon)
		potion_row.add_child(make_small_label("%d/%d" % [dungeon.flask_charges, dungeon.flask_stats[Flask.CHARGES]],
			Color(1, 1, 1, 0.8) if dungeon.flask_charges > 0 else Color(1, 1, 1, 0.35)))
	for potion in dungeon.potions:
		var bottle := TextureRect.new()
		bottle.texture = POTION_ICON
		bottle.self_modulate = potion.color
		bottle.custom_minimum_size = Vector2(34, 34)
		bottle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bottle.tooltip_text = "%s: %s\nDrink it during a fight." % [potion.potion_name, potion.effect_text()]
		potion_row.add_child(bottle)
	var free_slots := GameState.potion_slots() - dungeon.potions.size()
	if free_slots > 0:
		potion_row.add_child(make_small_label("+%d" % free_slots, Color(1, 1, 1, 0.4)))


# A found thing you can drag into the sack (or click).
func make_chip(text: String, data: Dictionary, tip: String) -> Button:
	var chip := Button.new()
	chip.text = text
	chip.add_theme_font_size_override("font_size", 14)
	chip.focus_mode = Control.FOCUS_NONE
	chip.tooltip_text = tip if not tip.is_empty() else "Drag into the Save Sack (or click)."
	chip.pressed.connect(_put_in_sack.bind(data))
	chip.set_drag_forwarding(func(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		preview.add_theme_font_size_override("font_size", 16)
		chip.set_drag_preview(preview)
		return data, Callable(), Callable())
	return chip


func _can_drop_in_sack(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("kind") and dungeon.sack.size() < GameState.sack_slots()


func _drop_in_sack(_at: Vector2, data: Variant) -> void:
	_put_in_sack(data)


func _put_in_sack(data: Dictionary) -> void:
	if dungeon.put_in_sack(data.kind, data.get("card"), data.get("name", "")):
		info_label.text = "Into the Save Sack: safe even if you die."
	else:
		info_label.text = "The Save Sack is full. Click a slot to take something out."
	refresh_sack()


func _on_sack_slot_pressed(slot: int) -> void:
	dungeon.take_out_of_sack(slot)
	refresh_sack()


# --- Putting an enchant on a card -------------------------------------------------

func show_enchant_picker() -> void:
	if dungeon.enchant_drops.is_empty() or popup.visible:
		return
	var choices: Array = dungeon.enchant_drops[0]
	if choices.size() == 1:
		pick_card_for(choices[0])
		return
	# The Enchanter's upgrade: choose which enchant first.
	var buttons := []
	var lines: Array[String] = []
	for enchant: Enchant in choices:
		buttons.append([enchant.enchant_name, func() -> void:
			close_popup()
			pick_card_for(enchant)])
		lines.append("%s: %s" % [enchant.enchant_name, enchant.description])
	show_popup("Choose an enchant", "\n".join(lines), buttons)


# A full-screen list of the cards this enchant can go on. Click one.
func pick_card_for(enchant: Enchant) -> void:
	picker = ColorRect.new()
	picker.color = Color(0, 0, 0, 0.85)
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(picker)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 40
	layout.offset_right = -40
	layout.offset_top = 24
	layout.offset_bottom = -24
	layout.add_theme_constant_override("separation", 10)
	picker.add_child(layout)
	var heading := Label.new()
	heading.text = "Enchant: %s" % enchant.enchant_name
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", enchant.color)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(heading)
	var about := Label.new()
	about.text = "%s\nClick a card to put it on (for this run; each card holds one enchant)." % enchant.description
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(about)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var cards := GridContainer.new()
	cards.columns = 7
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	scroll.add_child(cards)
	var fits := GameState.enchantable_cards(enchant)
	for i in fits:
		var card: Card = CARD_SCENE.instantiate()
		cards.add_child(card)
		card.setup(GameState.leveled(GameState.deck[i]))
		card.clicked.connect(_on_enchant_card_chosen.bind(i, enchant))
	if fits.is_empty():
		about.text += "\n\nNo card in your deck can take this enchant (it needs a card with dice, or one that deals damage)."

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	var later := Button.new()
	later.text = "Later"
	later.custom_minimum_size = Vector2(150, 44)
	later.pressed.connect(close_picker)
	buttons.add_child(later)
	var drop := Button.new()
	drop.text = "Throw it away"
	drop.custom_minimum_size = Vector2(170, 44)
	drop.pressed.connect(func() -> void:
		dungeon.enchant_drops.pop_front()
		dungeon.add_log("You throw away the %s enchant." % enchant.enchant_name)
		close_picker())
	buttons.add_child(drop)
	layout.add_child(buttons)


func _on_enchant_card_chosen(_card_data: CardData, deck_index: int, enchant: Enchant) -> void:
	GameState.enchant_card(deck_index, enchant)
	dungeon.enchant_drops.pop_front()
	dungeon.add_log("%s is enchanted: %s." % [GameState.deck[deck_index].card_name, enchant.enchant_name])
	close_picker()


func close_picker() -> void:
	if picker:
		picker.queue_free()
		picker = null
	refresh()
