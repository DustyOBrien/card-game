# battle.gd
#
# The "brain" of the game. It is attached to the root node of
# scenes/battle.tscn and runs the whole fight:
#
#   1. Player turn: reset energy, clear block, draw 5 cards, play cards.
#   2. Player clicks "End Turn": the hand goes to the discard pile.
#   3. Enemy turn: the enemy attacks.
#   4. Back to step 1, until someone's HP hits 0.
extends Control

# preload() loads a file once, when the script loads. These are the
# "blueprints" we use to build the deck and the cards on screen.
const CARD_SCENE := preload("res://scenes/card.tscn")
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"

const HAND_SIZE := 5  # Cards drawn at the start of each turn.
const MAX_ENERGY := 3  # Energy you get each turn.
const ENEMY_MIN_ATTACK := 2
const ENEMY_MAX_ATTACK := 5
const DICE_SPIN_STEPS := 10  # How many fake numbers flash by before the real roll...
const DICE_SPIN_TIME := 0.05  # ...and how long each one shows (seconds).
const PREVIEW_COLOR := Color(1, 0.85, 0.3)  # Tint for numbers a dragged card would change.
const CRIT_COLOR := Color(1, 0.45, 0.25)  # The dice display when a die crits.
const TARGET_COLOR := Color(1.4, 1.2, 0.8)  # Enemy tint while you aim an attack at it. Above 1 = brighter.

# The three card piles. `Array[CardData]` means "a list that only holds CardData".
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var energy := 0
# Bonuses waiting for your next Attack / Defense card (from Rage and Brace).
var next_attack_bonus := 0
var next_defense_bonus := 0
var next_roll_bonus := 0  # Added to every die of the next card that rolls (Master of None).
var enemy_next_attack := 0  # Chosen at the start of your turn, shown as the "intent".
var game_over := false
var dragged_card: CardData = null  # The card being dragged right now, if any.
var busy := false  # true while dice are rolling, so you can't play two cards at once.
var newly_rolled: Array[CardData] = []  # Cards that just rolled on draw (to animate in the hand).

# References to nodes in the scene. $Name finds a direct child by name;
# %Name finds any node marked as a "unique name" anywhere in this scene.
@onready var player: Combatant = $Player
@onready var enemy: Combatant = $Enemy

@onready var enemy_name_label: Label = %EnemyNameLabel
@onready var enemy_hp_label: Label = %EnemyHpLabel
@onready var enemy_intent_label: Label = %EnemyIntentLabel
@onready var message_label: Label = %MessageLabel
@onready var player_hp_label: Label = %PlayerHpLabel
@onready var player_block_label: Label = %PlayerBlockLabel
@onready var energy_label: Label = %EnergyLabel
@onready var piles_label: Label = %PilesLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var hand_box: HBoxContainer = %Hand
@onready var game_over_screen: ColorRect = %GameOverScreen
@onready var result_label: Label = %ResultLabel
@onready var restart_button: Button = %RestartButton
@onready var play_zone: PlayZone = %PlayZone
@onready var play_zone_hint: Control = %PlayZoneHint
@onready var hint_label: Label = %HintLabel
@onready var enemy_box: Control = %EnemyBox
@onready var dice_label: Label = %DiceLabel
@onready var roll_on_draw_toggle: CheckButton = %RollOnDrawToggle
@onready var change_deck_button: Button = %ChangeDeckButton


func _ready() -> void:
	# Hook up signals: "when X happens, call this function".
	player.stats_changed.connect(update_ui)
	enemy.stats_changed.connect(update_ui)
	player.died.connect(_on_player_died)
	enemy.died.connect(_on_enemy_died)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	restart_button.pressed.connect(start_battle)
	change_deck_button.pressed.connect(_on_change_deck_pressed)
	play_zone.card_dropped.connect(_on_card_played)  # Dropping a card plays it.
	play_zone.enemy_target = enemy_box  # Attacks have to be dropped on this.
	roll_on_draw_toggle.button_pressed = GameState.roll_dice_on_draw
	roll_on_draw_toggle.toggled.connect(_on_roll_on_draw_toggled)

	start_battle()


# ---------------------------------------------------------------------------
# Battle flow
# ---------------------------------------------------------------------------

