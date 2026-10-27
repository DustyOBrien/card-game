# talent.gd
#
# One talent in a class's talent tree. Like cards, talents come from a
# spreadsheet: data/talents/<class>.csv (one sheet per class), which the card
# importer turns into talents/<class>/<name>.tres files.
#
# A talent has a spot in the tree (Tier = row, Column = left to right), some
# rules about when you can learn it, and ONE effect the game knows how to do.
# Spend talent points on it to raise its rank (up to max_ranks).
class_name Talent
extends Resource

# The effects the game understands. In the sheet's Effect column, use one of
# these names exactly (upper or lower case doesn't matter). Blank = no effect yet.
const SCHOOL_LIMIT := "school limit"  # +Amount cards of School allowed in the deck ("All" = every school).
const ENERGY := "energy"  # +Amount Energy every turn.
const ENERGY_IF_ONLY_NEUTRAL := "energy if only neutral"  # +Amount Energy if every card in the deck is Neutral.
const COST_DISCOUNT_CHANCE := "cost discount chance"  # Amount% chance a drawn School card costs 1 less this turn.
const DRAW_DAMAGE_CHANCE := "draw damage chance"  # Amount% chance a drawn School card deals 1 damage to all enemies.
const EFFECTS: Array[String] = [SCHOOL_LIMIT, ENERGY, ENERGY_IF_ONLY_NEUTRAL, COST_DISCOUNT_CHANCE, DRAW_DAMAGE_CHANCE]

@export var talent_name: String = "New Talent"
@export var class_display_name: String = ""  # Whose tree it's in ("Adventurer").

@export_group("Place in the tree")
@export var tier: int = 1  # The row, 1 = the top.
@export var column: float = 1.0  # Left to right. 1.5 sits halfway between columns 1 and 2.

@export_group("Learning")
@export var cost: int = 1  # Talent points per rank.
@export var max_ranks: int = 1
@export var needs: PackedStringArray = []  # Talents you must have first (at least 1 rank).
@export var needs_any: bool = false  # true = any ONE of `needs` is enough. false = all of them.
@export var points_in_tree: int = 0  # Points you must have spent in this class's whole tree.
@export var tier_unlock: int = 0  # Points you must have spent in the tier above.
@export var choice_group: String = ""  # Only one talent per group can be learned.
@export var locks_out: PackedStringArray = []  # Learning this one stops you learning these.

@export_group("Effect")
@export var effect: String = ""  # One of EFFECTS, or "" for none.
@export var school: String = ""  # "strength", "neutral", "all"... or "".
# What the effect adds at each rank. One number = that much per rank
# (so [1] at rank 3 is 3). A list = the total at each rank ([2, 4, 6]).
@export var amounts: Array[int] = []

@export_group("Text")
@export_multiline var rules: String = ""  # The summary, e.g. "10% / 20% / 30% chance..."
@export var rank_texts: PackedStringArray = []  # What each rank does, for the tooltip.


# The effect's number at this rank. 0 at rank 0 (not learned).
func amount_at(rank: int) -> int:
	if rank <= 0 or amounts.is_empty():
		return 0
	if amounts.size() == 1:
		return amounts[0] * rank
	return amounts[mini(rank, amounts.size()) - 1]


# Does this talent's School match this card?
func matches_card(card: CardData) -> bool:
	match school:
		"", "all", "any":
			return true
		"neutral":
			return card.is_neutral()
	return (card.schools & school_flag()) != 0


# The CardData.School flag for our school (0 for "all", "neutral" or blank).
func school_flag() -> int:
	return CardData.School.get(school.to_upper(), 0)


# The text for one rank, falling back to the summary.
func rank_text(rank: int) -> String:
	if rank >= 1 and rank <= rank_texts.size() and not rank_texts[rank - 1].is_empty():
		return rank_texts[rank - 1]
	return rules
