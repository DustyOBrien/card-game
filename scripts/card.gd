# card.gd
#
# The script for ONE card on screen (scenes/card.tscn).
# The card is a Button, so Godot already handles hovering and clicking.
#
# A card works in one of two ways:
#   - In the deck builder you CLICK it: it emits `clicked` with its CardData.
#   - In battle you DRAG it (draggable = true): see _get_drag_data() below.
#     (A click in battle only matters when Gamble asks you to pick a card.)
# Either way, the card doesn't know the rules of the game; the screen that
# owns it decides what clicking or playing it actually does.
class_name Card
extends Button

signal clicked(card_data: CardData)

const PREVIEW_LINE_HEIGHT := 26  # Height of one line in the drag preview banner.
const PREVIEW_SCALE := 0.8  # The dragged card is a bit smaller, so it hides less of the screen.
const HOVER_SCALE := 1.35  # How big a card in your hand gets when you point at it.
const HOVER_TIME := 0.1  # Seconds the zoom takes.
const ICON_SIZE := 24  # Width and height of an effect symbol, in pixels.
const DIE_SIZE := 32.0  # The little dice on a card in your hand.
const ROLL_STEPS := 8  # Random faces that flash by while a card's dice tumble...
const ROLL_STEP_TIME := 0.06  # ...and how long each one shows (seconds).
const ROLL_TIME := ROLL_STEPS * ROLL_STEP_TIME + 0.2  # How long roll_dice() takes, roughly.

# The symbols shown on cards instead of rules text.
# preload() loads a file once, when this script loads (the path must be fixed text).
const ICONS := {
	"attack": preload("res://icons/attack.svg"),
	"block": preload("res://icons/block.svg"),
	"draw": preload("res://icons/draw.svg"),
	"discard": preload("res://icons/discard.svg"),
	"heal": preload("res://icons/heal.svg"),
}

var card_data: CardData
var draggable := false  # true in battle: drag to play instead of clicking.
# What playing this card would do right now, e.g. "Deal 9 damage".
# The battle fills this in, because only it knows about bonuses like Rage.
var preview_text := ""
var zoom_tween: Tween  # The running hover zoom animation, if any.

# @onready means "fill this in when the node is ready", because child nodes
# don't exist yet when the script is first created.
# The % symbol finds a child node marked "Access as Unique Name" in the editor.
@onready var cost_label: Label = %CostLabel
@onready var school_label: Label = %SchoolLabel
@onready var name_label: Label = %NameLabel
@onready var type_label: Label = %TypeLabel
@onready var icon_row: HFlowContainer = %IconRow  # Symbol + number for each effect.
@onready var effect_label: Label = %EffectLabel  # Text for effects with no symbol.
@onready var rarity_label: Label = %RarityLabel
@onready var keyword_label: Label = %KeywordLabel  # "Wild", "Vanish"...
@onready var dice_row: HBoxContainer = %DiceRow  # The card's dice, once it has rolled.


func _ready() -> void:
	# `pressed` is a signal every Button has. Connect it to our function.
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# Called by the battle script right after the card is added to the hand.
func setup(data: CardData) -> void:
	card_data = data
	cost_label.text = str(data.cost)
	school_label.text = data.get_school_text()
	name_label.text = data.card_name
	fit_name()
	type_label.text = data.get_type_text()
	if data.is_class_card():
		# e.g. "Attack - Knight", so you can see who's allowed to use it.
		type_label.text += " - " + ", ".join(data.class_only)
	show_effects(data)
	rarity_label.text = data.get_rarity_text()
	# Leveled-up cards say so: "Common · Lv 2". (Every copy of a card shares
	# its level, so we ask GameState by name.)
	var level := maxi(data.level, GameState.card_level(data))
	if level > 1:
		rarity_label.text += "  ·  Lv %d" % level
	rarity_label.add_theme_color_override("font_color", CardData.RARITY_COLORS[data.rarity])
	# self_modulate tints only the card background, not the text on it.
	self_modulate = data.color
	keyword_label.text = data.get_keyword_text()
	keyword_label.visible = not keyword_label.text.is_empty()
	show_roll()