func start_battle() -> void:
	game_over = false
	game_over_screen.visible = false
	GameState.ensure_ready()
	player.max_hp = GameState.character_class.max_hp  # Each class has its own HP.
	player.reset()
	enemy.reset()

	next_attack_bonus = 0
	next_defense_bonus = 0
	next_roll_bonus = 0

	# The deck you built in the deck builder is waiting in GameState (an autoload,
	# see game_state.gd). ensure_ready() above gives you a starter deck if there
	# isn't one, e.g. when you press F6 to run only this scene.
	hand.clear()
	discard_pile.clear()
	# We give every card its OWN copy (card.duplicate()), so two Strikes can
	# each remember their own dice roll. map() runs the function on every card
	# and makes a new list; assign() copies that list into our typed array.
	# The deck you built stays untouched for the next battle.
	draw_pile.assign(GameState.deck.map(func(card: CardData) -> CardData: return card.duplicate()))
	draw_pile.shuffle()
	dice_label.text = ""

	message_label.text = "A %s appears!" % enemy.display_name
	start_player_turn()


func start_player_turn() -> void:
	player.clear_block()
	energy = MAX_ENERGY
	# Decide now what the enemy will do, so the player can plan around it.
	enemy_next_attack = randi_range(ENEMY_MIN_ATTACK, ENEMY_MAX_ATTACK)
	draw_cards(HAND_SIZE)
	end_turn_button.disabled = false


func _on_end_turn_pressed() -> void:
	if game_over or busy:
		return
	end_turn_button.disabled = true

	# Everything left in your hand goes to the discard pile.
	discard_pile.append_array(hand)
	hand.clear()
	refresh_hand()

	await enemy_turn()  # `await` waits for enemy_turn() to finish.
	if not game_over:
		start_player_turn()


func enemy_turn() -> void:
	message_label.text = "%s's turn..." % enemy.display_name
	# Pause for a moment so the player can see what's happening.
	# create_timer() makes a one-shot timer; we wait for its `timeout` signal.
	await get_tree().create_timer(0.6).timeout

	enemy.clear_block()
	player.take_damage(enemy_next_attack)
	if game_over:
		return  # The attack defeated the player.
	message_label.text = "%s attacks for %d!" % [enemy.display_name, enemy_next_attack]
	await get_tree().create_timer(0.4).timeout


# ---------------------------------------------------------------------------
# Cards
# ---------------------------------------------------------------------------

func draw_cards(amount: int) -> void:
	for i in amount:
		# Out of cards? Shuffle the discard pile to make a new draw pile.
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break  # No cards anywhere, stop drawing.
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			draw_pile.shuffle()
		var card: CardData = draw_pile.pop_back()
		card.roll_result = {}  # Forget any old roll.
		if GameState.roll_dice_on_draw and card.has_dice():
			card.roll_result = CardRoller.roll(card)  # Roll now; the dice show on the card.
			newly_rolled.append(card)
		hand.append(card)
	refresh_hand()


