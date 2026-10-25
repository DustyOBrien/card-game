# shop.gd
#
# The shop you visit at the end of every run (scenes/shop.tscn).
# Spend gold on booster packs, then go to the map for the next run.
#
# The packs don't do anything yet: buying one just adds it to
# GameState.booster_packs, so we can open them in a later update.
extends Control

const MAP_SCENE := "res://scenes/map.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"

# Every pack the shop sells. To add a pack or change a price, edit this list.
# `school` picks the pack's colour (0 = Neutral, grey).
const PACKS := [
	{"name": "Neutral Pack", "price": 3, "school": 0, "blurb": "Cards any class can use"},
	{"name": "Strength Pack", "price": 5, "school": CardData.School.STRENGTH, "blurb": "Strength cards"},
	{"name": "Agility Pack", "price": 5, "school": CardData.School.AGILITY, "blurb": "Agility cards"},
	{"name": "Intellect Pack", "price": 5, "school": CardData.School.INTELLECT, "blurb": "Intellect cards"},
	{"name": "Wisdom Pack", "price": 5, "school": CardData.School.WISDOM, "blurb": "Wisdom cards"},
]

@onready var gold_label: Label = %GoldLabel
@onready var summary_label: Label = %SummaryLabel
@onready var pack_row: HBoxContainer = %PackRow
@onready var owned_label: Label = %OwnedLabel
@onready var edit_deck_button: Button = %EditDeckButton
@onready var next_run_button: Button = %NextRunButton


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	edit_deck_button.pressed.connect(_on_edit_deck_pressed)
	next_run_button.pressed.connect(_on_next_run_pressed)

	# How the run went.
	if GameState.run_died:
		summary_label.text = "You fell after beating %d Slime(s), and earned %d gold." % [
			GameState.fights_won, GameState.run_gold]
	else:
		summary_label.text = "You beat all %d Slimes and earned %d gold!" % [
			GameState.fights_won, GameState.run_gold]

	for pack in PACKS:
		pack_row.add_child(_make_pack(pack))
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


func _on_edit_deck_pressed() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)


func _on_next_run_pressed() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)  # Pick where the next run happens.
