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
const SHOP_SCENE := "res://scenes/shop.tscn"

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
}
const OPEN_CHEST_ICON := preload("res://art/rooms/open_chest.svg")
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
			RoomCard.Type.TREASURE, RoomCard.Type.CAMPFIRE, RoomCard.Type.MINI_BOSS, RoomCard.Type.BOSS]:
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
	title_label.text = "%s  ·  Tier %d / %d" % [dungeon.area.display_name, dungeon.tier, dungeon.max_tier]
	var lines: Array[String] = []
	lines.append("[color=#ff8080]HP %d / %d[/color]" % [hp, GameState.player_max_hp()])
	lines.append("[color=#ffd75a]Keys: %d[/color]" % dungeon.keys)
	var danger_color := "#ffffff" if dungeon.danger() == 0 else "#ff9050"
	lines.append("[color=%s]Danger %d[/color]  (enemies +%d Strength; +1 more in %d steps)" % [
		danger_color, dungeon.danger(), dungeon.danger(), dungeon.steps_to_next_danger()])
	lines.append("Found: %s" % dungeon.loot_text())
	lines.append("Rooms left in the deck: %d" % dungeon.deck.size())
	if dungeon.boss_unlocked:
		lines.append("[color=#ff6060]The Boss is somewhere in the deck![/color]")
	elif dungeon.tier_up_waiting:
		lines.append("[color=#ffd75a]Rest at a campfire to go deeper.[/color]")
	stats_label.text = "\n".join(lines)
	stats_label.tooltip_text = "\n".join([
		"HP: carries over from fight to fight. Resting at a campfire heals %d%%." % roundi(DungeonRun.REST_HEAL * 100),
		"Keys: fights drop a small key %d%% of the time. A key opens one Locked Chest." % DungeonRun.KEY_CHANCE,
		"Danger: every %d steps since your last rest, every enemy gets +1 Strength. Resting resets it." % DungeonRun.STEPS_PER_DANGER,
		"Found: only yours once you get out (Leave at a campfire, or beat the Boss). Die and it's lost.",
		"Rooms left: blank squares draw from this deck. When it's empty, the rest are dead ends until you rest.",
	])
	info_label.text = default_info()
	log_label.text = "\n".join(dungeon.history.slice(-14))


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
		return "Dead end: the room deck ran out.\nRest at a campfire to shuffle the rooms back in."
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
	if popup.visible:
		return
	var what := "chest" if square == dungeon.position else dungeon.move_to(square)
	if square == dungeon.position and dungeon.rooms[square].campfire:
		what = "campfire"
	refresh()
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
		"treasure":
			show_popup("Treasure!", "You find %s." % dungeon.history[-1].trim_prefix("Treasure! "), [["Nice", close_popup]])


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
			[["Open it", _on_open_chest], ["Leave it", close_popup]])
	else:
		show_popup(card.room_name, "A locked chest. You need a small key: fights sometimes drop one.",
			[["OK", close_popup]])


func _on_open_chest() -> void:
	var loot := dungeon.open_chest(dungeon.position)
	refresh()
	show_popup("Opened!", "Inside: %s" % loot, [["Nice", close_popup]])


func show_campfire() -> void:
	var text := "Rest: heal %d%% HP, get your Vanished cards back, and the rooms shift (the map goes blank and every room goes back in the deck)." % roundi(DungeonRun.REST_HEAL * 100)
	if dungeon.tier_up_waiting:
		text += "\nThe Mini Boss is beaten: resting takes you deeper (Tier %d)." % (dungeon.tier + 1) \
			if dungeon.tier < dungeon.max_tier else "\nThe Mini Boss is beaten: resting opens the way to the Boss."
	text += "\nLeave: go home with what you found (%s)." % dungeon.loot_text()
	var choices := [["Rest", _on_rest], ["Leave the dungeon", _on_leave], ["Not now", close_popup]]
	show_popup("Campfire", text, choices)


func _on_rest() -> void:
	var healed := dungeon.rest()
	close_popup()
	refresh()
	info_label.text = "You rest and heal %d HP." % healed


func _on_leave() -> void:
	dungeon.leave()
	dungeon.claim_loot()
	get_tree().change_scene_to_file(SHOP_SCENE)


# --- The popup ----------------------------------------------------------------

# choices: a list of [button text, function to call].
func show_popup(heading: String, text: String, choices: Array) -> void:
	popup_title.text = heading
	popup_text.text = text
	for old in popup_buttons.get_children():
		old.queue_free()
	for choice in choices:
		var button := Button.new()
		button.text = choice[0]
		button.custom_minimum_size = Vector2(150, 44)
		button.pressed.connect(choice[1])
		popup_buttons.add_child(button)
	if not choices.is_empty():
		popup_buttons.get_child(0).theme_type_variation = &"PrimaryButton"
	popup.show()


func close_popup() -> void:
	popup.hide()
	refresh()