# Called when a card is dropped on the play zone (see play_zone.gd).
func _on_card_played(card: CardData) -> void:
	if busy or game_over or card.cost > energy:
		return

	energy -= card.cost
	message_label.text = ""
	# Take the card out of your hand FIRST, so effects like "discard 2 cards"
	# can't pick the card you're playing.
	hand.erase(card)

	# Check this BEFORE healing, otherwise healing could fill you up first.
	var was_at_full_hp := player.hp == player.max_hp

	# Dice cards: roll now (unless the card already rolled when it was drawn).
	var animate := not card.is_rolled()
	if card.has_dice() and not card.is_rolled():
		card.roll_result = CardRoller.roll(card)
	# Add the modifiers and check for crits (see card_roller.gd).
	var result := CardRoller.resolve(card, card.roll_result, get_bonuses())

	# Show the roll. `await` pauses here until the animation is done.
	if card.has_dice():
		busy = true
		refresh_hand()  # The card leaves your hand while the dice roll.
		await show_dice_roll(card, result, animate)
		busy = false
		if game_over:
			return
		next_roll_bonus = 0  # Used up by this roll.

	# Apply each effect the card has. A card can have several.
	for hit: int in result.hits:  # Each hit goes through the enemy's Block on its own.
		enemy.take_damage(hit)
	if card.has_type(CardData.CardType.ATTACK):
		next_attack_bonus = 0  # An Attack card uses up the waiting attack bonus (Rage).
	if result.block > 0:
		player.gain_block(result.block)
	if card.has_type(CardData.CardType.DEFENSE):
		next_defense_bonus = 0  # A Defense card uses up the waiting block bonus (Brace).
	if result.heal > 0:
		player.heal(result.heal)
	energy += card.energy + result.energy
	if card.lose_hp > 0:
		player.lose_hp(card.lose_hp)
	if card.draw_if_full_hp > 0 and was_at_full_hp:
		draw_cards(card.draw_if_full_hp)
	# Save bonuses for later cards.
	next_attack_bonus += card.next_attack_bonus
	next_defense_bonus += card.next_defense_bonus
	next_roll_bonus += card.next_roll_bonus
	if card.discard > 0:
		discard_random_cards(card.discard)
	if card.draw + result.draw > 0:
		draw_cards(card.draw + result.draw)
	if result.crits > 0:
		# e.g. "Critical! Draw 1 (x2)   Discarded Guard"
		var crit_text := "Critical! %s" % card.critical
		if result.crits > 1:
			crit_text += " (x%d)" % result.crits
		if message_label.text.begins_with("Discarded"):
			crit_text += "   " + message_label.text
		message_label.text = crit_text

	# The played card goes to the discard pile like everything else.
	card.roll_result = {}  # It rolls again next time.
	discard_pile.append(card)
	refresh_hand()


# Show a dice roll above your stats, e.g. "Strike   Attack: [3] + 1 crit = 4  CRIT!".
# With `animate`, the numbers spin for a moment first, like dice tumbling.
func show_dice_roll(card: CardData, result: Dictionary, animate: bool) -> void:
	dice_label.modulate.a = 1.0
	if animate:
		for i in DICE_SPIN_STEPS:
			# Show a random fake roll each step. Only the real one counts.
			var fake := CardRoller.resolve(card, CardRoller.roll(card), get_bonuses())
			dice_label.text = "%s   %s" % [card.card_name, "    ".join(fake.lines)]
			await get_tree().create_timer(DICE_SPIN_TIME).timeout
	dice_label.text = "%s   %s" % [card.card_name, "    ".join(result.lines)]
	# Crits are shown in red-gold so they stand out.
	dice_label.add_theme_color_override("font_color", CRIT_COLOR if result.crits > 0 else PREVIEW_COLOR)
	# A little "pop", then fade the text away after a while.
	dice_label.pivot_offset = dice_label.size / 2
	dice_label.scale = Vector2(1.4, 1.4) if result.crits > 0 else Vector2(1.25, 1.25)
	var tween := create_tween()
	tween.tween_property(dice_label, "scale", Vector2.ONE, 0.15)
	tween.tween_property(dice_label, "modulate:a", 0.0, 0.5).set_delay(2.5)
	await get_tree().create_timer(0.6 if result.crits > 0 else 0.45).timeout


func _on_roll_on_draw_toggled(on: bool) -> void:
	GameState.roll_dice_on_draw = on


# The bonuses waiting right now, in the form CardRoller.resolve() wants.
func get_bonuses() -> Dictionary:
	return {"roll": next_roll_bonus, "attack": next_attack_bonus, "defense": next_defense_bonus}


# What this card would do if played now, at worst and at best:
# [low result, high result]. Once the card has rolled, both are the same.
# Used for the previews, so they always match what playing it really does.
func get_outcomes(card: CardData) -> Array[Dictionary]:
	if card.is_rolled():
		var rolled := CardRoller.resolve(card, card.roll_result, get_bonuses())
		return [rolled, rolled]
	return [CardRoller.resolve(card, CardRoller.fixed_roll(card, false), get_bonuses()),
		CardRoller.resolve(card, CardRoller.fixed_roll(card, true), get_bonuses())]


# One number from both outcomes, e.g. outcome_range(outcomes, "block") -> Vector2i(1, 4)
func outcome_range(outcomes: Array[Dictionary], what: String) -> Vector2i:
	if what == "damage":
		return Vector2i(CardRoller.total_damage(outcomes[0]), CardRoller.total_damage(outcomes[1]))
	return Vector2i(outcomes[0][what], outcomes[1][what])