# Long names like "Master of None" would wrap onto two lines and push the
# card's bottom off. Shrink the font until the name fits on one line.
func fit_name() -> void:
	var font := name_label.get_theme_font("font")
	var width := custom_minimum_size.x - 20  # The card minus its side margins.
	for size in [20, 18, 16, 14]:
		name_label.add_theme_font_size_override("font_size", size)
		if font.get_string_size(card_data.card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			return


# Instead of a sentence like "Deal 4 Damage and Gain 2 Block", show a symbol
# with a number for each effect: [sword] 4  [shield] 2. Much quicker to read.
func show_effects(data: CardData) -> void:
	for child in icon_row.get_children():
		child.queue_free()
	if data.deals_damage():
		add_icon("attack", data.get_attack_text())  # e.g. [sword] d3, or d3 x2 for two hits
	if not data.block.is_empty():
		add_icon("block", data.get_block_text())
	if data.draw > 0:
		add_icon("draw", str(data.draw))
	if data.discard > 0:
		add_icon("discard", str(data.discard))
	if not data.heal.is_empty():
		add_icon("heal", data.get_heal_text())  # e.g. "d3-1" with a Heal Modifier.
	# Anything without a symbol (Rage, Energy...) still gets a few words,
	# and so does what a Critical does.
	var lines := data.get_extra_text()
	if not data.critical.is_empty():
		lines += ("\n" if not lines.is_empty() else "") + "Crit: " + data.critical
	effect_label.text = lines
	effect_label.visible = not effect_label.text.is_empty()


# One symbol with its number next to it, built in code.
func add_icon(icon_name: String, amount: String) -> void:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let the card get the mouse.

	var icon := TextureRect.new()
	icon.texture = ICONS[icon_name]
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # Shrink the 64px image to ICON_SIZE.
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)

	var label := Label.new()
	label.text = amount
	# Dice text like "2d6+1" is longer, so it's a bit smaller.
	label.add_theme_font_size_override("font_size", 16 if amount.length() > 3 else 22)
	# A dark outline keeps the number readable on every card colour.
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)

	icon_row.add_child(chip)


# A dice card that rolled when you drew it shows its dice right on the card,
# so you can plan with them. A gold die is a Critical.
func show_roll() -> void:
	for child in dice_row.get_children():
		dice_row.remove_child(child)  # Take it out now (queue_free() waits for the end of the frame).
		child.queue_free()
	dice_row.visible = card_data.is_rolled()
	if not card_data.is_rolled():
		return
	var formulas := card_data.get_formulas()
	for key in formulas:
		var sides: int = Dice.parse(formulas[key]).get("sides", 0)
		for value: int in card_data.roll_result.get(key, []):
			var die := DieView.new(DIE_SIZE)
			die.sides = sides
			die.show_value(value, value >= sides)  # The top number is always a crit.
			dice_row.add_child(die)


# Bonuses (like Master of None's +1) can turn a lower die into a crit. The
# battle works that out with CardRoller.resolve() and passes in its "rolls",
# and we light up the matching dice.
func show_crits(rolls: Array) -> void:
	var crits: Array[bool] = []
	for roll: Dictionary in rolls:
		crits.append_array(roll.crit_dice)
	var dice := dice_row.get_children()
	for i in mini(dice.size(), crits.size()):
		var die: DieView = dice[i]
		if die.is_crit != crits[i]:
			die.show_value(die.value, crits[i])


