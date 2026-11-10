# room_card.gd
#
# One MAP CARD: one square of the dungeon board. At the start of a run (and
# every time you Go Deeper) 24 of them are dealt FACE DOWN onto the 5 x 5
# board. Step onto one and it flips over: that's what the square is.
#
# Every card is one of three TILES (Dusty's design):
#   Safe     nothing dangerous: an empty field, a pile of stone...
#   Unsafe   always a fight, and danger goes up. Once you win, it's Safe
#            until it gets shuffled back into the deck.
#   Explore  a choice: a locked shed, an old well, a barn... Some choices
#            need something (a key), and failing one raises danger.
#
# The Abandoned Farm's cards come from data/dungeons/farm_cards.csv. That
# sheet is read straight in when the game starts (map_cards.gd), so you can
# change it and press Play: no importer needed. (The old room decks in
# rooms.csv are still imported into areas/*.tres for places that haven't
# moved to map cards yet.)
class_name RoomCard
extends Resource

# What the card does when you step on it (the sheet's Kind column).
# (New types go on the END: room files store the number, so the order must not change.)
enum Type { FIGHT, HARD_FIGHT, LOCKED_CHEST, TREASURE, CAMPFIRE, MINI_BOSS, BOSS, EMPTY, EVENT }

# What each type is called in the sheet, and on screen.
const TYPE_NAMES := {
	Type.FIGHT: "Fight",
	Type.HARD_FIGHT: "Hard Fight",
	Type.LOCKED_CHEST: "Locked Chest",
	Type.TREASURE: "Treasure",
	Type.CAMPFIRE: "Campfire",
	Type.MINI_BOSS: "Mini Boss",
	Type.BOSS: "Boss",
	Type.EMPTY: "Empty",
	Type.EVENT: "Event",  # Choices from data/dungeons/events.csv (see dungeon_event.gd).
}

enum Tile { SAFE, UNSAFE, EXPLORE }
const TILE_NAMES := {Tile.SAFE: "Safe", Tile.UNSAFE: "Unsafe", Tile.EXPLORE: "Explore"}
# The colour of each tile's border and badge on the board.
const TILE_COLORS := {
	Tile.SAFE: Color(0.45, 0.85, 0.45),
	Tile.UNSAFE: Color(0.95, 0.35, 0.3),
	Tile.EXPLORE: Color(1.0, 0.8, 0.3),
}

# Which part of the map deck a card belongs to (the sheet's Deck column):
const DECK_GUIDE := "Guide"  # The first trip's board, dealt in the sheet's order.
const DECK_BASE := "Base"  # The place's own 20 cards (plus deeper floors' cards).
const DECK_FILLER := "Filler"  # Fills your empty map card slots.
const DECK_YOURS := "Yours"  # Your own map cards (from quests and Maps).
const DECK_CAMPFIRE := "Campfire"  # The campfire hidden on every board.
const DECK_BOSS := "Boss"  # Dealt onto every board from its Floor on.
const DECK_DANGER := "Danger"  # Bad cards shuffled in as Danger grows (never in the starting deck).
const DECK_PERK := "Perk"  # Only in the deck through a place perk (Swap Card).
const DECK_LINKED := "Linked"  # Only added by another card: the Rusty Lever's Sealed Vault, the Hoard's guards.
const DECK_ROAMER := "Roamer"  # A mini boss that wanders the board, face down, a square per step.
const DECK_SECRET := "Secret"  # Only appears when a tool finds it (a bombed wall).

@export var room_name: String = "Room"
@export var type: Type = Type.EMPTY
@export var tile: Tile = Tile.SAFE
@export var deck_part: String = DECK_BASE
@export var art: Texture2D  # The picture on the card's face.
@export_multiline var text: String = ""  # The card's flavour text.
# The card only joins the map deck once you reach this floor (1 = from the start).
@export var floor_from: int = 1
# VANISH: once it's used (beaten, opened...), it's gone for the rest of the run
# instead of being shuffled back in. For very good cards and mini bosses.
@export var vanish: bool = false

