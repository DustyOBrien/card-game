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
	popup.hide()
	refresh()
	# Back from beating a Mini Boss: its room is a campfire now, and you
	# MUST stop there (rest, or leave with your loot).
	if dungeon.tier_up_waiting and dungeon.rooms[dungeon.position].campfire:
		show_campfire(true)


# --- Drawing ----------------------------------------------------------------

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
	var color := FOG_COLOR
	var reachable := dungeon.can_move_to(square)
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


func make_box(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
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
	var distance := dungeon.steps_to(square)
	if distance <= 0:
		return
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
		"fight":
			var card: RoomCard = dungeon.rooms[square].card
			var heading := "Boss!" if card.type == RoomCard.Type.BOSS else card.type_name() + "!"
			show_popup(heading, "%s\n%s" % [card.room_name, enemy_list(dungeon.fight_enemies)],
				[["Fight!", start_fight]])
		"chest":
			show_chest()
		"campfire":
			show_campfire(false)
		"treasure":
			show_popup("Treasure!", "You find %s." % dungeon.history[-1].trim_prefix("Treasure! "), [["Nice", close_popup]])


func enemy_list(enemies: Array[EnemyData]) -> String:
	var names: Array[String] = []
	for enemy in enemies:
		names.append(enemy.display_name)
	return ", ".join(names)


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


# forced = straight after a Mini Boss: no "Not now", you must Rest or Leave.
func show_campfire(forced: bool) -> void:
	var text := "Rest: heal %d%% HP, get your Vanished cards back, and the rooms shift (the map goes blank and every room goes back in the deck)." % roundi(DungeonRun.REST_HEAL * 100)
	if dungeon.tier_up_waiting:
		text += "\nThe Mini Boss is beaten: resting takes you deeper (Tier %d)." % (dungeon.tier + 1) \
			if dungeon.tier < dungeon.max_tier else "\nThe Mini Boss is beaten: resting opens the way to the Boss."
	text += "\nLeave: go home with what you found (%s)." % dungeon.loot_text()
	var choices := [["Rest", _on_rest], ["Leave the dungeon", _on_leave]]
	if not forced:
		choices.append(["Not now", close_popup])
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
