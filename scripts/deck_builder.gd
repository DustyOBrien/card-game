# deck_builder.gd
#
# The screen before the battle (scenes/deck_builder.tscn).
#
#   - Top: your class with its level and Exp bar, and filter tabs to show one
#     school at a time.
#   - Left: the card POOL, one of every card you own that your class can use.
#     (Cards you haven't found in booster packs yet don't show up.)
#     Click one to add it to your deck. Under each card, dots show its copies:
#       gold = in your deck, grey = owned but not in it, hollow = not owned.
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
const BLOCKED_TINT := Color(0.5, 0.5, 0.55)  # Cards you can't add right now are drawn darker...
const ALL_IN_TINT := Color(0.85, 0.85, 0.85)  # ...but only a little when every copy is already in.
const REASON_COLOR := Color(1, 0.6, 0.45)  # "Deck is full" and other reasons.
const DIM_TEXT := Color(1, 1, 1, 0.5)

# The ways the pool can be sorted (the "Sort by" menu).
const SORT_OPTIONS := ["School", "Cost", "Name", "Rarity"]

# The deck rules (deck size, copies per card) come from the class you picked.
# They live in classes/*.tres: click one in Godot and change them in the Inspector.
var rules: CharacterClass
var card_pool: Array[CardData] = []
var school_filter := ALL_SCHOOLS
var sort_mode := 0  # Index into SORT_OPTIONS.
# The pieces of each card's cell in the pool, so refresh() can update them:
# CardData -> {"cell": VBoxContainer, "card": Card, "pips": RichTextLabel, "note": Label}
var cells := {}

@onready var emblem: TextureRect = %Emblem
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var exp_bar: ExpBar = %ExpBar
@onready var pool_count_label: Label = %PoolCountLabel
@onready var sort_button: OptionButton = %SortButton
@onready var empty_label: Label = %EmptyLabel
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
	add_talents_button()

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
	exp_bar.show_class(rules)

	# The "Sort by" menu. An OptionButton is a drop-down list.
	for option in SORT_OPTIONS:
		sort_button.add_item(option)
	sort_button.item_selected.connect(_on_sort_selected)

	card_pool = GameState.load_card_pool()  # Only the cards this class can use.
	build_filters()
	build_pool()
	sort_pool()
	refresh()


# ---------------------------------------------------------------------------
# Building the screen (once)
# ---------------------------------------------------------------------------

# One toggle button per school the class can use (or has cards for), plus "All" and "Neutral".
func build_filters() -> void:
	# A ButtonGroup makes toggle buttons work like radio buttons:
	# pressing one un-presses the others.
	var group := ButtonGroup.new()
	var options := [["All", ALL_SCHOOLS]]
	for school_name in CardData.School.keys():
		var school: int = CardData.School[school_name]
		# Also a tab for a school only a talent opens (the Adventurer's).
		if (rules.allowed_schools & school) != 0 or card_pool.any(func(card: CardData) -> bool: return card.has_school(school)):
			options.append([school_name.capitalize(), school])
	if rules.allow_neutral:
		options.append(["Neutral", NEUTRAL])

	for option in options:
		var button := Button.new()
		# e.g. "Strength 3": how many of your cards are in that tab.
		var count := card_pool.filter(func(card: CardData) -> bool: return matches(card, option[1])).size()
		button.text = "%s  %d" % [option[0], count]
		button.toggle_mode = true  # Stays pressed in, like a tab.
		button.button_group = group
		button.button_pressed = option[1] == school_filter
		button.pressed.connect(_on_filter_pressed.bind(option[1]))
		filter_bar.add_child(button)


