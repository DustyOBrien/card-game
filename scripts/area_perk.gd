# area_perk.gd
#
# One PERK for a place (an area): bought with that place's Explorer points,
# which you earn by levelling the place up (Farm Exp from your trips there).
# Each place has its own flat list of perks in its own sheet, e.g.
# data/dungeons/farm_perks.csv (the Area's perk_sheet). Columns:
#
#   Place    the area it belongs to ("Abandoned Farm")
#   Perk     its name
#   Cost     Explorer points
#   Needs    another perk you must own first (blank = none)
#   Requires something you must have UNLOCKED before the perk even shows on
#            the Perks screen (blank = always shown). A perk about flasks
#            means nothing before you've brewed one, so it stays hidden:
#              Flask               you've brewed (unlocked) a flask
#              Potions             the Alchemist is built (potions drop)
#              Map Card: <name>    that map card is unlocked (Bunny Burrow)
#   Effect   what it does (see the list below)
#   Target   who or what it's about: an enemy name part ("Slime"), a card...
#   Amount   how much
#   Into     Swap Card only: the card it becomes
#   Text     the description shown on the Perks screen
#
# Effects:
#   Campfire Heal      Going Deeper heals you Amount HP first
#   Campfire Flask     Going Deeper refills Amount flask charges
#   Campfire Vanished  Going Deeper brings back your Vanished cards
#   Campfire Remove    Going Deeper throws Amount Danger cards out of the map deck
#   Enemy HP           enemies whose name has Target in it get Amount % less HP
#   Enemy Strength     ...get Amount Strength (use a minus number: -1 hits for 1 less)
#   Unlock Card        your map card Target is unlocked (like a Map)
#   Start Potion       start every trip with the potion Target
#   Start Key          start every trip with Amount small keys
#   Swap Card          Amount copies of the card Target become the card Into
#                      (a Deck "Perk" row in the place's map card sheet)
#
# Like the map card sheet, it's read when the game runs (and remembered).
class_name AreaPerk
extends RefCounted

const CAMPFIRE_HEAL := "campfire heal"
const CAMPFIRE_FLASK := "campfire flask"
const CAMPFIRE_VANISHED := "campfire vanished"
const CAMPFIRE_REMOVE := "campfire remove"
const ENEMY_HP := "enemy hp"
const ENEMY_STRENGTH := "enemy strength"
const UNLOCK_CARD := "unlock card"
const START_POTION := "start potion"
const START_KEY := "start key"
const SWAP_CARD := "swap card"
const EFFECTS := [CAMPFIRE_HEAL, CAMPFIRE_FLASK, CAMPFIRE_VANISHED, CAMPFIRE_REMOVE, ENEMY_HP, ENEMY_STRENGTH,
	UNLOCK_CARD, START_POTION, START_KEY, SWAP_CARD]

var perk_name := ""
var cost := 1
var needs := ""
var requires := ""  # See "Requires" above. GameState.perk_shown() checks it.
var effect := ""
var target := ""
var amount := 0
var into := ""
var text := ""

static var _sheets := {}  # Sheet path -> Array[AreaPerk], read once.


static func load_sheet(path: String) -> Array[AreaPerk]:
	if _sheets.has(path):
		return _sheets[path]
	var perks: Array[AreaPerk] = []
	if not path.is_empty():
		for row in CardImporter._read_sheet(path):
			var perk := AreaPerk.new()
			perk.perk_name = row.get("perk", "")
			if perk.perk_name.is_empty():
				continue
			perk.cost = maxi(CardImporter._to_int(row.get("cost", ""), 1), 0)
			perk.needs = row.get("needs", "")
			perk.requires = row.get("requires", "").strip_edges()
			perk.effect = row.get("effect", "").to_lower()
			if not perk.effect in EFFECTS:
				push_warning("%s: %s has Effect '%s'. Use one of: %s" % [path.get_file(), perk.perk_name, row.get("effect", ""), ", ".join(EFFECTS)])
				continue
			perk.target = row.get("target", "")
			perk.amount = CardImporter._to_int(row.get("amount", ""), 0)
			perk.into = row.get("into", "")
			perk.text = row.get("text", "")
			perks.append(perk)
	_sheets[path] = perks
	return perks


# Is this perk about this enemy / card? (Blank Target = everything.)
func fits(thing_name: String) -> bool:
	return target.is_empty() or thing_name.to_lower().contains(target.to_lower())
