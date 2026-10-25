# dice_tray.gd
#
# The panel in the middle of the battle where dice tumble and land when a card
# rolls. It shows each roll of the card as a group, for example Multi Strike:
#
#      Hit 1 · d3            Hit 2 · d3
#      [3] + 1  = 4          [1] + 1  = 2
#        CRIT!
#
# Everything inside the panel is built in code each time, from the "rolls"
# that CardRoller.resolve() returns.
class_name DiceTray
extends PanelContainer

const TUMBLE_STEPS := 10  # How many random faces flash by while the dice tumble...
const TUMBLE_TIME := 0.05  # ...and how long each one shows (seconds).
const LAND_GAP := 0.15  # Pause between one die landing and the next.
const SHOW_TIME := 2.5  # Seconds the result stays before fading out.
const KIND_COLORS := {
	"attack": Color(1.0, 0.55, 0.45),
	"block": Color(0.55, 0.75, 1.0),
	"heal": Color(0.5, 0.9, 0.55),
}
const CRIT_COLOR := Color(1.0, 0.6, 0.2)

var title_label: Label
var groups_box: HBoxContainer
var fade_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # Never get in the way of dropping cards.
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.09, 0.9)
	style.border_color = Color(1, 0.85, 0.3, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)

	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)
	title_label = _make_label("", 20, Color(1, 0.85, 0.3))
	layout.add_child(title_label)
	groups_box = HBoxContainer.new()
	groups_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groups_box.alignment = BoxContainer.ALIGNMENT_CENTER
	groups_box.add_theme_constant_override("separation", 28)
	layout.add_child(groups_box)


# Show a card's rolls. With `animate`, the dice tumble first, then land one by
# one. Without it (the card rolled when drawn), they appear straight away.
# Call it with `await`: it returns once every die has landed.
func play(card_name: String, rolls: Array, animate: bool) -> void:
	if fade_tween:
		fade_tween.kill()  # A new roll replaces one that's still fading.
	modulate.a = 1.0
	visible = true
	title_label.text = card_name
	for child in groups_box.get_children():
		child.queue_free()

	# Build one group per roll, and remember every die and its result.
	var dice: Array[DieView] = []
	var results: Array = []  # [value, is_crit] for each die, in the same order.
	var totals: Array[Label] = []
	for roll: Dictionary in rolls:
		var group := _make_group(roll, dice, results)
		groups_box.add_child(group)
		totals.append(group.get_meta("total_label"))

	if animate:
		await _tumble(dice)
	# Land each die in turn: the real number, a little bounce, and a glow if it crit.
	for i in dice.size():
		_land(dice[i], results[i][0], results[i][1])
		if animate:
			await get_tree().create_timer(LAND_GAP).timeout
	for label in totals:
		label.visible = true  # "= 4" appears once its dice are down.

	# Leave the result up for a while, then fade it away. This runs by itself;
	# play() doesn't wait for it, so the card's effects happen straight away.
	fade_tween = create_tween()
	fade_tween.tween_interval(SHOW_TIME)
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	fade_tween.tween_callback(hide)
	await get_tree().create_timer(0.3).timeout


# One roll: its name, the dice, the modifier and the total.
func _make_group(roll: Dictionary, dice: Array[DieView], results: Array) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.alignment = BoxContainer.ALIGNMENT_CENTER
	var color: Color = KIND_COLORS.get(roll.kind, Color.WHITE)
	group.add_child(_make_label("%s · d%d" % [roll.name, roll.sides], 15, color))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	group.add_child(row)
	for i in roll.dice.size():
		var die := DieView.new()
		die.sides = roll.sides
		row.add_child(die)
		dice.append(die)
		results.append([roll.dice[i], roll.crit_dice[i]])
	if roll.modifier != 0:
		row.add_child(_make_label("%+d" % roll.modifier, 22, Color.WHITE))  # e.g. "+1"
	if roll.crit_bonus > 0:
		row.add_child(_make_label("+%d crit" % roll.crit_bonus, 18, CRIT_COLOR))

	var total_text := "= %d" % roll.total
	if roll.crits > 0:
		total_text += "  CRIT!" if roll.crits == 1 else "  CRIT x%d!" % roll.crits
	var total := _make_label(total_text, 24, CRIT_COLOR if roll.crits > 0 else Color.WHITE)
	total.visible = false
	group.add_child(total)
	group.set_meta("total_label", total)  # set_meta() lets us tag a node with extra data.
	return group


# Spin the dice and flash random numbers, like dice bouncing on a table.
func _tumble(dice: Array[DieView]) -> void:
	for step in TUMBLE_STEPS:
		for die in dice:
			die.show_value(randi_range(1, die.sides))
			die.rotation = randf_range(-0.7, 0.7)  # In radians: about ±40°.
			die.scale = Vector2.ONE * randf_range(0.85, 1.1)
		await get_tree().create_timer(TUMBLE_TIME).timeout


func _land(die: DieView, value: int, is_crit: bool) -> void:
	die.show_value(value, is_crit)
	die.rotation = 0.0
	die.scale = Vector2.ONE * (1.45 if is_crit else 1.25)
	var tween := create_tween()
	# TRANS_BACK overshoots a little before settling: a bouncy landing.
	tween.tween_property(die, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
