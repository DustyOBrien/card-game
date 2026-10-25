# enemy_view.gd
#
# One enemy on the battle screen: its picture, name, health bar and intent,
# stacked top to bottom. The battle makes one of these for every enemy in the
# fight (see battle.gd, start_battle()) and puts them side by side.
#
# The numbers (HP, Block) live in a Combatant, just like the player's. This
# script only draws them and plays the animations.
class_name EnemyView
extends VBoxContainer

const TARGET_COLOR := Color(1.4, 1.2, 0.8)  # Tint while you aim an attack at it. Above 1 = brighter.
const OUTLINE := Color(0.05, 0.05, 0.08)

var data: EnemyData
var combatant: Combatant  # HP and Block. Its `died` signal tells the battle.
var next_attack := 0  # Chosen at the start of your turn, shown as the "intent".

var sprite: TextureRect
var name_label: Label
var health_bar: HealthBar
var intent_label: Label
var idle_tween: Tween  # The endless "breathing" wobble.


# Build everything for this enemy. Call it right after EnemyView.new().
func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	alignment = BoxContainer.ALIGNMENT_END  # Line enemies up by their feet.
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The play zone handles the mouse.

	combatant = Combatant.new()
	combatant.display_name = data.display_name
	combatant.max_hp = data.max_hp
	combatant.armor = data.armor
	add_child(combatant)  # A plain Node child: containers ignore it for layout.

	sprite = TextureRect.new()
	sprite.texture = data.texture
	sprite.custom_minimum_size = data.sprite_size
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Squash and stretch from its feet, not its top-left corner.
	sprite.pivot_offset = Vector2(data.sprite_size.x / 2, data.sprite_size.y)
	add_child(sprite)

	name_label = _make_label(data.display_name, 26, data.name_color)
	add_child(name_label)

	health_bar = HealthBar.new()
	health_bar.custom_minimum_size = Vector2(180, 24)
	health_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_bar)

	intent_label = _make_label("", 17, Color(1, 0.6, 0.5))
	add_child(intent_label)
	refresh()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 7)
	return label


func is_alive() -> bool:
	return combatant.hp > 0


# Pick this turn's attack, so the player can plan around it.
func choose_attack() -> void:
	next_attack = randi_range(data.attack_min, data.attack_max)
	refresh()


# Copy the numbers onto the screen.
func refresh() -> void:
	health_bar.set_values(combatant.hp, combatant.max_hp, combatant.block)
	if not is_alive():
		intent_label.text = "Defeated"
		return
	intent_label.text = "Attacks for %d" % next_attack
	if combatant.armor > 0:
		intent_label.text += "  (Armor %d)" % combatant.armor


# Its HP after taking `amount` damage. Block soaks up damage first, just like
# in Combatant.take_damage().
func hp_after(amount: int) -> int:
	return maxi(combatant.hp - maxi(amount - combatant.block, 0), 0)


# Light up while you aim at it (or back to normal).
func set_targeted(targeted: bool) -> void:
	modulate = TARGET_COLOR if targeted and is_alive() else Color.WHITE


# Is this point on the screen on (or near) this enemy?
func has_point(screen_point: Vector2, margin: float) -> bool:
	return is_alive() and get_global_rect().grow(margin).has_point(screen_point)


# ---------------------------------------------------------------------------
# Animations (all Tweens: "change this value to that, over this many seconds")
# ---------------------------------------------------------------------------

# A slow squash and stretch, forever, so it looks alive. Each enemy starts at
# a slightly different speed so a group doesn't bob in perfect step.
func start_idle() -> void:
	if idle_tween:
		idle_tween.kill()
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	var time := randf_range(0.6, 0.8)
	idle_tween = create_tween().set_loops()  # set_loops() with no number = repeat forever.
	idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # Smooth, like breathing.
	idle_tween.tween_property(sprite, "scale", Vector2(1.05, 0.94), time)
	idle_tween.tween_property(sprite, "scale", Vector2.ONE, time)


# Hit! Flash red and wobble.
func show_hurt() -> void:
	if not is_alive():
		return  # show_defeated() is already playing.
	sprite.modulate = Color(1, 0.35, 0.35)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.3)
	# A second tween runs at the same time as the first.
	var wobble := create_tween()
	wobble.tween_property(sprite, "rotation", -0.12, 0.05)
	wobble.tween_property(sprite, "rotation", 0.12, 0.08)
	wobble.tween_property(sprite, "rotation", 0.0, 0.05)


# Its turn: a little hop towards you.
func show_attack() -> void:
	var hop := create_tween()
	hop.tween_property(sprite, "position:y", sprite.position.y + 14, 0.08)
	hop.tween_property(sprite, "position:y", sprite.position.y, 0.12)


# Defeated: squish flat and fade away. The name and bar fade out a bit too.
func show_defeated() -> void:
	if idle_tween:
		idle_tween.kill()
	modulate = Color.WHITE
	var tween := create_tween().set_parallel()  # set_parallel(): all changes at once.
	tween.tween_property(sprite, "scale", Vector2(1.4, 0.1), 0.35).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.35)
	tween.tween_property(name_label, "modulate:a", 0.4, 0.35)
	tween.tween_property(health_bar, "modulate:a", 0.4, 0.35)
