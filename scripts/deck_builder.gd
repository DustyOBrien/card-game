# deck_builder.gd
#
# The screen before the battle (scenes/deck_builder.tscn).
#
#   - Top: your class, and filter buttons to show one school at a time.
#   - Left: the card POOL, one of every card you own that your class can use.
#     (Cards you haven't found in booster packs yet don't show up.)
#     Click one to add it to your deck.
#   - Right: your DECK, with some stats (size, schools, costs, types).
#     Click a row to take one copy back out.
#   - "To the Map" goes to the map, where you pick an area to fight in. The
#     battle then reads the deck from GameState (see game_state.gd).
#
# Most of the screen is built in code, from small helper functions further
# down, because it changes every time you add or remove a card.
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")
const MAP_SCENE := "res://scenes/map.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"

const ALL_SCHOOLS := -1  # Filter value meaning "show every card".
const NEUTRAL := 0  # Filter value meaning "only cards with no school".
const GOLD := Color(1, 0.85, 0.3)
const BAR_TOO_SMALL := Color(0.85, 0.38, 0.32)  # Deck size bar below the minimum...
const BAR_READY := Color(0.42, 0.78, 0.47)  # ...and once it's big enough.
const COST_BAR_STEP := 8  # Pixels of bar per card in the cost curve.
const COST_BAR_MAX := 44  # Tallest a cost bar can get.

# The deck rules (deck size, copies per card) come from the class you picked.
# They live in classes/*.tres: click one in Godot and change them in the Inspector.
var rules: CharacterClass
var card_pool: Array[CardData] = []
var school_filter := ALL_SCHOOLS