# The card was just drawn and rolled: tumble its dice, then land them on
# the real roll with a little bounce. Call it with `await` to wait for it.
# `await` pauses this function (not the whole game) until the timer finishes.
func roll_dice() -> void:
	show_roll()  # Make the dice (already showing the real roll)...
	var dice := dice_row.get_children()
	var landed: Array = []  # ...and remember what they really show.
	for die: DieView in dice:
		landed.append([die.value, die.is_crit])
	for step in ROLL_STEPS:
		for die: DieView in dice:
			die.show_value(randi_range(1, die.sides))
			die.rotation = randf_range(-0.7, 0.7)  # In radians: about ±40°.
		await get_tree().create_timer(ROLL_STEP_TIME).timeout
		if not is_inside_tree():
			return  # The hand was rebuilt while we waited; this card is gone.
	for i in dice.size():
		var die: DieView = dice[i]
		die.show_value(landed[i][0], landed[i][1])
		die.rotation = 0.0
		die.scale = Vector2.ONE * 1.4
		# TRANS_BACK overshoots a little before settling: a bouncy landing.
		create_tween().tween_property(die, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


# A click (pressing and letting go without dragging). The deck builder adds
# the card; in battle it's only used to pick a card for Gamble.
func _on_pressed() -> void:
	clicked.emit(card_data)


# ---------------------------------------------------------------------------
# Hover zoom (battle only)
# ---------------------------------------------------------------------------

func _on_mouse_entered() -> void:
	# Don't zoom in the deck builder, or while another card is being dragged.
	if draggable and not get_viewport().gui_is_dragging():
		set_zoom(HOVER_SCALE, true)


func _on_mouse_exited() -> void:
	set_zoom(1.0, true)


func set_zoom(amount: float, animate: bool) -> void:
	# pivot_offset is the point the card grows from: its bottom middle, so it
	# grows UP out of your hand instead of off the bottom of the screen.
	pivot_offset = Vector2(size.x / 2, size.y)
	# z_index draws the zoomed card on top of its neighbours.
	z_index = 1 if amount > 1.0 else 0
	if zoom_tween:
		zoom_tween.kill()  # Stop a zoom that's still running, so they don't fight.
	if animate:
		# A Tween changes a value smoothly over time: here, scale over 0.1 s.
		zoom_tween = create_tween()
		zoom_tween.tween_property(self, "scale", Vector2(amount, amount), HOVER_TIME)
	else:
		scale = Vector2(amount, amount)


# ---------------------------------------------------------------------------
# Drag and drop
# ---------------------------------------------------------------------------
# Godot has drag and drop built in. It takes three functions:
#   1. _get_drag_data()  on the thing you drag     (this card): "what am I carrying?"
#   2. _can_drop_data()  on the place you drop it  (play_zone.gd): "can I take it?"
#   3. _drop_data()      on the place you drop it  (play_zone.gd): "here it is!"
# Godot calls them for us when the mouse is held down and moved.

# Called when you start dragging this card. Whatever we return is the
# "data" being carried (our CardData). Returning null means "can't drag".
func _get_drag_data(at_position: Vector2) -> Variant:
	if not draggable or disabled:
		return null  # Not in battle, or we can't afford it.
	# The drag preview is what follows the mouse. We build one that looks
	# like this card, with a banner on top saying what will happen.
	set_zoom(1.0, false)  # Un-zoom first, so the preview copy isn't zoomed too.
	set_drag_preview(make_drag_preview(at_position))
	modulate.a = 0.35  # Fade the card left behind in the hand.
	return card_data


# Godot sends every node a notification when a drag ends (dropped or not).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate.a = 1.0


func make_drag_preview(at_position: Vector2) -> Control:
	var lines := preview_text.split("\n")
	var banner_height := lines.size() * PREVIEW_LINE_HEIGHT + 12

	# A plain Control holds the banner and card, so we can move both together.
	var holder := Control.new()

	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.92)
	style.border_color = Color(1, 0.85, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	banner.add_theme_stylebox_override("panel", style)
	banner.custom_minimum_size = Vector2(0, banner_height)  # As wide as its text.
	var banner_label := Label.new()
	banner_label.text = preview_text
	banner_label.add_theme_font_size_override("font_size", 18)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)
	holder.add_child(banner)

	# duplicate() makes a copy of this card, labels and colours included.
	var copy: Card = duplicate()
	copy.disabled = false
	copy.size = size
	copy.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	holder.add_child(copy)

	# Keep the card under the mouse where you grabbed it, with the banner to
	# its right (above would go off the screen when you aim at the enemy).
	copy.position = -at_position * PREVIEW_SCALE
	banner.position = copy.position + Vector2(size.x * PREVIEW_SCALE + 8, 0)
	return holder
