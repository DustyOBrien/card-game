# deck_builder.gd
#
# The screen before the battle (scenes/deck_builder.tscn).
#
#   - Left side: the card POOL, one of every card. Click one to add it to your deck.
#   - Right side: your DECK. Click a line to take one copy back out.
#   - "Start Battle" saves the deck into GameState (see game_state.gd) and
#     switches to the battle scene, which reads it from there.
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")
const BATTLE_SCENE := "res://scenes/battle.tscn"

# --- Deck rules -----------------------------------------------------------------
# Change these to try different rules. Everything else on the screen follows them.
const MIN_DECK_SIZE := 10  # You can't start a battle with fewer cards than this.
const MAX_DECK_SIZE := 20  # You can't add cards beyond this.
const MAX_COPIES := 3  # The most copies of any one card a deck may have.

var card_pool: Array[CardData] = []

@onready var pool_grid: GridContainer = %PoolGrid
@onready var deck_list: VBoxContainer = %DeckList
@onready var deck_count_label: Label = %DeckCountLabel
@onready var rules_label: Label = %RulesLabel
@onready var clear_button: Button = %ClearButton
@onready var default_button: Button = %DefaultButton
@onready var start_button: Button = %StartButton


func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	default_button.pressed.connect(_on_default_pressed)
	start_button.pressed.connect(_on_start_pressed)

	card_pool = GameState.load_card_pool()
	build_pool()

	# First visit: start from the suggested deck so you can jump straight in.
	# Coming back from a battle: GameState.deck still holds your last deck, keep it.
	if GameState.deck.is_empty():
		GameState.deck = GameState.make_default_deck()
	refresh()


# ---------------------------------------------------------------------------
# Building the screen
# ---------------------------------------------------------------------------

# Make one clickable card (plus an "In deck: 0" label under it) for every card
# in the pool. This only happens once; refresh() updates the labels later.
func build_pool() -> void:
	for card_data in card_pool:
		var cell := VBoxContainer.new()  # .new() makes a node in code instead of in a scene.
		pool_grid.add_child(cell)

		var card: Card = CARD_SCENE.instantiate()
		cell.add_child(card)
		card.setup(card_data)
		card.played.connect(_on_pool_card_clicked)  # Reusing the card's own "played" signal.

		var count_label := Label.new()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(count_label)


# Make the whole screen match GameState.deck. Called after every change.
func refresh() -> void:
	var deck := GameState.deck

	# Pool: show how many of each card you have, and grey out cards you can't add.
	# The cells were created in the same order as card_pool, so index i matches.
	for i in card_pool.size():
		var cell := pool_grid.get_child(i)
		var card: Card = cell.get_child(0)
		var count_label: Label = cell.get_child(1)
		var count := deck.count(card_pool[i])  # How many times this card is in the list.
		count_label.text = "In deck: %d / %d" % [count, MAX_COPIES]
		card.disabled = not can_add(card_pool[i])

	# Deck list: throw away the old lines and make one button per kind of card.
	for child in deck_list.get_children():
		child.queue_free()
	for card_data in card_pool:
		var count := deck.count(card_data)
		if count == 0:
			continue  # Not in the deck, no line for it.
		var line := Button.new()
		line.text = "%dx  %s   (%s)" % [count, card_data.card_name, card_data.get_school_text()]
		line.alignment = HORIZONTAL_ALIGNMENT_LEFT
		line.tooltip_text = "Click to remove one"
		# bind() fills in the function's argument ahead of time, so this line
		# button calls _on_deck_line_clicked(card_data) when pressed.
		line.pressed.connect(_on_deck_line_clicked.bind(card_data))
		deck_list.add_child(line)

	deck_count_label.text = "Your deck: %d cards" % deck.size()

	# Only allow starting once the deck is big enough, and say why if it isn't.
	start_button.disabled = deck.size() < MIN_DECK_SIZE
	if deck.size() < MIN_DECK_SIZE:
		rules_label.text = "Add %d more card(s) to start." % (MIN_DECK_SIZE - deck.size())
	else:
		rules_label.text = "Deck size %d to %d, up to %d copies of each card." % [
			MIN_DECK_SIZE, MAX_DECK_SIZE, MAX_COPIES]


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

func can_add(card_data: CardData) -> bool:
	return GameState.deck.size() < MAX_DECK_SIZE and GameState.deck.count(card_data) < MAX_COPIES


# ---------------------------------------------------------------------------
# Clicks
# ---------------------------------------------------------------------------

func _on_pool_card_clicked(card_data: CardData) -> void:
	if can_add(card_data):
		GameState.deck.append(card_data)
		refresh()


func _on_deck_line_clicked(card_data: CardData) -> void:
	GameState.deck.erase(card_data)  # erase() removes only the FIRST match, so one copy.
	refresh()


func _on_clear_pressed() -> void:
	GameState.deck.clear()
	refresh()


func _on_default_pressed() -> void:
	GameState.deck = GameState.make_default_deck()
	refresh()


func _on_start_pressed() -> void:
	# change_scene_to_file() throws away this whole scene and loads the battle.
	# The deck survives because it lives in GameState, not in this scene.
	get_tree().change_scene_to_file(BATTLE_SCENE)
