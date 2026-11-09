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
const TORCH_ICON := preload("res://art/map_cards/torch.svg")
const TOOL_ICONS := {
	DungeonRun.TORCH: TORCH_ICON,
	DungeonRun.CROWBAR: preload("res://art/map_cards/crowbar.svg"),
	DungeonRun.BOMB: preload("res://art/map_cards/bomb.svg"),
}

# Each map card is a WIDE card (Dusty's playtest: the old small squares were
# hard to read): its picture on top, its name under it, and a row of "?" for
# the things you can scavenge there.
const CARD_SIZE := Vector2(148, 112)
const ART_RECT := Rect2(6, 6, 136, 58)  # Where the picture sits on the card.
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
const PLAYER_ICON := preload("res://art/rooms/player.svg")
const GATE_ICON_PATH := "res://art/map_cards/gate.svg"  # load()ed when drawn (a new picture: Godot imports it on first open)
const GOLD_ICON := preload("res://icons/gold.svg")
const CARD_ICON := preload("res://icons/draw.svg")
const MAP_ICON := preload("res://art/map/world_map.svg")

# Square colours.
# VISITED or NOT? Face-down cards (not visited yet) are DARK wood. Face-up
# cards (you've been there) are LIGHT parchment. Torchlit (scouted) cards stay
# dark: you've only peeked at them, you haven't been there.
const BACK_COLOR := Color(0.13, 0.1, 0.07, 0.97)  # A face-down card.
const FACE_COLOR := Color(0.86, 0.79, 0.62, 0.98)  # A face-up card: parchment.
const FACE_DANGER_COLOR := Color(0.92, 0.6, 0.53, 0.98)  # A fight you haven't won yet.
const FACE_CAMPFIRE_COLOR := Color(1.0, 0.74, 0.4, 0.98)
const FACE_DONE_COLOR := Color(0.62, 0.59, 0.52, 0.98)  # Used up (looted, picked clean...).
const GROUND_COLOR := Color(0.12, 0.11, 0.1, 0.9)  # A square with no card (the deck ran out).
const INK := Color(0.2, 0.13, 0.06)  # Dark writing on a face-up card.
const SCOUTED_TINT := Color(0.62, 0.68, 0.85, 0.55)  # A torchlit picture: ghostly blue.
const HOVER_BORDER := Color(1.0, 0.85, 0.35)
const HERE_BORDER := Color(0.55, 0.9, 1.0)
const USED_TINT := Color(1, 1, 1, 0.45)  # The picture on a card you've used up.

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
var new_find_square := Vector2i(-1, -1)  # A card whose "?" just turned into an icon (it pops in).
var new_find_item := ""
var scouting := false  # The torch is out: the next face-down card you click gets lit up.
var torch_button: Button
var tool_mode := ""  # A tool you clicked (Crowbar, Bomb): the next card you click gets it.
var tool_row: HBoxContainer  # One button per tool you carry (drag it onto a card, or click).
var journal_button: Button
var journal_list: ColorRect  # The Journal, while it's open.
# The Save Sack, Found and enchant/potion rows in the side panel (built in code).
var sack_row: HFlowContainer
var found_row: HFlowContainer
var backpack_title: Label
var backpack_row: HFlowContainer  # One button per backpack slot.
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
	# Dark card = not visited yet, light card = you've been there.
	for look: Array in [[BACK_COLOR, "Not visited", "Face down: you haven't been there yet. (Torchlit cards stay dark too, with a SCOUTED tag.)"],
			[FACE_COLOR, "Visited", "Face up: you've been there."]]:
		var swatch := ColorRect.new()
		swatch.color = look[0]
		swatch.custom_minimum_size = Vector2(20, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		var look_label := Label.new()
		look_label.text = look[1]
		look_label.tooltip_text = look[2]
		look_label.mouse_filter = Control.MOUSE_FILTER_PASS
		look_label.add_theme_font_size_override("font_size", 14)
		legend.add_child(look_label)
	deck_button = Button.new()
	deck_button.custom_minimum_size = Vector2(130, 34)
	deck_button.add_theme_font_size_override("font_size", 15)
	deck_button.tooltip_text = "Every card in this place's map deck, and how many you haven't seen yet."
	deck_button.pressed.connect(show_deck_list)
	legend.add_child(deck_button)
	journal_button = Button.new()
	journal_button.custom_minimum_size = Vector2(110, 34)
	journal_button.add_theme_font_size_override("font_size", 15)
	journal_button.tooltip_text = "Every tool trick you've found: what a crowbar, a bomb or a torch does to each card."
	journal_button.pressed.connect(show_journal)
	journal_button.visible = not dungeon.guided
	legend.add_child(journal_button)
	add_child(legend)


func make_square(square: Vector2i) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	button.pivot_offset = CARD_SIZE / 2  # Flips turn around the middle.
	button.pressed.connect(_on_square_pressed.bind(square))
	button.mouse_entered.connect(_on_square_hovered.bind(square))
	button.mouse_exited.connect(func() -> void: info_label.text = default_info())
	# Everything inside ignores the mouse, so clicks go through to the button.
	# The BACK: the compass on a face-down card, filling the whole card.
	var back := TextureRect.new()
	back.name = "Back"
	back.texture = CARD_BACK
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.offset_top = 8
	back.offset_bottom = -8
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(back)
	# The FACE: a window at the top with the card's picture in it...
	var window := Panel.new()
	window.name = "Window"
	window.position = ART_RECT.position
	window.size = ART_RECT.size
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(window)
	var art := TextureRect.new()
	art.name = "Art"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_top = 3
	art.offset_bottom = -3
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(art)
	# ...its name under the picture...
	var label := Label.new()
	label.name = "Name"
	label.position = Vector2(4, ART_RECT.end.y + 1)
	label.size = Vector2(CARD_SIZE.x - 8, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 15)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	# ...and the FINDS row along the bottom: one "?" per thing you can
	# scavenge here, or that thing's icon once you've found it (draw_finds()).
	var finds := HBoxContainer.new()
	finds.name = "Finds"
	finds.position = Vector2(6, CARD_SIZE.y - 25)
	finds.size = Vector2(CARD_SIZE.x - 12, 20)
	finds.alignment = BoxContainer.ALIGNMENT_CENTER
	finds.add_theme_constant_override("separation", 5)
	finds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(finds)
	# The player's marker, in the top-left corner of the card you're on.
	var marker := TextureRect.new()
	marker.name = "Player"
	marker.texture = PLAYER_ICON
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.size = Vector2(34, 34)
	marker.position = Vector2(2, 2)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(marker)
	# SCOUTED tag: your torch showed this card, but you haven't been there.
	var tag := Label.new()
	tag.name = "Scouted"
	tag.text = "SCOUTED"
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(1, 0.8, 0.45))
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 4)
	tag.position = Vector2(8, 6)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(tag)
	# TOOL TRICKS badge, top right: how many this card has, and how many you've
	# found ("1/2"). Which ones? Try your tools (the Journal remembers).
	var badge := PanelContainer.new()
	badge.name = "Tricks"
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	badge_box.border_color = Color(0.85, 0.68, 0.3)
	badge_box.set_border_width_all(1)
	badge_box.set_corner_radius_all(6)
	badge_box.content_margin_left = 3
	badge_box.content_margin_right = 4
	badge.add_theme_stylebox_override("panel", badge_box)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_top = 4
	badge.offset_right = -4
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_row := HBoxContainer.new()
	badge_row.name = "Row"
	badge_row.add_theme_constant_override("separation", 2)
	badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_row)
	var badge_icon := TextureRect.new()
	badge_icon.texture = TOOL_ICONS[DungeonRun.CROWBAR]
	badge_icon.custom_minimum_size = Vector2(16, 16)
	badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_row.add_child(badge_icon)
	var badge_label := Label.new()
	badge_label.name = "Count"
	badge_label.add_theme_font_size_override("font_size", 12)
	badge_label.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_row.add_child(badge_label)
	button.add_child(badge)
	# Drop a tool (dragged from the tool buttons) on the square to use it there.
	button.set_drag_forwarding(Callable(), _can_drop_tool.bind(square), _drop_tool.bind(square))
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
	lines.append("[color=#ff8080]HP %d / %d[/color]     [color=#ffd75a]Keys: %d[/color]     [color=#ffb060]Torches: %d[/color]" % [
		hp, GameState.player_max_hp(), dungeon.keys, dungeon.torches])
	# The DANGER METER: how much, what it does now, and when it gets worse.
	var danger_color := "#ffffff" if dungeon.danger() == 0 else "#ff9050"
	var next := "Danger card" + (", +%d Str" % (dungeon.enemy_strength() + 1) if dungeon.next_danger_adds_strength() else "")
	lines.append("[color=%s]Danger %d[/color]  ·  enemies +%d Str  ·  [color=#ffb080]%d more → %s[/color]" % [
		danger_color, dungeon.danger(), dungeon.enemy_strength(), dungeon.danger_to_next(), next])
	var hunting := dungeon.hunting_text()
	if not hunting.is_empty():
		lines.append("[color=#a8e0ff]Hunting: %s[/color]" % hunting)
	if dungeon.boss_here():
		lines.append("[color=#ff6060]The %s is somewhere on this board![/color]" % dungeon.boss_card().room_name)
	if dungeon.roamer_here():
		lines.append("[color=#ff9a60]A %s roams this board! It moves every step you take.[/color]" % dungeon.roamer_card().room_name)
	stats_label.text = "\n".join(lines)
	stats_label.tooltip_text = "\n".join([
		"HP: carries over from fight to fight.",
		"Keys: fights drop a small key %d%% of the time. A key opens one locked chest or shed." % DungeonRun.KEY_CHANCE,
		"Danger: +1 for every Unsafe card you find, and for some failed choices. Every %d Danger shuffles a bad Danger card into the map deck (it can swap onto the board too), and every %d gives every enemy +1 Strength. It lasts the whole trip." % [dungeon.danger_per_card(), dungeon.danger_per_strength()],
		"Backpack: %d slots, each holds up to %d of one thing (materials and torches). Gold, cards, packs and keys don't take space. The Tailor sews a bigger one." % [dungeon.backpack_slots(), DungeonRun.BACKPACK_STACK],
		"Torches: light up any face-down card to see it first. Each time, a d4 burnout roll: %s, then it always burns out." % torch_targets_text(),
		"Tools: drag a crowbar, bomb or torch onto a face-up card next to you. The corner badge says how many tool tricks a card has; the Journal remembers the ones you find.",
		"Scavenge: stand on a wall, field, hay bale... and click it. Free the first time, then push your luck.",
		"Hunting: what your quests want you to bring home (the Bank counts too).",
		"Found: only yours once you get home (Return to Town at a campfire, or beat the Boss). Die and it's lost.",
	])
	deck_button.text = "Map Deck (%d)" % (dungeon.deck.size() + dungeon.face_down_count())
	journal_button.text = "Journal (%d)" % GameState.journal.size()
	refresh_torch_button()
	info_label.text = default_info()
	log_label.text = "\n".join(dungeon.history.slice(-14))
	refresh_sack()
	if guide_label:
		refresh_goals()
		guide_torch_nudge.call_deferred()  # Once any popup from this click is up (it waits for those).
	if not dungeon.left_over.is_empty() or dungeon.last_danger_card != null or not dungeon.last_roamer_news.is_empty():
		show_news.call_deferred()


