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
const PREVIEW_COLOR := Color(1, 0.85, 0.3)  # Tint for numbers a dragged card would change.

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
var dragged_card: CardData = null  # The card being dragged right now, if any.

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

	# The deck you built in the deck builder is waiting in GameState (an autoload,
	# see game_state.gd). ensure_ready() above gives you a starter deck if there
	# isn't one, e.g. when you press F6 to run only this scene.
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


# Called when a card is dropped on the play zone (see play_zone.gd).
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
		enemy.take_damage(get_damage(card))
		# Rage: an Attack card uses up the waiting attack bonus.
		if card.has_type(CardData.CardType.ATTACK):
			next_attack_bonus = 0
	if card.block > 0:
		player.gain_block(get_block(card))
		# Brace: a Defense card uses up the waiting block bonus.
		if card.has_type(CardData.CardType.DEFENSE):
			next_defense_bonus = 0
	if card.heal > 0:
		player.heal(card.heal)
	if card.energy > 0:
		energy += card.energy
	if card.lose_hp > 0:
		player.lose_hp(card.lose_hp)
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


# How much damage this card would deal right now, including a Rage bonus.
# Used both to play the card and to preview it, so the two always agree.
func get_damage(card: CardData) -> int:
	if card.damage == 0:
		return 0
	if card.has_type(CardData.CardType.ATTACK):
		return card.damage + next_attack_bonus
	return card.damage


# The enemy's HP after this card hits. Enemy Block soaks up damage first,
# just like in Combatant.take_damage().
func enemy_hp_after(card: CardData) -> int:
	return maxi(enemy.hp - maxi(get_damage(card) - enemy.block, 0), 0)


# How much Block this card would give right now, including a Brace bonus.
func get_block(card: CardData) -> int:
	if card.block == 0:
		return 0
	if card.has_type(CardData.CardType.DEFENSE):
		return card.block + next_defense_bonus
	return card.block


# The text in the banner above a dragged card, one effect per line.
func describe_card(card: CardData) -> String:
	var lines: Array[String] = []
	if card.damage > 0:
		lines.append("Deal %d damage" % get_damage(card))
		lines.append("%s: %d → %d HP" % [enemy.display_name, enemy.hp, enemy_hp_after(card)])
	if card.block > 0:
		lines.append("Gain %d Block" % get_block(card))
	if card.heal > 0:
		lines.append("Heal %d HP" % card.heal)
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
	return "\n".join(lines)


# Godot tells every node when a drag starts and ends. We use that to show
# the drop zone and to preview the card's effect on the HP and Block numbers.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data = get_viewport().gui_get_drag_data()  # What's being dragged.
		if data is CardData:
			dragged_card = data
			play_zone_hint.visible = true
			update_ui()
	elif what == NOTIFICATION_DRAG_END:
		dragged_card = null
		play_zone_hint.visible = false
		update_ui()


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

	# Grey out cards you can't afford, and tell each card what it would do.
	for card: Card in hand_box.get_children():
		card.disabled = game_over or card.card_data.cost > energy
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

	if card.damage > 0:
		enemy_hp_label.text = "HP %d → %d / %d" % [enemy.hp, enemy_hp_after(card), enemy.max_hp]
		enemy_hp_label.modulate = PREVIEW_COLOR
	if card.heal > 0 or card.lose_hp > 0:
		var hp_after := mini(player.hp + card.heal, player.max_hp) - card.lose_hp
		player_hp_label.text = "HP %d → %d / %d" % [player.hp, maxi(hp_after, 0), player.max_hp]
		player_hp_label.modulate = PREVIEW_COLOR
	if card.block > 0:
		player_block_label.text = "Block %d → %d" % [player.block, player.block + get_block(card)]
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