# Make one clickable card (plus its copy dots and a note) for every card in
# the pool. This only happens once; refresh() updates them later.
func build_pool() -> void:
	for card_data in card_pool:
		var cell := VBoxContainer.new()  # .new() makes a node in code instead of in a scene.
		cell.add_theme_constant_override("separation", 2)
		pool_grid.add_child(cell)

		var card: Card = CARD_SCENE.instantiate()
		cell.add_child(card)
		# Show the level 2 or 3 version once the card has leveled up...
		card.setup(GameState.leveled(card_data))
		# ...but always add the level 1 card to the deck (the battle swaps in
		# the leveled one). A lambda lets us pass card_data instead of what
		# the card shows.
		card.clicked.connect(func(_shown: CardData) -> void: _on_pool_card_clicked(card_data))
		card.mouse_entered.connect(_on_pool_card_hovered.bind(card, true))
		card.mouse_exited.connect(_on_pool_card_hovered.bind(card, false))

		# Copy dots, e.g. ●●○. A RichTextLabel can colour parts of its text
		# with BBCode tags like [color=gold]...[/color].
		var pips := RichTextLabel.new()
		pips.bbcode_enabled = true
		pips.fit_content = true
		pips.scroll_active = false
		pips.autowrap_mode = TextServer.AUTOWRAP_OFF
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pips.add_theme_font_size_override("normal_font_size", 18)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(pips)

		# A small note: the card's level and Exp, or why you can't add it.
		var note := Label.new()
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 12)
		cell.add_child(note)

		cells[card_data] = {"cell": cell, "card": card, "pips": pips, "note": note}


# Put the pool in the order picked in the "Sort by" menu.
func sort_pool() -> void:
	card_pool.sort_custom(func(a: CardData, b: CardData) -> bool:
		match SORT_OPTIONS[sort_mode]:
			"Cost":
				if a.cost != b.cost:
					return a.cost < b.cost
			"Rarity":
				if a.rarity != b.rarity:
					return a.rarity > b.rarity  # Rare first.
			"School":
				if a.schools != b.schools:
					return a.schools < b.schools
		return a.card_name < b.card_name)
	# move_child() changes a node's place among its siblings, which is
	# also its place in the grid.
	for i in card_pool.size():
		pool_grid.move_child(cells[card_pool[i]].cell, i)


# ---------------------------------------------------------------------------
# Updating the screen (after every change)
# ---------------------------------------------------------------------------

func refresh() -> void:
	var deck := GameState.deck
	refresh_pool(deck)
	refresh_stats(deck)
	refresh_deck_list(deck)
	empty_label.visible = deck.is_empty()

	# Only allow starting once the deck is big enough, and say why if it isn't.
	var missing := rules.min_deck_size - deck.size()
	start_button.disabled = missing > 0
	if missing > 0:
		rules_label.text = "Add %d more card%s to start" % [missing, "" if missing == 1 else "s"]
	else:
		rules_label.text = "Ready to fight!"


# The pool: copy dots, notes, darker cards you can't add, and the school filter.
func refresh_pool(deck: Array[CardData]) -> void:
	var shown := 0
	for card_data in card_pool:
		var parts: Dictionary = cells[card_data]
		var card: Card = parts.card
		var count := deck.count(card_data)  # How many times this card is in the list.
		var owned := GameState.owned(card_data)
		# The most this class can put in: 3, or 1 for the Adventurer's school cards.
		var limit := rules.max_copies_of(card_data)
		if rules.max_cards_per_school > 0 and not card_data.is_neutral():
			limit = mini(limit, rules.max_cards_per_school)
		# The dots always show all the copies you OWN, even when your class
		# can only put fewer in the deck (the Adventurer's 1 per school).
		parts.pips.text = "[center]%s[/center]" % make_pips(count, owned, GameState.MAX_COPIES)

		var reason := rules.why_not(deck, card_data)
		card.disabled = not reason.is_empty()
		var note: Label = parts.note
		if count > 0 and count >= mini(owned, limit):
			# Every copy you can use is already in. That's good news, so the
			# card only dims a little and the note is gold.
			card.modulate = ALL_IN_TINT
			# "All in deck", or "In deck (max 1)" when the class allows fewer than you own.
			note.text = "✓ All in deck" if count >= owned else "✓ In deck (max %d)" % limit
			note.add_theme_color_override("font_color", GOLD)
		elif card.disabled:
			# Blocked by a rule: darken it and say why ("Deck is full"...).
			card.modulate = BLOCKED_TINT
			note.text = reason
			note.add_theme_color_override("font_color", REASON_COLOR)
		else:
			card.modulate = Color.WHITE
			note.text = "Lv %d  ·  %s" % [GameState.card_level(card_data), GameState.card_exp_text(card_data)]
			note.add_theme_color_override("font_color", DIM_TEXT)

		parts.cell.visible = matches_filter(card_data)
		if parts.cell.visible:
			shown += 1
	pool_count_label.text = "%d card%s" % [shown, "" if shown == 1 else "s"]


