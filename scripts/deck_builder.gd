# deck_builder.gd
#
# The screen before the battle (scenes/deck_builder.tscn).
#
#   - Left side: the card POOL, one of every card your class can use.
#     Click one to add it to your deck.
#   - Right side: your DECK. Click a line to take one copy back out.
#   - "Start Battle" saves the deck into GameState (see game_state.gd) and
#     switches to the battle scene, which reads it from there.
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")
const BATTLE_SCENE := "res://scenes/battle.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"

# The deck rules (deck size, copies per card) come from the class you picked.
# They live in classes/*.tres: click one in Godot and change them in the Inspector.
var rules: CharacterClass
var card_pool: Array[CardData] = []

@onready var title_label: Label = %TitleLabel
@onready var pool_grid: GridContainer = %PoolGrid
@onready var deck_list: VBoxContainer = %DeckList
@onready var deck_count_label: Label = %DeckCountLabel
@onready var rules_label: Label = %RulesLabel
@onready var clear_button: Button = %ClearButton
@onready var default_button: Button = %DefaultButton
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	default_button.pressed.connect(_on_default_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Picking a class already gave you its starter deck, and coming back from a
	# battle keeps your last deck. ensure_ready() only matters when you press F6
	# to run this scene on its own.
	GameState.ensure_ready()
	rules = GameState.character_class
	title_label.text = "Build Your Deck: %s" % rules.display_name

	card_pool = GameState.load_card_pool()  # Only the cards this class can use.
	build_pool()
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
		count_label.text = "In deck: %d / %d" % [count, rules.max_copies_of(card_pool[i])]
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
	start_button.disabled = deck.size() < rules.min_deck_size
	if deck.size() < rules.min_deck_size:
		rules_label.text = "Add %d more card(s) to start." % (rules.min_deck_size - deck.size())
	else:
		rules_label.text = "%s deck: %d to %d cards." % [
			rules.display_name, rules.min_deck_size, rules.max_deck_size]


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

func can_add(card_data: CardData) -> bool:
	return (GameState.deck.size() < rules.max_deck_size
			and GameState.deck.count(card_data) < rules.max_copies_of(card_data))


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
	GameState.deck = GameState.make_starter_deck()
	refresh()


func _on_start_pressed() -> void:
	# change_scene_to_file() throws away this whole scene and loads the battle.
	# The deck survives because it lives in GameState, not in this scene.
	get_tree().change_scene_to_file(BATTLE_SCENE)


# Back to Character Select to pick a different class.
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
