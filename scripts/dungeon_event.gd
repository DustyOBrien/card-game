# dungeon_event.gd
#
# An EVENT: a little story with choices, found in an Event room ("Mystery"
# on the map). "A fountain bubbles... Drink / Fill your flask / Walk away."
#
# Events come from data/dungeons/events.csv -> dungeon_events/*.tres. The
# sheet has one row per CHOICE; rows with the same Event are one event.
# When you step into an Event room, DungeonRun.pick_event() picks one that
# fits the area and tier, and one you haven't seen yet this run.
#
# What a choice does is a list of EFFECTS, split by ";":
#   Heal 8          heal 8 HP            Lose HP 4      lose 4 HP (never below 1)
#   Gold 10-20      found gold           Pay 10         costs 10 found gold (needs it)
#   Key, Potion, Enchant, Card, Pack, Super Card        loot, like chests
#   Flask           +1 flask charge (needs a flask)
#   Danger 1        danger goes up 1     Calm           danger back to 0
#   Fight Wolf, Wolf    start a fight with these enemies (no backing off)
# Chance = % that the Effect happens; otherwise the Fail Effect does.
class_name DungeonEvent
extends Resource

@export var event_name: String = "Event"
@export var area: String = ""  # "" = any area.
@export var min_tier: int = 1  # Only found in this tier or deeper.
@export_multiline var text: String = ""

# One entry per choice.
@export var choice_labels: PackedStringArray = []
@export var chances: Array[int] = []  # 100 = always works.
@export var effects: PackedStringArray = []  # "Heal 8; Gold 5" (split by ";" when used).
@export var fail_effects: PackedStringArray = []
@export var results: PackedStringArray = []  # Text shown after it works.
@export var fail_results: PackedStringArray = []  # Text shown after it fails.


func fits(area_name: String, tier: int) -> bool:
	return (area.is_empty() or area.to_lower() == "any" or area == area_name) and tier >= min_tier


# "Heal 8; Gold 5" -> ["Heal 8", "Gold 5"].
static func split_effects(text: String) -> Array[String]:
	var list: Array[String] = []
	for part in text.split(";", false):
		if not part.strip_edges().is_empty():
			list.append(part.strip_edges())
	return list
