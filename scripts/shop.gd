# shop.gd
#
# The Shop (scenes/shop.tscn), one of the buildings in town (see town.gd).
# Spend gold on booster packs, then go back to town.
#
# Bought packs (and packs from quests and chests) wait under "Your packs"
# until you press Open. Opening one shows its cards (3, 5 or 7) and adds them
# to your collection (GameState.open_pack()), so they show up in the deck builder.
#
# Before the Shop is built, town's "Your Packs" button still brings you here,
# but only to open packs: nothing is for sale yet.
extends Control

const TOWN_SCENE := "res://scenes/town.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CARD_SCENE := preload("res://scenes/card.tscn")
const REVEAL_GAP := 0.35  # Seconds between the cards of a pack appearing.

# The packs (names, card counts, prices) are GameState.PACKS, and the odds
# are GameState.PACK_ODDS: edit them there.
const FARM_COLOR := Color(0.36, 0.58, 0.27)  # Farm packs are grassy green.
const PACK_ICON := preload("res://icons/booster.svg")  # A Farm booster pack.

@onready var gold_label: Label = %GoldLabel
var essence_counter: Label  # "Essence 12" on the pack opening screen (the orbs fly into it).
var _shown_essence := 0
@onready var summary_label: Label = %SummaryLabel
@onready var pack_row: HBoxContainer = %PackRow
@onready var owned_label: Label = %OwnedLabel
@onready var edit_deck_button: Button = %EditDeckButton
@onready var next_run_button: Button = %NextRunButton

var open_row: HBoxContainer  # One "Open" button per kind of pack you own. Made in code.
var reveal_layer: ColorRect  # The dark screen the opened cards appear on.


func _ready() -> void:
	GameState.ensure_ready()  # So pressing F6 on this scene still works.
	edit_deck_button.pressed.connect(_on_edit_deck_pressed)
	next_run_button.pressed.connect(_on_next_run_pressed)

	next_run_button.text = "← Back to Town"
	if shop_built():
		summary_label.text = "Farm packs cost gold AND Stone from the Abandoned Farm (it comes out of your Bank). Open them here or later."
		for pack in GameState.PACKS:
			pack_row.add_child(_make_pack(pack))
	else:
		summary_label.text = "The Shop isn't built yet, so nothing's for sale. You can still open the packs you have."
		pack_row.visible = false
	open_row = HBoxContainer.new()
	open_row.alignment = BoxContainer.ALIGNMENT_CENTER
	open_row.add_theme_constant_override("separation", 12)
	# add_sibling() puts the buttons right after "Your packs" in the layout.
	owned_label.add_sibling(open_row)
	refresh()


func shop_built() -> bool:
	return GameState.town_bonus(TownBuilding.SHOP) > 0


# Update the gold, the Buy buttons and the "you own" line.
func refresh() -> void:
	gold_label.text = "Gold %d   Stone %d   Essence %d" % [GameState.gold, GameState.material_count("Stone"), essence_total()]
	gold_label.mouse_filter = Control.MOUSE_FILTER_PASS
	gold_label.tooltip_text = essence_tooltip()
	for panel in pack_row.get_children():
		var button: Button = panel.get_meta("buy_button")
		button.disabled = not can_buy(panel.get_meta("pack"))
	owned_label.text = "Your packs:" if GameState.pack_count() > 0 else "Your packs: none yet"
	for old in open_row.get_children():
		old.queue_free()
	for pack in GameState.PACKS:  # Small, Medium, Large order.
		var count: int = GameState.booster_packs.get(pack.name, 0)
		if count <= 0:
			continue
		var button := Button.new()
		button.icon = PACK_ICON
		button.add_theme_constant_override("icon_max_width", 30)
		button.text = "Open %s  x%d" % [pack.size, count]
		button.tooltip_text = pack.name
		button.theme_type_variation = &"PrimaryButton"
		button.custom_minimum_size = Vector2(0, 44)
		button.pressed.connect(open_pack.bind(pack.name))
		open_row.add_child(button)


# What a pack costs you: its price, less any Pack Discount talents (never below 1).
func price_of(pack: Dictionary) -> int:
	var discount := GameState.talent_bonus(GameState.character_class, Talent.PACK_DISCOUNT) \
		+ GameState.town_bonus(TownBuilding.PACK_DISCOUNT)  # Loot Hound, and the Shop's upgrade.
	return maxi(pack.price - discount, 1)