# --- Older room deck fields (rooms.csv) ---
# Which tier of the dungeon it belongs to (the old room decks only).
@export var tier: int = 1
# Tier "Guide" in rooms.csv: the old guided first run.
const GUIDE_TIER := -1
@export var copies: int = 1  # How many of this card go in the deck.
# false = you need to find a Map in a chest before this card goes in the deck.
@export var unlocked: bool = true
# true = only a QUEST can unlock it (the sheet's Unlocked column says "Quest").
# Maps from chests never pick these.
@export var quest_only: bool = false
@export var ambush: bool = false  # Old room decks only. (Unsafe map cards are always a fight.)
# Fights: the enemy groups it can be. One is picked at random each time.
@export var encounters: Array[Encounter] = []
# What you find: one entry is picked at random, e.g. ["Gold 5-10", "Card", "Pack"].
# Chests and Treasure always have loot. A fight's loot is a bonus for winning.
# Words the game knows: Gold N-M, Card, Pack, Map, Key, Potion, Enchant, or a
# material ("Stone 1-2", "Hops 1").
@export var loot: PackedStringArray = []
# SCAVENGING (dungeon_run.gd): what you can dig up here. Each find rolls a
# tier: Common finds come from scavenge_common (the card's own things);
# Uncommon / Rare from scavenge_uncommon / scavenge_rare if the card has
# them, otherwise from the place's loot table (GameState.area_loot()).
# Same words as loot. A card with none of these can't be scavenged.
@export var scavenge_common: PackedStringArray = []
@export var scavenge_uncommon: PackedStringArray = []
@export var scavenge_rare: PackedStringArray = []
# Events only: the event this card always is (the sheet's Event column),
# e.g. "Old Well". Empty = a random event, like "Mystery".
# Any other card can have an Event too (an Old Barn, a Dark Cellar): it
# happens FIRST, when the card flips, and then you can scavenge. Event
# Chance = how likely it is to happen (25 = 1 time in 4; blank = always).
@export var event_name: String = ""
@export var event_chance: int = 100
# GUARDS (map cards): the card dealt next to this one (up to 2), e.g. the
# Guarded Hoard's "Slime Guard". You can't take this card's loot while one stands.
@export var guards: String = ""
const GUARD_COUNT := 2


func is_fight() -> bool:
	return type in [Type.FIGHT, Type.HARD_FIGHT, Type.MINI_BOSS, Type.BOSS]


func can_scavenge() -> bool:
	return not (scavenge_common.is_empty() and scavenge_uncommon.is_empty() and scavenge_rare.is_empty())


# The loot words that aren't materials ("Gold 5-10", "Torch", "Card"...).
const LOOT_WORDS := ["gold", "card", "pack", "key", "torch", "crowbar", "bomb", "enchant", "potion", "map"]


# What one loot entry gives, without the amount: "Stone 1-2" -> "Stone",
# "Gold 5-10" -> "Gold", "Golden Fleece 1" -> "Golden Fleece", "Torch" -> "Torch".
static func loot_item_name(entry: String) -> String:
	var words := entry.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	if words[0].to_lower() in LOOT_WORDS:
		return words[0].capitalize()
	var last := words[-1].split("-")
	if words.size() > 1 and last[0].is_valid_int():
		return " ".join(words.slice(0, -1))
	return entry.strip_edges()


# Every DIFFERENT thing you could scavenge here, from all three tables, in
# order (Common first). The board shows one "?" per thing, and swaps each "?"
# for the thing's icon once you've found it here (GameState.scavenge_finds).
func scavenge_items() -> Array[String]:
	var items: Array[String] = []
	for table: PackedStringArray in [scavenge_common, scavenge_uncommon, scavenge_rare]:
		for entry in table:
			var item := loot_item_name(entry)
			if not item.is_empty() and not items.has(item):
				items.append(item)
	return items


func type_name() -> String:
	return TYPE_NAMES[type]


func tile_name() -> String:
	return TILE_NAMES[tile]


# A random enemy group for this fight (empty if it isn't a fight).
func pick_encounter() -> Array[EnemyData]:
	var enemies: Array[EnemyData] = []
	if not encounters.is_empty():
		enemies.assign(encounters.pick_random().enemies)
	return enemies


# The tile a card from an old room deck counts as: fights are Unsafe,
# chests and events Explore, the rest Safe.
static func tile_for_type(for_type: Type) -> Tile:
	if for_type in [Type.FIGHT, Type.HARD_FIGHT, Type.MINI_BOSS, Type.BOSS]:
		return Tile.UNSAFE
	if for_type in [Type.LOCKED_CHEST, Type.EVENT]:
		return Tile.EXPLORE
	return Tile.SAFE
