# game_state.gd
#
# Data that has to survive when we switch from one scene to another.
#
# Normally, when you change scenes, Godot throws the old scene away along with
# all of its variables. So how does the battle know which deck you built?
#
# Answer: an AUTOLOAD. This script is listed under Project Settings > Globals >
# Autoload with the name "GameState". Godot creates it once when the game
# starts and keeps it alive the whole time, no matter which scene is showing.
# Any script can then reach it by that name, e.g. `GameState.deck`.
# (It's a bit like a Python module with variables in it that every file imports.)
extends Node

const CARDS_FOLDER := "res://cards/"  # Every card file in here is in the card pool.
const CLASSES_FOLDER := "res://classes/"  # Every class file in here is on the Character Select screen.

# The class picked on the Character Select screen. Its rules decide which
# cards the deck builder lets you use, and how many of each.
var character_class: CharacterClass

# The deck the player built. It holds one entry per card, so two Strikes means
# Strike appears twice in the list. The battle copies this and shuffles the copy.
var deck: Array[CardData] = []


# Called by the Character Select screen. A new class means a new deck,
# so we throw the old one away and start from that class's starter deck.
func choose_class(new_class: CharacterClass) -> void:
	character_class = new_class
	deck = make_starter_deck()


# Every class, loaded from the classes/ folder, in their sort_order.
func load_classes() -> Array[CharacterClass]:
	var classes: Array[CharacterClass] = []
	for file_name in ResourceLoader.list_directory(CLASSES_FOLDER):
		if file_name.ends_with(".tres"):
			classes.append(load(CLASSES_FOLDER + file_name))
	classes.sort_custom(func(a: CharacterClass, b: CharacterClass) -> bool:
		return a.sort_order < b.sort_order)
	return classes


# Every card the chosen class is allowed to build with (one of each), loaded
# from the cards/ folder. Sorted by school, then name, so schools sit together.
func load_card_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	for file_name in ResourceLoader.list_directory(CARDS_FOLDER):
		if file_name.ends_with(".tres"):
			var card: CardData = load(CARDS_FOLDER + file_name)
			if character_class == null or character_class.can_use(card):
				pool.append(card)
	# sort_custom() takes a function that answers "should a come before b?".
	# `func(a, b): ...` is a lambda: a small function with no name (like Python's lambda).
	pool.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.schools != b.schools:
			return a.schools < b.schools
		return a.card_name < b.card_name)
	return pool


# The suggested starting deck for the chosen class: as many copies of every
# card it can use as its rules allow, stopping if the deck gets full.
# Used when you pick a class, and by the deck builder's Starter Deck button.
func make_starter_deck() -> Array[CardData]:
	var starter: Array[CardData] = []
	for card in load_card_pool():
		for i in character_class.max_copies_of(card):
			if starter.size() < character_class.max_deck_size:
				starter.append(card)
	return starter


# For testing a scene on its own (F6): if nothing was picked yet, use the
# first class and its starter deck, so the scene still has something to show.
func ensure_ready() -> void:
	if character_class == null:
		choose_class(load_classes()[0])
	elif deck.is_empty():
		deck = make_starter_deck()
