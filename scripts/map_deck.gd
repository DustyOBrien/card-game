# map_deck.gd
#
# CHAPTER 1's MAP DECK screen (scenes/map_deck.tscn): before the Architect's
# first trip, Kale shows how the map works. It comes between the world map
# and the first trip (map.gd), and only that once: later trips use the
# Prepare Expedition screen, which has its own map card list.
#
#   1. A banner: every place is a DECK of map cards, dealt face down.
#   2. On the RIGHT, the place's DEFAULT cards: always in its deck. Each one
#      shows what you can scavenge there (a ? until you've found it) and any
#      EVENT it can have.
#   3. Kale's gift: your own map cards (2 Farmer's Sheds, 2 Dark Cellars, a
#      Stone Pile). They fly into YOUR MAP CARDS on the left, and are
#      unlocked for good (they're "Yours" rows in farm_cards.csv).
#   4. "Into the Abandoned Farm!" deals the board.
#
# Which cards are which comes from the sheet: the first trip's board is the
# Guide rows; a Guide card that ALSO has a Yours row is one of Kale's.
# Everything is built in code (like prepare.gd), so the .tscn is one Control.
extends Control

const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const INN_ICON := preload("res://art/town/inn.svg")
const DECK_ICON := preload("res://art/map_cards/card_back.svg")
const GOLD := Color(1, 0.84, 0.35)
const PARCHMENT := Color(0.86, 0.79, 0.62, 0.98)
const INK := Color(0.2, 0.13, 0.06)
const CARD_SIZE := Vector2(186, 112)

var area: Area
var defaults: Array[Dictionary] = []  # [{"card": RoomCard, "copies": 5}], the place's own cards.
var gifts: Array[Dictionary] = []  # Kale's cards, the same way.
var default_grid: GridContainer
var yours_box: HFlowContainer
var yours_panel: PanelContainer
var yours_empty: Label
var go_button: Button


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	area = GameState.current_area
	if area == null:
		area = GameState.load_areas()[0]
		GameState.current_area = area
	sort_cards()
	build_screen()
	if gifts_given():
		show_gift_cards(false)  # Back for another go: no need for the lesson again.
	else:
		show_deck_banner.call_deferred()


# Have you already got Kale's cards? (Coming back for another first trip.)
func gifts_given() -> bool:
	return not gifts.is_empty() and gifts.all(func(entry: Dictionary) -> bool:
		return GameState.unlocked_rooms.get(area.display_name, []).has(entry.card.room_name))


# Split the first trip's cards into the place's defaults and Kale's gifts,
# counting copies (the sheet has one row per card on the board).
func sort_cards() -> void:
	var yours_names: Array[String] = []
	for card in area.cards():
		if card.deck_part == RoomCard.DECK_YOURS:
			yours_names.append(card.room_name)
	for card in area.cards():
		if card.deck_part != RoomCard.DECK_GUIDE or card.type == RoomCard.Type.CAMPFIRE:
			continue
		var list: Array[Dictionary] = gifts if yours_names.has(card.room_name) else defaults
		var found := false
		for entry in list:
			if entry.card.room_name == card.room_name:
				entry.copies += 1
				found = true
		if not found:
			list.append({"card": card, "copies": 1})


func build_screen() -> void:
	var background := TextureRect.new()
	background.texture = area.background
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.45, 0.45, 0.45)
	add_child(background)

	var title := make_label("The %s: your Map Deck" % area.display_name, 32, GOLD)
	title.position = Vector2(0, 14)
	title.size = Vector2(1280, 44)
	add_child(title)

	# LEFT: what Kale says, and your own map cards.
	var left := VBoxContainer.new()
	left.position = Vector2(24, 70)
	left.size = Vector2(430, 620)
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	var kale := make_panel(Color(0.18, 0.14, 0.09, 0.95), GOLD)
	left.add_child(kale)
	var kale_row := HBoxContainer.new()
	kale_row.add_theme_constant_override("separation", 10)
	kale.add_child(kale_row)
	var portrait := TextureRect.new()
	portrait.texture = INN_ICON
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kale_row.add_child(portrait)
	var words := make_label("\"Every place out there is a DECK of map cards. Some cards are always in it. And you can bring your own!\"", 15, Color.WHITE)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kale_row.add_child(words)

	yours_panel = make_panel(Color(0.12, 0.16, 0.1, 0.92), Color(0.5, 0.75, 0.4))
	yours_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(yours_panel)
	var yours_layout := VBoxContainer.new()
	yours_layout.add_theme_constant_override("separation", 8)
	yours_panel.add_child(yours_layout)
	yours_layout.add_child(make_label("YOUR MAP CARDS", 18, Color(0.7, 1, 0.6)))
	yours_empty = make_label("None yet.", 15, Color(1, 1, 1, 0.5))
	yours_layout.add_child(yours_empty)
	yours_box = HFlowContainer.new()
	yours_box.add_theme_constant_override("h_separation", 8)
	yours_box.add_theme_constant_override("v_separation", 8)
	yours_layout.add_child(yours_box)

	go_button = Button.new()
	go_button.text = "Into the %s!" % area.display_name
	go_button.theme_type_variation = &"PrimaryButton"
	go_button.custom_minimum_size = Vector2(0, 52)
	go_button.disabled = true
	go_button.tooltip_text = "Kale has something for you first."
	go_button.pressed.connect(_on_go)
	left.add_child(go_button)
	var back := Button.new()
	back.text = "Back to the map"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	left.add_child(back)

	# RIGHT: the place's default cards.
	var right := make_panel(Color(0.12, 0.1, 0.07, 0.92), Color(0.55, 0.42, 0.22))
	right.position = Vector2(474, 70)
	right.size = Vector2(782, 620)
	add_child(right)
	var right_layout := VBoxContainer.new()
	right_layout.add_theme_constant_override("separation", 8)
	right.add_child(right_layout)
	var count := 0
	for entry in defaults:
		count += int(entry.copies)
	right_layout.add_child(make_label("ALWAYS IN THE %s's DECK  (%d cards)" % [area.display_name.to_upper(), count], 18, GOLD))
	default_grid = GridContainer.new()
	default_grid.columns = 4
	default_grid.add_theme_constant_override("h_separation", 8)
	default_grid.add_theme_constant_override("v_separation", 8)
	right_layout.add_child(default_grid)
	for entry in defaults:
		default_grid.add_child(make_card(entry.card, entry.copies))
	var note := make_label("? = something you can scavenge there (you'll see what once you find it).   Event = something that can happen when it flips over.", 13, Color(1, 1, 1, 0.6))
	right_layout.add_child(note)


