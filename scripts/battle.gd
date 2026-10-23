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
const ENEMY_MIN_ATTACK := 6
const ENEMY_MAX_ATTACK := 11

# The three card piles. `Array[CardData]` means "a list that only holds CardData".
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var energy := 0
# Bonuses waiting for your next Attack / Defense card (from Rage and Brace).
var next_attack_bonus := 0
var next_defense_bonus := 0
var enemy_next_attack := 0  # Chosen at the start of your turn, shown as the "intent".
var game_over := false

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

	start_battle()


# ---------------------------------------------------------------------------
# Battle flow
# ---------------------------------------------------------------------------

func start_battle() -> void:
	game_over = false
	game_over_screen.visible = false
	player.reset()
	enemy.reset()

	next_attack_bonus = 0
	next_defense_bonus = 0

	# The deck you built in the deck builder is waiting in GameState (an autoload,
	# see game_state.gd). If it's empty, e.g. you pressed F6 to run only this
	# scene, use the starter deck instead.
	if GameState.deck.is_empty():
		GameState.deck = GameState.make_default_deck()
	hand.clear()
	discard_pile.clear()
	# duplicate() makes a COPY of the list. We shuffle and draw from the copy,
	# so the deck you built stays the same for the next battle.
	draw_pile = GameState.deck.duplicate()
	draw_pile.shuffle()

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
	if game_over:
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
		hand.append(draw_pile.pop_back())
	refresh_hand()


# Called when a card in the hand emits its `played` signal.
func _on_card_played(card: CardData) -> void:
	if game_over or card.cost > energy:
		return

	energy -= card.cost
	# Take the card out of your hand FIRST, so effects like "discard 2 cards"
	# can't pick the card you're playing.
	hand.erase(card)

	# Check this BEFORE healing, otherwise healing could fill you up first.
	var was_at_full_hp := player.hp == player.max_hp

	# Apply each effect the card has. A card can have several (Guarded Blow
	# deals damage AND gives Block).
	if card.damage > 0:
		var damage := card.damage
		# Rage: an Attack card uses up the waiting attack bonus.
		if card.has_type(CardData.CardType.ATTACK):
			damage += next_attack_bonus
			next_attack_bonus = 0
		enemy.take_damage(damage)
	if card.block > 0:
		var block := card.block
		# Brace: a Defense card uses up the waiting block bonus.
		if card.has_type(CardData.CardType.DEFENSE):
			block += next_defense_bonus
			next_defense_bonus = 0
		player.gain_block(block)
	if card.heal > 0:
		player.heal(card.heal)
	if card.draw_if_full_hp > 0 and was_at_full_hp:
		draw_cards(card.draw_if_full_hp)
	# Rage / Brace: save a bonus for the next Attack / Defense card.
	next_attack_bonus += card.next_attack_bonus
	next_defense_bonus += card.next_defense_bonus
	if card.discard > 0:
		discard_random_cards(card.discard)
	if card.draw > 0:
		draw_cards(card.draw)

	# The played card goes to the discard pile like everything else.
	discard_pile.append(card)
	refresh_hand()


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
		card.played.connect(_on_card_played)
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
	energy_label.text = "Energy %d / %d" % [energy, MAX_ENERGY]
	piles_label.text = "Draw pile %d   Discard %d" % [draw_pile.size(), discard_pile.size()]

	# Grey out cards you can't afford.
	for card: Card in hand_box.get_children():
		card.disabled = game_over or card.card_data.cost > energy


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
