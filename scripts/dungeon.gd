# dungeon.gd
#
# The dungeon screen (scenes/dungeon.tscn): the 5 x 5 BOARD of map cards.
# Every card starts face down. Click a card next to the ones you've made
# safe to step onto it: it FLIPS over, and you deal with whatever it is.
# Click any face-up safe card to walk back to it.
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
const PACK_ICON := preload("res://icons/booster.svg")
const SACK_ICON := preload("res://art/potions/sack.svg")
const POTION_ICON := preload("res://art/potions/potion.svg")
const FLASK_ICON := preload("res://art/potions/flask.svg")
const CARD_BACK := preload("res://art/map_cards/card_back.svg")

const SQUARE_SIZE := Vector2(108, 108)
const GAP := 6
const FLIP_TIME := 0.14  # Seconds for each half of a card flip.

# A picture for cards whose row has no Art (the old room decks).
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
const BACK_COLOR := Color(0.16, 0.12, 0.08, 0.95)  # A face-down card.
const CARD_COLOR := Color(0.3, 0.26, 0.2, 0.96)  # A face-up card.
const DANGER_CARD_COLOR := Color(0.45, 0.16, 0.14, 0.96)  # A fight you haven't won yet.
const CAMPFIRE_COLOR := Color(0.5, 0.32, 0.1, 0.96)
const GROUND_COLOR := Color(0.12, 0.11, 0.1, 0.9)  # A square with no card (the deck ran out).
const HOVER_BORDER := Color(1.0, 0.85, 0.35)
const HERE_BORDER := Color(0.55, 0.9, 1.0)
const USED_TINT := Color(1, 1, 1, 0.4)  # A card you've used up (looted, beaten...).

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
var busy := false  # A card is flipping: clicks wait.
# The Save Sack, Found and enchant/potion rows in the side panel (built in code).
var sack_row: HBoxContainer
var found_row: HFlowContainer
var enchant_button: Button
var potion_row: HBoxContainer
var picker: ColorRect  # The "put an enchant on a card" screen, while it's open.
var deck_list: ColorRect  # The "Map Deck" list, while it's open.
var deck_button: Button
var guide_label: Label  # The first trip's tip box (null on normal runs).
# The popup's picture (a key, a chest...) and its little animation.
var popup_holder: Control
var popup_picture: TextureRect
var popup_badge: Label  # "SAFE" / "UNSAFE" / "EXPLORE" under the title, for map cards.
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


# --- Drawing ----------------------------------------------------------------

# Under the board: what the three tile colours mean, and the Map Deck button.
func build_legend() -> void:
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 10)
	legend.position = grid.position + Vector2(0, grid.size.y + 8)
	legend.size = Vector2(grid.size.x, 40)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	for tile in [RoomCard.Tile.SAFE, RoomCard.Tile.UNSAFE, RoomCard.Tile.EXPLORE]:
		var chip := ColorRect.new()
		chip.color = RoomCard.TILE_COLORS[tile]
		chip.custom_minimum_size = Vector2(16, 16)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(chip)
		var name_label := Label.new()
		name_label.text = RoomCard.TILE_NAMES[tile]
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.tooltip_text = {
			RoomCard.Tile.SAFE: "Safe: nothing to fear here.",
			RoomCard.Tile.UNSAFE: "Unsafe: always a fight, and Danger goes up when you find it.",
			RoomCard.Tile.EXPLORE: "Explore: a choice. Some need something (a key), and failing one raises Danger.",
		}[tile]
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		legend.add_child(name_label)
	deck_button = Button.new()
	deck_button.custom_minimum_size = Vector2(150, 34)
	deck_button.add_theme_font_size_override("font_size", 15)
	deck_button.tooltip_text = "Every card in this place's map deck, and how many you haven't seen yet."
	deck_button.pressed.connect(show_deck_list)
	legend.add_child(deck_button)
	add_child(legend)


