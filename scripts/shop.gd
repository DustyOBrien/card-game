# shop.gd
#
# The shop you visit at the end of every run (scenes/shop.tscn).
# Spend gold on booster packs, then go to the map for the next run.
#
# Bought packs wait under "Your packs" until you press Open Pack. Opening one
# shows its 3 cards and adds them to your collection (GameState.open_pack()),
# so they show up in the deck builder.
extends Control

const MAP_SCENE := "res://scenes/map.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CARD_SCENE := preload("res://scenes/card.tscn")
const REVEAL_GAP := 0.35  # Seconds between the cards of a pack appearing.

# Every pack the shop sells. To add a pack or change a price, edit this list.
# `school` picks the pack's colour (0 = Neutral, grey).
# (The odds and the number of cards are in game_state.gd: PACK_ODDS, CARDS_PER_PACK.)
const PACKS := [
	{"name": "Basic Booster", "price": 5, "school": 0,
		"blurb": "3 cards\nCommon 60%  ·  Uncommon 30%  ·  Rare 10%"},
]

@onready var gold_label: Label = %GoldLabel
@onready var summary_label: Label = %SummaryLabel
@onready var pack_row: HBoxContainer = %PackRow
@onready var owned_label: Label = %OwnedLabel
@onready var edit_deck_button: Button = %EditDeckButton
@onready var next_run_button: Button = %NextRunButton

var open_button: Button  # "Open Pack", under "Your packs". Made in code.
var reveal_layer: ColorRect  # The dark screen the opened cards appear on.


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	edit_deck_button.pressed.connect(_on_edit_deck_pressed)
	next_run_button.pressed.connect(_on_next_run_pressed)

	# How the run went.
	if GameState.run_died:
		summary_label.text = "You fell after winning %d fight(s), and earned %d gold." % [
			GameState.fights_won, GameState.run_gold]
	else:
		summary_label.text = "You won all %d fights and earned %d gold!" % [
			GameState.fights_won, GameState.run_gold]

	for pack in PACKS:
		pack_row.add_child(_make_pack(pack))
	open_button = Button.new()
	open_button.text = "Open Pack"
	open_button.theme_type_variation = &"PrimaryButton"
	open_button.custom_minimum_size = Vector2(200, 44)
	open_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	open_button.pressed.connect(open_pack)
	# add_sibling() puts the button right after "Your packs" in the layout.
	owned_label.add_sibling(open_button)
	refresh()


# Update the gold, the Buy buttons and the "you own" line.
func refresh() -> void:
	gold_label.text = "Gold %d" % GameState.gold
	for panel in pack_row.get_children():
		var button: Button = panel.get_meta("buy_button")
		button.disabled = GameState.gold < panel.get_meta("price")
	var owned: Array[String] = []
	for pack_name in GameState.booster_packs:
		owned.append("%s x%d" % [pack_name, GameState.booster_packs[pack_name]])
	owned_label.text = "Your packs: " + (", ".join(owned) if not owned.is_empty() else "none yet")
	open_button.disabled = GameState.booster_packs.is_empty()


func buy(pack: Dictionary, panel: Control) -> void:
	if GameState.gold < pack.price:
		return
	GameState.gold -= pack.price
	# Dictionary.get(key, 0) gives 0 if we don't own this pack yet.
	GameState.booster_packs[pack.name] = GameState.booster_packs.get(pack.name, 0) + 1
	# A little bounce so you can see what you bought.
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(1.08, 1.08)
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	refresh()


# One pack for sale: a coloured "packet" with its name, price and a Buy button.
func _make_pack(pack: Dictionary) -> PanelContainer:
	var color: Color = CardData.SCHOOL_COLORS.get(pack.school, CardData.NEUTRAL_COLOR)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 300)
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55)
	style.border_color = color.lightened(0.25)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# The "packet": a coloured block with a big question mark, like a sealed pack.
	var packet := PanelContainer.new()
	packet.custom_minimum_size = Vector2(0, 140)
	var packet_style := StyleBoxFlat.new()
	packet_style.bg_color = color
	packet_style.set_corner_radius_all(8)
	packet_style.border_color = Color(1, 1, 1, 0.5)
	packet_style.border_width_top = 6  # The packet's sealed edge.
	packet.add_theme_stylebox_override("panel", packet_style)
	var mark := Label.new()
	mark.text = "?"
	mark.add_theme_font_size_override("font_size", 64)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	packet.add_child(mark)
	box.add_child(packet)

	var name_label := Label.new()
	name_label.text = pack.name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var blurb := Label.new()
	blurb.text = pack.blurb
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(blurb)

	var button := Button.new()
	button.text = "Buy  (%d gold)" % pack.price
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	# bind() fills in buy()'s arguments, so each button buys its own pack.
	button.pressed.connect(buy.bind(pack, panel))
	box.add_child(button)

	panel.set_meta("buy_button", button)
	panel.set_meta("price", pack.price)
	return panel


# Open the first pack you own and show its cards one by one.
func open_pack() -> void:
	if GameState.booster_packs.is_empty():
		return
	var pack_name: String = GameState.booster_packs.keys()[0]
	GameState.booster_packs[pack_name] -= 1
	if GameState.booster_packs[pack_name] <= 0:
		GameState.booster_packs.erase(pack_name)  # None of that pack left.
	refresh()
	var opened := GameState.open_pack()

	# A dark layer over the whole shop, with the cards in a row in the middle.
	reveal_layer = ColorRect.new()
	reveal_layer.color = Color(0, 0, 0, 0.8)
	reveal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(reveal_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reveal_layer.add_child(center)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	center.add_child(layout)
	var title := Label.new()
	title.text = pack_name
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(row)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(160, 44)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.disabled = true  # Until every card is shown.
	done.pressed.connect(reveal_layer.queue_free)
	layout.add_child(done)

	for item: Dictionary in opened:
		await get_tree().create_timer(REVEAL_GAP).timeout
		_add_reveal(item, row)
	done.disabled = false


# One card from a pack: the card itself, with "NEW!" or how many you own under it.
func _add_reveal(item: Dictionary, row: HBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)  # In the scene first, so the card's @onready labels exist for setup().
	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 20)
	var card: Card = CARD_SCENE.instantiate()
	box.add_child(card)
	card.setup(GameState.leveled(item.card))  # Its level 2 or 3 version, if it has one.
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Just for looking at.
	# e.g. "NEW!  Rare" or "Owned 2 / 3  Common", in the rarity's colour.
	# A card you already own 3 of gives it Exp instead: "+1 Exp (2 / 3)".
	var owned_text := "Owned %d / %d" % [item.owned, GameState.MAX_COPIES]
	if item.new:
		owned_text = "NEW!"
	elif item.level_up:
		owned_text = "LEVEL UP! Lv %d" % item.level
	elif item.exp:
		owned_text = "+1 Exp  (%s)" % item.exp_text.trim_prefix("Exp ")
	note.text = "%s\n%s" % [owned_text, item.card.get_rarity_text()]
	note.add_theme_color_override("font_color", CardData.RARITY_COLORS[item.card.rarity])
	box.add_child(note)
	# Pop in: start big and see-through, settle to normal.
	card.pivot_offset = card.custom_minimum_size / 2
	card.scale = Vector2(1.3, 1.3)
	card.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card, "modulate:a", 1.0, 0.2)


func _on_edit_deck_pressed() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)


func _on_next_run_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)  # Pick where the next run happens.
