# binder.gd
#
# THE BINDER (scenes/binder.tscn): every card a place's booster packs can
# hold, like a collector's album. Cards you've found show face up with how many
# you own (and your foils); cards you haven't found are dark SILHOUETTES with
# a "?", so you can see what's still out there to chase.
#
# Finding a new card gives the place Exp (GameState.BINDER_EXP), and every
# 25% of the binder gives a reward (data/progression/binder_rewards.csv).
# Both happen in GameState.add_card(); this screen only draws them.
#
# Like the Prepare screen, everything is built in code. The Back button goes
# to GameState.screen_return_scene (the Shop, Prepare or town set it).
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")
const GOLD := Color(1, 0.84, 0.35)
const DIM := Color(1, 1, 1, 0.6)
const COLUMNS := 8
const CELL_SCALE := 0.85  # Cards are a bit smaller here, so more fit.

var area: Area


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	area = binder_area()
	build_screen()


# The binder of the place you're at, or the first place that has one.
static func binder_area() -> Area:
	if GameState.current_area and not GameState.current_area.booster.is_empty():
		return GameState.current_area
	for some_area in GameState.load_areas():
		if not some_area.booster.is_empty():
			return some_area
	return null


func build_screen() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.08, 0.07)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	# --- Title row: name, how much you've found, Back ---
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	page.add_child(title_row)
	var title := make_label("%s Binder" % (area.display_name if area else "No"), 32, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if area == null:
		return
	var cards := GameState.binder_cards(area)
	var found := GameState.binder_found(area)
	title_row.add_child(make_label("%d / %d found  ·  %d%%" % [found, cards.size(), GameState.binder_percent(area)], 22, Color.WHITE))
	var back := Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(120, 42)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(GameState.screen_return_scene))
	title_row.add_child(back)

	page.add_child(make_milestones())
	page.add_child(make_label("Every NEW card you find gives the %s Exp (Common %d, Uncommon %d, Rare %d, Legendary %d). Packs come from %s level ups, quests, chests and the Shop." % [
		area.display_name, GameState.BINDER_EXP[CardData.Rarity.COMMON], GameState.BINDER_EXP[CardData.Rarity.UNCOMMON],
		GameState.BINDER_EXP[CardData.Rarity.RARE], GameState.BINDER_EXP[CardData.Rarity.LEGENDARY], area.booster], 15, DIM, true))

	# --- The pages: one cell per card ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for i in cards.size():
		make_cell(grid, i + 1, cards[i])


# The reward line: a bar of how much you've found, with each % reward under it
# (✓ once you've had it).
func make_milestones() -> Control:
	var box := VBoxContainer.new()
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = GameState.binder_percent(area)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	box.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var claimed: int = GameState.binder_claimed.get(area.display_name, 0)
	for reward in GameState.binder_rewards(area):
		var done: bool = reward.percent <= claimed
		var chip := make_label("%s %d%%: %s" % ["✓" if done else "○", reward.percent,
			reward.text if not reward.text.is_empty() else reward.rewards], 15, GOLD if done else Color.WHITE, true)
		row.add_child(chip)
	return box


# One card: face up if you own it, a silhouette if you don't.
func make_cell(grid: GridContainer, number: int, card_data: CardData) -> void:
	var cell := VBoxContainer.new()
	grid.add_child(cell)  # In the scene first, so the card's labels exist for setup().
	cell.add_theme_constant_override("separation", 2)
	var holder := Control.new()  # Card scenes ignore scale in containers, so a holder sizes the slot.
	holder.custom_minimum_size = Vector2(140, 226) * CELL_SCALE
	cell.add_child(holder)
	var card: Card = CARD_SCENE.instantiate()
	holder.add_child(card)
	var owned := GameState.owned(card_data)
	var foil_count := GameState.foils_owned(card_data)
	card.setup(GameState.foil_of(card_data) if foil_count > 0 else card_data)  # Show off a foil if you have one.
	card.scale = Vector2(CELL_SCALE, CELL_SCALE)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var caption := ""
	if owned > 0:
		card.tooltip_text = card_data.effect
		caption = "#%02d  own %d / %d" % [number, owned, card_data.copy_limit()]
		if foil_count > 0:
			caption += "  ✦%d" % foil_count
	else:
		# Not found yet: a dark card SHAPE (just its school colour, very dim, and
		# a rim in its rarity colour) with a big "?". No name, no numbers.
		card.visible = false
		var shape := Panel.new()
		shape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shape.tooltip_text = "Not found yet. A %s card from %s booster packs." % [card_data.get_rarity_text(), area.booster]
		var style := StyleBoxFlat.new()
		style.bg_color = card_data.color.darkened(0.82)
		style.border_color = Color(CardData.RARITY_COLORS[card_data.rarity], 0.35)
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		shape.add_theme_stylebox_override("panel", style)
		holder.add_child(shape)
		var mark := make_label("?", 64, Color(1, 1, 1, 0.3))
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shape.add_child(mark)
		caption = "#%02d  ???" % number
	var label := make_label(caption, 14, DIM if owned == 0 else Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)
	var rarity := make_label(card_data.get_rarity_text(), 13, CardData.RARITY_COLORS[card_data.rarity])
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(rarity)


func make_label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