# The enemy's HP after taking `amount` damage. Enemy Block soaks up damage
# first, just like in Combatant.take_damage().
func enemy_hp_after(amount: int) -> int:
	return maxi(enemy.hp - maxi(amount - enemy.block, 0), 0)


# The enemy's HP after this card, as text: "18", or "14–17" before the dice roll.
func enemy_hp_after_text(card: CardData) -> String:
	var damage := outcome_range(get_outcomes(card), "damage")
	# Most damage leaves the LEAST HP, so the order flips.
	return range_text(Vector2i(enemy_hp_after(damage.y), enemy_hp_after(damage.x)))


# Vector2i(5, 5) -> "5",  Vector2i(4, 8) -> "4–8"
func range_text(values: Vector2i) -> String:
	if values.x == values.y:
		return str(values.x)
	return "%d–%d" % [values.x, values.y]


# The text in the banner above a dragged card, one effect per line.
func describe_card(card: CardData) -> String:
	var lines: Array[String] = []
	var outcomes := get_outcomes(card)
	if card.deals_damage():
		var damage_text := "Deal %s damage" % range_text(outcome_range(outcomes, "damage"))
		if card.attack.size() > 1:
			damage_text += " (%d hits)" % card.attack.size()
		lines.append(damage_text)
		lines.append("%s: %d → %s HP" % [enemy.display_name, enemy.hp, enemy_hp_after_text(card)])
	if outcomes[1].block > 0:
		lines.append("Gain %s Block" % range_text(outcome_range(outcomes, "block")))
	if outcomes[1].heal > 0:
		lines.append("Heal %s HP" % range_text(outcome_range(outcomes, "heal")))
	if card.energy > 0:
		lines.append("Gain %d Energy" % card.energy)
	if card.lose_hp > 0:
		lines.append("Lose %d HP" % card.lose_hp)
	if card.draw_if_full_hp > 0 and player.hp == player.max_hp:
		lines.append("Draw %d (full HP)" % card.draw_if_full_hp)
	if card.draw > 0:
		lines.append("Draw %d" % card.draw)
	if card.discard > 0:
		lines.append("Discard %d at random" % card.discard)
	if card.next_attack_bonus > 0:
		lines.append("Next Attack +%d" % card.next_attack_bonus)
	if card.next_defense_bonus > 0:
		lines.append("Next Defense +%d" % card.next_defense_bonus)
	if card.next_roll_bonus > 0:
		lines.append("Next roll +%d" % card.next_roll_bonus)
	if not card.critical.is_empty():
		if card.is_rolled() and outcomes[0].crits > 0:
			var times := " (x%d)" % outcomes[0].crits if outcomes[0].crits > 1 else ""
			lines.append("CRIT! %s%s" % [card.critical, times])  # Already rolled a crit.
		else:
			lines.append("Crit: %s" % card.critical)
	return "\n".join(lines)


# Godot tells every node when a drag starts and ends. We use that to show
# the drop zone and to preview the card's effect on the HP and Block numbers.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data = get_viewport().gui_get_drag_data()  # What's being dragged.
		if data is CardData:
			dragged_card = data
			play_zone_hint.visible = true
			if play_zone.needs_target(data):
				hint_label.text = "Drop on the %s to attack" % enemy.display_name
			else:
				hint_label.text = "Drop here to play"
			update_ui()
	elif what == NOTIFICATION_DRAG_END:
		dragged_card = null
		play_zone_hint.visible = false
		enemy_box.modulate = Color.WHITE
		update_ui()


# _process() runs every frame. While you aim an attack, light up the enemy
# when the mouse is over it, so you know letting go will hit.
func _process(_delta: float) -> void:
	if dragged_card != null and play_zone.needs_target(dragged_card):
		enemy_box.modulate = TARGET_COLOR if play_zone.is_over_enemy(get_global_mouse_position()) else Color.WHITE


# Throw `amount` random cards from the hand into the discard pile.
func discard_random_cards(amount: int) -> void:
	var discarded: Array[String] = []
	for i in amount:
		if hand.is_empty():
			break  # Nothing left to discard.
		var index := randi() % hand.size()  # A random position in the hand.
		var card: CardData = hand.pop_at(index)  # Remove it from the hand...
		discard_pile.append(card)  # ...and put it on the discard pile.
		discarded.append(card.card_name)
	if not discarded.is_empty():
		message_label.text = "Discarded " + ", ".join(discarded)


