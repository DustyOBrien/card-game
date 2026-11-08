# town_building.gd
#
# One building in the town (scenes/town.tscn). Every building starts in
# ruins (stage 0), apart from any whose first stage costs 0 gold. You put
# gold into it to restore it one stage at a time, and each stage unlocks
# something: the Tailor's first stage gives your Save Sack another slot.
#
# Buildings come from data/progression/town.csv (one row per STAGE), which
# the importer turns into town/*.tres. What a stage does is an Effect name
# (see EFFECTS) and an Amount. GameState.town_bonus("Sack Slots") adds up
# that effect over every stage you've restored, like talents do.
class_name TownBuilding
extends Resource

# Effect names the game knows, as written in the sheet's Effect column.
const SHOP := "shop"  # The shop opens: buy booster packs.
const PACK_DISCOUNT := "pack discount"  # Packs cost this much less.
const SACK_SLOTS := "sack slots"  # More Save Sack slots.
const GOLD_STACK := "gold stack"  # More gold fits in one Save Sack slot.
const ENCHANTER := "enchanter"  # Buy enchants to take into your next run.
const ENCHANT_CHOICE := "enchant choice"  # When an enchant drops, choose from this many more.
const ALCHEMIST := "alchemist"  # Buy potions to take into your next run.
const POTION_SLOTS := "potion slots"  # Carry more potions.
const MAPMAKER := "mapmaker"  # Buy maps that unlock room cards.
const DANGER_STEPS := "danger steps"  # Danger needed for each Danger card goes up by this much.
const BACKPACK_SLOTS := "backpack slots"  # More backpack slots on expeditions.
const INN := "inn"  # Opens quests, the map and adventuring.
const BANK := "bank"  # The Guild Hall's Bank: see your materials.
const DOJO := "dojo"  # The Old Master's Dojo: the Talents screen, from town.
const EFFECTS := [SHOP, PACK_DISCOUNT, SACK_SLOTS, GOLD_STACK, ENCHANTER, ENCHANT_CHOICE,
	ALCHEMIST, POTION_SLOTS, MAPMAKER, DANGER_STEPS, BACKPACK_SLOTS, INN, BANK, DOJO]

@export var building_name: String = "Building"
@export_multiline var description: String = ""
@export var icon: Texture2D  # Its picture (art/town/).
@export var sort_order: int = 0  # Left to right in town.

# One entry per stage, stage 1 first: what it costs, what it does, and its text.
@export var costs: Array[int] = []
@export var effects: PackedStringArray = []
@export var amounts: Array[int] = []
@export var stage_texts: PackedStringArray = []
# Materials each stage costs on top of the gold: "Lumber 5" (blank = none).
@export var material_costs: PackedStringArray = []
# true = hidden in town until a quest gives you its BLUEPRINT.
@export var needs_blueprint: bool = false


func max_stage() -> int:
	return costs.size()


# What the next stage costs (stage = the one you're at now).
func cost_of_next(stage: int) -> int:
	return costs[stage] if stage < costs.size() else 0


# The materials the next stage costs: {"Lumber": 5}.
func materials_for_next(stage: int) -> Dictionary:
	if stage < material_costs.size():
		return MaterialInfo.parse_costs(material_costs[stage])
	return {}


# Total of one effect over stages 1 to `stage`.
func bonus(effect: String, stage: int) -> int:
	var total := 0
	for i in mini(stage, effects.size()):
		if effects[i] == effect:
			total += amounts[i]
	return total