func make_square(square: Vector2i) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SQUARE_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	button.pivot_offset = SQUARE_SIZE / 2  # Flips turn around the middle.
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
	title_label.text = "%s  ·  Floor %d" % [dungeon.area.display_name, dungeon.floor_number] \
		if not dungeon.guided else "%s  ·  Your first trip" % dungeon.area.display_name
	var lines: Array[String] = []
	lines.append("[color=#ff8080]HP %d / %d[/color]     [color=#ffd75a]Keys: %d[/color]" % [hp, GameState.player_max_hp(), dungeon.keys])
	# The DANGER METER: how much, what it does now, and when it gets worse.
	var danger_color := "#ffffff" if dungeon.danger() == 0 else "#ff9050"
	lines.append("[color=%s]Danger %d[/color]  ·  enemies +%d Strength  ·  [color=#ffb080]%d more → +%d[/color]" % [
		danger_color, dungeon.danger(), dungeon.enemy_strength(), dungeon.danger_to_next(), dungeon.enemy_strength() + 1])
	var hunting := dungeon.hunting_text()
	if not hunting.is_empty():
		lines.append("[color=#a8e0ff]Hunting: %s[/color]" % hunting)
	if dungeon.boss_here():
		lines.append("[color=#ff6060]The %s is somewhere on this board![/color]" % dungeon.boss_card().room_name)
	stats_label.text = "\n".join(lines)
	stats_label.tooltip_text = "\n".join([
		"HP: carries over from fight to fight.",
		"Keys: fights drop a small key %d%% of the time. A key opens one locked chest or shed." % DungeonRun.KEY_CHANCE,
		"Danger: +1 for every Unsafe card you find, and for some failed choices. Every %d Danger gives every enemy +1 Strength. It lasts the whole trip." % dungeon.danger_per_strength(),
		"Hunting: what your quests want you to bring home (the Bank counts too).",
		"Found: only yours once you get home (Return to Town at a campfire, or beat the Boss). Die and it's lost.",
	])
	deck_button.text = "Map Deck (%d)" % (dungeon.deck.size() + dungeon.face_down_count())
	info_label.text = default_info()
	log_label.text = "\n".join(dungeon.history.slice(-14))
	refresh_sack()


# The picture on a card's face: its Art, or the old icon for its kind.
func card_art(card: RoomCard) -> Texture2D:
	return card.art if card.art else ICONS.get(card.type)


func draw_square(square: Vector2i) -> void:
	var button: Button = squares[square]
	var icon: TextureRect = button.get_node("Icon")
	var label: Label = button.get_node("Name")
	button.get_node("Player").visible = square == dungeon.position
	icon.texture = null
	icon.modulate = Color.WHITE
	label.text = ""
	button.tooltip_text = describe_square(square)  # Shown when you hover the square for a moment.
	var room: Dictionary = dungeon.rooms.get(square, {})
	var card: RoomCard = room.get("card")
	var reachable := reach.has(square)
	var color := CARD_COLOR
	var border := Color(0, 0, 0, 0.6)
	if room.is_empty() or not room.revealed:
		# FACE DOWN: just the card's back. The ones you can step onto glow gold.
		color = BACK_COLOR
		icon.texture = CARD_BACK
		icon.modulate = Color.WHITE if reachable else Color(0.6, 0.6, 0.6)
		border = Color(0.79, 0.64, 0.29, 0.9) if reachable else Color(0.3, 0.24, 0.14)
	elif card == null:
		if room.get("start", false):
			icon.texture = ICONS[RoomCard.Type.CAMPFIRE] if room.campfire else START_ICON
			label.text = "Way Home" if room.campfire else "Start"
			color = CAMPFIRE_COLOR if room.campfire else CARD_COLOR
			if not room.campfire:
				icon.modulate = USED_TINT  # Your old campfire, burnt out.
		else:
			color = GROUND_COLOR
			label.text = "Bare ground"
	else:
		# FACE UP: its picture, its name, and a border in its tile's colour.
		label.text = card.room_name
		icon.texture = card_art(card)
		border = RoomCard.TILE_COLORS[card.tile]
		if card.type == RoomCard.Type.EVENT and room.get("event") != null and card.event_name.is_empty():
			label.text = room.event.event_name  # A Mystery, once you know what it is.
		if room.campfire:
			color = CAMPFIRE_COLOR
		elif card.is_fight() and not room.cleared:
			color = DANGER_CARD_COLOR
		elif card.type == RoomCard.Type.LOCKED_CHEST and room.opened and not room.get("ruined", false) and card.art == null:
			icon.texture = OPEN_CHEST_ICON
		if room.done and not room.campfire:
			icon.modulate = USED_TINT  # Used up: faded out.
	var width := 4 if square == dungeon.position else (3 if reachable or room.get("revealed", false) else 2)
	if square == dungeon.position:
		border = HERE_BORDER
	button.add_theme_stylebox_override("normal", make_box(color, border, width))
	button.add_theme_stylebox_override("hover", make_box(color.lightened(0.12), HOVER_BORDER if reachable else border, 4 if reachable else width))
	button.add_theme_stylebox_override("pressed", make_box(color.lightened(0.2), HOVER_BORDER, 4))
	button.add_theme_stylebox_override("disabled", make_box(color, border, width))
	# You can click a square you can walk to, and the square you're on (to use
	# its campfire or chest again).
	button.disabled = not (reachable or (square == dungeon.position and has_action_here()))
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND


