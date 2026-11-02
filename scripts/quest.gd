# quest.gd
#
# A QUEST: an objective that moves the game forward. Several can run at
# once (GameState.active_quests): the STORY quest, plus class quests and side
# quests. When a quest's objective is done, hand it in at the Inn (town.gd)
# for its rewards, and its Next Quest starts.
#
# Type (Story / Adventurer / Side...) only groups quests on the Inn's quest
# screen. Starts After = a quest that starts this one when it's handed in
# (as well as that quest's own Next Quest), e.g. the side quests start after
# "Stone for the Inn", when the Adventurer arrives.
#
# From data/progression/quests.csv -> quests/*.tres, one row per quest, in
# order. The first row is the quest a new save starts with.
#
# Objectives (the Objective column, with Target and Amount):
#   Build        Inn            the building is restored (stage 1+)
#   Have         Green Ooze 5   you have this many in the Bank (not used up)
#   Deliver      Hops 3         like Have, but handing it in gives them away
#   Brew         Health Flask   the flask is unlocked at the Alchemist
#   Clear Room   Big Slime Nest beat that room (counted while the quest is active)
#   Defeat       Slime 10       defeat that many (counted while the quest is active;
#                Any = any monster, but not the training dummies)
#   Open Packs   Plains Booster Pack 10   open that many packs (any size)
#   Reach Tier   3              get to that tier in any dungeon
#
# Rewards and Start Gift (several, split by ";"):
#   Gold 20, Pack Small 2 (Small / Medium / Large Plains Booster Packs),
#   Material Lumber 5, Blueprint Alchemist, Unlock Pack Rat (opens a spec),
#   Room Plains: Big Slime Nest (puts a quest-locked room card in the deck)
class_name Quest
extends Resource

const BUILD := "build"
const HAVE := "have"
const DELIVER := "deliver"
const BREW := "brew"
const CLEAR_ROOM := "clear room"
const DEFEAT := "defeat"
const REACH_TIER := "reach tier"
const OPEN_PACKS := "open packs"
const OBJECTIVES := [BUILD, HAVE, DELIVER, BREW, CLEAR_ROOM, DEFEAT, REACH_TIER, OPEN_PACKS]
const ANY := "any"  # Defeat Any: every monster counts.

@export var quest_name: String = "Quest"
@export var giver: String = ""  # Who gives it: "The King", "The Innkeeper"...
@export_multiline var text: String = ""  # The story.
@export var objective: String = BUILD
@export var target: String = ""
@export var amount: int = 1
@export var start_gift: String = ""  # Rewards you get when the quest STARTS.
@export var rewards: String = ""  # Rewards for handing it in.
@export var next_quest: String = ""  # Starts when this one is handed in.
@export var quest_type: String = "Story"  # Story / Adventurer / Side: groups it on the quest screen.
@export var starts_after: String = ""  # Also starts when THAT quest is handed in.
@export var sort_order: int = 0


# "Bring home 5 Green Ooze" etc., for the quest panel.
func objective_text() -> String:
	match objective:
		BUILD: return "Build the %s" % target
		HAVE: return "Have %d %s in your Bank" % [amount, target]
		DELIVER: return "Bring %d %s to the Inn" % [amount, target]
		BREW: return "Brew a %s at the Alchemist" % target
		CLEAR_ROOM: return "Beat the %s" % target
		DEFEAT: return "Defeat %d %s" % [amount, "enemies" if target.to_lower() == ANY else target]
		OPEN_PACKS: return "Open %d %ss" % [amount, target]
		REACH_TIER: return "Reach Tier %d in a dungeon" % amount
	return "%s %s" % [objective, target]
