# talent.gd
#
# One talent in a class's talent tree. Like cards, talents come from a
# spreadsheet: data/talents/<class>.csv (one sheet per class), which the card
# importer turns into talents/<class>/<name>.tres files.
#
# Like World of Warcraft, a class can have several trees (the Tree column),
# e.g. the Adventurer's Jack of All Trades, Master of None and Pack Rat.
# Your talent points are shared: spend them in any tree.
#
# A SPEC talent (Spec column = Yes, usually the top of a tree) isn't bought
# with points: you pick ONE spec per class and get its spec talent for free.
#
# A talent has a spot in its tree (Tier = row, Column = left to right), some
# rules about when you can learn it, and up to THREE effects the game knows how
# to do (Effect / School / Amount, Effect 2 / School 2 / Amount 2, and Effect 3...).
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
const MAX_DECK_SIZE := "max deck size"  # +Amount to the most cards your deck can hold.
const HAND_SIZE := "hand size"  # +Amount cards drawn at the start of each turn.
const COPY_LIMIT := "copy limit"  # Only Amount copies of each card in the deck (Pack Rat: 1).
# Pack Rat's payoffs (big decks, 1 copy each):
const FIRST_PLAY_FLAWLESS := "first play flawless"  # The first time you play each card in a fight, it's Flawless (always a Critical).
const FIRST_PLAY_BONUS := "first play bonus"  # +Amount to every die the first time you play each card in a fight.
const HP_PER_EXTRA_CARDS := "max hp per 2 cards over 20"  # +Amount max HP for every 2 cards in your deck above 20.
const START_BLOCK_PER_SCHOOL := "start block per school"  # Start each fight with Amount Block per different school in your deck (Neutral counts).
const BONUS_GOLD := "bonus gold"  # +Amount gold from every enemy you beat.
const PACK_DISCOUNT := "pack discount"  # Booster packs cost Amount less gold (never below 1).
const EFFECTS: Array[String] = [SCHOOL_LIMIT, ENERGY, ENERGY_IF_ONLY_NEUTRAL, COST_DISCOUNT_CHANCE,
	DRAW_DAMAGE_CHANCE, MAX_DECK_SIZE, HAND_SIZE, COPY_LIMIT, FIRST_PLAY_FLAWLESS, FIRST_PLAY_BONUS,
	HP_PER_EXTRA_CARDS, START_BLOCK_PER_SCHOOL, BONUS_GOLD, PACK_DISCOUNT]

@export var talent_name: String = "New Talent"
@export var class_display_name: String = ""  # Whose tree it's in ("Adventurer").

@export_group("Place in the tree")
@export var tree: String = "Talents"  # Which of the class's trees it's in.
@export var tree_index: int = 0  # The tree's place in the sheet: 0 = first tree (the first tab).
@export var tier: int = 1  # The row, 1 = the top.
@export var column: float = 1.0  # Left to right. 1.5 sits halfway between columns 1 and 2.

@export_group("Learning")
@export var is_spec: bool = false  # A spec talent: free, and you pick only one spec per class.
@export var cost: int = 1  # Talent points per rank.
@export var max_ranks: int = 1
@export var needs: PackedStringArray = []  # Talents you must have first (at least 1 rank).
@export var needs_any: bool = false  # true = any ONE of `needs` is enough. false = all of them.
@export var points_in_tree: int = 0  # Points you must have spent in THIS tree (like WoW's "5 points per row").
@export var tier_unlock: int = 0  # Points you must have spent in the tier above, in this tree.
@export var choice_group: String = ""  # Only one talent per group can be learned.
@export var locks_out: PackedStringArray = []  # Learning this one stops you learning these.

@export_group("Effect")
@export var effect: String = ""  # One of EFFECTS, or "" for none.
@export var school: String = ""  # "strength", "neutral", "all"... or "".
# What the effect adds at each rank. One number = that much per rank
# (so [1] at rank 3 is 3). A list = the total at each rank ([2, 4, 6]).
@export var amounts: Array[int] = []
# A second effect, for talents that do two things (Pack Rat: bigger deck AND 1 copy each).
@export var effect_2: String = ""
@export var school_2: String = ""
@export var amounts_2: Array[int] = []
# And a third (Pack Rat: bigger deck, 1 copy each, AND Flawless first plays).
@export var effect_3: String = ""
@export var school_3: String = ""
@export var amounts_3: Array[int] = []

@export_group("Text")
@export_multiline var rules: String = ""  # The summary, e.g. "10% / 20% / 30% chance..."
@export var rank_texts: PackedStringArray = []  # What each rank does, for the tooltip.


# Our effects as a list, so code can loop over both slots:
# [{"effect": "max deck size", "school": "", "amounts": [10]}, ...]
func effect_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if not effect.is_empty():
		slots.append({"effect": effect, "school": school, "amounts": amounts})
	if not effect_2.is_empty():
		slots.append({"effect": effect_2, "school": school_2, "amounts": amounts_2})
	if not effect_3.is_empty():
		slots.append({"effect": effect_3, "school": school_3, "amounts": amounts_3})
	return slots


func has_effect(effect_name: String) -> bool:
	return effect_slots().any(func(slot: Dictionary) -> bool: return slot.effect == effect_name)


# How much of one effect this talent gives at this rank (0 if it doesn't have it).
# Pass a card to only count it if the School matches the card, or a school
# flag to only count it for that school ("All" always counts).
func effect_amount(effect_name: String, rank: int, card: CardData = null, for_school: int = -1) -> int:
	var total := 0
	for slot in effect_slots():
		if slot.effect != effect_name:
			continue
		if card and not Talent.school_matches_card(slot.school, card):
			continue
		if for_school >= 0 and not Talent.is_any_school(slot.school) and Talent.school_flag_of(slot.school) != for_school:
			continue
		total += Talent.amount_at(slot.amounts, rank)
	return total


# Does this talent open up `school` for the deck (a School Limit for it, or for All)?
func opens_school(for_school: int) -> bool:
	return effect_amount(SCHOOL_LIMIT, 1, null, for_school) > 0


# The number at this rank. 0 at rank 0 (not learned). One number = that much
# per rank ([1] at rank 3 is 3). A list = the total at each rank ([2, 4, 6]).
static func amount_at(numbers: Array[int], rank: int) -> int:
	if rank <= 0 or numbers.is_empty():
		return 0
	if numbers.size() == 1:
		return numbers[0] * rank
	return numbers[mini(rank, numbers.size()) - 1]


static func is_any_school(school_text: String) -> bool:
	return school_text in ["", "all", "any"]


# Does a School value ("strength", "neutral", "all") match this card?
static func school_matches_card(school_text: String, card: CardData) -> bool:
	if is_any_school(school_text):
		return true
	if school_text == "neutral":
		return card.is_neutral()
	return (card.schools & school_flag_of(school_text)) != 0


# The CardData.School flag for a school name (0 for "all", "neutral" or blank).
static func school_flag_of(school_text: String) -> int:
	return CardData.School.get(school_text.to_upper(), 0)


# The text for one rank, falling back to the summary.
func rank_text(rank: int) -> String:
	if rank >= 1 and rank <= rank_texts.size() and not rank_texts[rank - 1].is_empty():
		return rank_texts[rank - 1]
	return rules