# Rebuild the row of card buttons so it matches the `hand` array.
func refresh_hand() -> void:
	# Remove the old card nodes. queue_free() deletes a node safely at the
	# end of the current frame.
	for child in hand_box.get_children():
		child.queue_free()
	# ...and create a fresh one for every card in the hand.
	for card_data in hand:
		var card: Card = CARD_SCENE.instantiate()
		hand_box.add_child(card)
		card.setup(card_data)
		card.draggable = true  # In battle you drag cards up to play them.
		# Cards rolled as they were drawn get a little dice animation.
		if newly_rolled.has(card_data):
			card.animate_roll()
	newly_rolled.clear()
	update_ui()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

# Copy all the numbers into the labels. Called whenever something changes.
func update_ui() -> void:
	enemy_name_label.text = enemy.display_name
	enemy_hp_label.text = "HP %d / %d" % [enemy.hp, enemy.max_hp]
	if enemy.block > 0:
		enemy_hp_label.text += "   Block %d" % enemy.block
	enemy_intent_label.text = "Intends to attack for %d" % enemy_next_attack

	player_hp_label.text = "HP %d / %d" % [player.hp, player.max_hp]
	player_block_label.text = "Block %d" % player.block
	# Show waiting Rage / Brace bonuses next to your Block.
	if next_attack_bonus > 0:
		player_block_label.text += "   Next Attack +%d" % next_attack_bonus
	if next_defense_bonus > 0:
		player_block_label.text += "   Next Defense +%d" % next_defense_bonus
	if next_roll_bonus > 0:
		player_block_label.text += "   Next roll +%d" % next_roll_bonus
	energy_label.text = "Energy %d / %d" % [energy, MAX_ENERGY]
	piles_label.text = "Draw pile %d   Discard %d" % [draw_pile.size(), discard_pile.size()]

	# Grey out cards you can't afford, and tell each card what it would do.
	for card: Card in hand_box.get_children():
		card.disabled = game_over or busy or card.card_data.cost > energy
		card.preview_text = describe_card(card.card_data)

	show_drag_preview()


# While a card is being dragged, show "before -> after" on the numbers it
# would change, in gold, so you can see what will happen before you drop it.
func show_drag_preview() -> void:
	var labels: Array[Label] = [enemy_hp_label, player_hp_label, player_block_label, energy_label]
	for label in labels:
		label.modulate = Color.WHITE  # Back to normal colours.
	var card := dragged_card
	if card == null:
		return

	var outcomes := get_outcomes(card)
	if card.deals_damage():
		enemy_hp_label.text = "HP %d → %s / %d" % [enemy.hp, enemy_hp_after_text(card), enemy.max_hp]
		enemy_hp_label.modulate = PREVIEW_COLOR
	if outcomes[1].heal > 0 or card.lose_hp > 0:
		var heal := outcome_range(outcomes, "heal")
		var low := maxi(mini(player.hp + heal.x, player.max_hp) - card.lose_hp, 0)
		var high := maxi(mini(player.hp + heal.y, player.max_hp) - card.lose_hp, 0)
		player_hp_label.text = "HP %d → %s / %d" % [player.hp, range_text(Vector2i(low, high)), player.max_hp]
		player_hp_label.modulate = PREVIEW_COLOR
	if outcomes[1].block > 0:
		var block := outcome_range(outcomes, "block")
		player_block_label.text = "Block %d → %s" % [player.block, range_text(Vector2i(player.block + block.x, player.block + block.y))]
		player_block_label.modulate = PREVIEW_COLOR
	var energy_after := energy - card.cost + card.energy
	if energy_after != energy:
		energy_label.text = "Energy %d → %d / %d" % [energy, energy_after, MAX_ENERGY]
		energy_label.modulate = PREVIEW_COLOR


func _on_enemy_died() -> void:
	end_battle("Victory!")


func _on_player_died() -> void:
	end_battle("Defeat...")


# Go back to the deck builder. Your deck is still in GameState, so it's kept.
func _on_change_deck_pressed() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)


func end_battle(result: String) -> void:
	game_over = true
	end_turn_button.disabled = true
	message_label.text = ""
	result_label.text = result
	game_over_screen.visible = true
	update_ui()