# Things to tell you once nothing else is going on: loot that didn't fit in
# the backpack, then a new Danger card.
func show_news() -> void:
	if popup.visible or busy or picker or deck_list or journal_list or not dungeon.result.is_empty():
		return
	if not dungeon.left_over.is_empty():
		show_backpack_full()
	elif dungeon.last_danger_card != null:
		var card := dungeon.last_danger_card
		dungeon.last_danger_card = null
		show_popup("Danger card!", danger_news_text(card), [["Uh oh", close_popup]], card_art(card), "flip", card)
	elif not dungeon.last_roamer_news.is_empty():
		# The roamer is right next to you (still face down). Not a popup: just a warning.
		info_label.text = dungeon.last_roamer_news + " The %s is on a face-down card next to you." % dungeon.roamer_card().room_name
		dungeon.last_roamer_news = ""


func danger_news_text(card: RoomCard) -> String:
	return "All that noise... Danger is %d, so a %s card was shuffled into the map deck. If a card was still face down on the board, it may already be out there.\n%s" % [
		dungeon.danger(), card.room_name, card.text]


# The picture on a card's face: its Art, or the old icon for its kind.
func card_art(card: RoomCard) -> Texture2D:
	return card.art if card.art else ICONS.get(card.type)


# How one card looks. Three looks, easy to tell apart at a glance:
#   FACE DOWN (not visited)  dark wood with a gold compass. The ones you can
#                            step onto right now glow with a gold border.
#   SCOUTED (torchlit)       still dark wood (you haven't been there!), with
#                            a ghostly picture, its name in grey and a
#                            "SCOUTED" tag.
#   FACE UP (visited)        light parchment, the picture in a window, the
#                            name in dark ink, and a border in its tile's
#                            colour. Used-up cards go grey.
func draw_square(square: Vector2i) -> void:
	var button: Button = squares[square]
	var back: TextureRect = button.get_node("Back")
	var window: Panel = button.get_node("Window")
	var art: TextureRect = button.get_node("Window/Art")
	var label: Label = button.get_node("Name")
	button.get_node("Player").visible = square == dungeon.position
	button.get_node("Scouted").visible = false
	var tricks := trick_counts(square)
	button.get_node("Tricks").visible = tricks.y > 0
	button.get_node("Tricks/Row/Count").text = "%d/%d" % [tricks.x, tricks.y]
	art.modulate = Color.WHITE
	label.text = ""
	button.tooltip_text = describe_square(square)  # Shown when you hover the square for a moment.
	var room: Dictionary = dungeon.rooms.get(square, {})
	var card: RoomCard = room.get("card")
	var reachable := reach.has(square)
	var face_up := not room.is_empty() and room.revealed
	var scouted := not face_up and not room.is_empty() and room.get("scouted", false) and card != null
	var color := FACE_COLOR
	var border := Color(0, 0, 0, 0.6)
	var ink := INK
	back.visible = not face_up and not scouted
	window.visible = face_up or scouted
	if scouted:
		color = BACK_COLOR
		art.texture = card_art(card)
		art.modulate = SCOUTED_TINT if reachable else SCOUTED_TINT.darkened(0.3)
		label.text = card.room_name
		ink = Color(0.7, 0.72, 0.8)
		border = RoomCard.TILE_COLORS[card.tile].darkened(0.45)
		button.get_node("Scouted").visible = true
		window.add_theme_stylebox_override("panel", window_box(Color(0.06, 0.05, 0.04, 0.9), border))
	elif not face_up:
		color = BACK_COLOR
		back.modulate = Color.WHITE if reachable else Color(0.5, 0.5, 0.5)
		border = Color(0.95, 0.75, 0.3) if reachable else Color(0.25, 0.2, 0.12)
	elif card == null:
		if room.get("start", false):
			# Floor 1: the Farm Gate you came in by. Deeper: your old campfire,
			# burnt out. Neither takes you home: find this floor's campfire!
			art.texture = load(GATE_ICON_PATH) if dungeon.floor_number == 1 else ICONS[RoomCard.Type.CAMPFIRE]
			label.text = "Farm Gate" if dungeon.floor_number == 1 else "Burnt Out"
			if dungeon.floor_number > 1:
				art.modulate = USED_TINT
			color = FACE_DONE_COLOR
		else:
			color = GROUND_COLOR
			window.visible = false
			label.text = "Bare ground"
			ink = Color(0.6, 0.58, 0.54)
	else:
		label.text = card.room_name
		art.texture = card_art(card)
		border = RoomCard.TILE_COLORS[card.tile].darkened(0.15)
		if card.type == RoomCard.Type.EVENT and room.get("event") != null and card.event_name.is_empty():
			label.text = room.event.event_name  # A Mystery, once you know what it is.
		if room.campfire:
			color = FACE_CAMPFIRE_COLOR
		elif card.is_fight() and not room.cleared:
			color = FACE_DANGER_COLOR
		elif room.done:
			color = FACE_DONE_COLOR
			art.modulate = USED_TINT  # Used up: faded out.
		if card.type == RoomCard.Type.LOCKED_CHEST and room.opened and not room.get("ruined", false) and card.art == null:
			art.texture = OPEN_CHEST_ICON
	if window.visible and not scouted:
		window.add_theme_stylebox_override("panel", window_box(color.darkened(0.12), border.darkened(0.2)))
	label.add_theme_color_override("font_color", ink)
	draw_finds(button.get_node("Finds"), square, card if (face_up or scouted) else null)
	var width := 4 if square == dungeon.position else (3 if reachable or face_up else 2)
	if square == dungeon.position:
		border = HERE_BORDER
	button.add_theme_stylebox_override("normal", make_box(color, border, width))
	button.add_theme_stylebox_override("hover", make_box(color.lightened(0.12), HOVER_BORDER if reachable else border, 4 if reachable else width))
	button.add_theme_stylebox_override("pressed", make_box(color.lightened(0.2), HOVER_BORDER, 4))
	button.add_theme_stylebox_override("disabled", make_box(color, border, width))
	# You can click a square you can walk to, and the square you're on (to use
	# its campfire or chest again).
	if scouting:
		# Torch out: cards you can light up, and face-up cards next to you (try the torch on them).
		button.disabled = not (dungeon.can_scout(square) or dungeon.can_use_tool(DungeonRun.TORCH, square))
		if not button.disabled:
			button.add_theme_stylebox_override("normal", make_box(color, HOVER_BORDER, 3))
	elif not tool_mode.is_empty():
		button.disabled = not dungeon.can_use_tool(tool_mode, square)  # A tool out: only cards you can use it on.
		if not button.disabled:
			button.add_theme_stylebox_override("normal", make_box(color, HOVER_BORDER, 3))
	else:
		button.disabled = not (reachable or (square == dungeon.position and has_action_here()))
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND


# The FINDS row: one chip per different thing this card can be scavenged for.
# A "?" until you've found it on this kind of card (ever, on any trip), then
# the thing's own icon. Once the spot is picked clean, the row fades.
func draw_finds(row: HBoxContainer, square: Vector2i, card: RoomCard) -> void:
	for old in row.get_children():
		row.remove_child(old)
		old.queue_free()
	if card == null or not card.can_scavenge():
		row.visible = false
		return
	row.visible = true
	var room: Dictionary = dungeon.rooms[square]
	var face_up: bool = room.revealed
	row.modulate.a = 1.0 if dungeon.can_scavenge(square) or not face_up else 0.4
	for item in card.scavenge_items():
		var chip: Control
		if GameState.knows_find(dungeon.area, card.room_name, item):
			var icon := TextureRect.new()
			icon.texture = item_icon(item)
			icon.custom_minimum_size = Vector2(18, 18)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			chip = icon
			if icon.texture == null:  # No picture for it: its first letter.
				chip = make_chip_letter(item.left(1), face_up)
		else:
			chip = make_chip_letter("?", face_up)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		# Just found it? The new icon pops in, big and gold, then settles.
		if square == new_find_square and item == new_find_item:
			chip.pivot_offset = Vector2(9, 9)
			chip.scale = Vector2(2.4, 2.4)
			chip.modulate = Color(2, 1.7, 0.6)
			var tween := chip.create_tween().set_parallel()
			tween.tween_property(chip, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(chip, "modulate", Color.WHITE, 0.8)
	if square == new_find_square:
		new_find_square = Vector2i(-1, -1)  # Only pop it once.


func make_chip_letter(text: String, on_face: bool) -> Label:
	var mark := Label.new()
	mark.text = text
	mark.custom_minimum_size = Vector2(18, 18)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 16)
	mark.add_theme_color_override("font_color", INK if on_face else Color(0.85, 0.85, 0.9))
	return mark


# The picture for a thing you can find: a material's icon, gold, a torch...
func item_icon(item: String) -> Texture2D:
	match item:
		"Gold": return GOLD_ICON
		"Card": return CARD_ICON
		"Pack": return PACK_ICON
		"Key": return KEY_ICON
		"Torch": return TORCH_ICON
		"Potion": return POTION_ICON
		"Enchant": return ENCHANT_ICON
		"Map": return MAP_ICON
	if TOOL_ICONS.has(item):
		return TOOL_ICONS[item]
	var info := GameState.find_material(item)
	return info.icon if info else null


# The picture window's frame on a face-up card.
func window_box(color: Color, border: Color) -> StyleBoxFlat:
	var key := "window %s %s" % [color.to_html(), border.to_html()]
	if _boxes.has(key):
		return _boxes[key]
	var box := StyleBoxFlat.new()
	_boxes[key] = box
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	return box


# The tooltip for a square: what it is and what you can do with it.
func describe_square(square: Vector2i) -> String:
	var room: Dictionary = dungeon.rooms.get(square, {})
	if scouting and dungeon.can_scout(square):
		return "Light it up with your torch to see what it is."
	if scouting and dungeon.can_use_tool(DungeonRun.TORCH, square):
		return "Try your torch on it (%s)." % trick_hint(square, DungeonRun.TORCH)
	if not tool_mode.is_empty() and dungeon.can_use_tool(tool_mode, square):
		return "Use your %s on it (%s)." % [tool_mode.to_lower(), trick_hint(square, tool_mode)]
	if not room.is_empty() and not room.revealed and room.get("scouted", false) and room.card:
		var scouted: RoomCard = room.card
		var scout_lines: Array[String] = ["Scouted: %s  (%s)" % [scouted.room_name, scouted.tile_name()]]
		if not scouted.text.is_empty():
			scout_lines.append(scouted.text)
		if scouted.is_fight():
			scout_lines.append("Stepping on it starts a fight, and Danger +1.")
		if scouted.can_scavenge():
			scout_lines.append("You can scavenge it. " + finds_text(scouted))
		scout_lines.append("Still face down: step on it to flip it.")
		return "\n".join(scout_lines)
	if room.is_empty() or not room.revealed:
		var distance: int = reach[square].steps if reach.has(square) else -1
		if distance > 0:
			return "A face-down card (%d step%s away).\nStep onto it to flip it over." % [distance, "s" if distance > 1 else ""]
		return "A face-down card.\nFlip a card next to it first."
	var card: RoomCard = room.card
	if card == null:
		if room.get("start", false):
			return "The Farm Gate, where you came in. It's not a way home: find the campfire hidden on the board to Return to Town." \
				if dungeon.floor_number == 1 else "Your campfire from the floor above, burnt out. Find this floor's campfire to get home!"
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
	elif card.type == RoomCard.Type.TREASURE and not room.done:
		var guards := dungeon.guards_standing(square)
		if guards > 0:
			lines.append("Guarded! Beat the %d %s next to it first." % [guards, card.guards + ("s" if guards > 1 else "")])
		elif square == dungeon.position:
			lines.append("Click it to take it.")
	lines.append_array(trick_lines(square))
	if card.vanish:
		lines.append("Vanish: once it's used, it's gone for the rest of this trip.")
	if not card.loot.is_empty() and not room.done:
		lines.append("Loot: one of " + ", ".join(Array(card.loot)))
	if card.can_scavenge():
		lines.append(finds_text(card))
	if dungeon.can_scavenge(square):
		lines.append("Scavenge here (stand on it and click it). Next try: %s." % scavenge_odds(square))
	elif card.can_scavenge() and room.get("scavenges", 0) > 0:
		lines.append("Scavenged: nothing more to find here.")
	return "\n".join(lines.filter(func(line: String) -> bool: return not line.is_empty()))


