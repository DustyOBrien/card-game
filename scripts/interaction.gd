# interaction.gd
#
# A HIDDEN ITEM INTERACTION: what happens when you use a tool (a Crowbar, a
# Bomb, a Torch) on a map card. Drag the tool onto a face-up card next to you
# (or under you). The card shows HOW MANY tool tricks it has, but not which:
# you find out by trying, and the Journal remembers what you've found
# (GameState.journal, saved).
#
# They come from data/dungeons/interactions.csv (read when the game runs),
# one row per card + tool:
#
#   Card         the map card's name ("Locked Shed")
#   Tool         Crowbar, Bomb or Torch
#   Chance       % it works
#   Effect       what happens if it works (the event words, see dungeon_event.gd,
#                plus the ones below)
#   Fail Effect  what happens if it doesn't
#   Result       the text when it works
#   Fail Result  the text when it doesn't
#   Used Up      Always (the default for a Bomb or a Torch), On Fail (a Crowbar
#                that snaps), or Never
#
# Extra effect words for tools:
#   Open      open the card like a chest: you get its Loot
#   Clear     a fight card is dealt with, no fight (no fight loot either)
#   Destroy   the card is used up (its loot is gone)
#   Secret    the card turns into the place's Secret card (Deck "Secret"), face up
#   Add Sealed Vault   a card (any Deck) joins the board, face down (or the deck)
class_name Interaction
extends RefCounted

const SHEET := "res://data/dungeons/interactions.csv"
const ALWAYS := "always"
const ON_FAIL := "on fail"
const NEVER := "never"

var card_name := ""
var tool := ""
var chance := 100
var effect := ""
var fail_effect := ""
var result := ""
var fail_result := ""
var used_up := ALWAYS

static var _all: Array[Interaction] = []
static var _loaded := false


static func load_all() -> Array[Interaction]:
	if _loaded:
		return _all
	_loaded = true
	for row in CardImporter._read_sheet(SHEET):
		var interaction := Interaction.new()
		interaction.card_name = row.get("card", "")
		interaction.tool = row.get("tool", "").capitalize()
		if interaction.card_name.is_empty() or interaction.tool.is_empty():
			continue
		interaction.chance = clampi(CardImporter._to_int(row.get("chance", ""), 100), 0, 100)
		interaction.effect = row.get("effect", "")
		interaction.fail_effect = row.get("fail effect", "")
		interaction.result = row.get("result", "")
		interaction.fail_result = row.get("fail result", "")
		var used: String = row.get("used up", "").to_lower()
		interaction.used_up = used if used in [ALWAYS, ON_FAIL, NEVER] else ALWAYS
		_all.append(interaction)
	return _all


# Every tool trick a card has.
static func for_card(name: String) -> Array[Interaction]:
	return load_all().filter(func(i: Interaction) -> bool: return i.card_name == name)


static func find(name: String, tool_name: String) -> Interaction:
	for interaction in load_all():
		if interaction.card_name == name and interaction.tool == tool_name:
			return interaction
	return null


# The journal's key for this trick: "Locked Shed|Crowbar".
func key() -> String:
	return card_name + "|" + tool


# "Crowbar (60%): Open" for the journal and the card's tooltip.
func summary() -> String:
	return "%s (%d%%): %s" % [tool, chance, effect if not effect.is_empty() else "nothing"]