# The tooltip for a square: what it is and what you can do with it.
func describe_square(square: Vector2i) -> String:
	var room: Dictionary = dungeon.rooms.get(square, {})
	if room.is_empty() or not room.revealed:
		var distance: int = reach[square].steps if reach.has(square) else -1
		if distance > 0:
			return "A face-down card (%d step%s away).\nStep onto it to flip it over." % [distance, "s" if distance > 1 else ""]
		return "A face-down card.\nFlip a card next to it first."
	var card: RoomCard = room.card
	if card == null:
		if room.get("start", false):
			return "Where you came in. Return to Town from here." if room.campfire \
				else "Your campfire from the floor above, burnt out. Find this floor's campfire to get home!"
		return "Bare ground: the map deck ran out of cards."
	var lines: Array[String] = ["%s  (%s)" % [card.room_name, card.tile_name()]]
	if not card.text.is_empty():
		lines.append(card.text)
	if room.campfire:
		lines.append("A campfire! Stand here and click it to Return to Town or Go Deeper.")
		return "\n".join(lines)
	if card.is_fight():
		if room.cleared:
			lines.append("Beaten. Safe to walk over (until it's shuffled back in).")
			return "\n".join(lines)
		var groups: Array[String] = []
		for encounter in card.encounters:
			var names: Array[String] = []
			for enemy in encounter.enemies:
				names.append(enemy.display_name)
			groups.append(", ".join(names))
		lines.append(("Could be: " if groups.size() > 1 else "Enemies: ") + "  /  ".join(groups))
		if card.type == RoomCard.Type.BOSS:
			lines.append("Beat it to clear the %s and take your loot home." % dungeon.area.display_name)
	elif card.type == RoomCard.Type.LOCKED_CHEST:
		if room.get("ruined", false):
			lines.append("Smashed to pieces.")
		elif room.opened:
			lines.append("Opened.")
		else:
			lines.append("Locked. Use a small key (you have %d), or break it open." % dungeon.keys)
	elif card.type in [RoomCard.Type.TREASURE, RoomCard.Type.EMPTY]:
		lines.append("Taken." if room.done and card.type == RoomCard.Type.TREASURE else "")
	elif card.type == RoomCard.Type.EVENT:
		if room.get("event") != null and card.event_name.is_empty():
			lines[0] = "%s  (%s)" % [room.event.event_name, card.tile_name()]
		lines.append("Done." if room.done else "Step on it to see your choices.")
	if card.vanish:
		lines.append("Vanish: once it's used, it's gone for the rest of this trip.")
	if not card.loot.is_empty() and not room.done:
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
	return "Click a glowing face-down card to flip it, or a face-up card to walk back to it."


# Is there something to do on the square you're standing on?
func has_action_here() -> bool:
	var room: Dictionary = dungeon.rooms[dungeon.position]
	if room.campfire:
		return true
	var card: RoomCard = room.card
	return card != null and card.type == RoomCard.Type.LOCKED_CHEST and not room.done


# --- Clicking ---------------------------------------------------------------

func _on_square_hovered(square: Vector2i) -> void:
	if not reach.has(square) or busy:
		return
	var distance: int = reach[square].steps
	var face_down := not dungeon.is_revealed(square)
	var text := "%d step%s to %s." % [distance, "s" if distance > 1 else "", "flip this card" if face_down else "walk there"]
	info_label.text = text