# "Finds here: Stone, Gold, and 1 thing you haven't found yet (?)."
func finds_text(card: RoomCard) -> String:
	var known: Array[String] = []
	var unknown := 0
	for item in card.scavenge_items():
		if GameState.knows_find(dungeon.area, card.room_name, item):
			known.append(item)
		else:
			unknown += 1
	var parts: Array[String] = []
	if not known.is_empty():
		parts.append(", ".join(known))
	if unknown > 0:
		parts.append("%d thing%s you haven't found yet (?)" % [unknown, "" if unknown == 1 else "s"])
	return "Finds here: %s." % " and ".join(parts)


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
	if scouting:
		return "Torch out! Click ANY face-down card to see what it is (it stays face down). Then the torch makes its burnout roll."
	return "Click a glowing face-down card to flip it, or a face-up card to walk back to it."


# Is there something to do on the square you're standing on?
func has_action_here() -> bool:
	var room: Dictionary = dungeon.rooms[dungeon.position]
	if room.campfire:
		return true
	var card: RoomCard = room.card
	if dungeon.can_scavenge(dungeon.position):
		return true
	if dungeon.can_take_treasure(dungeon.position):
		return true
	return card != null and card.type == RoomCard.Type.LOCKED_CHEST and not room.done


# --- Clicking ---------------------------------------------------------------

func _on_square_hovered(square: Vector2i) -> void:
	if scouting and not busy:
		if dungeon.can_use_tool(DungeonRun.TORCH, square):
			info_label.text = "Click it to try your torch on it (%s)." % trick_hint(square, DungeonRun.TORCH)
		else:
			info_label.text = "Click it to light it up." if dungeon.can_scout(square) else "Pick a face-down card to light up, or a face-up card next to you to try the torch on it (click the torch again to put it away)."
		return
	if not tool_mode.is_empty() and not busy:
		info_label.text = ("Click it to use your %s (%s)." % [tool_mode.to_lower(), trick_hint(square, tool_mode)]) \
			if dungeon.can_use_tool(tool_mode, square) else dungeon.why_not_tool(tool_mode, square) + "."
		return
	if not reach.has(square) or busy:
		return
	var distance: int = reach[square].steps
	var face_down := not dungeon.is_revealed(square)
	var text := "%d step%s to %s." % [distance, "s" if distance > 1 else "", "flip this card" if face_down else "walk there"]
	info_label.text = text


