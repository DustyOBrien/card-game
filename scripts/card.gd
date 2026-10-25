# card.gd
#
# The script for ONE card on screen (scenes/card.tscn).
# The card is a Button, so Godot already handles hovering and clicking.
#
# A card works in one of two ways:
#   - In the deck builder you CLICK it: it emits `clicked` with its CardData.
#   - In battle you DRAG it (draggable = true): see _get_drag_data() below.
# Either way, the card doesn't know the rules of the game; the screen that
# owns it decides what clicking or playing it actually does.
class_name Card
extends Button

signal clicked(card_data: CardData)

const PREVIEW_LINE_HEIGHT := 26  # Height of one line in the drag preview banner.
const PREVIEW_SCALE := 0.8  # The dragged card is a bit smaller, so it hides less of the screen.
const HOVER_SCALE := 1.35  # How big a card in your hand gets when you point at it.
const HOVER_TIME := 0.1  # Seconds the zoom takes.

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
@onready var effect_label: Label = %EffectLabel
@onready var rarity_label: Label = %RarityLabel


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
	type_label.text = data.get_type_text()
	if data.is_class_card():
		# e.g. "Attack - Knight", so you can see who's allowed to use it.
		type_label.text += " - " + ", ".join(data.class_only)
	effect_label.text = data.effect
	rarity_label.text = data.get_rarity_text()
	rarity_label.add_theme_color_override("font_color", CardData.RARITY_COLORS[data.rarity])
	# self_modulate tints only the card background, not the text on it.
	self_modulate = data.color


func _on_pressed() -> void:
	if not draggable:
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