@onready var emblem: TextureRect = %Emblem
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var filter_bar: HBoxContainer = %FilterBar
@onready var pool_grid: GridContainer = %PoolGrid
@onready var deck_count_label: Label = %DeckCountLabel
@onready var deck_size_bar: ProgressBar = %DeckSizeBar
@onready var school_chips: HFlowContainer = %SchoolChips
@onready var cost_curve: HBoxContainer = %CostCurve
@onready var type_count_label: Label = %TypeCountLabel
@onready var deck_list: VBoxContainer = %DeckList
@onready var rules_label: Label = %RulesLabel
@onready var clear_button: Button = %ClearButton
@onready var default_button: Button = %DefaultButton
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	default_button.pressed.connect(_on_default_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Picking a class already gave you its starter deck, and coming back from a
	# battle keeps your last deck. ensure_ready() only matters when you press F6
	# to run this scene on its own.
	GameState.ensure_ready()
	rules = GameState.character_class

	emblem.texture = rules.emblem
	title_label.text = rules.display_name
	subtitle_label.text = "Build your deck  ·  %d HP  ·  %d to %d cards" % [
		rules.max_hp, rules.min_deck_size, rules.max_deck_size]
	if rules.armor > 0:
		subtitle_label.text = subtitle_label.text.replace(" HP ", " HP  ·  %d Armor " % rules.armor)
	deck_size_bar.max_value = rules.max_deck_size

	card_pool = GameState.load_card_pool()  # Only the cards this class can use.
	build_filters()
	build_pool()
	refresh()


# ---------------------------------------------------------------------------
# Building the screen (once)
# ---------------------------------------------------------------------------

# One toggle button per school the class can use, plus "All" and "Neutral".
func build_filters() -> void:
	# A ButtonGroup makes toggle buttons work like radio buttons:
	# pressing one un-presses the others.
	var group := ButtonGroup.new()
	var options := [["All", ALL_SCHOOLS]]
	for school_name in CardData.School.keys():
		var school: int = CardData.School[school_name]
		if (rules.allowed_schools & school) != 0:
			options.append([school_name.capitalize(), school])
	if rules.allow_neutral:
		options.append(["Neutral", NEUTRAL])

	for option in options:
		var button := Button.new()
		button.text = option[0]
		button.toggle_mode = true  # Stays pressed in, like a tab.
		button.button_group = group
		button.button_pressed = option[1] == school_filter
		button.pressed.connect(_on_filter_pressed.bind(option[1]))
		filter_bar.add_child(button)


# Make one clickable card (plus a small badge under it) for every card in the
# pool. This only happens once; refresh() updates the badges later.
func build_pool() -> void:
	for card_data in card_pool:
		var cell := VBoxContainer.new()  # .new() makes a node in code instead of in a scene.
		cell.add_theme_constant_override("separation", 6)
		pool_grid.add_child(cell)

		var card: Card = CARD_SCENE.instantiate()
		cell.add_child(card)
		card.setup(card_data)
		card.clicked.connect(_on_pool_card_clicked)

		var badge := make_pill("", Color(0, 0, 0, 0.35))
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(badge)


# ---------------------------------------------------------------------------
# Updating the screen (after every change)
# ---------------------------------------------------------------------------

func refresh() -> void:
	var deck := GameState.deck
	refresh_pool(deck)
	refresh_stats(deck)
	refresh_deck_list(deck)

	# Only allow starting once the deck is big enough, and say why if it isn't.
	var missing := rules.min_deck_size - deck.size()
	start_button.disabled = missing > 0
	if missing > 0:
		rules_label.text = "Add %d more card%s to start" % [missing, "" if missing == 1 else "s"]
	else:
		rules_label.text = "Ready to fight!"


# The pool: badges ("1 / 2", "Locked"), greyed-out cards, and the school filter.
func refresh_pool(deck: Array[CardData]) -> void:
	# The cells were created in the same order as card_pool, so index i matches.
	for i in card_pool.size():
		var card_data := card_pool[i]
		var cell := pool_grid.get_child(i)
		var card: Card = cell.get_child(0)
		var badge: PanelContainer = cell.get_child(1)
		var badge_label: Label = badge.get_child(0)

		var count := deck.count(card_data)  # How many times this card is in the list.
		# The most you can use: what the class allows, but never more than you own.
		var max_count := mini(rules.max_copies_of(card_data), GameState.owned(card_data))
		badge_label.text = "In deck  %d / %d" % [count, max_count]
		# Gold text once you have at least one, so your picks stand out.
		badge_label.add_theme_color_override("font_color", GOLD if count > 0 else Color(1, 1, 1, 0.6))

		card.disabled = not can_add(card_data)
		# Fade out cards you can't add (maxed out or deck full).
		card.modulate.a = 0.5 if card.disabled else 1.0
		cell.visible = matches_filter(card_data)


# The stats at the top of the deck panel.
func refresh_stats(deck: Array[CardData]) -> void:
	deck_count_label.text = "%d / %d" % [deck.size(), rules.max_deck_size]

	# Size bar: red until you reach the minimum, then green.
	deck_size_bar.value = deck.size()
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_READY if deck.size() >= rules.min_deck_size else BAR_TOO_SMALL
	fill.set_corner_radius_all(5)
	deck_size_bar.add_theme_stylebox_override("fill", fill)

	# School chips, e.g. [STR 1/1] [AGI 0/1] [Neutral 7], in each school's colour.
	clear_children(school_chips)
	for school_name in CardData.School.keys():
		var school: int = CardData.School[school_name]
		if (rules.allowed_schools & school) == 0:
			continue  # This class can't use the school, so don't show it.
		var count := CharacterClass.count_school(deck, school)
		var text := "%s %d" % [school_name.substr(0, 3), count]
		if rules.max_cards_per_school > 0:
			text += " / %d" % rules.max_cards_per_school
		var chip_color: Color = CardData.SCHOOL_COLORS[school]
		if count == 0:
			chip_color = chip_color.darkened(0.5)  # Dim schools you haven't used.
		school_chips.add_child(make_pill(text, chip_color))
	if rules.allow_neutral:
		var neutral := deck.filter(func(card: CardData) -> bool: return card.is_neutral()).size()
		school_chips.add_child(make_pill("Neutral %d" % neutral, CardData.NEUTRAL_COLOR))

	# Cost curve: how many cards cost 0, 1, 2 and 3 or more. A good deck has
	# plenty of cheap cards, so this helps you spot a deck that's too expensive.
	clear_children(cost_curve)
	var buckets := [0, 0, 0, 0]
	for card in deck:
		buckets[mini(card.cost, 3)] += 1
	for cost in buckets.size():
		cost_curve.add_child(make_cost_bar("3+" if cost == 3 else str(cost), buckets[cost]))

	# Type counts.
	var lines: Array[String] = []
	for type_name in CardData.CardType.keys():
		var type: int = CardData.CardType[type_name]
		var count := deck.filter(func(card: CardData) -> bool: return card.has_type(type)).size()
		lines.append("%d %s" % [count, type_name.capitalize()])
	type_count_label.text = "\n".join(lines)


# The list of cards in your deck: one row per kind of card, cheapest first.
func refresh_deck_list(deck: Array[CardData]) -> void:
	clear_children(deck_list)
	var unique: Array[CardData] = []
	for card in deck:
		if not unique.has(card):
			unique.append(card)
	unique.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.cost != b.cost:
			return a.cost < b.cost
		return a.card_name < b.card_name)
	for card_data in unique:
		deck_list.add_child(make_deck_row(card_data, deck.count(card_data)))