# The copy dots as BBCode: `in_deck` gold dots, then grey ones up to
# `owned`, then hollow ones up to `limit` (3).
func make_pips(in_deck: int, owned: int, limit: int) -> String:
	var text := ""
	for i in limit:
		if i < in_deck:
			text += "[color=#ffd94d]●[/color]"
		elif i < owned:
			text += "[color=#ffffff66]●[/color]"
		else:
			text += "[color=#ffffff40]○[/color]"
	return text


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
	# Average cost, e.g. "Avg cost 1.3". %.1f means "one digit after the point".
	var total_cost := 0
	for card in deck:
		total_cost += card.cost
	lines.append("Avg cost %.1f" % (float(total_cost) / maxi(deck.size(), 1)))
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
	var level := GameState.card_level(card_data)
	if level > 1:
		name_label.text += "  (Lv %d)" % level
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(name_label)

	# A small dot in the card's rarity colour.
	var rarity_dot := Label.new()
	rarity_dot.text = "◆"
	rarity_dot.tooltip_text = card_data.get_rarity_text()
	rarity_dot.add_theme_font_size_override("font_size", 12)
	rarity_dot.add_theme_color_override("font_color", CardData.RARITY_COLORS[card_data.rarity])
	rarity_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(rarity_dot)

	var count_label := Label.new()
	count_label.text = "×%d" % count
	count_label.custom_minimum_size = Vector2(24, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(count_label)
	row.set_meta("card", card_data)  # So we can find this row again to flash it.
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
	return matches(card_data, school_filter)


# Does this card belong in the tab for `school` (or ALL_SCHOOLS / NEUTRAL)?
func matches(card_data: CardData, school: int) -> bool:
	if school == ALL_SCHOOLS:
		return true
	if school == NEUTRAL:
		return card_data.is_neutral()
	return card_data.has_school(school)


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
	pop(cells[card_data].card)
	flash_deck_row(card_data)


func _on_sort_selected(index: int) -> void:
	sort_mode = index
	sort_pool()


# Lift a pool card a little while the mouse is over it.
func _on_pool_card_hovered(card: Card, hovered: bool) -> void:
	if card.disabled and hovered:
		return
	card.pivot_offset = card.size / 2
	create_tween().tween_property(card, "scale", Vector2(1.04, 1.04) if hovered else Vector2.ONE, 0.08)


# Flash the deck list row of the card you just added, so you can see where it went.
func flash_deck_row(card_data: CardData) -> void:
	for row in deck_list.get_children():
		if row.get_meta("card") == card_data:
			row.modulate = Color(1.6, 1.4, 0.8)  # Above 1 = brighter than normal.
			create_tween().tween_property(row, "modulate", Color.WHITE, 0.4)
			# Scroll the list so the row is on screen.
			(deck_list.get_parent() as ScrollContainer).ensure_control_visible(row)


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
	GameState.save_game()  # Also remembers this deck for next time.
	get_tree().change_scene_to_file(MAP_SCENE)


# A Talents button next to Back. Talents can change which cards you may use,
# so it's handy to hop over and come straight back.
func add_talents_button() -> void:
	var button := Button.new()
	var points := GameState.talent_points_left(GameState.character_class)
	button.text = "Talents"
	if points > 0:
		button.text = "★ Talents (%d point%s)" % [points, "" if points == 1 else "s"]
		button.add_theme_color_override("font_color", GOLD)
	button.pressed.connect(func() -> void:
		GameState.save_game()
		GameState.talents_return_scene = scene_file_path
		get_tree().change_scene_to_file("res://scenes/talents.tscn"))
	back_button.add_sibling(button)


# Back to Character Select to pick a different class.
func _on_back_pressed() -> void:
	GameState.save_game()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