# Enough gold AND Stone (in your Bank) for it?
func can_buy(pack: Dictionary) -> bool:
	return GameState.gold >= price_of(pack) and GameState.has_materials(pack.materials)


func buy(pack: Dictionary, panel: Control) -> void:
	if not can_buy(pack):
		return
	GameState.gold -= price_of(pack)
	GameState.spend_materials(pack.materials)
	GameState.add_packs(pack.name, 1)
	GameState.save_game()
	# A little bounce so you can see what you bought.
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(1.08, 1.08)
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	refresh()


# One pack for sale: a coloured "packet" with its name, price and a Buy button.
func _make_pack(pack: Dictionary) -> PanelContainer:
	var color := FARM_COLOR

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

	# The pack's picture (icons/booster.svg): bigger packs are drawn bigger.
	var picture := TextureRect.new()
	picture.texture = PACK_ICON
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(0, 70 + pack.cards * 12)
	picture.tooltip_text = pack.name
	box.add_child(picture)

	var name_label := Label.new()
	name_label.text = pack.size  # "Small": the picture says it's a Farm pack.
	name_label.tooltip_text = pack.name
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var blurb := Label.new()
	blurb.text = "%d cards\nCommon %d%%  ·  Uncommon %d%%  ·  Rare %d%%  ·  Legendary %d%%" % [pack.cards,
		GameState.PACK_ODDS[CardData.Rarity.COMMON], GameState.PACK_ODDS[CardData.Rarity.UNCOMMON],
		GameState.PACK_ODDS[CardData.Rarity.RARE], GameState.PACK_ODDS[CardData.Rarity.LEGENDARY]]
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(blurb)

	var button := Button.new()
	button.text = "Buy  (%d gold, %s)" % [price_of(pack), MaterialInfo.costs_text(pack.materials)]
	if price_of(pack) < pack.price:
		button.tooltip_text = "Was %d gold (discount)." % pack.price  # Loot Hound / the Shop's upgrade.
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	# bind() fills in buy()'s arguments, so each button buys its own pack.
	button.pressed.connect(buy.bind(pack, panel))
	box.add_child(button)

	panel.set_meta("buy_button", button)
	panel.set_meta("pack", pack)
	return panel


# ---------------------------------------------------------------------------
# Opening a pack
# ---------------------------------------------------------------------------
# The show, step by step (each step is a Tween: a little animation):
#   1. The sealed pack drops in, glows and shakes.
#   2. It bursts: a white flash, sparkles, and the pack is gone.
#   3. The cards fly out face down to their places.
#   4. They flip over one at a time. Rarer cards glow (blue Uncommon, gold
#      Rare), and a Rare one gets a bigger burst and a little screen shake.
# Click anywhere to hurry it up (every card flips at once).

const CARD_SIZE := Vector2(140, 226)  # Every card in a pack is drawn this size.
const CARD_GAP := 36  # Pixels between the cards.
const BACK_COLOR := Color(0.22, 0.16, 0.38)  # The back of a card.

var _skip := false  # Clicked to hurry up the reveal.


