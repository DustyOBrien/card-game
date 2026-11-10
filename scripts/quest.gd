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
#   Open Packs   Farm Booster Pack 10     open that many packs (any size)
#   Reach Tier   3              get to that floor in any dungeon (Go Deeper)
#   Gather       Have Stone 5; Have Sticks 2; Deliver Hops 2
#                several things at once, as a CHECKLIST. Each part is Have
#                (you keep it), Deliver (you hand it over), or Reach (a story
#                moment has happened: "Reach Cellar Opened"). Amount is ignored.
#
# Seed Cards: map cards this quest puts on the board when it's the run's
# goal (picked on the Prepare screen), e.g. "Dark Cellar". Only STORY quests
# are picked like that; every other quest counts on every run.
#
# Rewards and Start Gift (several, split by ";"):
#   Gold 20, Pack Small 2 (Small / Medium / Large Farm Booster Packs),
#   Material Lumber 5, Blueprint Alchemist, Unlock Pack Rat (opens a spec),
#   Room Abandoned Farm: Big Slime Nest (adds a quest-locked map card)
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
const GATHER := "gather"
const REACH := "reach"  # A Gather part: a story beat (GameState.story_beats) has happened.
const OBJECTIVES := [BUILD, HAVE, DELIVER, BREW, CLEAR_ROOM, DEFEAT, REACH_TIER, OPEN_PACKS, GATHER]
const ANY := "any"  # Defeat Any: every monster counts.

@export var quest_name: String = "Quest"
@export var giver: String = ""  # Who gives it: "The King", "Kale"...
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
@export var seed_cards: String = ""  # "Dark Cellar; Old Well": put on the board when it's the run's goal.
# Which place it belongs to ("Abandoned Farm"), for the Inn's tabs. Blank = the town.
@export var area: String = ""


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
		REACH_TIER: return "Reach Floor %d of a dungeon" % amount
		GATHER:
			var items: Array[String] = []
			var reach: Array[String] = []
			for part in parts():
				if part.verb == REACH:
					reach.append(REACH_TEXTS.get(part.name, part.name))
				else:
					items.append("%d %s" % [part.amount, part.name])
			var text := ("Bring home " + ", ".join(items)) if not items.is_empty() else ""
			if not reach.is_empty():
				text += ("; " if not text.is_empty() else "") + "; ".join(reach)
			return text
	return "%s %s" % [objective, target]


# What a Reach part says on the quest screen.
const REACH_TEXTS := {"Cellar Opened": "open the Dark Cellar with Kale's key for his ale", "Dark Cellar Cleared": "clear out the Dark Cellar (beat what lives at the bottom)"}


# A Gather quest's checklist: "Have Stone 5; Deliver Hops 2" ->
# [{"verb": "have", "name": "Stone", "amount": 5}, {"verb": "deliver", ...}].
# (A plain Have or Deliver quest is a checklist of one.)
func parts() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if objective in [HAVE, DELIVER]:
		list.append({"verb": objective, "name": target, "amount": amount})
	if objective != GATHER:
		return list
	for text in target.split(";", false):
		var words := text.strip_edges().split(" ", false)
		if words.size() < 2:
			continue
		var verb := words[0].to_lower()
		if verb == REACH:
			words.remove_at(0)
			list.append({"verb": REACH, "name": " ".join(words), "amount": 1})
			continue
		if not verb in [HAVE, DELIVER]:
			verb = HAVE  # "Stone 5" on its own means Have.
		else:
			words.remove_at(0)
		var count := 1
		if words.size() > 1 and words[-1].is_valid_int():
			count = words[-1].to_int()
			words.remove_at(words.size() - 1)
		list.append({"verb": verb, "name": " ".join(words), "amount": count})
	return list