func _on_square_pressed(square: Vector2i) -> void:
	if popup.visible or picker or deck_list or busy:
		return
	if scouting:
		if dungeon.can_use_tool(DungeonRun.TORCH, square):
			scouting = false
			use_tool(DungeonRun.TORCH, square)
		else:
			scout_square(square)
		return
	if not tool_mode.is_empty():
		var tool_name := tool_mode
		tool_mode = ""
		use_tool(tool_name, square)
		return
	var what := ""
	if square == dungeon.position:
		if dungeon.rooms[square].campfire:
			what = "campfire"
		elif dungeon.can_scavenge(square):
			what = "scavenge"
		elif dungeon.can_take_treasure(square):
			dungeon.take_treasure(square)
			what = "treasure"
		else:
			what = "chest"
	else:
		what = dungeon.move_to(square)
	if what.is_empty():
		return
	if dungeon.just_flipped == square:
		await flip_square(square)  # The card turns over before anything happens.
	refresh()
	if guide_label:
		show_guide_tip(what, square)
		await guide_spotlight(what, square)  # The first time: point right at it.
	var room: Dictionary = dungeon.rooms[square]
	var card: RoomCard = room.card
	match what:
		"fight":
			var heading := "Boss!" if card.type == RoomCard.Type.BOSS else ("Mini Boss!" if card.type == RoomCard.Type.MINI_BOSS else card.room_name)
			var text := ("%s\n" % card.text if not card.text.is_empty() else "") + "Enemies: " + enemy_list(dungeon.fight_enemies)
			text += "\nUnsafe cards are always a fight. Danger is now %d." % dungeon.danger()
			if dungeon.last_danger_card != null:
				text += "\nDanger card! A %s was shuffled into the map deck." % dungeon.last_danger_card.room_name
				dungeon.last_danger_card = null
			show_popup(heading, text, [["Fight!", start_fight]], card_art(card), "flip", card)
		"chest":
			show_chest()
		"campfire":
			show_campfire()
		"event":
			show_event()
		"empty":
			info_label.text = "%s: %s" % [card.room_name, card.text if not card.text.is_empty() else "Nothing here."]
		"scavenge":
			show_scavenge()
		"guarded":
			var guards := dungeon.guards_standing(square)
			show_popup(card.room_name, ("%s\n" % card.text if not card.text.is_empty() else "") +
				"%d %s stand%s guard right next to it. Beat them first, then come back and take it. (Or try a tool on it...)" % [
				guards, card.guards + ("s" if guards > 1 else ""), "" if guards > 1 else "s"],
				[["OK", close_popup]], card_art(card), "pop", card)
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
	var tween := create_tween()
	tween.tween_property(button, "scale:x", 0.0, FLIP_TIME).set_ease(Tween.EASE_IN)
	await tween.finished
	reach = dungeon.reachable()
	draw_square(square)  # Now it shows its face...
	tween = create_tween()
	tween.tween_property(button, "scale:x", 1.0, FLIP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tween.finished  # ...and it's back to full width.
	busy = false


# --- Torches -------------------------------------------------------------------------
# Click Light Torch, then any face-down card: it lights up (you see its face,
# but it stays face down). Then the d4 burnout roll tumbles on screen.

func _on_torch_pressed() -> void:
	if busy or popup.visible or picker or deck_list or dungeon.torches <= 0 or not dungeon.result.is_empty():
		scouting = false
	else:
		scouting = not scouting
	tool_mode = ""
	refresh()


func refresh_torch_button() -> void:
	if torch_button == null:
		return
	torch_button.text = ("Put it away" if scouting else "Light Torch") + " (%d)" % dungeon.torches
	torch_button.set_pressed_no_signal(scouting)
	torch_button.disabled = dungeon.torches <= 0 or not dungeon.result.is_empty()
	if dungeon.torches > 0:
		torch_button.tooltip_text = "Light up any face-down card to see what it is before you step on it.\nAfter each card, the torch rolls a d4 to keep burning: %s. Next roll needs %d+." % [
			torch_targets_text(), dungeon.torch_need()]
	else:
		torch_button.tooltip_text = "No torches left. Hay bales, fields and sheds sometimes have one."


# "2+, then 3+, then 4+"
func torch_targets_text() -> String:
	var parts: Array[String] = []
	for need in DungeonRun.TORCH_TARGETS:
		if need <= DungeonRun.TORCH_DIE:
			parts.append("%d+" % need)
	return ", then ".join(parts)


func scout_square(square: Vector2i) -> void:
	if not dungeon.can_scout(square):
		return
	scouting = false
	var outcome := dungeon.scout(square)
	if outcome.is_empty():
		refresh()
		return
	await flip_square(square)  # It turns over to show its face (but stays face down on the board).
	busy = true
	refresh()
	var card: RoomCard = dungeon.rooms[square].card
	var kept: bool = outcome.kept
	await roll_die(DungeonRun.TORCH_DIE, outcome.roll, "Still burning!" if kept else "Burnt out!",
		Color(1, 0.75, 0.35) if kept else Color(0.75, 0.75, 0.75))
	busy = false
	refresh()
	var how := "still burning: click Light Torch again to use it." if kept \
		else "it burns out. %d torch%s left." % [dungeon.torches, "" if dungeon.torches == 1 else "es"]
	info_label.text = "Your torch shows: %s (%s). Burnout roll %d, needed %d+: %s" % [card.room_name, card.tile_name(),
		outcome.roll, outcome.need, how]
	if guide_label:
		show_guide_tip("torch", square)
	elif dungeon.can_swap_scouted(square):
		# Don't like it? Swap it for a new face-down card (noisy: Danger +1).
		show_popup(card.room_name, "Your torch shows %s (%s).\n%s\nLeave it there, or SWAP it: it goes back into the map deck and a new face-down card takes its place. Shuffling cards is noisy: Danger +%d." % [
			card.room_name, card.tile_name(), "Torch: " + how, DungeonRun.TORCH_SWAP_DANGER],
			[["Leave it", close_popup], ["Swap it (Danger +%d)" % DungeonRun.TORCH_SWAP_DANGER, _on_swap_scouted.bind(square)]],
			card_art(card), "flip", card)


func _on_swap_scouted(square: Vector2i) -> void:
	var old: RoomCard = dungeon.rooms[square].card
	close_popup()
	if dungeon.swap_scouted(square) == null:
		return
	await flip_square(square)  # It turns over and is a fresh face-down card.
	refresh()
	info_label.text = "The %s goes back into the map deck. A new face-down card takes its place. Danger is now %d." % [old.room_name, dungeon.danger()]


# --- Tools -------------------------------------------------------------------------
# Crowbars and bombs (and your torch) can be used on face-up cards next to
# you, or the one you're on. Drag a tool button onto a card, or click the
# button and then the card. Each card's corner badge says how many tool
# tricks it has ("1/2" = you've found 1 of its 2); which tool does what, you
# find out by trying. The rules are in dungeon_run.gd (use_tool()) and the
# tricks in data/dungeons/interactions.csv (see interaction.gd).

# Vector2i(found, total) tool tricks for a face-up card.
func trick_counts(square: Vector2i) -> Vector2i:
	if dungeon.guided or not dungeon.is_revealed(square):
		return Vector2i.ZERO
	var tricks := dungeon.tricks_on(square)
	var found := tricks.filter(func(t: Interaction) -> bool: return GameState.journal.has(t.key())).size()
	return Vector2i(found, tricks.size())


# "a trick you know: Open, 60%" / "you don't know what it does yet" / "nothing in your Journal"
func trick_hint(square: Vector2i, tool_name: String) -> String:
	var card: RoomCard = dungeon.rooms[square].card
	var trick := Interaction.find(card.room_name, tool_name)
	if trick and GameState.journal.has(trick.key()):
		return "you know this one: %d%%, %s" % [trick.chance, trick.effect if not trick.effect.is_empty() else "nothing"]
	var counts := trick_counts(square)
	if counts.y > counts.x:
		return "%d trick%s here you haven't found yet" % [counts.y - counts.x, "" if counts.y - counts.x == 1 else "s"]
	return "no tricks left to find here"


# The tooltip lines about a card's tool tricks.
func trick_lines(square: Vector2i) -> Array[String]:
	var lines: Array[String] = []
	var counts := trick_counts(square)
	if counts.y == 0:
		return lines
	lines.append("Tool tricks: %d (found %d). Drag a tool onto it to try one." % [counts.y, counts.x])
	for trick in dungeon.tricks_on(square):
		if GameState.journal.has(trick.key()):
			lines.append("  %s" % trick.summary())
	if counts.y > counts.x:
		lines.append("  ? %d more to find" % (counts.y - counts.x))
	return lines


# The tool buttons, next to the torch: one for each tool you carry.
func refresh_tools() -> void:
	for old in tool_row.get_children():
		old.queue_free()
	for tool_name: String in DungeonRun.TOOLS:
		var have := dungeon.carried(tool_name)
		if have <= 0:
			continue
		var button := Button.new()
		button.text = "%s (%d)" % [tool_name, have]
		button.icon = TOOL_ICONS[tool_name]
		button.expand_icon = true
		button.custom_minimum_size = Vector2(130, 40)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.set_pressed_no_signal(tool_mode == tool_name)
		button.disabled = not dungeon.result.is_empty()
		button.tooltip_text = "Drag it onto a face-up card next to you (or the one you're on), or click it and then the card.\nCards show how many tool tricks they have in the corner. Nothing happens? Then it isn't used up."
		button.pressed.connect(_on_tool_pressed.bind(tool_name))
		button.set_drag_forwarding(_drag_tool.bind(tool_name), Callable(), Callable())
		tool_row.add_child(button)


func _on_tool_pressed(tool_name: String) -> void:
	scouting = false
	if busy or popup.visible or picker or deck_list or journal_list or not dungeon.result.is_empty():
		tool_mode = ""
	else:
		tool_mode = "" if tool_mode == tool_name else tool_name
	refresh()
	if not tool_mode.is_empty():
		info_label.text = "%s out! Click a face-up card next to you (or the one you're on). Click the button again to put it away." % tool_mode


# Dragging a tool button (or the torch): the data says which tool.
func _drag_tool(_at: Vector2, tool_name: String) -> Variant:
	if dungeon.carried(tool_name) <= 0 or busy or popup.visible:
		return null
	var preview := TextureRect.new()
	preview.texture = TOOL_ICONS[tool_name]
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(48, 48)
	set_drag_preview(preview)
	return {"tool": tool_name}


func _can_drop_tool(_at: Vector2, data: Variant, square: Vector2i) -> bool:
	return data is Dictionary and data.has("tool") and not busy and not popup.visible \
		and dungeon.can_use_tool(data.tool, square)


func _drop_tool(_at: Vector2, data: Variant, square: Vector2i) -> void:
	scouting = false
	tool_mode = ""
	use_tool(data.tool, square)


# Use a tool on a card and show what happened.
func use_tool(tool_name: String, square: Vector2i) -> void:
	var before: RoomCard = dungeon.rooms[square].card
	var outcome := dungeon.use_tool(tool_name, square)
	refresh()
	if outcome.is_empty():
		return
	if not outcome.found:
		info_label.text = "You try your %s on the %s. %s" % [tool_name.to_lower(), before.room_name, outcome.text]
		return
	var card: RoomCard = dungeon.rooms[square].card  # (A Secret can change it.)
	var lines: Array[String] = []
	if outcome.new:
		lines.append("[New trick! It's in your Journal now.]")
	if not outcome.text.is_empty():
		lines.append(outcome.text)
	lines.append("Your %s is used up." % tool_name.to_lower() if outcome.used else "You keep your %s." % tool_name.to_lower())
	var heading := "%s: %s" % [tool_name, "it works!" if outcome.worked else "no luck..."]
	if outcome.fight:
		lines.append("Enemies: " + enemy_list(dungeon.fight_enemies))
		show_popup(heading, "\n".join(lines), [["Fight!", start_fight]], card_art(before), "flip", before)
	elif card != before:
		show_popup(heading, "\n".join(lines), [["Nice", close_popup]], card_art(card), "flip", card)
	else:
		show_popup(heading, "\n".join(lines), [["OK", close_popup]], TOOL_ICONS[tool_name], "pop")


# --- The Journal --------------------------------------------------------------------
# Every tool trick you've ever found (it's saved, so it lasts between trips).

func show_journal() -> void:
	if journal_list or deck_list or popup.visible or busy:
		return
	journal_list = ColorRect.new()
	journal_list.color = Color(0, 0, 0, 0.82)
	journal_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(journal_list)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.14, 0.1, 0.98)
	style.border_color = Color(0.85, 0.68, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(660, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	journal_list.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "Journal"
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var everything := Interaction.load_all()
	var about := Label.new()
	about.text = "Tool tricks you've found: %d of %d.\nTry a crowbar, a bomb or a torch on a card to find more. A card's corner badge says how many it has." % [
		GameState.journal.size(), everything.size()]
	about.add_theme_font_size_override("font_size", 15)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(about)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	for trick in everything:
		if GameState.journal.has(trick.key()):
			rows.add_child(make_journal_row(trick))
	if GameState.journal.is_empty():
		var none := make_small_label("Nothing yet. Drag a tool onto a card with a badge in its corner!", Color(1, 1, 1, 0.6))
		rows.add_child(none)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		journal_list.queue_free()
		journal_list = null)
	box.add_child(close)


# One trick: the tool's picture, "Locked Shed + Crowbar  60%", what it does.
func make_journal_row(trick: Interaction) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var picture := TextureRect.new()
	picture.texture = TOOL_ICONS.get(trick.tool)
	picture.custom_minimum_size = Vector2(32, 32)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	var top := make_small_label("%s + %s   %d%%" % [trick.card_name, trick.tool, trick.chance], Color(1, 0.9, 0.6))
	top.add_theme_font_size_override("font_size", 17)
	words.add_child(top)
	var worked := "Works: " + (trick.effect if not trick.effect.is_empty() else "nothing")
	var failed := "Fails: " + (trick.fail_effect if not trick.fail_effect.is_empty() else "nothing")
	var used: String = {Interaction.ALWAYS: "used up", Interaction.ON_FAIL: "used up if it fails", Interaction.NEVER: "never used up"}[trick.used_up]
	var detail := make_small_label("%s  ·  %s  ·  %s" % [worked, failed, used], Color(1, 1, 1, 0.75))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(detail)
	return row


# --- Scavenging ----------------------------------------------------------------------
# Push your luck: the first try is free, then each try needs a higher d6
# roll. Every success raises your Luck here (better loot). A fail ends it
# and raises Danger. The rules are in dungeon_run.gd (scavenge()).

# "free, always works, finds Common things" or "4+ on a d6 (50%), finds Uncommon things"
func scavenge_odds(square: Vector2i) -> String:
	var need := dungeon.scavenge_need(square)
	var finds := DungeonRun.luck_name(dungeon.next_scavenge_luck(square))
	if need <= 0:
		return "free, always works, finds %s things" % finds
	var chance := roundi((DungeonRun.SCAVENGE_DIE - need + 1) * 100.0 / DungeonRun.SCAVENGE_DIE)
	return "%d+ on a d6 (%d%%), finds %s things" % [need, chance, finds]


# The scavenge popup for the card you're standing on. found = what the last
# try dug up (shown at the top).
func show_scavenge(found := "") -> void:
	var square := dungeon.position
	var card: RoomCard = dungeon.rooms[square].card
	var lines: Array[String] = []
	if not found.is_empty():
		lines.append("You found %s!" % found)
	elif not card.text.is_empty():
		lines.append(card.text)
	if not dungeon.can_scavenge(square):
		lines.append("Nothing more to find here: it's picked clean.")
		show_popup(card.room_name, "\n".join(lines), [["OK", close_popup]], card_art(card), "pop", card)
		return
	lines.append("Luck here: %d.  Next try: %s." % [dungeon.scavenge_luck(square), scavenge_odds(square)])
	lines.append("Each success raises your Luck: Luck 2 finds Uncommon things, Luck 3 Rare ones. A fail ends scavenging here, and Danger +1.")
	var need := dungeon.scavenge_need(square)
	var label := "Scavenge (free)" if need <= 0 else "Push your luck (%d+)" % need
	show_popup(card.room_name, "\n".join(lines), [[label, _on_scavenge], ["Stop", close_popup]], card_art(card), "pop", card)


func _on_scavenge() -> void:
	if busy:
		return
	var card: RoomCard = dungeon.rooms[dungeon.position].card
	var outcome := dungeon.scavenge()
	if outcome.is_empty():
		close_popup()
		return
	popup.hide()
	var worked: bool = outcome.worked
	if outcome.need > 0:
		busy = true
		await roll_die(DungeonRun.SCAVENGE_DIE, outcome.roll, "Lucky!" if worked else "Noise!",
			Color(0.55, 0.95, 0.55) if worked else Color(1, 0.45, 0.4))
		busy = false
	if worked and outcome.get("new_find", false):
		new_find_square = dungeon.position  # Its "?" turns into this icon, with a pop.
		new_find_item = outcome.item
	refresh()
	if guide_label:
		show_guide_tip("scavenged", dungeon.position)
	if worked:
		var found_text := "%s (Luck %d: %s)" % [outcome.text, outcome.luck, DungeonRun.luck_name(outcome.luck)]
		if outcome.get("new_find", false):
			found_text += ".\nNEW FIND! The card now shows %s instead of a ?, so you'll know next time" % outcome.item
		show_scavenge(found_text)
	else:
		show_popup("Nothing but noise!", "You rolled %d (needed %d+). Something heard that... Danger +1, and the %s has nothing more for you." % [
			outcome.roll, outcome.need, card.room_name], [["OK", close_popup]], card_art(card), "pop", card)


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
# farm_cards.csv). Dusty's playtest asked for it to be flashier and clearer,
# so it's built like the battle training:
#   1. A big intro banner ("THE ABANDONED FARM"), then a SPOTLIGHT TOUR
#      (screen_guide.gd) of the board, your marker, the cards you can step
#      on, your stats, and the goal list.
#   2. A GOAL LIST in the side panel (FARM_GOALS). Each goal ticks off by
#      itself (worked out from the board, see farm_goal_done()), with a big
#      gold "GOAL COMPLETE!" and sparkles. The first goal not done yet is
#      lit up, with a hint under it saying how to do it.
#   3. The first time you meet something new (a wall to scavenge, a fight,
#      a shed, the campfire...), a spotlight points right at it before its
#      popup opens (guide_spotlight()).
# Its campfires only offer Return to Town, and only once you have
# everything the quests need.

# id, text, and the hint shown while it's the goal you're on.
const FARM_GOALS := [
	{"id": "flip", "text": "Flip a map card", "hint": "Click a card with a gold border, next to you. You step onto it and it flips over."},
	{"id": "Stone", "text": "Scavenge Stone", "hint": "Collapsed Walls (green border) always give Stone the first time. Step on one, then click it again to scavenge."},
	{"id": "key", "text": "Find a key", "hint": "Keys lie around in the mud. Keep flipping cards!"},
	{"id": "Hops", "text": "Open the sheds for Hops", "hint": "Locked Sheds (gold border) hold the Hops. Walk to one with your key and use it."},
	{"id": "torch", "text": "Peek at a card with your torch", "hint": "Click Light Torch (right), then ANY face-down card: you see what it is without stepping on it."},
	{"id": "campfire", "text": "Find the hidden campfire", "hint": "There's no way home where you came in. The campfire is somewhere on the board: keep exploring!"},
	{"id": "home", "text": "Return to Town", "hint": "Stand on the campfire and click it, then Return to Town."},
]
const GUIDE_GOLD := Color(1, 0.84, 0.35)

var goal_rows := {}  # Goal id -> its Label in the goal list.
var goals_done: Array[String] = []  # Goals already ticked (so each one celebrates once).


func build_guide() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.17, 0.08, 0.95)
	style.border_color = GUIDE_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var heading := make_small_label("YOUR FIRST TRIP: GOALS", GUIDE_GOLD)
	box.add_child(heading)
	for goal: Dictionary in FARM_GOALS:
		var row := make_small_label("", Color.WHITE)
		row.add_theme_font_size_override("font_size", 14)
		box.add_child(row)
		goal_rows[goal.id] = row
	guide_label = Label.new()  # The hint for the goal you're on.
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.add_theme_font_size_override("font_size", 14)
	guide_label.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	box.add_child(guide_label)
	var side := info_label.get_parent()
	side.add_child(panel)
	side.move_child(panel, info_label.get_index() + 1)
	# Goals already done (coming back from a fight) don't celebrate again.
	for goal: Dictionary in FARM_GOALS:
		if farm_goal_done(goal.id):
			goals_done.append(goal.id)
	refresh_goals()
	if dungeon.cards_flipped == 0:
		start_farm_tour.call_deferred()  # Once the board is laid out.


