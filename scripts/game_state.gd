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

# The deck the player built. It holds one entry per card, so two Strikes means
# Strike appears twice in the list. The battle copies this and shuffles the copy.
var deck: Array[CardData] = []


# Every card the player is allowed to build with (one of each), loaded from
# the cards/ folder. Sorted by school, then name, so schools sit together.
func load_card_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	for file_name in ResourceLoader.list_directory(CARDS_FOLDER):
		if file_name.ends_with(".tres"):
			pool.append(load(CARDS_FOLDER + file_name))
	# sort_custom() takes a function that answers "should a come before b?".
	# `func(a, b): ...` is a lambda: a small function with no name (like Python's lambda).
	pool.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.schools != b.schools:
			return a.schools < b.schools
		return a.card_name < b.card_name)
	return pool


# The suggested starting deck: every card, as many times as its Copies column says.
# Used to pre-fill the deck builder, and by the battle if no deck was built.
func make_default_deck() -> Array[CardData]:
	var default_deck: Array[CardData] = []
	for card in load_card_pool():
		for i in card.copies:
			default_deck.append(card)
	return default_deck