# One map card: its picture, name and copies, what it has, and its event.
func make_card(card: RoomCard, copies: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PARCHMENT
	style.border_color = RoomCard.TILE_COLORS[card.tile]
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = CARD_SIZE
	panel.tooltip_text = card.text
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 2)
	panel.add_child(layout)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	layout.add_child(head)
	var picture := TextureRect.new()
	picture.texture = card.art
	picture.custom_minimum_size = Vector2(44, 44)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(picture)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var name_label := make_label(card.room_name + ("  ×%d" % copies if copies > 1 else ""), 15, INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(name_label)
	var tile := make_label(card.tile_name().to_upper(), 11, RoomCard.TILE_COLORS[card.tile].darkened(0.35))
	tile.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(tile)
	var items := card.scavenge_items()
	var finds: Array[String] = []
	for item in items:
		finds.append(item if GameState.knows_find(area, card.room_name, item) else "?")
	var finds_label := make_label("Finds: " + (" ".join(finds) if not finds.is_empty() else "nothing to scavenge"), 12, INK)
	finds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	layout.add_child(finds_label)
	if not card.event_name.is_empty():
		var chance := "" if card.event_chance >= 100 or card.type == RoomCard.Type.EVENT else " (%d%%)" % card.event_chance
		var event_label := make_label("Event: %s%s" % [card.event_name, chance], 12, Color(0.55, 0.3, 0.05))
		event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		layout.add_child(event_label)
	return panel


func make_panel(color: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# --- Kale's lesson ---------------------------------------------------------------

func show_deck_banner() -> void:
	UnlockBanner.show_in(self, "THE MAP DECK", "How exploring works", DECK_ICON,
		"Every place you explore is a DECK of MAP CARDS. When you head out, the cards are dealt FACE DOWN onto a board, and you flip them over as you walk.\n\nSome cards are always in a place's deck. And you can add your own!",
		"Show me", show_defaults_guide)


func show_defaults_guide() -> void:
	var guide := ScreenGuide.start(self, "map deck defaults", [
		{"target": default_grid, "text": "These cards are ALWAYS in the %s's deck. Each one shows what you can scavenge there (a ? until you find it), and any EVENT that can happen when it flips over. A barn might have an animal in it!" % area.display_name},
	])
	if guide:
		await guide.finished
	show_gift()


func show_gift() -> void:
	var shed: Texture2D = gifts[0].card.art if not gifts.is_empty() else DECK_ICON
	var lines: Array[String] = []
	for entry in gifts:
		lines.append("%d %s" % [entry.copies, entry.card.room_name])
	UnlockBanner.show_in(self, "KALE'S MAP CARDS!", "Your own cards for the deck", shed,
		"\"Here, take these: %s. The Hops are in those sheds, and you'll want a torch for the cellars. They're yours now: they go in the deck every time you head out to the farm.\"" % ", ".join(lines),
		"Add them to my deck", give_gift)


func give_gift() -> void:
	var rewards: Array[String] = []
	for entry in gifts:
		rewards.append("Room %s: %s" % [area.display_name, entry.card.room_name])
	GameState.give_rewards("; ".join(rewards))
	GameState.save_game()
	var delay := show_gift_cards(true)
	await get_tree().create_timer(delay + 0.4).timeout
	ScreenGuide.start(self, "map deck yours", [
		{"target": yours_panel, "text": "YOUR MAP CARDS. Every time you go to the farm, they're shuffled into its deck along with the default cards. Later you'll find more (and choose which ones to take)."},
		{"target": go_button, "text": "That's your whole deck: %d cards, plus a campfire hidden somewhere (your way home). Ready? Into the farm!" % (total_cards())},
	])


# Put Kale's cards in YOUR MAP CARDS (popping in one by one if `animate`).
# Returns how long the animation takes.
func show_gift_cards(animate: bool) -> float:
	yours_empty.visible = false
	var delay := 0.0
	for entry in gifts:
		var card := make_card(entry.card, entry.copies)
		card.custom_minimum_size = Vector2(196, 112)
		yours_box.add_child(card)
		if animate:
			card.modulate.a = 0.0
			card.scale = Vector2(0.4, 0.4)
			card.pivot_offset = card.custom_minimum_size / 2
			var tween := card.create_tween()
			tween.tween_interval(delay)
			tween.tween_property(card, "modulate:a", 1.0, 0.15)
			tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			delay += 0.2
	go_button.disabled = false
	go_button.tooltip_text = ""
	return delay


func total_cards() -> int:
	var total := 0
	for entry in defaults:
		total += int(entry.copies)
	for entry in gifts:
		total += int(entry.copies)
	return total


func _on_go() -> void:
	GameState.start_run()  # A fresh trip: the first trip's board is dealt.
	get_tree().change_scene_to_file(DUNGEON_SCENE)