# Is this goal done? Worked out from the board itself, so nothing extra has
# to be saved (and it's still right after a fight, when this screen is
# built again).
func farm_goal_done(id: String) -> bool:
	var needs := dungeon.guide_needs()
	match id:
		"flip":
			return dungeon.cards_flipped > 0
		"key":
			return dungeon.keys > 0 or dungeon.rooms.values().any(func(room: Dictionary) -> bool: return room.opened)
		"torch":
			return dungeon.rooms.values().any(func(room: Dictionary) -> bool: return room.get("scouted", false))
		"campfire":
			return dungeon.rooms.values().any(func(room: Dictionary) -> bool: return room.campfire and room.revealed)
		"home":
			return false  # Done when you leave.
	# A material the quests need (Stone, Hops).
	if not needs.has(id):
		return true  # This quest isn't asking for it: nothing to do.
	return dungeon.material_total(id) + GameState.material_count(id) >= needs[id]


# Redraw the goal list: ✓ done, ▶ the one you're on (gold), ○ the rest.
# Material goals show how many you have ("3/5"). New ticks celebrate.
func refresh_goals() -> void:
	if guide_label == null:
		return
	var current := ""
	var needs := dungeon.guide_needs()
	for goal: Dictionary in FARM_GOALS:
		var done := farm_goal_done(goal.id)
		var row: Label = goal_rows[goal.id]
		var text: String = goal.text
		if needs.has(goal.id):
			var have := mini(dungeon.material_total(goal.id) + GameState.material_count(goal.id), needs[goal.id])
			text += "  %d/%d" % [have, needs[goal.id]]
		if done:
			row.text = "✓  " + text
			row.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		elif current.is_empty():
			current = goal.id
			row.text = "▶  " + text
			row.add_theme_color_override("font_color", GUIDE_GOLD)
		else:
			row.text = "○  " + text
			row.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		if done and not goals_done.has(goal.id):
			goals_done.append(goal.id)
			celebrate_goal(goal.text)
	for goal: Dictionary in FARM_GOALS:
		if goal.id == current:
			guide_label.text = goal.hint