func _on_square_pressed(square: Vector2i) -> void:
	if popup.visible or picker or deck_list or busy:
		return
	var what := ""
	if square == dungeon.position:
		what = "campfire" if dungeon.rooms[square].campfire else "chest"
	else:
		what = dungeon.move_to(square)
	if what.is_empty():
		return
	if dungeon.just_flipped == square:
		await flip_square(square)  # The card turns over before anything happens.
	refresh()
	if guide_label:
		show_guide_tip(what, square)
	var room: Dictionary = dungeon.rooms[square]
	var card: RoomCard = room.card
	match what:
		"fight":
			var heading := "Boss!" if card.type == RoomCard.Type.BOSS else ("Mini Boss!" if card.type == RoomCard.Type.MINI_BOSS else card.room_name)
			var text := ("%s\n" % card.text if not card.text.is_empty() else "") + "Enemies: " + enemy_list(dungeon.fight_enemies)
			text += "\nUnsafe cards are always a fight. Danger is now %d." % dungeon.danger()
			show_popup(heading, text, [["Fight!", start_fight]], card_art(card), "flip", card)
		"chest":
			show_chest()
		"campfire":
			show_campfire()
		"event":
			show_event()
		"empty":
			info_label.text = "%s: %s" % [card.room_name, card.text if not card.text.is_empty() else "Nothing here."]
		"treasure":
			var found := dungeon.history[-1].trim_prefix("Treasure! ")
			var text := ("%s\n" % card.text if not card.text.is_empty() else "") + "You find %s." % found
			if dungeon.guided and dungeon.guide_goal_met():
				text += "\n" + guide_goal_text()
			if card.loot.has("Key"):
				show_popup("A Key!", text, [["Nice", close_popup]], KEY_ICON, "key", card)
			else:
				show_popup(card.room_name, text, [["Nice", close_popup]], loot_picture(card), "pop", card)


# Turn a square's card over: it squashes to nothing showing its back, then
# grows back showing its face (like turning a real card over).
func flip_square(square: Vector2i) -> void:
	busy = true
	var button: Button = squares[square]
	var icon: TextureRect = button.get_node("Icon")
	icon.texture = CARD_BACK
	button.get_node("Name").text = ""
	var tween := create_tween()
	tween.tween_property(button, "scale:x", 0.0, FLIP_TIME).set_ease(Tween.EASE_IN)
	await tween.finished
	reach = dungeon.reachable()
	draw_square(square)  # Now it shows its face...
	tween = create_tween()
	tween.tween_property(button, "scale:x", 1.0, FLIP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tween.finished  # ...and it's back to full width.
	busy = false


# --- The Map Deck list -------------------------------------------------------------
# Every card in the place's map deck, and how many you haven't seen yet
# (face down on this board, or waiting in the draw pile). "Is the Old Well
# still out there?" Look here.

func show_deck_list() -> void:
	if deck_list or popup.visible or busy:
		return
	deck_list = ColorRect.new()
	deck_list.color = Color(0, 0, 0, 0.82)
	deck_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(deck_list)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.11, 0.09, 0.98)
	style.border_color = Color(0.85, 0.68, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	deck_list.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "Map Deck"
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var about := Label.new()
	about.text = "%d cards face down on this board, %d in the draw pile.\n\"Unseen\" = not flipped yet: still face down here, or waiting in the deck for the next floor." % [
		dungeon.face_down_count(), dungeon.deck.size()]
	about.add_theme_font_size_override("font_size", 15)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(about)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for entry in dungeon.deck_summary():
		rows.add_child(make_deck_row(entry))
	if not dungeon.gone.is_empty():
		var gone_names: Array[String] = []
		for card in dungeon.gone:
			gone_names.append(card.room_name)
		var gone_label := Label.new()
		gone_label.text = "Vanished this trip: " + ", ".join(gone_names)
		gone_label.add_theme_font_size_override("font_size", 14)
		gone_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		gone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(gone_label)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		deck_list.queue_free()
		deck_list = null)
	box.add_child(close)


