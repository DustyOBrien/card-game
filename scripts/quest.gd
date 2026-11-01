# quest.gd
#
# A QUEST: an objective that moves the game forward. You have ONE active
# quest at a time (GameState.active_quest). When its objective is done,
# hand it in at the Inn (town.gd) for its rewards, and the next quest starts.
#
# From data/progression/quests.csv -> quests/*.tres, one row per quest, in
# order. The first row is the quest a new save starts with.
#
# Objectives (the Objective column, with Target and Amount):
#   Build        Inn            the building is restored (stage 1+)
#   Have         Green Ooze 5   you have this many in the Bank (not used up)
#   Brew         Health Flask   the flask is unlocked at the Alchemist
#   Clear Room   Big Slime Nest beat that room (counted while the quest is active)
#   Defeat       Slime 10       defeat that many (counted while the quest is active)
#   Reach Tier   3              get to that tier in any dungeon
#
# Rewards and Start Gift (several, split by ";"):
#   Gold 20, Pack 1, Material Lumber 5, Blueprint Alchemist,
#   Room Plains: Big Slime Nest (puts a quest-locked room card in the deck)
class_name Quest
extends Resource

const BUILD := "build"
const HAVE := "have"
const BREW := "brew"
const CLEAR_ROOM := "clear room"
const DEFEAT := "defeat"
const REACH_TIER := "reach tier"
const OBJECTIVES := [BUILD, HAVE, BREW, CLEAR_ROOM, DEFEAT, REACH_TIER]

@export var quest_name: String = "Quest"
@export var giver: String = ""  # Who gives it: "The King", "The Innkeeper"...
@export_multiline var text: String = ""  # The story.
@export var objective: String = BUILD
@export var target: String = ""
@export var amount: int = 1
@export var start_gift: String = ""  # Rewards you get when the quest STARTS.
@export var rewards: String = ""  # Rewards for handing it in.
@export var next_quest: String = ""  # Starts when this one is handed in.
@export var sort_order: int = 0


# "Bring home 5 Green Ooze" etc., for the quest panel.
func objective_text() -> String:
	match objective:
		BUILD: return "Build the %s" % target
		HAVE: return "Have %d %s in your Bank" % [amount, target]
		BREW: return "Brew a %s at the Alchemist" % target
		CLEAR_ROOM: return "Beat the %s" % target
		DEFEAT: return "Defeat %d %s" % [amount, target]
		REACH_TIER: return "Reach Tier %d in a dungeon" % amount
	return "%s %s" % [objective, target]