# GOAL COMPLETE! A big gold word over the board, sparkles, then it floats
# away by itself. It doesn't stop you clicking (mouse_filter IGNORE).
func celebrate_goal(goal_text: String) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(box)
	var word := Label.new()
	word.text = "GOAL COMPLETE!"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_font_size_override("font_size", 52)
	word.add_theme_color_override("font_color", GUIDE_GOLD)
	word.add_theme_color_override("font_outline_color", Color(0.35, 0.18, 0))
	word.add_theme_constant_override("outline_size", 12)
	box.add_child(word)
	var line := Label.new()
	line.text = "✓ " + goal_text
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 24)
	line.add_theme_color_override("font_outline_color", Color.BLACK)
	line.add_theme_constant_override("outline_size", 6)
	box.add_child(line)
	box.reset_size()
	var middle := grid.get_global_rect().get_center()
	box.position = middle - box.size / 2
	box.pivot_offset = box.size / 2
	box.scale = Vector2(2, 2)
	box.modulate.a = 0
	var sparkles := CPUParticles2D.new()
	sparkles.position = middle
	sparkles.amount = 40
	sparkles.one_shot = true
	sparkles.explosiveness = 0.95
	sparkles.lifetime = 1.1
	sparkles.spread = 180
	sparkles.initial_velocity_min = 160
	sparkles.initial_velocity_max = 380
	sparkles.gravity = Vector2(0, 300)
	sparkles.scale_amount_min = 3
	sparkles.scale_amount_max = 6
	sparkles.color = GUIDE_GOLD
	layer.add_child(sparkles)
	layer.move_child(sparkles, 0)
	sparkles.emitting = true
	var tween := layer.create_tween()
	tween.set_parallel()
	tween.tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "modulate:a", 1.0, 0.2)
	tween.chain().tween_interval(1.3)
	tween.chain().tween_property(box, "position:y", box.position.y - 40, 0.5)
	tween.parallel().tween_property(box, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(layer.queue_free)


# The first thing you see: a big banner, then a spotlight tour.
func start_farm_tour() -> void:
	UnlockBanner.show_in(self, "THE ABANDONED FARM", "Your first trip", dungeon.area.icon,
		"The Innkeeper needs %s.\nFind it all, then find the campfire to get home with it. Watch out: if you fall, you lose what you found!" % dungeon.hunting_text(),
		"Let's explore! →", func() -> void:
			var reachable_card: Control = null
			for square: Vector2i in reach:
				if not dungeon.is_revealed(square):
					reachable_card = squares[square]
					break
			ScreenGuide.start(self, "farm trip tour", [
				{"target": grid, "text": "This is the farm, laid out as MAP CARDS. Dark cards are face down: places you haven't been yet."},
				{"target": squares[dungeon.position], "text": "You're HERE, at the Farm Gate. It's only the way in, not the way home: there's a campfire hidden somewhere on the board. Find it to get home!"},
				{"target": reachable_card, "text": "Cards with a GOLD border are right next to you. Click one to step onto it: it flips over and turns light. Light cards = places you've been."},
				{"target": stats_label, "text": "Your HP, keys and torches. And DANGER: red cards (Unsafe) are always a fight and raise it. The more Danger, the stronger the monsters."},
				{"target": guide_label.get_parent().get_parent(), "text": "Your GOALS. Each one ticks off by itself. The gold one is what to do next, with a hint under it."},
			]))


# The first time you meet something new, a spotlight points right at it
# before its popup opens. `await` it: it returns once you've read it (or
# straight away if there's nothing to show, or you've seen it before).
func guide_spotlight(what: String, square: Vector2i) -> void:
	if guide_label == null:
		return
	var card: RoomCard = dungeon.rooms[square].card if dungeon.rooms.has(square) else null
	var steps := []
	var guide_name := "farm trip " + what
	match what:
		"scavenge":
			steps = [
				{"target": squares[square], "text": "A COLLAPSED WALL: a Safe card (green border) you can SCAVENGE. Each ? along the bottom is something you can dig up here."},
				{"target": squares[square].get_node("Finds"), "text": "Find one, and its ? turns into a picture of it, for good. Next time you'll know what this kind of card gives!"},
			]
		"fight":
			steps = [
				{"target": squares[square], "text": "An UNSAFE card (red border): always a fight. Win, and it's safe to walk over."},
				{"target": stats_label, "text": "Finding it raised your DANGER. Every %d Danger makes every monster stronger, for the whole trip. Greedy explorers beware!" % dungeon.danger_per_strength()},
			]
		"treasure":
			if card and card.loot.has("Key"):
				guide_name = "farm trip key"
				steps = [{"target": stats_label, "text": "A small KEY! Your keys show here. Each key opens one Locked Shed or chest."}]
		"chest":
			steps = [{"target": squares[square], "text": "A LOCKED SHED: an Explore card (gold border). Explore cards give you a choice. Got a key? Open it! No key yet? Come back later: it waits for you."}]
		"campfire":
			steps = [{"target": squares[square], "text": "THE CAMPFIRE! Every board hides one. It's your way home: stand on it and click it to Return to Town with everything you found."}]
	if steps.is_empty():
		return
	var guide := ScreenGuide.start(self, guide_name, steps)
	if guide:
		await guide.finished


# The torch: once you've flipped a few cards, a spotlight on the torch button.
func guide_torch_nudge() -> void:
	if guide_label == null or popup.visible or busy or farm_goal_done("torch") or dungeon.torches <= 0:
		return
	if get_children().any(func(child: Node) -> bool: return child is ScreenGuide or child is UnlockBanner):
		return  # Another spotlight or banner is up: wait for the next click.
	if dungeon.cards_flipped < 3 or GameState.seen_guides.has("farm trip torch"):
		return
	ScreenGuide.start(self, "farm trip torch", [{"target": torch_button,
		"text": "Your TORCH! Click it, then click ANY face-down card on the board: you see what it is, without stepping on it. Then it rolls to keep burning (harder each time)."}])


# "Stone 3 / 5  Hops 1 / 3" for the guide, from what the quests need.
func guide_progress() -> String:
	return dungeon.hunting_text()


# Once you have it all: back to a campfire.
func guide_goal_text() -> String:
	return "You have the Stone and the Hops! Find the campfire hidden somewhere on the board and Return to Town."


# Called after anything happens on the first trip: tick the goals.
# (The old version wrote a tip here; now the hint under the goals does that.)
func show_guide_tip(_what: String, _square: Vector2i) -> void:
	refresh_goals()


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
	await roll_die(sides, value, "+%d HP" % heal, Color(0.5, 0.95, 0.55))


# Any die tumbling in the middle of the screen: it lands on `value`, then
# `text` fades in under it (the flask, a torch's burnout roll, scavenging).
func roll_die(sides: int, value: int, text: String, color: Color) -> void:
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(holder)
	var die := DieView.new(110)
	die.sides = sides
	die.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(die)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", color)
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
	# What the trip gave the place (Farm Exp, level ups) before heading home.
	show_popup("Home safe!", "You bring home %s.\n%s" % [dungeon.loot_text(), dungeon.area_exp_text()],
		[["To Town", func() -> void: get_tree().change_scene_to_file(TOWN_SCENE)]], ICONS[RoomCard.Type.CAMPFIRE], "pop")


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
	sack_row = HFlowContainer.new()  # Wraps onto a second line when the Tailor adds slots.
	sack_row.add_theme_constant_override("h_separation", 6)
	sack_row.add_theme_constant_override("v_separation", 4)
	# No Save Sack until the Tailor sews one: then the title and slots show.
	if GameState.sack_open():
		nodes.append(sack_title)
		nodes.append(sack_row)

	nodes.append(make_small_label("Found (lost if you die):", Color(0.85, 0.82, 0.76)))
	found_row = HFlowContainer.new()
	found_row.add_theme_constant_override("h_separation", 6)
	found_row.add_theme_constant_override("v_separation", 4)
	nodes.append(found_row)

	backpack_title = make_small_label("", Color(0.85, 0.82, 0.76))
	backpack_title.mouse_filter = Control.MOUSE_FILTER_PASS
	nodes.append(backpack_title)
	backpack_row = HFlowContainer.new()
	backpack_row.add_theme_constant_override("h_separation", 4)
	backpack_row.add_theme_constant_override("v_separation", 4)
	nodes.append(backpack_row)

	# HFlowContainer: like an HBox, but wraps onto a new line when it runs out
	# of room (the side panel got narrower when the map cards got bigger).
	var gear := HFlowContainer.new()
	gear.add_theme_constant_override("h_separation", 8)
	gear.add_theme_constant_override("v_separation", 6)
	torch_button = Button.new()
	torch_button.icon = TORCH_ICON
	torch_button.expand_icon = true
	torch_button.custom_minimum_size = Vector2(170, 40)
	torch_button.toggle_mode = true
	torch_button.focus_mode = Control.FOCUS_NONE
	torch_button.pressed.connect(_on_torch_pressed)
	torch_button.set_drag_forwarding(_drag_tool.bind(DungeonRun.TORCH), Callable(), Callable())
	gear.add_child(torch_button)
	tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 8)
	gear.add_child(tool_row)
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
	for old in sack_row.get_children() + found_row.get_children() + potion_row.get_children() + backpack_row.get_children():
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
	if found_row.get_child_count() == 0:
		found_row.add_child(make_small_label("nothing yet" if dungeon.found_materials.is_empty() else "only what's in your backpack", Color(1, 1, 1, 0.5)))
	refresh_backpack()
	refresh_tools()
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