# ---------------------------------------------------------------------------
# Small builders for the pieces above
# ---------------------------------------------------------------------------

# A rounded coloured box with a bit of text in it. Used for badges and chips.
func make_pill(text: String, color: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	pill.add_child(label)
	return pill


# One column of the cost curve: the count on top, a gold bar, the cost below.
func make_cost_bar(cost_text: String, count: int) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END  # Stack from the bottom up.
	column.add_theme_constant_override("separation", 2)

	var count_label := Label.new()
	count_label.text = str(count)
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(count_label)

	var bar := ColorRect.new()
	bar.color = GOLD if count > 0 else Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(22, maxi(mini(count * COST_BAR_STEP, COST_BAR_MAX), 2))
	column.add_child(bar)

	var cost_label := Label.new()
	cost_label.text = cost_text
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(cost_label)
	return column


# One row in the deck list: [cost] Name ............ x2
# The row is a Button (so it can be clicked), with labels laid on top of it.
func make_deck_row(card_data: CardData, count: int) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 34)
	row.tooltip_text = "%s\n%s\n\nClick to remove one" % [card_data.card_name, card_data.effect]
	row.add_theme_stylebox_override("normal", make_row_style(card_data.color, false))
	row.add_theme_stylebox_override("hover", make_row_style(card_data.color, true))
	row.add_theme_stylebox_override("pressed", make_row_style(card_data.color, true))
	# bind() fills in the function's argument ahead of time, so this row
	# calls _on_deck_line_clicked(card_data) when pressed.
	row.pressed.connect(_on_deck_line_clicked.bind(card_data))

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -10
	content.add_theme_constant_override("separation", 10)
	# MOUSE_FILTER_IGNORE lets clicks pass through to the button underneath.
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)

	var cost_label := Label.new()
	cost_label.text = str(card_data.cost)
	cost_label.add_theme_color_override("font_color", GOLD)
	cost_label.add_theme_font_size_override("font_size", 18)
	cost_label.custom_minimum_size = Vector2(14, 0)
	cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(cost_label)

	var name_label := Label.new()
	name_label.text = card_data.card_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "×%d" % count
	count_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(count_label)
	return row


# A deck row's background: dark, with a stripe of the card's colour on the left.
func make_row_style(card_color: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color.darkened(0.45 if hovered else 0.6)
	style.border_width_left = 5
	style.border_color = card_color.lightened(0.15)
	style.set_corner_radius_all(6)
	if hovered:
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = GOLD
	return style


# Delete every child of a node (to rebuild it from scratch).
func clear_children(node: Node) -> void:
	for child in node.get_children():
		# remove_child() takes it out right away (so it doesn't take up space
		# this frame), then queue_free() deletes it safely.
		node.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Rules and filters
# ---------------------------------------------------------------------------

func can_add(card_data: CardData) -> bool:
	return rules.can_add_to(GameState.deck, card_data)  # All the rules live in character_class.gd.


func matches_filter(card_data: CardData) -> bool:
	if school_filter == ALL_SCHOOLS:
		return true
	if school_filter == NEUTRAL:
		return card_data.is_neutral()
	return card_data.has_school(school_filter)


# ---------------------------------------------------------------------------
# Clicks
# ---------------------------------------------------------------------------

func _on_filter_pressed(school: int) -> void:
	school_filter = school
	refresh()


func _on_pool_card_clicked(card_data: CardData) -> void:
	if not can_add(card_data):
		return
	GameState.deck.append(card_data)
	refresh()
	pop(pool_grid.get_child(card_pool.find(card_data)).get_child(0))


# A quick "bounce" so you can see which card you just added.
func pop(card: Control) -> void:
	card.pivot_offset = card.size / 2  # Grow from the middle.
	card.scale = Vector2(1.08, 1.08)
	create_tween().tween_property(card, "scale", Vector2.ONE, 0.15)


func _on_deck_line_clicked(card_data: CardData) -> void:
	GameState.deck.erase(card_data)  # erase() removes only the FIRST match, so one copy.
	refresh()


func _on_clear_pressed() -> void:
	GameState.deck.clear()
	refresh()


func _on_default_pressed() -> void:
	GameState.deck = GameState.make_starter_deck()
	refresh()


func _on_start_pressed() -> void:
	# change_scene_to_file() throws away this whole scene and loads the map.
	# The deck survives because it lives in GameState, not in this scene.
	get_tree().change_scene_to_file(MAP_SCENE)


# Back to Character Select to pick a different class.
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