# Open one of your packs of this kind and show its cards.
func open_pack(pack_name: String) -> void:
	var opened := GameState.open_pack(pack_name)
	if opened.is_empty():
		return
	refresh()
	# The Essence counter starts at what you had BEFORE this pack, and counts
	# up as each extra card's orbs fly into it.
	_shown_essence = essence_total()
	for item in opened:
		for school_name in item.essence:
			_shown_essence -= item.essence[school_name]
	var color := FARM_COLOR
	_skip = false

	# A dark layer over the whole shop. Clicking it hurries the reveal.
	reveal_layer = ColorRect.new()
	reveal_layer.color = Color(0, 0, 0, 0.0)
	reveal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reveal_layer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_skip = true)
	add_child(reveal_layer)
	create_tween().tween_property(reveal_layer, "color:a", 0.85, 0.25)
	essence_counter = Label.new()
	essence_counter.text = "Essence %d" % _shown_essence
	essence_counter.add_theme_font_size_override("font_size", 26)
	essence_counter.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	essence_counter.add_theme_color_override("font_outline_color", Color.BLACK)
	essence_counter.add_theme_constant_override("outline_size", 6)
	essence_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	essence_counter.size = Vector2(260, 40)
	essence_counter.position = Vector2(get_viewport_rect().size.x - 290, 130)
	essence_counter.pivot_offset = essence_counter.size / 2
	essence_counter.visible = opened.any(func(item: Dictionary) -> bool: return not item.essence.is_empty())
	reveal_layer.add_child(essence_counter)
	var middle := reveal_layer.size / 2 if reveal_layer.size.x > 0 else get_viewport_rect().size / 2

	var title := Label.new()
	title.text = pack_name
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(600, 50)
	title.position = Vector2(middle.x - 300, 70)
	reveal_layer.add_child(title)

	# 1. The sealed pack drops in and shakes.
	var sealed := _make_sealed_pack(color)
	sealed.position = middle - sealed.size / 2 + Vector2(0, -300)
	sealed.pivot_offset = sealed.size / 2
	reveal_layer.add_child(sealed)
	var drop := create_tween()
	drop.tween_property(sealed, "position:y", middle.y - sealed.size.y / 2, 0.35) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await drop.finished
	var shake := create_tween()
	for i in 6:
		var amount := 0.06 + i * 0.025  # Shakes harder and harder...
		shake.tween_property(sealed, "rotation", amount if i % 2 == 0 else -amount, 0.06)
	shake.parallel().tween_property(sealed, "scale", Vector2(1.12, 1.12), 0.36)
	shake.tween_property(sealed, "rotation", 0.0, 0.04)
	if not _skip:
		await shake.finished

	# 2. Burst: flash, sparkles, the pack swells and fades away.
	_flash(Color(1, 1, 1, 0.8), 0.35)
	_sparkles(middle, color.lightened(0.4), 40, 260.0)
	var burst := create_tween().set_parallel()
	burst.tween_property(sealed, "scale", Vector2(1.8, 1.8), 0.25)
	burst.tween_property(sealed, "modulate:a", 0.0, 0.25)
	burst.chain().tween_callback(sealed.queue_free)

	# 3. The cards fly out face down to their places in a row.
	var slots: Array[Control] = []
	# A Large pack has 7 cards: close the gaps so they all fit on screen.
	var gap := minf(CARD_GAP, (get_viewport_rect().size.x - 40 - opened.size() * CARD_SIZE.x) / maxf(opened.size() - 1, 1))
	var row_width := opened.size() * CARD_SIZE.x + (opened.size() - 1) * gap
	for i in opened.size():
		var slot := _make_slot(opened[i])
		slot.position = middle - CARD_SIZE / 2
		slot.scale = Vector2(0.3, 0.3)
		slot.rotation = randf_range(-1.5, 1.5)
		slots.append(slot)
		var target := Vector2(middle.x - row_width / 2 + i * (CARD_SIZE.x + gap), middle.y - CARD_SIZE.y / 2 - 20)
		var fly := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		fly.tween_property(slot, "position", target, 0.45).set_delay(i * 0.08)
		fly.tween_property(slot, "scale", Vector2.ONE, 0.45).set_delay(i * 0.08)
		fly.tween_property(slot, "rotation", 0.0, 0.45).set_delay(i * 0.08)
	await get_tree().create_timer(0.45 + opened.size() * 0.08).timeout
	if not is_instance_valid(reveal_layer):
		return

	# 4. Flip them over, one at a time (rarest last is more exciting, but
	# left to right is easier to follow).
	for i in slots.size():
		if not _skip:
			await get_tree().create_timer(REVEAL_GAP).timeout
		if not is_instance_valid(slots[i]):
			return  # The reveal was closed early.
		await _flip(slots[i], opened[i])

	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(160, 44)
	done.size = done.custom_minimum_size
	done.position = Vector2(middle.x - 80, middle.y + CARD_SIZE.y / 2 + 90)
	done.pressed.connect(reveal_layer.queue_free)
	reveal_layer.add_child(done)