# --- The Backpack ------------------------------------------------------------------
# One button per slot: materials and torches, up to 5 of one thing in each.
# Click a slot to drop it (or put it in the Save Sack). Drag a material
# slot into the sack, like the Found chips.

func refresh_backpack() -> void:
	var used := dungeon.backpack_used()
	var slots := dungeon.backpack_slots()
	backpack_title.text = "Backpack %d / %d slots (lost if you die):" % [used, slots]
	backpack_title.add_theme_color_override("font_color", Color(1, 0.6, 0.45) if used >= slots else Color(0.85, 0.82, 0.76))
	backpack_title.tooltip_text = "Materials and torches go in your backpack: up to %d of one thing in each slot.\nGold, cards, packs and keys don't take space. Click a slot to drop it.\nThe Tailor in town sews a bigger backpack." % DungeonRun.BACKPACK_STACK
	var contents := dungeon.backpack_contents()
	for i in maxi(slots, contents.size()):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(66, 34)
		slot.add_theme_font_size_override("font_size", 14)
		slot.focus_mode = Control.FOCUS_NONE
		if i >= contents.size():
			slot.text = "-"
			slot.modulate.a = 0.45
			slot.tooltip_text = "An empty backpack slot."
			backpack_row.add_child(slot)
			continue
		var item: Dictionary = contents[i]
		slot.text = "x%d" % item.amount
		slot.add_theme_constant_override("icon_max_width", 20)
		if TOOL_ICONS.has(item.name):
			slot.icon = TOOL_ICONS[item.name]
		else:
			var info := GameState.find_material(item.name)
			if info:
				slot.icon = info.icon
				slot.add_theme_color_override("font_color", info.color)
		slot.tooltip_text = "%d %s. Click to drop it%s." % [item.amount, item.name,
			" or put it in the Save Sack" if GameState.sack_open() and not TOOL_ICONS.has(item.name) else ""]
		slot.pressed.connect(show_backpack_slot.bind(item.name))
		if GameState.sack_open() and not TOOL_ICONS.has(item.name):
			var data := {"kind": "material", "name": item.name}
			slot.set_drag_forwarding(func(_at: Vector2) -> Variant:
				var preview := Label.new()
				preview.text = "%d %s" % [item.amount, item.name]
				preview.add_theme_font_size_override("font_size", 16)
				slot.set_drag_preview(preview)
				return data, Callable(), Callable())
		backpack_row.add_child(slot)


# What to do with one backpack slot.
func show_backpack_slot(item_name: String) -> void:
	if popup.visible or busy or picker or deck_list:
		return
	var have := dungeon.carried(item_name)
	var top := have % DungeonRun.BACKPACK_STACK if have % DungeonRun.BACKPACK_STACK != 0 else DungeonRun.BACKPACK_STACK
	var choices := [["Drop %d" % top, _on_drop_stack.bind(item_name)]]
	if GameState.sack_open() and not TOOL_ICONS.has(item_name):
		choices.append(["Into the Save Sack", _on_backpack_to_sack.bind(item_name)])
	choices.append(["Keep it", close_popup])
	show_popup(item_name, "You carry %d %s. Drop a slot's worth (%d) to make room?" % [have, item_name, top], choices, backpack_picture(item_name), "pop")


func _on_drop_stack(item_name: String) -> void:
	var dropped := dungeon.drop_stack(item_name)
	close_popup()
	info_label.text = "You drop %d %s." % [dropped, item_name]


func _on_backpack_to_sack(item_name: String) -> void:
	close_popup()
	_put_in_sack({"kind": "material", "name": item_name})
	refresh()


func backpack_picture(item_name: String) -> Texture2D:
	if TOOL_ICONS.has(item_name):
		return TOOL_ICONS[item_name]
	var info := GameState.find_material(item_name)
	return info.icon if info else null


# Something you found doesn't fit: drop a slot of something else to make
# room, or leave it behind.
func show_backpack_full() -> void:
	var item_name: String = dungeon.left_over.keys()[0]
	var amount: int = dungeon.left_over[item_name]
	var choices := [["Leave it", _on_leave_behind]]
	var names: Array = dungeon.found_materials.keys()
	for tool_name: String in DungeonRun.TOOLS:
		if dungeon.carried(tool_name) > 0:
			names.push_front(tool_name)
	if dungeon.torches > 0:
		names.push_front(DungeonRun.TORCH)
	for other: String in names:
		if other == item_name:
			continue
		var have := dungeon.carried(other)
		var top := have % DungeonRun.BACKPACK_STACK if have % DungeonRun.BACKPACK_STACK != 0 else DungeonRun.BACKPACK_STACK
		choices.append(["Drop %d %s" % [top, other], _on_make_room.bind(other)])
	var text := "%d %s won't fit: all %d slots are full (up to %d of one thing in each).\nDrop something to make room, or leave it here." % [
		amount, item_name, dungeon.backpack_slots(), DungeonRun.BACKPACK_STACK]
	show_popup("Backpack full!", text, choices, backpack_picture(item_name), "pop")
	if choices.size() > 3:  # Lots of choices: let the buttons shrink to fit.
		for button: Button in popup_buttons.get_children():
			if not button.is_queued_for_deletion():
				button.custom_minimum_size.x = 0


func _on_make_room(item_name: String) -> void:
	dungeon.drop_stack(item_name)
	dungeon.repack_left_over()
	close_popup()  # (If it still doesn't all fit, it asks again.)


func _on_leave_behind() -> void:
	dungeon.leave_behind()
	close_popup()


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
		card.setup(GameState.deck_card(i))  # Foil copies show shiny.
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