# One line of the list: picture, name, tile, "2 unseen / 3".
func make_deck_row(entry: Dictionary) -> Control:
	var card: RoomCard = entry.card
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.tooltip_text = card.text
	var picture := TextureRect.new()
	picture.texture = card_art(card)
	picture.custom_minimum_size = Vector2(34, 34)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var name_label := Label.new()
	name_label.text = card.room_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	var tile_label := Label.new()
	tile_label.text = card.tile_name()
	tile_label.custom_minimum_size = Vector2(80, 0)
	tile_label.add_theme_font_size_override("font_size", 15)
	tile_label.add_theme_color_override("font_color", RoomCard.TILE_COLORS[card.tile])
	tile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tile_label)
	var count := Label.new()
	count.text = "%d unseen / %d" % [entry.unseen, entry.total]
	count.custom_minimum_size = Vector2(120, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color", Color.WHITE if entry.unseen > 0 else Color(1, 1, 1, 0.4))
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	return row


# --- The first trip ---------------------------------------------------------------
# The Adventurer's first trip to the Farm, for the Innkeeper's first two
# quests: Stone (from Collapsed Walls) and Hops (locked in sheds, so you
# learn keys). The board is always the same (the Guide rows of
# farm_cards.csv) and a box under the stats explains each new thing the
# first time you meet it. Its campfires only offer Return to Town, and only
# once you have everything the quests need.

const GUIDE_START := "Welcome to the Abandoned Farm! This board is made of MAP CARDS, all face down. Click a glowing card next to you to flip it over. The Innkeeper needs 5 Stone (from Collapsed Walls) and 3 Hops (locked in sheds)."

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


# "Stone 3 / 5  Hops 1 / 3" for the guide, from what the quests need.
func guide_progress() -> String:
	return dungeon.hunting_text()


# Once you have it all: back to a campfire.
func guide_goal_text() -> String:
	return "You have the Stone and the Hops! Walk back to the campfire where you started (or find the hidden one) and Return to Town."


# A tip for what just happened, the first time each thing happens.
func show_guide_tip(what: String, square: Vector2i) -> void:
	var card: RoomCard = dungeon.rooms[square].card if dungeon.rooms.has(square) else null
	var tip := ""
	match what:
		"treasure":
			if card and card.loot.has("Key"):
				tip = "A small key! Each key opens one locked shed or chest. Face-up Safe cards can be walked over for free, so you can go back for the sheds."
			else:
				tip = "A Collapsed Wall: Stone! SAFE cards (green border) are nothing to fear. What you find shows on the right under Found. It's only yours once you get home: if you fall, you lose it."
		"fight":
			tip = "An UNSAFE card (red border): always a fight, and it raises DANGER. Every %d Danger makes every enemy stronger, for the whole trip. Once you win, the card is safe to walk over." % dungeon.danger_per_strength()
		"chest":
			tip = "An EXPLORE card (gold border): you choose what to do. Use a key to open it." if dungeon.keys > 0 \
				else "An EXPLORE card (gold border): a locked shed, and no key yet. Keep exploring, then come back: it waits for you."
		"event":
			tip = "Another EXPLORE card: pick a choice. Some choices are a gamble: the % shows the chance it works."
		"empty":
			tip = "Nothing here, just the farm. Most of the Farm's cards are like this... for now."
		"campfire":
			tip = "A campfire! Campfires are your way home. On later trips, they also let you GO DEEPER: a fresh board, one floor down." if not dungeon.guide_goal_met() else guide_goal_text()
		"opened":
			tip = "The key opened it! Sheds and chests hold the good stuff: here, the Innkeeper's Hops."
	if dungeon.guide_goal_met() and what != "campfire":
		tip = guide_goal_text()
	if not tip.is_empty():
		guide_label.text = "Guide:  %s\n(%s)" % [tip, guide_progress()]


# The first trip's campfire: Return to Town is the only choice, greyed out
# until you have the Stone and the Hops.
func show_guided_campfire() -> void:
	var text := "Campfires let you return to town with everything you found."
	var blocked := ""
	if dungeon.guide_goal_met():
		text += "\nYou have everything the Innkeeper asked for. Time to head home!"
	else:
		blocked = "The Innkeeper is still waiting for some of it (%s)." % guide_progress()
		text += "\n" + blocked
	show_popup("Campfire", text, [["Return to Town", _on_leave, blocked], ["Keep exploring", close_popup]],
		ICONS[RoomCard.Type.CAMPFIRE], "pop")


# An Explore card's event: its story and a button per choice. Choices you
# can't pick yet (not enough gold, no flask) are greyed out with the reason as a tooltip.
func show_event() -> void:
	var room: Dictionary = dungeon.rooms[dungeon.position]
	var event: DungeonEvent = room.event
	var card: RoomCard = room.card
	var choices := []
	for i in event.choice_labels.size():
		if dungeon.choice_hidden(event, i):
			continue  # Not open yet (enchants before the Enchanter).
		var label := event.choice_labels[i]
		for effect in DungeonEvent.split_effects(event.effects[i]):
			if effect.to_lower().begins_with("pay "):
				label += " (%s gold)" % effect.substr(4)  # Show the price.
		if event.chances[i] < 100:
			label += " (%d%%)" % event.chances[i]
		var blocked := dungeon.choice_blocked(event, i)
		choices.append([label, _on_event_choice.bind(i), blocked])
	var picture := event_picture(event)
	if picture[0] == null and card:
		picture = [card_art(card), "flip"]
	show_popup(event.event_name, event.text, choices, picture[0], picture[1], card)


# The picture (and animation) an event shows, from its Picture column:
# [texture, animation], or [null, ""] for none (the card's own picture then).
func event_picture(event: DungeonEvent) -> Array:
	match event.picture.to_lower():
		"wiggling chest":  # Someone's stuck inside: it wiggles and shouts.
			return [ICONS[RoomCard.Type.LOCKED_CHEST], "help"]
	return [null, ""]


func _on_event_choice(index: int) -> void:
	var event: DungeonEvent = dungeon.rooms[dungeon.position].event
	if dungeon.choice_hidden(event, index) or not dungeon.choice_blocked(event, index).is_empty():
		return  # Not shown, or greyed out (not enough gold...).
	var outcome := dungeon.choose(index)
	refresh()
	if not str(outcome.blueprint).is_empty():
		# Someone gave you a blueprint (the trapped Enchanter): they jump out!
		var art := "res://art/town/%s.svg" % str(outcome.blueprint).to_snake_case()
		var picture: Texture2D = load(art) if ResourceLoader.exists(art) else ICONS[RoomCard.Type.TREASURE]
		show_popup(event.event_name, outcome.text, [["OK", close_popup]], picture, "jump")
		return
	if outcome.fight:
		show_popup(event.event_name, outcome.text + "\n" + enemy_list(dungeon.fight_enemies), [["Fight!", start_fight]])
	else:
		show_popup(event.event_name, outcome.text if not outcome.text.is_empty() else "...", [["OK", close_popup]])


func enemy_list(enemies: Array[EnemyData]) -> String:
	var names: Array[String] = []
	for enemy in enemies:
		names.append(enemy.display_name)
	return ", ".join(names)


func start_fight() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


# A Locked Chest (a shed, a stash...): use a key, break it open, or leave it.
# (The first trip only offers the key, so the Hops can't be lost.)
func show_chest() -> void:
	var card: RoomCard = dungeon.rooms[dungeon.position].card
	var text := ("%s\n" % card.text if not card.text.is_empty() else "") + "How do you want to open it?"
	var choices := []
	choices.append(["Use a key (100%)", _on_open_chest, "" if dungeon.keys > 0 else "You need a small key (fights sometimes drop one)."])
	if not dungeon.guided:
		choices.append(["Break it open (%d%%)" % DungeonRun.BREAK_CHANCE, _on_break_chest])
	choices.append(["Leave it", close_popup])
	text += "\nKeys: %d." % dungeon.keys
	if not dungeon.guided:
		text += " Breaking it is free but LOUD: if it fails, Danger +1 and whatever is inside is ruined."
	show_popup(card.room_name, text, choices, card_art(card) if card.art else ICONS[RoomCard.Type.LOCKED_CHEST], "chest", card)


func _on_open_chest() -> void:
	var card: RoomCard = dungeon.rooms[dungeon.position].card
	var loot := dungeon.open_chest(dungeon.position)
	if loot.is_empty():
		return
	refresh()
	if guide_label:
		show_guide_tip("opened", dungeon.position)
	var text := "Inside: %s" % loot
	if dungeon.guided and dungeon.guide_goal_met():
		text += "\n" + guide_goal_text()
	# The chest rattles, then bursts open (see play_picture).
	show_popup("Opened!", text, [["Nice", close_popup]], ICONS[RoomCard.Type.LOCKED_CHEST], "unlock")
	popup_loot_texture = loot_picture(card)


func _on_break_chest() -> void:
	var card: RoomCard = dungeon.rooms[dungeon.position].card
	var outcome := dungeon.break_chest(dungeon.position)
	refresh()
	if outcome.worked:
		show_popup("Smashed open!", "Inside: %s" % outcome.text, [["Nice", close_popup]], ICONS[RoomCard.Type.LOCKED_CHEST], "unlock")
		popup_loot_texture = loot_picture(card)
	else:
		show_popup("CRASH!", outcome.text, [["Oops", close_popup]], card_art(card), "help")


# A campfire: the way home, and (except where you came in) the way deeper.
func show_campfire() -> void:
	if dungeon.guided:
		show_guided_campfire()
		return
	var text := "Return to Town with what you found (%s)." % dungeon.loot_text()
	var choices := [["Return to Town", _on_leave]]
	if dungeon.can_go_deeper():
		text += "\nOr GO DEEPER: every card goes back in the deck and a fresh board is dealt, one floor down (Floor %d). You start here, and this fire goes out: you'll have to find the next campfire to get home!" % (dungeon.floor_number + 1)
		choices.append(["Go Deeper", _on_go_deeper])
	choices.append(["Not now", close_popup])
	show_popup("Campfire", text, choices, ICONS[RoomCard.Type.CAMPFIRE], "pop")


func _on_go_deeper() -> void:
	close_popup()
	busy = true
	# Every card on the board flips back over and is swept up...
	var tween := create_tween().set_parallel()
	for square: Vector2i in squares:
		tween.tween_property(squares[square], "scale", Vector2(0.0, 0.0), 0.25).set_delay(randf_range(0.0, 0.2))
	await tween.finished
	dungeon.go_deeper()
	refresh()
	# ...and the new board is dealt, card by card.
	tween = create_tween().set_parallel()
	var i := 0
	for square: Vector2i in squares:
		tween.tween_property(squares[square], "scale", Vector2.ONE, 0.2).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	await tween.finished
	busy = false
	info_label.text = "Floor %d! A new board. Find the campfire to get home." % dungeon.floor_number
	if dungeon.boss_here():
		info_label.text += " The %s is on this board!" % dungeon.boss_card().room_name


# Drink the flask between fights: heal your run HP.
func _on_flask_pressed() -> void:
	if not dungeon.can_sip_on_map():
		return
	var max_hp := GameState.player_max_hp()
	var hp_before := GameState.run_hp if GameState.run_hp > 0 else max_hp
	var sip := dungeon.sip_flask()
	GameState.run_hp = mini(hp_before + sip.heal, max_hp)
	refresh()  # The flask button shows the charge is used straight away...
	await roll_flask_die(dungeon.flask_stats[Flask.HEAL_DIE], sip.roll, sip.heal)  # ...then the die tumbles.
	var text := "You drink from your %s: d%d rolled %d, heal %d (HP %d/%d)." % [dungeon.flask.flask_name,
		dungeon.flask_stats[Flask.HEAL_DIE], sip.roll, GameState.run_hp - hp_before, GameState.run_hp, max_hp]
	if sip.kept:
		text += " Lucky, the flask is still full!"
	dungeon.add_log(text)
	refresh()
	info_label.text = text  # After refresh(), which sets its own hint.


# The flask's die tumbles in the middle of the screen and lands on its roll,
# then "+3 HP" floats up. (Like the dice tray in battle, just on its own.)
func roll_flask_die(sides: int, value: int, heal: int) -> void:
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(holder)
	var die := DieView.new(110)
	die.sides = sides
	die.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(die)
	var label := Label.new()
	label.text = "+%d HP" % heal
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate.a = 0
	holder.add_child(label)
	holder.reset_size()
	holder.position = (get_viewport_rect().size - holder.size) / 2
	# Tumble: random faces, tilted, then land with a bounce.
	for step in 10:
		die.show_value(randi_range(1, sides))
		die.rotation = randf_range(-0.7, 0.7)
		await get_tree().create_timer(0.05).timeout
	die.rotation = 0.0
	die.show_value(value, value == sides)
	die.pivot_offset = die.size / 2
	die.scale = Vector2.ONE * 1.3
	var tween := create_tween()
	tween.tween_property(die, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.tween_interval(0.8)
	tween.tween_property(holder, "modulate:a", 0.0, 0.4)
	tween.tween_callback(holder.queue_free)
	await tween.finished


func _on_leave() -> void:
	if dungeon.guided:
		GameState.reach_milestone(GameState.FIRST_TRIP)  # The first trip is done: next time, a shuffled deck.
	dungeon.leave()
	dungeon.claim_loot()
	get_tree().change_scene_to_file(TOWN_SCENE)


# --- The popup ----------------------------------------------------------------

# choices: a list of [button text, function to call], or [text, function,
# why it's blocked] to grey a button out (with the reason as its tooltip).
# card: the map card it's about, so the popup shows its tile (Safe/Unsafe/Explore).
func show_popup(heading: String, text: String, choices: Array, picture: Texture2D = null, animation := "", card: RoomCard = null) -> void:
	play_picture(picture, animation)
	popup_badge.visible = card != null
	if card:
		popup_badge.text = card.tile_name().to_upper()
		popup_badge.add_theme_color_override("font_color", RoomCard.TILE_COLORS[card.tile])
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
#   "help"   a chest that keeps wiggling, with "Help!" floating up out of it
#   "jump"   leaps up out of the picture's box and lands with a sparkle
#   "flip"   turns over like a card (for a map card's own picture)

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
	# The tile badge sits just under the title.
	popup_badge = Label.new()
	popup_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_badge.add_theme_font_size_override("font_size", 14)
	popup_badge.visible = false
	var box := popup_title.get_parent()
	box.add_child(popup_badge)
	box.move_child(popup_badge, popup_title.get_index() + 1)


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
		"help":
			# Wiggle, pause, wiggle... forever (until the popup closes:
			# close_popup() kills the tween). Each wiggle lets out a "Help!".
			popup_tween.set_loops()
			popup_tween.tween_callback(_shout_help)
			for i in 4:
				popup_tween.tween_property(popup_picture, "rotation", 0.15, 0.05)
				popup_tween.tween_property(popup_picture, "rotation", -0.15, 0.05)
			popup_tween.tween_property(popup_picture, "rotation", 0.0, 0.05)
			popup_tween.tween_interval(0.9)
		"jump":
			var rest_y := popup_picture.position.y
			popup_picture.scale = Vector2(1.2, 0.6)  # Squashed, ready to spring.
			popup_tween.tween_property(popup_picture, "scale", Vector2(0.85, 1.2), 0.12)
			popup_tween.parallel().tween_property(popup_picture, "position:y", rest_y - 50, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			popup_tween.tween_property(popup_picture, "position:y", rest_y, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			popup_tween.tween_callback(func() -> void: popup_sparkles.restart())
			popup_tween.tween_property(popup_picture, "scale", Vector2(1.15, 0.85), 0.08)
			popup_tween.tween_property(popup_picture, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
		"flip":
			popup_picture.scale = Vector2(0.0, 1.0)  # Edge on...
			popup_tween.tween_property(popup_picture, "scale:x", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_:  # "pop"
			popup_picture.scale = Vector2.ZERO
			popup_tween.tween_property(popup_picture, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			popup_tween.tween_callback(func() -> void: popup_sparkles.restart())


# A little "Help!" floats up out of the wiggling chest and fades.
func _shout_help() -> void:
	var shout := Label.new()
	shout.text = "Help!"
	shout.add_theme_font_size_override("font_size", 20)
	shout.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	shout.add_theme_color_override("font_outline_color", Color.BLACK)
	shout.add_theme_constant_override("outline_size", 5)
	shout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Alternate sides, so it looks like it's coming from inside the chest.
	var side := 1.0 if randf() < 0.5 else -1.0
	shout.position = popup_picture.position + Vector2(PICTURE_SIZE.x / 2 + side * 46 - 24, 40)
	popup_holder.add_child(shout)
	var tween := shout.create_tween()
	tween.tween_property(shout, "position:y", shout.position.y - 40, 1.0).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(shout, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tween.tween_callback(shout.queue_free)


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
	sack_row = HBoxContainer.new()
	sack_row.add_theme_constant_override("separation", 6)
	# No Save Sack until the Tailor sews one: then the title and slots show.
	if GameState.sack_open():
		nodes.append(sack_title)
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
	enchant_button.visible = GameState.enchants_open()  # Enchants come with the Enchanter.
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
		var pack_chip := make_chip("x%d" % dungeon.found_packs, {"kind": "pack"}, "")
		pack_chip.icon = PACK_ICON  # A Small Farm Booster Pack.
		pack_chip.add_theme_constant_override("icon_max_width", 22)
		pack_chip.tooltip_text = "%d %s. " % [dungeon.found_packs, DungeonRun.PACK_NAME] + pack_chip.tooltip_text
		found_row.add_child(pack_chip)
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
	if not GameState.sack_open():  # No Save Sack yet: just something you found.
		chip.tooltip_text = "Bring it home to keep it."
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		return chip
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
