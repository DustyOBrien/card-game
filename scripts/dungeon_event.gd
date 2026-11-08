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
#   Key, Potion, Enchant, Card, Pack, Stone 1-2         loot, like chests
#   Flask           +1 flask charge (needs a flask)
#   Danger 1        danger goes up 1     Calm           danger back to 0
#   Fight Wolf, Wolf    start a fight with these enemies (no backing off)
#   Use Key         uses up a small key (the choice needs one)
#   Use Torch       uses up a torch (the choice needs one)
#   Pack | Card     loot: one of these, picked at random
#   Drop 3          throw away 3 random supplies from your backpack (needs some)
#   Blueprint Enchanter   a building's blueprint, yours for good right away
#   Come Back       the room isn't finished: it goes back into the room deck
#                   at your next rest, so you can find it again
#   Add Sealed Vault    that map card (any Deck) joins the board face down
#                   (or the map deck if there's no room)
# Tool tricks (interactions.csv, see interaction.gd) can also use:
#   Open, Clear, Destroy, Secret    (what they do to the card the tool hit)
# Area "Room" = never picked at random: only a room card that names it
# (rooms.csv, an Event row with the event's name in Encounters) leads to it.
# Chance = % that the Effect happens; otherwise the Fail Effect does.
class_name DungeonEvent
extends Resource

@export var event_name: String = "Event"
@export var area: String = ""  # "" = any area.
@export var min_tier: int = 1  # Only found in this tier or deeper.
@export_multiline var text: String = ""
# A picture above the text (see dungeon.gd event_picture()), e.g. "Wiggling Chest".
@export var picture: String = ""

# One entry per choice.
@export var choice_labels: PackedStringArray = []
@export var chances: Array[int] = []  # 100 = always works.
@export var effects: PackedStringArray = []  # "Heal 8; Gold 5" (split by ";" when used).
@export var fail_effects: PackedStringArray = []
@export var results: PackedStringArray = []  # Text shown after it works.
@export var fail_results: PackedStringArray = []  # Text shown after it fails.


func fits(area_name: String, tier: int) -> bool:
	if area.to_lower() == "room":
		return false  # Only its own room card leads here.
	return (area.is_empty() or area.to_lower() == "any" or area == area_name) and tier >= min_tier


# The buildings this event can give a blueprint for ("Blueprint Enchanter").
func blueprints() -> Array[String]:
	var names: Array[String] = []
	for text in effects:
		for effect in split_effects(text):
			if effect.to_lower().begins_with("blueprint "):
				names.append(effect.substr(10).strip_edges())
	return names


# "Heal 8; Gold 5" -> ["Heal 8", "Gold 5"].
static func split_effects(text: String) -> Array[String]:
	var list: Array[String] = []
	for part in text.split(";", false):
		if not part.strip_edges().is_empty():
			list.append(part.strip_edges())
	return list
