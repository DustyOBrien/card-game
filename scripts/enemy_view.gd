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
# Its INTENT: the move it picked at the start of your turn, so you can plan.
var move: EnemyMove
var hit_rolls: Array[int] = []  # The damage of each hit, rolled with the move (before Strength).
var splitting := false  # true = its intent is to Split (it's at half HP or less).
var move_index := -1  # For IN_ORDER enemies: which move it's on.
var last_move: EnemyMove  # So a move can't be picked too many times in a row...
var in_a_row := 0  # ...this many times so far.

var sprite: TextureRect
var name_label: Label
var health_bar: HealthBar
var intent_label: Label
var idle_tween: Tween  # The endless "breathing" wobble.


# Build everything for this enemy. Call it right after EnemyView.new().
# `hp` is for enemies that come from a split: they keep the HP that was left.
func setup(enemy_data: EnemyData, hp: int = 0) -> void:
	data = enemy_data
	alignment = BoxContainer.ALIGNMENT_END  # Line enemies up by their feet.
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # The play zone handles the mouse.

	combatant = Combatant.new()
	combatant.display_name = data.display_name
	combatant.max_hp = data.max_hp
	combatant.armor = data.armor
	if hp > 0:
		combatant.max_hp = hp
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


# Smaller everything, so 4 enemies fit next to the Battle Log.
func set_compact(compact: bool) -> void:
	var scale_by := 0.75 if compact else 1.0
	sprite.custom_minimum_size = data.sprite_size * scale_by
	sprite.pivot_offset = Vector2(sprite.custom_minimum_size.x / 2, sprite.custom_minimum_size.y)
	health_bar.custom_minimum_size.x = 130 if compact else 180
	name_label.add_theme_font_size_override("font_size", 20 if compact else 26)
	intent_label.add_theme_font_size_override("font_size", 14 if compact else 17)
	# Long intents ("Block 3 + Shield allies 3") wrap instead of widening the enemy.
	intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact else TextServer.AUTOWRAP_OFF
	intent_label.custom_minimum_size.x = 130 if compact else 0


# How wide it is at full size, for the battle to check if the row fits.
func full_width() -> float:
	return maxf(data.sprite_size.x, 180)


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


# Pick this turn's move, so the player can plan around it.
func choose_move() -> void:
	if should_split():
		splitting = true
		move = null
		refresh()
		return
	var moves := data.moves if not data.moves.is_empty() else [data.default_move()]
	if data.move_order == EnemyData.MoveOrder.IN_ORDER:
		move_index = (move_index + 1) % moves.size()
		move = moves[move_index]
	else:
		move = _pick_by_weight(moves)
	in_a_row = in_a_row + 1 if move == last_move else 1
	last_move = move
	# Roll each hit's damage now, so the intent shows the real number.
	hit_rolls.clear()
	if move.attacks():
		for i in maxi(move.hits, 1):
			hit_rolls.append(randi_range(move.attack_min, move.attack_max))
	refresh()


# A random move: a move with weight 2 is twice as likely as one with weight 1.
# Moves that hit their Max In A Row are left out this time.
func _pick_by_weight(moves: Array) -> EnemyMove:
	var allowed := moves.filter(func(m: EnemyMove) -> bool:
		return not (m == last_move and m.max_in_a_row > 0 and in_a_row >= m.max_in_a_row))
	if allowed.is_empty():
		allowed = moves
	var total := 0
	for m: EnemyMove in allowed:
		total += maxi(m.weight, 1)
	var roll := randi_range(1, total)
	for m: EnemyMove in allowed:
		roll -= maxi(m.weight, 1)
		if roll <= 0:
			return m
	return allowed[-1]


# Splitting enemies (the Big Slime) split once they're down to half HP.
func should_split() -> bool:
	return not data.split_into.is_empty() and is_alive() and combatant.hp * 2 <= combatant.max_hp


# The damage of each hit right now: the roll plus its Strength.
func hit_damages() -> Array[int]:
	var damages: Array[int] = []
	for roll in hit_rolls:
		damages.append(maxi(roll + combatant.strength, 0))
	return damages


# The intent as text, e.g. "Attack 3 x2", "Attack 4 + Block 3", "Strength +1".
func intent_text() -> String:
	if splitting:
		return "Split!"
	if move == null:
		return ""
	var parts: Array[String] = []
	if move.attacks():
		var damages := hit_damages()
		parts.append("Attack %d" % damages[0] + (" x%d" % damages.size() if damages.size() > 1 else ""))
	if move.block > 0:
		parts.append("Block %d" % move.block)
	if move.ally_block > 0:
		parts.append("Shield allies %d" % move.ally_block)
	if move.strength > 0:
		parts.append("Strength +%d" % move.strength)
	if move.ally_strength > 0:
		parts.append("All Strength +%d" % move.ally_strength)
	if move.heal > 0:
		parts.append("Heal %d" % move.heal)
	if not move.summon.is_empty():
		parts.append("Summon %s" % move.summon)
	return " + ".join(parts) if not parts.is_empty() else move.move_name


const INTENT_COLORS := {
	"attack": Color(1, 0.6, 0.5),
	"block": Color(0.6, 0.8, 1),
	"buff": Color(1, 0.85, 0.4),
	"summon": Color(0.85, 0.65, 1),
	"split": Color(0.6, 1, 0.6),
}


# Copy the numbers onto the screen.
func refresh() -> void:
	health_bar.set_values(combatant.hp, combatant.max_hp, combatant.block)
	if not is_alive():
		intent_label.text = "Defeated"
		return
	if not splitting and should_split():
		splitting = true  # Hit down to half: it will split on its turn instead.
	intent_label.text = intent_text()
	var kind := "split" if splitting else (move.kind() if move else "attack")
	intent_label.add_theme_color_override("font_color", INTENT_COLORS[kind])
	# Lasting stats on a second line: "Strength 2 · Armor 3".
	var stats: Array[String] = []
	if combatant.strength != 0:
		stats.append("Strength %d" % combatant.strength)
	if combatant.armor > 0:
		stats.append("Armor %d" % combatant.armor)
	if not stats.is_empty():
		intent_label.text += "\n" + "  ·  ".join(stats)


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


# A move that isn't an attack (Block, a buff...): a quick glow in that colour.
func show_glow(color: Color) -> void:
	sprite.modulate = color
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.4)


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
