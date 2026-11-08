# enchant.gd
#
# An ENCHANT is a bonus you put on one card in your deck, for the rest of the
# run. Fights sometimes drop one (and the Enchanter in town sells them). Each
# card can hold one enchant. A new run starts with no enchants.
#
# Enchants come from the spreadsheet data/progression/enchants.csv, which
# the importer turns into enchants/*.tres. An enchant can do several things
# at once ("Leech + Vanish").
#
# How it works in a fight: battle.gd copies each deck card for the fight, and
# apply_to() changes the copy (adds Advantage, +1 to its dice...). The card
# in your collection never changes.
class_name Enchant
extends Resource

@export var enchant_name: String = "Enchant"
@export_multiline var description: String = ""
@export var rarity: CardData.Rarity = CardData.Rarity.COMMON
@export var color: Color = Color(0.7, 0.5, 1.0)  # Its glow on the card.

@export_group("What it does")
@export var roll_bonus: int = 0  # +this to every die the card rolls (attack, block and heal).
@export var advantage: bool = false  # The card's dice roll twice and keep the higher.
@export var empowered: bool = false  # Every die one size bigger (d6 -> d8).
@export var wild: bool = false  # Rolls when played instead of when drawn.
@export var flawless: bool = false  # Every die is a Critical.
@export var vanish: bool = false  # A drawback: gone for the run once played.
@export var leech: int = 0  # Heal this % of the damage the card deals.
@export var cost_change: int = 0  # -1 = costs 1 less Energy (never below 0).
@export var draw: int = 0  # Draw this many more cards when played.

# How likely each rarity is to drop, compared with each other.
const RARITY_WEIGHTS := {CardData.Rarity.COMMON: 60, CardData.Rarity.UNCOMMON: 30, CardData.Rarity.RARE: 10, CardData.Rarity.LEGENDARY: 3}


# Does it only make sense on a card that rolls dice?
func needs_dice() -> bool:
	return roll_bonus != 0 or advantage or empowered or wild or flawless


func needs_damage() -> bool:
	return leech > 0


# Can this enchant go on this card? (Each card holds one enchant, and
# dice enchants need a card with dice.)
func fits(card: CardData) -> bool:
	if needs_dice() and not card.has_dice():
		return false
	if needs_damage() and not card.deals_damage():
		return false
	return true


# Change a fight copy of a card. (Never call this on the card itself, or
# every copy in your collection would change.)
func apply_to(card: CardData) -> void:
	if card.has_dice() and roll_bonus != 0:
		if not card.attack.is_empty():
			card.attack_modifier += roll_bonus
		if not card.block.is_empty():
			card.block_modifier += roll_bonus
		if not card.heal.is_empty():
			card.heal_modifier += roll_bonus
	card.advantage = card.advantage or advantage
	card.empowered = card.empowered or empowered
	card.wild = card.wild or wild
	card.flawless = card.flawless or flawless
	card.vanish = card.vanish or vanish
	card.leech += leech
	card.cost = maxi(card.cost + cost_change, 0)
	card.draw += draw
	card.enchant_name = enchant_name
	card.enchant_color = color


# A random enchant from the list, rarer ones less often.
static func pick_random(from: Array[Enchant]) -> Enchant:
	if from.is_empty():
		return null
	var total := 0
	for enchant in from:
		total += RARITY_WEIGHTS[enchant.rarity]
	var roll := randi_range(1, total)
	for enchant in from:
		roll -= RARITY_WEIGHTS[enchant.rarity]
		if roll <= 0:
			return enchant
	return from[-1]