# The sealed pack: a coloured packet with a shiny edge and a big "?".
func _make_sealed_pack(color: Color) -> PanelContainer:
	var packet := PanelContainer.new()
	packet.size = Vector2(170, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.border_color = color.lightened(0.5)
	style.set_border_width_all(4)
	style.border_width_top = 14  # The sealed edge.
	style.shadow_color = color.lightened(0.3)
	style.shadow_size = 24  # A glow around it.
	packet.add_theme_stylebox_override("panel", style)
	var picture := TextureRect.new()  # The Farm pack's picture on the front.
	picture.texture = PACK_ICON
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	packet.add_child(picture)
	return packet


# One card's place: a glow (hidden until it flips), the card back, and the
# card itself (hidden). Everything is CARD_SIZE, so every card is the same size.
func _make_slot(item: Dictionary) -> Control:
	var slot := Control.new()
	slot.size = CARD_SIZE
	slot.custom_minimum_size = CARD_SIZE
	slot.pivot_offset = CARD_SIZE / 2  # Spin and flip around the middle.
	reveal_layer.add_child(slot)  # In the scene first, so the card's labels exist for setup().

	var glow := Panel.new()
	glow.name = "Glow"
	glow.size = CARD_SIZE
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.set_corner_radius_all(12)
	glow_style.shadow_color = CardData.RARITY_COLORS[item.card.rarity]
	glow_style.shadow_size = 0 if item.card.rarity == CardData.Rarity.COMMON else (18 if item.card.rarity == CardData.Rarity.UNCOMMON else 30)
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.visible = false
	slot.add_child(glow)

	var card: Card = CARD_SCENE.instantiate()
	card.name = "Face"
	slot.add_child(card)
	card.setup(item.card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Just for looking at.
	# Force the exact size: some cards have more on them than others, and
	# without this a busy card grows a little bigger than its neighbours.
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.clip_contents = true
	card.visible = false

	var back := Panel.new()
	back.name = "Back"
	back.size = CARD_SIZE
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = BACK_COLOR
	back_style.border_color = Color(0.85, 0.7, 0.35)
	back_style.set_border_width_all(4)
	back_style.set_corner_radius_all(10)
	back.add_theme_stylebox_override("panel", back_style)
	var star := Label.new()
	star.text = "★"
	star.add_theme_font_size_override("font_size", 64)
	star.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	star.size = CARD_SIZE
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back.add_child(star)
	slot.add_child(back)
	return slot


# Turn one card over: squash it flat, swap the back for the face, stretch it
# back out. Then its glow, its note ("NEW!") and, for rarer cards, a burst.
func _flip(slot: Control, item: Dictionary) -> void:
	var speed := 0.06 if _skip else 0.12
	var squash := create_tween()
	squash.tween_property(slot, "scale:x", 0.0, speed).set_ease(Tween.EASE_IN)
	await squash.finished
	slot.get_node("Back").visible = false
	slot.get_node("Face").visible = true
	slot.get_node("Glow").visible = true
	var grow := create_tween()
	grow.tween_property(slot, "scale", Vector2(1.15, 1.15), speed).set_ease(Tween.EASE_OUT)
	grow.tween_property(slot, "scale", Vector2.ONE, 0.15)

	var rarity: CardData.Rarity = item.card.rarity
	var color: Color = CardData.RARITY_COLORS[rarity]
	var centre := slot.position + CARD_SIZE / 2
	if rarity == CardData.Rarity.LEGENDARY:
		_sparkles(centre, color, 90, 380.0)
		_flash(Color(1, 0.55, 0.2, 0.6), 0.6)
		_shake_screen()
	elif rarity == CardData.Rarity.RARE:
		_sparkles(centre, color, 50, 300.0)
		_flash(Color(1, 0.85, 0.4, 0.45), 0.4)
		_shake_screen()
	elif rarity == CardData.Rarity.UNCOMMON:
		_sparkles(centre, color, 24, 200.0)
	if rarity != CardData.Rarity.COMMON:
		# The glow breathes in and out.
		var pulse := create_tween().set_loops()
		pulse.bind_node(slot)  # Stops when the slot is freed.
		pulse.tween_property(slot.get_node("Glow"), "modulate:a", 0.45, 0.6)
		pulse.tween_property(slot.get_node("Glow"), "modulate:a", 1.0, 0.6)

	# e.g. "NEW!  Rare" or "Owned 2 / 3  Common", in the rarity's colour.
	# A card you already own the most of (its rarity limit) turns into
	# Essence instead: "+2 Strength Essence", and orbs fly up to the counter.
	var owned_text := "Owned %d / %d" % [item.owned, item.card.copy_limit()]
	if item.new:
		owned_text = "NEW!"
	elif not item.essence.is_empty():
		owned_text = GameState.essence_text(item.essence)
		for school_name: String in item.essence:
			_essence_orbs(centre, GameState.ESSENCE_COLORS.get(school_name, Color.WHITE), mini(item.essence[school_name] + 2, 8), item.essence[school_name])
	var note := Label.new()
	note.text = "%s\n%s" % [owned_text, item.card.get_rarity_text()]
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", color)
	note.add_theme_color_override("font_outline_color", Color.BLACK)
	note.add_theme_constant_override("outline_size", 6)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size = Vector2(CARD_SIZE.x + CARD_GAP, 50)
	note.position = Vector2(slot.position.x - CARD_GAP / 2.0, slot.position.y + CARD_SIZE.y + 12)
	note.pivot_offset = note.size / 2
	note.scale = Vector2(0.4, 0.4)
	reveal_layer.add_child(note)
	create_tween().tween_property(note, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if item.new:
		# "NEW!" bobs up and down.
		var bob := create_tween().set_loops()
		bob.bind_node(note)
		bob.tween_property(note, "position:y", note.position.y - 5, 0.4)
		bob.tween_property(note, "position:y", note.position.y, 0.4)
	await grow.finished


# ESSENCE: little glowing orbs fly from the card up to the counter at the top.
func _essence_orbs(from: Vector2, color: Color, count: int, amount: int) -> void:
	var to := essence_counter.position + Vector2(essence_counter.size.x - 30, 10)
	for i in count:
		var orb := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(9)
		style.shadow_color = Color(color, 0.7)
		style.shadow_size = 8
		orb.add_theme_stylebox_override("panel", style)
		orb.size = Vector2(18, 18)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orb.position = from + Vector2(randf_range(-40, 40), randf_range(-50, 50))
		reveal_layer.add_child(orb)
		var fly := create_tween()
		fly.tween_interval(0.15 + i * 0.07)
		fly.tween_property(orb, "position", to, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fly.parallel().tween_property(orb, "scale", Vector2(0.5, 0.5), 0.55)
		fly.tween_callback(orb.queue_free)
	var update := create_tween()
	update.tween_interval(0.8 + count * 0.07)
	update.tween_callback(_count_up.bind(amount))


# The orbs landed: the counter goes up and pops.
func _count_up(amount: int) -> void:
	if not is_instance_valid(essence_counter):
		return
	_shown_essence += amount
	essence_counter.text = "Essence %d" % _shown_essence
	var pop := create_tween()
	pop.tween_property(essence_counter, "scale", Vector2(1.25, 1.25), 0.1)
	pop.tween_property(essence_counter, "scale", Vector2.ONE, 0.15)


func essence_total() -> int:
	var total := 0
	for school_name in GameState.essence:
		total += GameState.essence[school_name]
	return total


# "Essence: copies past a card's rarity limit turn into Essence of its school.
#  Strength 3, Neutral 2"
func essence_tooltip() -> String:
	var parts: Array[String] = []
	for school_name in GameState.ESSENCE_NAMES:
		if GameState.essence.get(school_name, 0) > 0:
			parts.append("%s %d" % [school_name, GameState.essence[school_name]])
	return "Essence: copies past a card's rarity limit (Common 3, Uncommon 3, Rare 2, Legendary 1) turn into Essence of its school.\n" + \
		(", ".join(parts) if not parts.is_empty() else "None yet.")


# A quick full-screen flash of colour that fades away.
func _flash(color: Color, time: float) -> void:
	var flash := ColorRect.new()
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reveal_layer.add_child(flash)
	var fade := create_tween()
	fade.tween_property(flash, "color:a", 0.0, time)
	fade.tween_callback(flash.queue_free)


# A burst of little sparks flying out from a point. CPUParticles2D makes
# lots of tiny squares; one_shot = one burst, then it's done.
func _sparkles(at: Vector2, color: Color, amount: int, speed: float) -> void:
	var sparks := CPUParticles2D.new()
	sparks.position = at
	sparks.one_shot = true
	sparks.explosiveness = 0.95  # All at once, not a trickle.
	sparks.amount = amount
	sparks.lifetime = 0.8
	sparks.direction = Vector2.UP
	sparks.spread = 180.0  # Every direction.
	sparks.initial_velocity_min = speed * 0.5
	sparks.initial_velocity_max = speed
	sparks.gravity = Vector2(0, 300)
	sparks.scale_amount_min = 3.0
	sparks.scale_amount_max = 6.0
	sparks.color = color
	var fade := Gradient.new()  # Fade out as they fall.
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	sparks.color_ramp = fade
	reveal_layer.add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(1.2).timeout.connect(sparks.queue_free)


# Rattle the reveal for a moment (for Rare cards).
func _shake_screen() -> void:
	var shake := create_tween()
	for i in 6:
		shake.tween_property(reveal_layer, "position", Vector2(randf_range(-8, 8), randf_range(-6, 6)), 0.04)
	shake.tween_property(reveal_layer, "position", Vector2.ZERO, 0.04)


func _on_edit_deck_pressed() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)


func _on_next_run_pressed() -> void:
	get_tree().change_scene_to_file(TOWN_SCENE)
