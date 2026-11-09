# game_state.gd
#
# Data that has to survive when we switch from one scene to another.
#
# Normally, when you change scenes, Godot throws the old scene away along with
# all of its variables. So how does the battle know which deck you built?
#
# Answer: an AUTOLOAD. This script is listed under Project Settings > Globals >
# Autoload with the name "GameState". Godot creates it once when the game
# starts and keeps it alive the whole time, no matter which scene is showing.
# Any script can then reach it by that name, e.g. `GameState.deck`.
# (It's a bit like a Python module with variables in it that every file imports.)
extends Node

const CARDS_FOLDER := "res://cards/"  # Every card file in here is in the card pool.
const CLASSES_FOLDER := "res://classes/"  # Every class file in here is on the Character Select screen.
const AREAS_FOLDER := "res://areas/"  # Every area file in here is on the map.
const TALENTS_FOLDER := "res://talents/"  # talents/<class>/*.tres: each class's talent tree.

# The class picked on the Character Select screen. Its rules decide which
# cards the deck builder lets you use, and how many of each.
var character_class: CharacterClass

# The deck the player built. It holds one entry per card, so two Strikes means
# Strike appears twice in the list. The battle copies this and shuffles the copy.
var deck: Array[CardData] = []

# The area picked on the map. This run's fights happen here.
var current_area: Area

# --- Getting ready for an expedition (scenes/prepare.tscn) ---
const MAX_PACKED_TORCHES := 3  # Torches you can pack (they take backpack space).
const MAX_LOADOUTS := 6
var packed_torches := 2  # How many torches you take (DungeonRun.STARTING_TORCHES on the first trip).
# Your own map cards you've taken OUT of the map deck, per place: {"Abandoned Farm": ["Bunny Warren"]}.
var map_cards_off := {}
# Saved loadouts: {"name", "class", "spec", "talents", "deck", "flask", "torches", "map_cards_off"}.
var loadouts: Array[Dictionary] = []
var last_loadout := {}  # The setup you last set out with ("Same as last time").
var preparing := false  # Editing your deck/class from the Prepare screen: come back there after.
# --- Place progression: each place has its own Exp, level and perks ---
const AREA_MAX_LEVEL := 15
const AREA_FIRST_LEVEL_EXP := 25  # Exp from level 1 to 2...
const AREA_LEVEL_EXP_STEP := 15  # ...and each level after needs this much more.
const AREA_LEVEL_PACK := "Small Farm Booster Pack"  # Every level up gives one.
var area_exp := {}  # Place name -> its total Exp: {"Abandoned Farm": 140}
var area_perks := {}  # Place name -> the perks you bought: {"Abandoned Farm": ["Camper"]}
# TOOLS you pack on the Prepare screen, paid for from the Bank when you set out.
const TOOL_COSTS := {"Crowbar": {"Stone": 3}, "Bomb": {"Green Ooze": 2, "Stone": 1}}
const MAX_PACKED_TOOLS := 3  # Of each tool.
var packed_tools := {}  # {"Crowbar": 1, "Bomb": 0}
# The JOURNAL: tool tricks you've found ("Locked Shed|Crowbar"), see interaction.gd.
var journal: Array[String] = []
# What you've SCAVENGED from each kind of map card, ever: "Abandoned Farm/Collapsed Wall"
# -> ["Stone", "Gold"]. The board turns a card's "?" into that thing's icon.
var scavenge_finds := {}

# --- The run --------------------------------------------------------------
# A "run" is one trip into an area's dungeon (see dungeon_run.gd): explore
# rooms, beat Mini Bosses, and beat the Boss, Leave at a campfire, or die.
# Your HP carries over from one fight to the next. Then you go back to town,
# and from there you start a new run with full HP.
const GOLD_MIN := 1  # Gold each enemy drops (a random amount between these).
const GOLD_MAX := 3  # Was 1-5: too much gold, not enough Stone (Dusty's playtest, 2026-11-03).

var gold := 0  # Kept between runs, and saved (see "Saving" below).
var dungeon: DungeonRun  # The dungeon in progress (null between runs).
var run_gold := 0  # Gold you took home from the last run, for the shop's summary.
var run_hp := -1  # Your HP between fights. -1 = start the next fight at full HP.
# Map cards you've unlocked with Maps and quests, per place: {"Abandoned Farm": ["Deep Well"]}.
var unlocked_rooms := {}
# Booster packs you own and have not opened yet, by name: {"Small Farm Booster Pack": 2}.
var booster_packs := {}

# --- Town, enchants and potions ---------------------------------------------
# The town (scenes/town.tscn): buildings you restore with gold. Saved.
const TOWN_FOLDER := "res://town/"
const ENCHANTS_FOLDER := "res://enchants/"
const POTIONS_FOLDER := "res://potions/"
const FLASKS_FOLDER := "res://flasks/"
const BASE_SACK_SLOTS := 0  # No Save Sack until the Tailor is built (town.csv: its stage 1 gives 2 slots).
const BASE_GOLD_STACK := 5  # Gold one Save Sack slot holds before the Tailor.
const BASE_POTION_SLOTS := 3  # Potions you can carry before the Alchemist.
const ENCHANT_PRICE := 15  # At the Enchanter.
const MAP_PRICE := 25  # At the Mapmaker.
var town_stages := {}  # Building name -> stage restored: {"Tailor": 2}
# Bought in town for your next run (names): they go into the dungeon when it starts.
var pending_enchants: Array[String] = []
var pending_potions: Array[String] = []
# Flasks (flask.gd): which ones you've unlocked (ones that cost 0 are always
# unlocked), the upgrade stages you've bought per flask, and the one you're
# taking into your next run. All saved.
var unlocked_flasks: Array[String] = []
# Potions you've unlocked at the Alchemist (they can drop in the dungeon), and
# the upgrades you've bought for them: "Stone Skin" -> {"Stronger": 1}.
var unlocked_potions: Array[String] = []
var potion_upgrades := {}
var flask_upgrades := {}  # "Health Flask" -> {"Bigger Die": 1}
var chosen_flask := ""  # "" = the first unlocked one (the Health Flask).
var _flasks: Array[Flask] = []
# Enchants on your deck this run: deck index -> Enchant (each card holds one).
var run_enchants := {}
var _town: Array[TownBuilding] = []
var _enchants: Array[Enchant] = []
var _potions: Array[Potion] = []

# --- Your card collection ----------------------------------------------------
# Which cards you own, and how many: {"Strike": 3, "Punch": 1}. The deck
# builder only shows cards you own, and a deck can't hold more copies than you
# own. Cards marked Unlocked in the spreadsheet start in your collection (as
# many as their Copies column, so you own your starter deck), and you find the
# rest in booster packs.
# How many copies you can own depends on the card's RARITY (CardData.RARITY_LIMITS:
# Common 3, Uncommon 3, Rare 2, Legendary 1). MAX_COPIES is the biggest of them.
const MAX_COPIES := 3
# The chance of each rarity for ONE loose card (a card found in the dungeon).
# They add up to 100. Packs use their own SLOTS instead (below).
const PACK_ODDS := {CardData.Rarity.COMMON: 60, CardData.Rarity.UNCOMMON: 30, CardData.Rarity.RARE: 9, CardData.Rarity.LEGENDARY: 1}
# The booster packs: how many cards each holds, and its Shop price: gold
# AND Farm Stone ("materials"), so you farm the Farm for Farm packs.
# Quest rewards name them by size ("Pack Medium 2", "Pack Foil 1").
#
# SLOTS (from the card doc's "Suggested pack contents"): what each card in
# the pack can be. "C" = a Common, "U" = an Uncommon, "U+" = Uncommon or
# better, with the pack's "plus_odds" chance (out of 100) of a Rare or a
# Legendary instead. So every pack has at least 1 Uncommon, and only Medium
# and Large packs can hold a Rare.
# "pity": the pack counts toward the RARE PITY COUNTER (Small packs don't: Dusty).
# "craft": the Farm supplies that make one at the Shop (card doc: crafting packs).
# "foil": one card is always a foil (a reward, never sold: "for_sale" false).
const PACKS := [
	{"name": "Small Farm Booster Pack", "size": "Small", "cards": 3, "price": 5, "materials": {"Stone": 1}, "booster": "Farm",
		"slots": ["C", "C", "U"], "pity": false, "craft": {"Hay": 3, "Stone": 1}},
	{"name": "Medium Farm Booster Pack", "size": "Medium", "cards": 5, "price": 8, "materials": {"Stone": 2}, "booster": "Farm",
		"slots": ["C", "C", "C", "U", "U+"], "plus_odds": {CardData.Rarity.RARE: 15, CardData.Rarity.LEGENDARY: 1}, "pity": true,
		"craft": {"Wool": 3, "Grain": 2, "Stone": 1}},
	{"name": "Large Farm Booster Pack", "size": "Large", "cards": 7, "price": 11, "materials": {"Stone": 3}, "booster": "Farm",
		"slots": ["C", "C", "C", "C", "U", "U", "U+"], "plus_odds": {CardData.Rarity.RARE: 25, CardData.Rarity.LEGENDARY: 2}, "pity": true,
		"craft": {"Wool": 5, "Grain": 4, "Stone": 2}},
	{"name": "Foil Farm Booster Pack", "size": "Foil", "cards": 5, "price": 0, "materials": {}, "booster": "Farm",
		"slots": ["C", "C", "C", "U", "U+"], "plus_odds": {CardData.Rarity.RARE: 15, CardData.Rarity.LEGENDARY: 1}, "pity": true,
		"foil": true, "for_sale": false},
]
var collection := {}

# --- The Shop's stock ------------------------------------------------------------
# The Shop doesn't sell every pack all the time: after each trip it puts out a
# small ROTATING stock (card doc). Shop upgrades ("Shop Stock" in town.csv) add
# more. Each pack in stock can be bought once; the rest wait for the next trip.
const BASE_SHOP_STOCK := 2
const SHOP_STOCK_WEIGHTS := {"Small": 50, "Medium": 35, "Large": 15}  # How often each size shows up.
var shop_stock: Array[String] = []  # Pack names for sale right now (duplicates allowed).
var trips_done := 0  # Trips that ended (home, Boss or dead): a new stock after each.
var shop_stock_trip := -1  # The trips_done the stock was made for.

# --- Crafting ---------------------------------------------------------------------
# Fill out a playset of a card you've FOUND (you own at least 1) with Essence
# of its school plus supplies (card doc "Crafting and Plans"):
#   Commons and Uncommons: Essence + supplies.
#   Rares and Legendaries: only with a PLAN for that card (one Plan = one
#   copy), plus Essence. Plans drop from bosses (rarely, until Hard Mode).
# Foils can never be crafted: a crafted copy is always plain.
const CRAFT_ESSENCE := {CardData.Rarity.COMMON: 3, CardData.Rarity.UNCOMMON: 6, CardData.Rarity.RARE: 10, CardData.Rarity.LEGENDARY: 20}
const CRAFT_MATERIALS := {CardData.Rarity.COMMON: {"Stone": 1}, CardData.Rarity.UNCOMMON: {"Stone": 2, "Grain": 1},
	CardData.Rarity.RARE: {"Stone": 3}, CardData.Rarity.LEGENDARY: {"Stone": 5}}
var plans := {}  # Card name -> Plans you have for it: {"Iron Wall": 1}

# --- Essence -------------------------------------------------------------------
# A copy past a card's rarity limit turns into ESSENCE of its school(s):
# Strength (red), Agility (green), Intellect (blue), Wisdom (purple), or
# Neutral (grey) for cards with no school. A card with two schools gives the
# full amount of each. Later it crafts cards and gear (see the card doc).
const NEUTRAL := "Neutral"
const ESSENCE_NAMES := ["Strength", "Agility", "Intellect", "Wisdom", NEUTRAL]
const ESSENCE_COLORS := {
	"Strength": Color(0.9, 0.35, 0.3), "Agility": Color(0.4, 0.8, 0.45),
	"Intellect": Color(0.4, 0.6, 1.0), "Wisdom": Color(0.7, 0.45, 0.95), NEUTRAL: Color(0.75, 0.75, 0.75),
}
const ESSENCE_PER_EXTRA := {CardData.Rarity.COMMON: 1, CardData.Rarity.UNCOMMON: 2, CardData.Rarity.RARE: 5, CardData.Rarity.LEGENDARY: 10}
var essence := {}  # {"Strength": 4, "Neutral": 2}

# --- Foils ----------------------------------------------------------------------
# A FOIL is a very rare shiny copy of a card with one stat change (the cards
# sheet's Foil column, see CardData.make_foil()). Any card in a pack has
# FOIL_CHANCE % to be one, and the Foil Farm Booster Pack always has one.
# A foil copy is still a copy: it counts toward the rarity limit, so
# `collection` counts ALL your copies and `foils` says how many of them shine.
const FOIL_CHANCE := 2  # % per card in a pack. My number: the card doc left it open.
var foils := {}  # {"Strike": 1}: 1 of your Strikes is a foil.
# Which copies in your deck are foils: {"Strike": 1} = one of the deck's
# Strikes is the foil one. The deck itself holds the plain cards, so every deck
# rule (copies, schools, size) works just like before.
var deck_foils := {}
const FOIL_MARK := "Foil: "  # Saved decks write a foil copy as "Foil: Strike".
var _foil_cards := {}  # Card name -> its foil CardData, made once (foil_of()).

# --- Rare pity counter ------------------------------------------------------------
# Bad luck has a visible end: open RARE_PITY_PACKS Medium/Large packs without a
# Rare and the last of them is sure to have one. (Card doc: 1 every 5 packs.)
const RARE_PITY_PACKS := 5
var rare_pity := 0  # Medium/Large packs opened since your last Rare (or better).

# --- Binders --------------------------------------------------------------------
# Each place with a booster (Area.booster, "Farm") has a BINDER: every card
# its packs can hold. Cards you haven't found show as silhouettes (binder.gd).
# Finding a NEW card gives that place Exp (BINDER_EXP), so the place's level,
# perks and level-up packs grow from collecting as well as exploring (card
# doc: "one track per biome"). Every 25% found gives a reward from
# data/progression/binder_rewards.csv.
const BINDER_EXP := {CardData.Rarity.COMMON: 5, CardData.Rarity.UNCOMMON: 10, CardData.Rarity.RARE: 20, CardData.Rarity.LEGENDARY: 40}
const BINDER_REWARDS_SHEET := "res://data/progression/binder_rewards.csv"
var binder_claimed := {}  # Place name -> the highest % reward you've had: {"Abandoned Farm": 50}
var explorer_bonus := {}  # Place name -> extra Explorer points (from binder rewards).

# --- Class Exp: spec levels ------------------------------------------------------
# Class Exp goes into the SPEC you're playing (card doc, "Class progression"):
#   - each spec levels on its own, from 1 to SPEC_MAX_LEVEL (10);
#   - a locked spec (Pack Rat before you unlock it) is level 0 and gets no Exp;
#   - the CLASS level is all its spec levels added up, so the Adventurer's 3
#     specs make a class level from 1 to 30.
# Every spec level up gives TWO rewards:
#   1. the spec reward: a class card and/or a booster pack, set per spec and
#      level in data/progression/class_cards.csv;
#   2. the class level reward from the CLASS TRACK (a season pass:
#      data/progression/class_track.csv), plus 1 talent point.
const SPEC_MAX_LEVEL := 10
# Every enemy gives its own Exp (EnemyData.exp: 10 for most, more for bosses)...
const EXP_PER_RUN := 25  # ...plus this for beating all of them.
const FIRST_LEVEL_EXP := 100  # Exp from level 1 to level 2...
const LEVEL_EXP_STEP := 50  # ...and each level after needs this much more.
const CLASS_CARDS_SHEET := "res://data/progression/class_cards.csv"
const CLASS_TRACK_SHEET := "res://data/progression/class_track.csv"
var spec_exp := {}  # Class name -> {spec -> total Exp}: {"Adventurer": {"Jack of All Trades": 140}}
var track_claimed := {}  # Class name -> the highest class level whose track reward you've had.

# Cards that Vanished this run, by their position in `deck` (so with two
# Bandages, we know WHICH one is gone). The battle leaves these out.
var vanished: Array[int] = []

# --- Talents -------------------------------------------------------------------
# Each class has its own talent tree (talent.gd, from data/talents/<class>.csv).
# You get 1 talent point per class level after level 1, plus any bonus points
# (later: clearing areas, quests, bosses), and spend them on talents.
var talent_ranks := {}  # Class name -> {talent name -> rank}: {"Adventurer": {"Big Backpack": 3}}
# Each class's spec: the tree whose spec talent it picked. {"Adventurer": "Pack Rat"}
var class_specs := {}
# false: once you have a spec, points can go in ANY tree (Classic WoW style).
# true: points only go in your spec's tree (modern WoW style).
const SPEC_TREE_ONLY := false
# LEGACY TALENT POINTS: earned from quests (the Old Master's duel...), and
# EVERY class gets them, on top of its own points from leveling up.
var legacy_talent_points := 0
var _bonus_cache := {}  # Remembered talent_bonus() totals (see there).
var talents_return_scene := "res://scenes/character_select.tscn"  # Where the Talents screen's Back goes.
var screen_return_scene := "res://scenes/town.tscn"  # Where the Binder and Class Track screens' Back goes.

# The last deck you built for each class, as card names: {"Knight": ["Strike", ...]}.
# Picking that class again gives you this deck back instead of the starter deck.
var saved_decks := {}

# Remembered lists, so the cards/ folder is only read once (see load_all_cards()).
var _all_cards: Array[CardData] = []
var _cards_by_name := {}  # "Strike" -> its CardData, for find_card().
var _classes: Array[CharacterClass] = []  # For load_classes().
var _talents := {}  # Class name -> its Array[Talent], for talents_for().
var _enemies_by_name := {}  # "Slime" -> its EnemyData, for find_enemy().

const ENEMIES_FOLDER := "res://enemies/"
# Places whose boss you've beaten: ["Abandoned Farm"].
# An area with Unlock After = "Abandoned Farm" opens once the Farm is in here.
var cleared_areas: Array[String] = []
# The last final-Boss win, for the Victory screen (victory.gd): area, boss, opened areas, exp.
var last_victory := {}
# The tutorial (tutorial.gd): which stage is running (0 = none), whether it's
# been finished or skipped (saved), and your real setup while it runs.
var tutorial_stage := 0
var tutorial_done := false
var tutorial_backup := {}

# --- Materials, blueprints and quests (all saved) -------------------------------
var materials := {}  # The Bank: what you've brought home. {"Lumber": 5, "Green Ooze": 3}
var blueprints: Array[String] = []  # Buildings you can build: ["Inn", "Alchemist"]
var active_quests: Array[String] = []  # The quests you're on (story, class and side quests). See quest.gd.
var quest_progress := {}  # Quest name -> kills / rooms / packs / tier counted for it.
var unseen_quests: Array[String] = []  # Just started: town shows their story once.
var quests_done: Array[String] = []
# Parts of the game a quest has opened up ("Unlock Talents" reward), e.g. ["Talents"].
var unlocked_features: Array[String] = []
var seen_guides: Array[String] = []  # Screen guides you've seen (screen_guide.gd): each shows once.
# STORY BEATS: the one-time moments of the start of the game that have
# already played (the King's welcome, the Innkeeper's thanks...). See town.gd.
# Some of them are also MILESTONES that start quests: a quest whose
# "Starts After" is "Inn Built" starts when that beat happens (reach_milestone()).
var story_beats: Array[String] = []
const TALENTS_FEATURE := "Talents"
# The first adventurer moves into the Inn the moment it's built (town.gd).
# Until then you're the Architect, running the town: nobody can explore yet.
const ADVENTURER_FEATURE := "Adventurer"
# Milestones (quests.csv "Starts After" can name one of these instead of a quest).
const INN_BUILT := "Inn Built"  # The Innkeeper has thanked you, and the Adventurer checks in.
const ADVENTURER_TRAINED := "Adventurer Trained"  # Back in town after the training + deck builder: the first quests.
# Story beat: the FIRST TRIP to the Farm is done (you came home with the
# Innkeeper's Stone and Hops). Until then, every Farm trip is that guided one.
const FIRST_TRIP := "First Farm Trip"
const FIRST_LEVEL_UP := "First Level Up"  # Any class reached level 2: the Old Master appears.
# Monsters you've beaten in the dungeons (not the training dummies). Saved.
# The Old Master is impressed by it.
var monsters_slain := 0
# THE DOJO'S MONSTER BOOK. Every monster you've met, by name:
#   {"seen": ["Abandoned Farm, Floor 1", ...], "kills": 3}
# "seen" lists the places you've fought it. Each kill is worth MONSTER_EXP_PER_KILL
# Monster Exp for that monster (nothing uses the levels yet, it's the start of
# the feature). Saved.
var bestiary := {}
const MONSTER_EXP_PER_KILL := 1
# Monster Exp needed for each Monster Level: level 2 at 5, level 3 at 15...
const MONSTER_LEVELS: Array[int] = [5, 15, 30, 50, 75, 100]
# A DUEL: a one-off fight from town (the Old Master), not part of a dungeon
# run. The enemy's name while it's on ("" = none). Losing costs nothing.
# start_duel() keeps your real run here, end_duel() puts it back.
var duel := ""
var duel_backup := {}
var _materials: Array[MaterialInfo] = []
var _quests: Array[Quest] = []


func _ready() -> void:
	start_fresh()
	load_game()  # If there's a save file, it replaces the fresh start.


# A brand new player: the starter cards, no gold, no Exp.
# Used when the game starts, and by the Reset Save button (reset_save()).
func start_fresh() -> void:
	gold = 0
	collection.clear()
	essence.clear()
	foils.clear()
	deck_foils.clear()
	rare_pity = 0
	binder_claimed.clear()
	explorer_bonus.clear()
	spec_exp.clear()
	track_claimed.clear()
	plans.clear()
	shop_stock.clear()
	trips_done = 0
	shop_stock_trip = -1
	booster_packs.clear()
	saved_decks.clear()
	talent_ranks.clear()
	class_specs.clear()
	_talents_changed()
	cleared_areas.clear()
	unlocked_rooms.clear()
	town_stages.clear()
	pending_enchants.clear()
	pending_potions.clear()
	unlocked_flasks.clear()
	flask_upgrades.clear()
	unlocked_potions.clear()
	potion_upgrades.clear()
	chosen_flask = ""
	packed_torches = 2
	area_exp.clear()
	area_perks.clear()
	packed_tools.clear()
	journal.clear()
	scavenge_finds.clear()
	map_cards_off.clear()
	loadouts.clear()
	last_loadout.clear()
	preparing = false
	tutorial_done = false  # A new player sees the tutorial again.
	materials.clear()
	blueprints.clear()
	quests_done.clear()
	unlocked_features.clear()
	seen_guides.clear()
	story_beats.clear()
	active_quests.clear()
	quest_progress.clear()
	unseen_quests.clear()
	# No quests at the start: they only appear once the Inn is built (the
	# town's welcome, in town.gd, hands you the Inn blueprint first).
	legacy_talent_points = 0
	monsters_slain = 0
	bestiary.clear()
	duel = ""
	character_class = null
	deck.clear()
	start_run()
	# Your first cards come at the end of the Adventurer's training
	# (give_starter_cards(), called by tutorial.gd).


# The starter cards (cards.csv Unlocked = TRUE, as many as Copies), given
# at the end of the training. Returns them all for the NEW CARDS screen,
# even ones you already had (so the screen is never empty). If you already
# own more copies than the starter amount, you keep them.
func give_starter_cards() -> Array[CardData]:
	var given: Array[CardData] = []
	for card in load_all_cards():
		if card.unlocked:
			collection[card.card_name] = maxi(owned(card), clampi(card.copies, 1, card.copy_limit()))
			given.append(card)
	return given


# Specs with Unlocked = No in specs.csv open with an "Unlock <spec name>" reward.
func is_spec_open(spec: Talent) -> bool:
	return not spec.spec_locked or unlocked_features.has(spec.talent_name)


# Specs open once the training is done; talent TREES wait for a quest.
func specs_open() -> bool:
	return tutorial_done


# How many copies of this card do you own? (0 = you haven't found it yet.)
func owned(card: CardData) -> int:
	return collection.get(card.card_name, 0)


# Add one copy of a card to your collection. Past its rarity limit (Common 3,
# Uncommon 3, Rare 2, Legendary 1) it turns into Essence instead. Returns what
# happened, for the screen to show:
#   {"card": CardData, "new": true/false, "owned": 2, "essence": {"Strength": 2},
#    "foil": true/false, "upgraded": true/false,
#    "area_exp": [{"area": Area, "exp": 5, "levels": [3]}], "binder": ["reward lines"]}
#
# A FOIL past the limit isn't wasted: if some of your copies are still plain,
# the foil takes one's place ("upgraded") and the plain copy turns into Essence.
func add_card(card: CardData, foil := false) -> Dictionary:
	var result := {"card": card, "new": owned(card) == 0, "essence": {}, "foil": foil, "upgraded": false,
		"area_exp": [], "binder": []}
	if owned(card) < card.copy_limit():
		collection[card.card_name] = owned(card) + 1
		if foil:
			foils[card.card_name] = foils_owned(card) + 1
	elif foil and foils_owned(card) < owned(card):
		foils[card.card_name] = foils_owned(card) + 1
		result.upgraded = true
		_add_essence(card, result)  # The plain copy it replaced.
	else:
		_add_essence(card, result)
	if result.new:
		# A card you'd never found: it fills its place's binder, which gives
		# that place Exp (and maybe a level, a perk point and a pack).
		for area in binder_areas(card):
			var amount: int = BINDER_EXP.get(card.rarity, 5)
			result.area_exp.append({"area": area, "exp": amount, "levels": add_area_exp(area, amount)})
			result.binder.append_array(check_binder(area))
	# Write down the numbers NOW. If the same card comes out twice in one pack,
	# the shop shows each one with the numbers it had at that moment.
	result.owned = owned(card)
	return result


func _add_essence(card: CardData, result: Dictionary) -> void:
	result.essence = essence_for(card)
	for school_name in result.essence:
		essence[school_name] = essence.get(school_name, 0) + result.essence[school_name]


# The Essence one extra copy of this card gives: {"Strength": 2}.
func essence_for(card: CardData) -> Dictionary:
	var amount: int = ESSENCE_PER_EXTRA.get(card.rarity, 1)
	var result := {}
	for school in CardData.School.values():
		if card.schools & school:
			result[CardData.School.find_key(school).capitalize()] = amount
	if result.is_empty():
		result[NEUTRAL] = amount
	return result


# "+2 Strength Essence"
static func essence_text(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for school_name in amounts:
		parts.append("+%d %s" % [amounts[school_name], school_name])
	return ", ".join(parts) + " Essence"


# The pack with this size ("Small") or name. Unknown = the Small one.
func find_pack(size_or_name: String) -> Dictionary:
	for pack in PACKS:
		if pack.size.to_lower() == size_or_name.to_lower() or pack.name.to_lower() == size_or_name.to_lower():
			return pack
	return PACKS[0]


func add_packs(pack_name: String, count: int) -> void:
	booster_packs[pack_name] = booster_packs.get(pack_name, 0) + count


func pack_count() -> int:
	var total := 0
	for pack_name in booster_packs:
		total += booster_packs[pack_name]
	return total


# Open one booster pack you own, each card added to your collection with
# add_card(). Returns what you got, for the shop to show (plus "pity": true on
# the card the pity counter made Rare). Any card can come out, even one you
# already own the most of (it gives Essence).
func open_pack(pack_name: String) -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	if booster_packs.get(pack_name, 0) <= 0:
		return opened
	booster_packs[pack_name] -= 1
	if booster_packs[pack_name] <= 0:
		booster_packs.erase(pack_name)  # None of that pack left.
	record_for_quest(Quest.OPEN_PACKS, pack_name)
	var pack := find_pack(pack_name)
	var slots: Array = pack.get("slots", ["C", "C", "U"])
	# The pity counter: this is the 5th pack without a Rare, so its "U+" card will be one.
	var pity_due: bool = pack.get("pity", false) and rare_pity >= RARE_PITY_PACKS - 1
	var foil_slot := randi() % slots.size() if pack.get("foil", false) else -1
	var got_rare := false
	for i in slots.size():
		var rarity := _roll_slot(slots[i], pack)
		var pity_hit := false
		if pity_due and slots[i] == "U+" and rarity < CardData.Rarity.RARE:
			rarity = CardData.Rarity.RARE
			pity_hit = true
		var card := _card_of_rarity(rarity, pack.get("booster", ""))
		if card == null:
			continue  # Only if no card at all can come from packs.
		var item := add_card(card, i == foil_slot or randi_range(1, 100) <= FOIL_CHANCE)
		item.pity = pity_hit
		opened.append(item)
		if card.rarity >= CardData.Rarity.RARE:
			got_rare = true
	if pack.get("pity", false):
		rare_pity = 0 if got_rare else rare_pity + 1
	save_game()
	return opened


# How many more Medium/Large packs until a Rare is certain (1 = the next one).
func pity_packs_left() -> int:
	return maxi(RARE_PITY_PACKS - rare_pity, 1)


# What one pack slot ("C", "U" or "U+") turns out to be.
func _roll_slot(slot: String, pack: Dictionary) -> CardData.Rarity:
	match slot:
		"C":
			return CardData.Rarity.COMMON
		"U":
			return CardData.Rarity.UNCOMMON
	var odds: Dictionary = pack.get("plus_odds", {})
	var roll := randi_range(1, 100)
	var legendary: int = odds.get(CardData.Rarity.LEGENDARY, 0)
	if roll <= legendary:
		return CardData.Rarity.LEGENDARY
	if roll <= legendary + int(odds.get(CardData.Rarity.RARE, 0)):
		return CardData.Rarity.RARE
	return CardData.Rarity.UNCOMMON


# One random loose card (found in the dungeon): its rarity rolled with PACK_ODDS.
func _pick_pack_card(booster := "") -> CardData:
	var roll := randi_range(1, 100)
	for rarity in PACK_ODDS:
		roll -= PACK_ODDS[rarity]
		if roll <= 0:
			return _card_of_rarity(rarity, booster)
	return _card_of_rarity(CardData.Rarity.COMMON, booster)


# A random pack card of this rarity. If the sheet has none (no Legendary cards
# yet), the next rarity DOWN is used, then up, so a pack is never short.
# Class cards never come from packs: classes get them from spec levels.
# A card with a Booster ("Farm") only comes from that place's packs.
func _card_of_rarity(rarity: int, booster := "") -> CardData:
	var by_rarity := {}  # Rarity -> the cards of that rarity.
	for card in load_all_cards():
		if card.is_class_card():
			continue
		if not card.booster.is_empty() and card.booster.to_lower() != booster.to_lower():
			continue
		if not by_rarity.has(card.rarity):
			by_rarity[card.rarity] = []
		by_rarity[card.rarity].append(card)
	var order: Array = range(rarity, -1, -1) + range(rarity + 1, CardData.Rarity.size())
	for try_rarity in order:
		if by_rarity.has(try_rarity):
			return by_rarity[try_rarity].pick_random()
	return null


# --- Foils ------------------------------------------------------------------------

func foils_owned(card: CardData) -> int:
	return foils.get(card.card_name, 0)


# The shiny version of a card, made once and shared (so it's the same CardData
# everywhere, like the plain cards).
func foil_of(card: CardData) -> CardData:
	if card.is_foil:
		return card
	if not _foil_cards.has(card.card_name):
		_foil_cards[card.card_name] = card.make_foil()
	return _foil_cards[card.card_name]


# The card at this place in your deck as it really plays: the foil version for
# the first deck_foils[name] copies of a card, the plain one after that.
func deck_card(index: int) -> CardData:
	var card := deck[index]
	var foil_copies: int = deck_foils.get(card.card_name, 0)
	if foil_copies <= 0:
		return card
	var before := 0
	for i in index:
		if deck[i] == card:
			before += 1
	return foil_of(card) if before < foil_copies else card


# Keep deck_foils honest: never more foil copies than the deck holds of that
# card, or than you own. fill = true also uses every foil you own (your best
# copies first), for a deck the game builds for you.
func fix_deck_foils(fill := false) -> void:
	var counts := {}
	for card in deck:
		counts[card.card_name] = counts.get(card.card_name, 0) + 1
	var fixed := {}
	for card_name in counts:
		var card := find_card(card_name)
		var want: int = foils_owned(card) if fill else deck_foils.get(card_name, 0)
		var use: int = mini(want, mini(counts[card_name], foils_owned(card)))
		if use > 0:
			fixed[card_name] = use
	deck_foils = fixed


# The deck as names for saving, foil copies marked: ["Foil: Strike", "Strike", "Guard"].
func deck_names() -> Array:
	var names := []
	var marked := {}
	for card in deck:
		var foil_left: int = deck_foils.get(card.card_name, 0) - marked.get(card.card_name, 0)
		if foil_left > 0:
			marked[card.card_name] = marked.get(card.card_name, 0) + 1
			names.append(FOIL_MARK + card.card_name)
		else:
			names.append(card.card_name)
	return names


# Names back into cards. Returns {"cards": [...], "foils": {"Strike": 1}}.
func _read_deck_names(names: Array) -> Dictionary:
	var cards: Array[CardData] = []
	var foil_counts := {}
	for entry in names:
		var card_name := str(entry)
		var is_foil := card_name.begins_with(FOIL_MARK)
		card_name = card_name.trim_prefix(FOIL_MARK)
		var card := find_card(card_name)
		if card:
			cards.append(card)
			if is_foil:
				foil_counts[card_name] = foil_counts.get(card_name, 0) + 1
	return {"cards": cards, "foils": foil_counts}


# --- Crafting -------------------------------------------------------------------------

# What one crafted copy costs: {"essence": {"Strength": 3}, "materials": {"Stone": 1}, "plan": false}.
func craft_cost(card: CardData) -> Dictionary:
	var amount: int = CRAFT_ESSENCE.get(card.rarity, 3)
	var essence_cost := {}
	for school_name in essence_for(card):  # Its school(s), or Neutral.
		essence_cost[school_name] = amount
	return {"essence": essence_cost, "materials": CRAFT_MATERIALS.get(card.rarity, {}),
		"plan": card.rarity >= CardData.Rarity.RARE}


# "6 Strength Essence, 2 Stone, 1 Grain" (+ ", a Plan").
func craft_cost_text(card: CardData) -> String:
	var cost := craft_cost(card)
	var parts: Array[String] = []
	for school_name in cost.essence:
		parts.append("%d %s Essence" % [cost.essence[school_name], school_name])
	if not cost.materials.is_empty():
		parts.append(MaterialInfo.costs_text(cost.materials))
	if cost.plan:
		parts.append("a Plan")
	return ", ".join(parts)


# Why can't you craft a copy of this card? "" = you can.
func why_cant_craft(card: CardData) -> String:
	if card.is_class_card():
		return "Class cards come from spec levels"
	if owned(card) == 0:
		return "Find it first"
	if owned(card) >= card.copy_limit():
		return "You have the most (%d)" % card.copy_limit()
	var cost := craft_cost(card)
	if cost.plan and plans.get(card.card_name, 0) <= 0:
		return "Needs a Plan (bosses drop them)"
	for school_name in cost.essence:
		if essence.get(school_name, 0) < cost.essence[school_name]:
			return "Needs %d %s Essence" % [cost.essence[school_name], school_name]
	if not has_materials(cost.materials):
		return "Needs " + MaterialInfo.costs_text(cost.materials)
	return ""


# Craft one plain copy. Returns false if you can't.
func craft_card(card: CardData) -> bool:
	if not why_cant_craft(card).is_empty():
		return false
	var cost := craft_cost(card)
	for school_name in cost.essence:
		essence[school_name] -= cost.essence[school_name]
	spend_materials(cost.materials)
	if cost.plan:
		plans[card.card_name] -= 1
		if plans[card.card_name] <= 0:
			plans.erase(card.card_name)
	add_card(card)
	save_game()
	return true


# A random Rare or Legendary from this place's binder, for a Plan (null if none).
func random_plan_card(area: Area) -> CardData:
	if area == null:
		return null
	var choices := binder_cards(area).filter(func(c: CardData) -> bool: return c.rarity >= CardData.Rarity.RARE)
	return choices.pick_random() if not choices.is_empty() else null


func _area_named(place: String) -> Area:
	for area in load_areas():
		if area.display_name.to_lower() == place.to_lower():
			return area
	return null


# Craft a booster pack from supplies (the pack's "craft" in PACKS).
func can_craft_pack(pack: Dictionary) -> bool:
	return pack.has("craft") and has_materials(pack.craft)


func craft_pack(pack: Dictionary) -> bool:
	if not can_craft_pack(pack):
		return false
	spend_materials(pack.craft)
	add_packs(pack.name, 1)
	save_game()
	return true


# --- The Shop's stock --------------------------------------------------------------

func shop_stock_size() -> int:
	return BASE_SHOP_STOCK + town_bonus(TownBuilding.SHOP_STOCK)


# A trip ended (DungeonRun.claim_loot()): the Shop restocks next time you look.
func trip_ended() -> void:
	trips_done += 1


# Make a new stock if a trip has ended since the last one (the Shop calls this).
func check_shop_stock() -> void:
	if shop_stock_trip == trips_done:
		return
	shop_stock_trip = trips_done
	shop_stock.clear()
	var total := 0
	for size in SHOP_STOCK_WEIGHTS:
		total += SHOP_STOCK_WEIGHTS[size]
	for i in shop_stock_size():
		var roll := randi_range(1, total)
		for size in SHOP_STOCK_WEIGHTS:
			roll -= SHOP_STOCK_WEIGHTS[size]
			if roll <= 0:
				shop_stock.append(find_pack(size).name)
				break
	save_game()


# --- Binders ----------------------------------------------------------------------

# Every card in this place's binder (the cards its booster packs can hold),
# Commons first, then by name. Empty if the place has no booster.
func binder_cards(area: Area) -> Array[CardData]:
	var cards: Array[CardData] = []
	if area == null or area.booster.is_empty():
		return cards
	if _binders.has(area.booster):  # Worked out once per booster, then remembered.
		return _binders[area.booster]
	for card in load_all_cards():
		if card.is_class_card():
			continue  # Class cards come from spec levels, not packs.
		if card.booster.is_empty() or card.booster.to_lower() == area.booster.to_lower():
			cards.append(card)
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return a.card_name < b.card_name)
	_binders[area.booster] = cards
	return cards


# The places whose binder holds this card.
func binder_areas(card: CardData) -> Array[Area]:
	var areas: Array[Area] = []
	if card.is_class_card():
		return areas
	for area in load_areas():
		if not area.booster.is_empty() and (card.booster.is_empty() or card.booster.to_lower() == area.booster.to_lower()):
			areas.append(area)
	return areas


func binder_found(area: Area) -> int:
	return binder_cards(area).filter(func(card: CardData) -> bool: return owned(card) > 0).size()


# How much of the binder you've found, 0 to 100.
func binder_percent(area: Area) -> int:
	var total := binder_cards(area).size()
	return 0 if total == 0 else floori(100.0 * binder_found(area) / total)


# A sheet read while the game runs (binder rewards, class cards, the class
# track): read from disk once, then remembered. Screens like the Class Track
# ask for these many times while they draw.
var _sheets := {}
var _binders := {}  # Booster name -> its binder_cards(), sorted.


func _sheet(path: String) -> Array[Dictionary]:
	if not _sheets.has(path):
		_sheets[path] = CardImporter._read_sheet(path)
	return _sheets[path]


# The binder rewards for this place: [{"percent": 25, "rewards": "Pack Medium 1"}], lowest first.
func binder_rewards(area: Area) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for row in _sheet(BINDER_REWARDS_SHEET):
		if row.get("area", "").to_lower() == area.display_name.to_lower():
			list.append({"percent": CardImporter._to_int(row.get("percent", ""), 100), "rewards": row.get("rewards", ""),
				"text": row.get("text", "")})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.percent < b.percent)
	return list


# Give any binder rewards you've just reached. Returns what they gave, as lines.
func check_binder(area: Area) -> Array[String]:
	var lines: Array[String] = []
	var percent := binder_percent(area)
	var claimed: int = binder_claimed.get(area.display_name, 0)
	for reward in binder_rewards(area):
		if reward.percent > claimed and reward.percent <= percent:
			binder_claimed[area.display_name] = reward.percent
			for line in give_rewards(reward.rewards):
				lines.append("%s binder %d%%: %s" % [area.display_name, reward.percent, line])
	return lines


# How much Exp it takes to go from `level` to the next one: 100, 150, 200...
func exp_for_next_level(level: int) -> int:
	return FIRST_LEVEL_EXP + LEVEL_EXP_STEP * (level - 1)


# The spec that gets this class's Exp: the one you picked, or (before you pick)
# the first open one. "" for a class with no specs.
func exp_spec(for_class: CharacterClass) -> String:
	if not spec_of(for_class).is_empty():
		return spec_of(for_class)
	for spec in specs_for(for_class):
		if is_spec_open(spec):
			return spec.tree
	return ""


# A spec's level, from its Exp: 0 while it's locked, then 1 to SPEC_MAX_LEVEL.
func spec_level(for_class: CharacterClass, spec_name: String) -> int:
	var spec := _spec_named(for_class, spec_name)
	if spec and not is_spec_open(spec):
		return 0
	var exp_left: int = spec_exp.get(for_class.display_name, {}).get(spec_name, 0)
	var level := 1
	while level < SPEC_MAX_LEVEL and exp_left >= exp_for_next_level(level):
		exp_left -= exp_for_next_level(level)
		level += 1
	return level


# Progress towards the spec's next level, for the Exp bar: Vector2i(40, 150)
# means "40 of the 150 Exp needed". (0, 0) at the max level or while locked.
func spec_exp_progress(for_class: CharacterClass, spec_name: String) -> Vector2i:
	var level := spec_level(for_class, spec_name)
	if level >= SPEC_MAX_LEVEL or level == 0:
		return Vector2i.ZERO
	var exp_left: int = spec_exp.get(for_class.display_name, {}).get(spec_name, 0)
	for i in range(1, level):
		exp_left -= exp_for_next_level(i)
	return Vector2i(exp_left, exp_for_next_level(level))


func _spec_named(for_class: CharacterClass, spec_name: String) -> Talent:
	for spec in specs_for(for_class):
		if spec.tree == spec_name:
			return spec
	return null


# The CLASS level: every spec's level added up (at least 1).
func class_level(for_class: CharacterClass) -> int:
	var specs := specs_for(for_class)
	if specs.is_empty():
		return spec_level(for_class, "")  # A class with no specs levels by itself.
	var total := 0
	for spec in specs:
		total += spec_level(for_class, spec.tree)
	return maxi(total, 1)


# The highest class level there is: 10 per spec (30 for the Adventurer).
func class_max_level(for_class: CharacterClass) -> int:
	return SPEC_MAX_LEVEL * maxi(specs_for(for_class).size(), 1)


# The Exp bar's progress for the spec that's getting Exp now.

# Is the spec you'd get Exp for already at the top? Then Exp is wasted
# (the Prepare screen warns you before you set out).
func spec_maxed(for_class: CharacterClass) -> bool:
	return spec_level(for_class, exp_spec(for_class)) >= SPEC_MAX_LEVEL


# Give the chosen class some Exp (it goes into the spec you're playing).
# Returns one entry per level gained:
#   [{"spec": "Jack of All Trades", "level": 3, "class_level": 4,
#     "spec_rewards": ["Trail Rations", ...], "track": ["10 gold", ...]}]
func add_class_exp(amount: int) -> Array[Dictionary]:
	var level_ups: Array[Dictionary] = []
	var spec_name := exp_spec(character_class)
	if spec_maxed(character_class):
		return level_ups  # Nothing to fill: the spec is already at the top.
	var level_before := spec_level(character_class, spec_name)
	var exps: Dictionary = spec_exp.get(character_class.display_name, {})
	exps[spec_name] = exps.get(spec_name, 0) + amount
	spec_exp[character_class.display_name] = exps
	for level in range(level_before + 1, spec_level(character_class, spec_name) + 1):
		level_ups.append({"spec": spec_name, "level": level,
			"spec_rewards": give_spec_rewards(character_class, spec_name, level),
			"class_level": class_level(character_class) - (spec_level(character_class, spec_name) - level),
			"track": []})
	# The class track: one reward per class level reached (claim_class_track()
	# hands out each one only once). They go on the LAST level up's entry.
	if not level_ups.is_empty():
		level_ups[-1].track = claim_class_track(character_class)
		reach_milestone(FIRST_LEVEL_UP)  # The first time: the Old Master's quest (only once).
	save_game()
	return level_ups


# The spec reward rows for this class: [{"spec", "level", "card", "copies", "pack"}].
func spec_reward_rows(for_class: CharacterClass) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in _sheet(CLASS_CARDS_SHEET):
		if row.get("class", "").to_lower() != for_class.display_name.to_lower():
			continue
		rows.append({"spec": row.get("spec", ""), "level": CardImporter._to_int(row.get("level", ""), 2),
			"card": row.get("card", ""), "copies": maxi(CardImporter._to_int(row.get("copies", ""), 1), 1),
			"pack": row.get("pack", "")})
	return rows


# The spec reward for reaching `level` in a spec, as reward text for
# give_rewards(): "Card Trail Rations 2; Pack Small 1".
func spec_reward_text(for_class: CharacterClass, spec_name: String, level: int) -> String:
	var parts: Array[String] = []
	for row in spec_reward_rows(for_class):
		# A blank Spec means "every spec of this class".
		if row.level == level and (row.spec.is_empty() or row.spec.to_lower() == spec_name.to_lower()):
			if not row.card.is_empty():
				parts.append("Card %s %d" % [row.card, row.copies])
			if not row.pack.is_empty():
				parts.append("Pack " + row.pack)
	return "; ".join(parts)


func give_spec_rewards(for_class: CharacterClass, spec_name: String, level: int) -> Array[String]:
	return give_rewards(spec_reward_text(for_class, spec_name, level))


# The class track, level by level: [{"level": 2, "rewards": "Gold 10", "text": ""}].
# Every level also gives 1 talent point (talent_points_earned() counts those).
func class_track(for_class: CharacterClass) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in _sheet(CLASS_TRACK_SHEET):
		if row.get("class", "").to_lower() == for_class.display_name.to_lower():
			rows.append({"level": CardImporter._to_int(row.get("level", ""), 0), "rewards": row.get("rewards", ""),
				"text": row.get("text", "")})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.level < b.level)
	return rows


# Hand out every class track reward you've reached but not had yet.
# Returns what they gave, as lines ("Class level 4: 10 gold").
func claim_class_track(for_class: CharacterClass) -> Array[String]:
	var lines: Array[String] = []
	var level := class_level(for_class)
	var claimed: int = track_claimed.get(for_class.display_name, 1)  # Level 1 is where you start.
	if level <= claimed:
		return lines
	for row in class_track(for_class):
		if row.level > claimed and row.level <= level:
			for line in give_rewards(row.rewards):
				lines.append("Class level %d: %s" % [row.level, line])
	for reached in range(claimed + 1, level + 1):
		lines.append("Class level %d: +1 talent point" % reached)
	track_claimed[for_class.display_name] = level
	return lines


# A spec just unlocked (level 0 -> 1): the class goes up a level too.
func _spec_unlocked(spec_name: String) -> Array[String]:
	var lines: Array[String] = []
	for for_class in load_classes():
		if _spec_named(for_class, spec_name):
			lines.append_array(claim_class_track(for_class))
	return lines


# --- Duels ------------------------------------------------------------------------

# Fight one enemy straight from town (the Old Master), with your current class
# and deck at full HP. Then change to the battle scene.
func start_duel(enemy_name: String) -> void:
	ensure_ready()
	duel_backup = {"dungeon": dungeon, "run_hp": run_hp, "vanished": vanished.duplicate(),
		"enchants": run_enchants.duplicate()}
	duel = enemy_name
	run_hp = -1
	vanished.clear()
	run_enchants.clear()
	var fight := DungeonRun.new(current_area)  # Not start()ed: no board, just this fight.
	var enemy := find_enemy(enemy_name)
	if enemy:
		fight.fight_enemies.append(enemy)
	# Bring your flask, full (no potions: those are for the dungeon).
	fight.flask = current_flask()
	if fight.flask:
		fight.flask_stats = flask_stats(fight.flask)
		fight.flask_charges = fight.flask_stats[Flask.CHARGES]
	dungeon = fight


# The duel is over (won or lost): put your real run back.
func end_duel() -> void:
	if not duel_backup.is_empty():
		dungeon = duel_backup.dungeon
		run_hp = duel_backup.run_hp
		vanished = duel_backup.vanished
		run_enchants = duel_backup.enchants
	duel_backup = {}
	duel = ""
	save_game()


# The card with this name, or null.
func find_card(card_name: String) -> CardData:
	if _cards_by_name.is_empty():
		for card in load_all_cards():
			_cards_by_name[card.card_name] = card
	return _cards_by_name.get(card_name)


# The enemies for the current fight: the dungeon room you stepped into
# picked them (see dungeon_run.gd). An empty list = no enemies were set up.
func current_encounter() -> Array[EnemyData]:
	var enemies: Array[EnemyData] = []
	if dungeon:
		enemies.assign(dungeon.fight_enemies)
	return enemies


# Called when you pick an area on the map: a fresh run there.
func start_run() -> void:
	run_gold = 0
	run_hp = -1
	vanished.clear()  # Vanished cards come back for a new run.
	run_enchants.clear()  # Enchants only last one run.
	dungeon = DungeonRun.new(current_area) if current_area else null
	if dungeon:
		dungeon.start()  # Build the map deck and deal the first board.
		# What you bought in town for this run.
		for enchant_name in pending_enchants:
			var enchant := find_enchant(enchant_name)
			if enchant:
				dungeon.enchant_drops.append([enchant])
		for potion_name in pending_potions:
			var potion := find_potion(potion_name)
			if potion:
				dungeon.add_potion(potion)
		# Your flask, full of charges.
		dungeon.flask = current_flask()
		if dungeon.flask:
			dungeon.flask_stats = flask_stats(dungeon.flask)
			dungeon.flask_charges = dungeon.flask_stats[Flask.CHARGES]
		# The tools you packed, paid for from the Bank (as many as you can afford).
		if not dungeon.guided:
			for tool_name in packed_tools:
				for i in packed_tools[tool_name]:
					var cost: Dictionary = TOOL_COSTS.get(tool_name, {})
					if not has_materials(cost) or dungeon.pack_item(tool_name, 1) == 0:
						break
					spend_materials(cost)
			dungeon.left_over.clear()
		# Starter Kit perks: a potion for every trip to this place.
		for perk in owned_area_perks(current_area):
			if perk.effect == AreaPerk.START_POTION:
				var potion := find_potion(perk.target)
				if potion:
					dungeon.add_potion(potion)
		if not pending_enchants.is_empty() or not pending_potions.is_empty():
			pending_enchants.clear()
			pending_potions.clear()
			save_game()


# --- The town ------------------------------------------------------------------

func load_town() -> Array[TownBuilding]:
	if _town.is_empty():
		for file_name in ResourceLoader.list_directory(TOWN_FOLDER):
			if file_name.ends_with(".tres"):
				_town.append(load(TOWN_FOLDER + file_name))
		_town.sort_custom(func(a: TownBuilding, b: TownBuilding) -> bool: return a.sort_order < b.sort_order)
	return _town


# How far a building is restored: 0 = ruins. Stages that cost nothing at all
# (no gold, no materials, no blueprint) are restored from the start.
func town_stage(building: TownBuilding) -> int:
	var free := 0
	if not building.needs_blueprint:
		while free < building.costs.size() and building.costs[free] == 0 and building.materials_for_next(free).is_empty():
			free += 1
	return maxi(town_stages.get(building.building_name, 0), free)


# Shown in town? Buildings that need a blueprint stay hidden until a quest gives it.
func has_blueprint(building: TownBuilding) -> bool:
	return not building.needs_blueprint or blueprints.has(building.building_name)


# Why you can't build the next stage right now ("" = you can).
func restore_blocked(building: TownBuilding) -> String:
	var stage := town_stage(building)
	if stage >= building.max_stage():
		return "Fully restored"
	if not has_blueprint(building):
		return "You need its blueprint"
	if gold < building.cost_of_next(stage):
		return "Needs %d gold" % building.cost_of_next(stage)
	var needs := building.materials_for_next(stage)
	if not has_materials(needs):
		return "Needs " + MaterialInfo.costs_text(needs)
	return ""


# Pay for the next stage. Returns false if you can't afford it (or it's done).
func restore(building: TownBuilding) -> bool:
	if not restore_blocked(building).is_empty():
		return false
	var stage := town_stage(building)
	gold -= building.cost_of_next(stage)
	spend_materials(building.materials_for_next(stage))
	town_stages[building.building_name] = stage + 1
	check_quest()
	save_game()
	return true


# --- Materials (the Bank) --------------------------------------------------------

func load_materials() -> Array[MaterialInfo]:
	if _materials.is_empty():
		for file_name in ResourceLoader.list_directory(CardImporter.MATERIALS_FOLDER):
			if file_name.ends_with(".tres"):
				_materials.append(load(CardImporter.MATERIALS_FOLDER + file_name))
	return _materials


func find_material(material_name: String) -> MaterialInfo:
	for info in load_materials():
		if info.material_name == material_name:
			return info
	return null


func material_count(material_name: String) -> int:
	return materials.get(material_name, 0)


func add_material(material_name: String, amount: int) -> void:
	materials[material_name] = material_count(material_name) + amount


func has_materials(costs: Dictionary) -> bool:
	for material_name in costs:
		if material_count(material_name) < costs[material_name]:
			return false
	return true


func spend_materials(costs: Dictionary) -> void:
	for material_name in costs:
		materials[material_name] = maxi(material_count(material_name) - costs[material_name], 0)


# --- Quests (see quest.gd) --------------------------------------------------------

func load_quests() -> Array[Quest]:
	if _quests.is_empty():
		for file_name in ResourceLoader.list_directory(CardImporter.QUESTS_FOLDER):
			if file_name.ends_with(".tres"):
				_quests.append(load(CardImporter.QUESTS_FOLDER + file_name))
		_quests.sort_custom(func(a: Quest, b: Quest) -> bool: return a.sort_order < b.sort_order)
	return _quests


func find_quest(quest_name: String) -> Quest:
	for quest in load_quests():
		if quest.quest_name == quest_name:
			return quest
	return null


# The STORY quest you're on (null = none). Side and class quests run
# alongside it: see quests_active().
# Every quest you're on, story first, in quests.csv order.
func quests_active() -> Array[Quest]:
	var list: Array[Quest] = []
	for quest in load_quests():
		if active_quests.has(quest.quest_name):
			list.append(quest)
	# Story quests first, then the rest in their sheet order.
	list.sort_custom(func(a: Quest, b: Quest) -> bool:
		var a_story := a.quest_type == "Story"
		var b_story := b.quest_type == "Story"
		if a_story != b_story:
			return a_story
		return a.sort_order < b.sort_order)
	return list


# Start a quest: hand out its Start Gift, and town shows its story next visit.
func start_quest(quest_name: String) -> void:
	var quest := find_quest(quest_name)
	if quest == null or active_quests.has(quest.quest_name) or quests_done.has(quest.quest_name):
		return
	active_quests.append(quest.quest_name)
	quest_progress[quest.quest_name] = 0
	unseen_quests.append(quest.quest_name)
	give_rewards(quest.start_gift)


# How far along a quest is, and how much it needs: Vector2i(3, 5).
func quest_status(quest: Quest) -> Vector2i:
	if quest == null:
		return Vector2i.ZERO
	match quest.objective:
		Quest.BUILD:
			var building := find_building(quest.target)
			return Vector2i(mini(town_stage(building) if building else 0, 1), 1)
		Quest.HAVE, Quest.DELIVER:
			return Vector2i(mini(material_count(quest.target), quest.amount), quest.amount)
		Quest.BREW:
			var flask := find_flask(quest.target)
			return Vector2i(1 if flask and is_flask_unlocked(flask) else 0, 1)
	return Vector2i(mini(quest_progress.get(quest.quest_name, 0), quest.amount), quest.amount)


func quest_ready(quest: Quest) -> bool:
	if quest == null or not active_quests.has(quest.quest_name):
		return false
	var status := quest_status(quest)
	return status.x >= status.y


# How many of your quests are done and waiting to be handed in.
func quests_ready_count() -> int:
	return quests_active().filter(quest_ready).size()


# Count something for every quest it fits: a kill, a beaten room, a pack, a tier.
func record_for_quest(objective: String, target: String, value: int = 1) -> void:
	for quest in quests_active():
		if quest.objective != objective:
			continue
		var count: int = quest_progress.get(quest.quest_name, 0)
		if objective == Quest.REACH_TIER:
			quest_progress[quest.quest_name] = maxi(count, value)
		elif quest.target.to_lower() == target.to_lower() or quest.target.to_lower() == Quest.ANY \
				or (objective == Quest.OPEN_PACKS and target.to_lower().contains(quest.target.to_lower())):
			quest_progress[quest.quest_name] = count + value


# Nothing to do here yet: quests are handed in at the Inn (town.gd).
func check_quest() -> void:
	pass


# Hand in a quest: rewards, then its Next Quest starts, and any quest whose
# Starts After names it. Returns what you got, one line each.
func complete_quest(quest: Quest) -> Array[String]:
	if not quest_ready(quest):
		return []
	active_quests.erase(quest.quest_name)
	quest_progress.erase(quest.quest_name)
	unseen_quests.erase(quest.quest_name)
	quests_done.append(quest.quest_name)
	# Deliver: you hand the materials over (Have just checks you've got them).
	if quest.objective == Quest.DELIVER:
		spend_materials({quest.target: quest.amount})
	var lines := give_rewards(quest.rewards)
	start_quest(quest.next_quest)
	_start_quests_after(quest.quest_name)
	save_game()
	return lines


func _start_quests_after(done_name: String) -> void:
	for other in load_quests():
		if other.starts_after == done_name:
			start_quest(other.quest_name)


# A one-time story moment (a STORY BEAT) has happened. Returns false if it
# already had. Quests whose Starts After names it start now.
func reach_milestone(beat: String) -> bool:
	if story_beats.has(beat):
		return false
	story_beats.append(beat)
	_start_quests_after(beat)
	save_game()
	return true


# What your quests want you to bring home (the dungeon's HUNTING LIST, and
# the first trip's goal): every material an active Have or Deliver quest
# needs, e.g. {"Stone": 5, "Hops": 3}.
func guide_needs() -> Dictionary:
	var needs := {}
	for quest in quests_active():
		if quest.objective in [Quest.HAVE, Quest.DELIVER]:
			needs[quest.target] = needs.get(quest.target, 0) + quest.amount
	return needs


# "Gold 20; Pack 1; Material Lumber 5; Blueprint Alchemist; Room Abandoned Farm: Big Slime Nest"
# unlocks_only = true skips gold, packs and materials and only hands out
# blueprints, rooms and unlocks. load_game() uses that to catch an old save up
# when a quest it already finished gets a new reward in quests.csv (giving
# those twice is harmless; giving gold twice would not be).
func give_rewards(text: String, unlocks_only := false) -> Array[String]:
	var lines: Array[String] = []
	for part in text.split(";", false):
		var reward := part.strip_edges()
		var words := reward.split(" ", false)
		if words.is_empty():
			continue
		var rest := reward.substr(words[0].length()).strip_edges()
		if unlocks_only and not words[0].to_lower() in ["blueprint", "room", "unlock"]:
			continue
		match words[0].to_lower():
			"gold":
				gold += rest.to_int()
				lines.append("%d gold" % rest.to_int())
			"pack":  # "Pack Small 2" (or just "Pack 2" = Small)
				var size_word := rest.get_slice(" ", 0) if rest.get_slice(" ", 0).to_int() == 0 else "Small"
				var count := maxi(rest.get_slice(" ", rest.get_slice_count(" ") - 1).to_int(), 1)
				var pack := find_pack(size_word)
				add_packs(pack.name, count)
				lines.append("%d %s%s" % [count, pack.name, "s" if count > 1 else ""])
			"material":
				var costs := MaterialInfo.parse_costs(rest)
				for material_name in costs:
					add_material(material_name, costs[material_name])
				lines.append(MaterialInfo.costs_text(costs))
			"blueprint":
				if not blueprints.has(rest):
					blueprints.append(rest)
				lines.append("Blueprint: " + rest)
			"room":  # "Room Abandoned Farm: Blue Slime Patch"
				var area_name := rest.get_slice(":", 0).strip_edges()
				var room_name := rest.get_slice(":", 1).strip_edges()
				if not unlocked_rooms.has(area_name):
					unlocked_rooms[area_name] = []
				if not unlocked_rooms[area_name].has(room_name):
					unlocked_rooms[area_name].append(room_name)
				lines.append("New map card for the %s: %s" % [area_name, room_name])
			"essence":  # "Essence Strength 5" (or "Essence 5" = Neutral)
				var count := maxi(rest.get_slice(" ", rest.get_slice_count(" ") - 1).to_int(), 1)
				var school_name := rest.get_slice(" ", 0).capitalize() if rest.get_slice(" ", 0).to_int() == 0 else NEUTRAL
				essence[school_name] = essence.get(school_name, 0) + count
				lines.append("%d %s Essence" % [count, school_name])
			"card":  # "Card Trail Rations 2": copies of a card (class cards from spec levels).
				var count := 1
				var card_name := rest
				if rest.get_slice_count(" ") > 1 and rest.get_slice(" ", rest.get_slice_count(" ") - 1).is_valid_int():
					count = rest.get_slice(" ", rest.get_slice_count(" ") - 1).to_int()
					card_name = rest.substr(0, rest.rfind(" ")).strip_edges()
				var card := find_card(card_name)
				if card == null:
					push_warning("Reward: there's no card called '%s'" % card_name)
					continue
				for i in maxi(count, 1):
					var got := add_card(card)
					lines.append(card.card_name + (" (%s)" % essence_text(got.essence) if not got.essence.is_empty() else ""))
			"plan":  # "Plan Iron Wall" (a Plan for that card) or "Plan Abandoned Farm" (a random one from its binder).
				var plan_card := find_card(rest)
				if plan_card == null:
					plan_card = random_plan_card(_area_named(rest))
				if plan_card == null:
					continue
				plans[plan_card.card_name] = plans.get(plan_card.card_name, 0) + 1
				lines.append("a Plan: %s (crafts 1 copy)" % plan_card.card_name)
			"binder":  # "Binder Card Abandoned Farm 1": cards you haven't found yet, from that binder.
				var count := 1
				var place := rest.trim_prefix("Card").strip_edges()
				if place.get_slice(" ", place.get_slice_count(" ") - 1).is_valid_int():
					count = place.get_slice(" ", place.get_slice_count(" ") - 1).to_int()
					place = place.substr(0, place.rfind(" ")).strip_edges()
				var area := _area_named(place)
				for i in maxi(count, 1):
					var unfound := binder_cards(area).filter(func(c: CardData) -> bool: return owned(c) == 0) if area else []
					if unfound.is_empty():
						lines.append_array(give_rewards("Pack Small 1"))  # The binder's full: a pack instead.
						continue
					var got := add_card(unfound.pick_random())
					lines.append("a new card for your binder: %s" % got.card.card_name)
					lines.append_array(got.binder)
			"explorer":  # "Explorer Abandoned Farm 1": extra Explorer points for that place's perks.
				var points := 1
				var place := rest
				if rest.get_slice(" ", rest.get_slice_count(" ") - 1).is_valid_int():
					points = rest.get_slice(" ", rest.get_slice_count(" ") - 1).to_int()
					place = rest.substr(0, rest.rfind(" ")).strip_edges()
				explorer_bonus[place] = explorer_bonus.get(place, 0) + points
				lines.append("%d Explorer point%s for the %s" % [points, "" if points == 1 else "s", place])
			"legacy":  # "Legacy Point 1": Legacy Talent Points, for every class.
				var points := maxi(rest.get_slice(" ", rest.get_slice_count(" ") - 1).to_int(), 1)
				legacy_talent_points += points
				lines.append("%d Legacy Talent Point%s" % [points, "s" if points > 1 else ""])
			"unlock":  # "Unlock Talents": opens up a part of the game.
				if not unlocked_features.has(rest):
					unlocked_features.append(rest)
					# A spec (Pack Rat) goes from level 0 to 1: a class level, so a track reward.
					if not unlocks_only:
						lines.append_array(_spec_unlocked(rest))
				lines.append("%s unlocked!" % ("Talent System" if rest == TALENTS_FEATURE else rest))
			_:
				push_warning("quests.csv: unknown reward '%s'" % reward)
	return lines


func find_building(building_name: String) -> TownBuilding:
	for building in load_town():
		if building.building_name == building_name:
			return building
	return null


# One effect added up over every building's restored stages, e.g.
# town_bonus(TownBuilding.SACK_SLOTS) = 1 once the Tailor is at stage 1.
func town_bonus(effect: String) -> int:
	var total := 0
	for building in load_town():
		total += building.bonus(effect, town_stage(building))
	return total


func sack_slots() -> int:
	return BASE_SACK_SLOTS + town_bonus(TownBuilding.SACK_SLOTS)


# The Save Sack only exists once the Tailor has sewn it.
func sack_open() -> bool:
	return sack_slots() > 0


# Enchants only drop (and show up in events) once the Enchanter is built.
func enchants_open() -> bool:
	return town_bonus(TownBuilding.ENCHANTER) > 0


func gold_stack() -> int:
	return BASE_GOLD_STACK + town_bonus(TownBuilding.GOLD_STACK)


func potion_slots() -> int:
	return BASE_POTION_SLOTS + town_bonus(TownBuilding.POTION_SLOTS)


# --- Flasks ------------------------------------------------------------------------

func load_flasks() -> Array[Flask]:
	if _flasks.is_empty():
		for file_name in ResourceLoader.list_directory(FLASKS_FOLDER):
			if file_name.ends_with(".tres"):
				_flasks.append(load(FLASKS_FOLDER + file_name))
		_flasks.sort_custom(func(a: Flask, b: Flask) -> bool: return a.sort_order < b.sort_order)
	return _flasks


func find_flask(flask_name: String) -> Flask:
	for flask in load_flasks():
		if flask.flask_name == flask_name:
			return flask
	return null


func is_flask_unlocked(flask: Flask) -> bool:
	return flask.starts_unlocked() or unlocked_flasks.has(flask.flask_name)


# The flask you'll take on your next run: the one you chose, or else the
# first unlocked one. null only if flasks/ is empty.
func current_flask() -> Flask:
	var first: Flask = null
	for flask in load_flasks():
		if is_flask_unlocked(flask):
			if flask.flask_name == chosen_flask:
				return flask
			if first == null:
				first = flask
	return first


# How many stages of one upgrade you've bought (0 = none).
func flask_upgrade_stage(flask: Flask, upgrade: String) -> int:
	return int(flask_upgrades.get(flask.flask_name, {}).get(upgrade, 0))


# What the flask does with your upgrades (see Flask.stats()).
func flask_stats(flask: Flask) -> Dictionary:
	return flask.stats(flask_upgrades.get(flask.flask_name, {}))


# Flasks are unlocked and upgraded at the Alchemist, so it has to be open.
func alchemist_open() -> bool:
	return town_bonus(TownBuilding.ALCHEMIST) > 0


func unlock_flask(flask: Flask) -> bool:
	var needs := MaterialInfo.parse_costs(flask.unlock_materials)
	if is_flask_unlocked(flask) or not alchemist_open() or gold < flask.unlock_cost or not has_materials(needs):
		return false
	gold -= flask.unlock_cost
	spend_materials(needs)
	unlocked_flasks.append(flask.flask_name)
	save_game()
	return true


# Buy the next stage of one upgrade. Returns false if you can't.
func buy_flask_upgrade(flask: Flask, upgrade: String) -> bool:
	var stages := flask.stages_of(upgrade)
	var stage := flask_upgrade_stage(flask, upgrade)
	if not is_flask_unlocked(flask) or not alchemist_open() or stage >= stages.size():
		return false
	var cost: int = flask.costs[stages[stage]]
	if gold < cost:
		return false
	gold -= cost
	if not flask_upgrades.has(flask.flask_name):
		flask_upgrades[flask.flask_name] = {}
	flask_upgrades[flask.flask_name][upgrade] = stage + 1
	save_game()
	return true


# --- Enchants and potions ---------------------------------------------------------

func load_enchants() -> Array[Enchant]:
	if _enchants.is_empty():
		for file_name in ResourceLoader.list_directory(ENCHANTS_FOLDER):
			if file_name.ends_with(".tres"):
				_enchants.append(load(ENCHANTS_FOLDER + file_name))
	return _enchants


func load_potions() -> Array[Potion]:
	if _potions.is_empty():
		for file_name in ResourceLoader.list_directory(POTIONS_FOLDER):
			if file_name.ends_with(".tres"):
				_potions.append(load(POTIONS_FOLDER + file_name))
	return _potions


# --- Potions at the Alchemist -----------------------------------------------------
#
# Potions only drop in the dungeon once the Alchemist is built. Building it
# unlocks the STARTER_POTION for free; the rest you unlock there for gold and
# Green Ooze. An unlocked potion has two upgrades, each with 2 stages:
#   Stronger    - its numbers x1.5, then x2 (see strengthened()).
#   More Common - it drops 2x as often, then 3x (see roll_dropped_potion()).

const STARTER_POTION := "Healing Potion"
const STRONGER := "Stronger"
const MORE_COMMON := "More Common"
# What unlocking a potion costs, by rarity: [gold, Green Ooze].
const POTION_UNLOCK_COSTS := {
	CardData.Rarity.COMMON: [15, 2],
	CardData.Rarity.UNCOMMON: [30, 4],
	CardData.Rarity.RARE: [50, 6],
}
const POTION_UNLOCK_MATERIAL := "Green Ooze"
# Gold for each stage of each upgrade (stage 1, stage 2).
const POTION_UPGRADES := {STRONGER: [25, 50], MORE_COMMON: [20, 40]}


func potions_open() -> bool:
	return alchemist_open()


func is_potion_unlocked(potion: Potion) -> bool:
	return potions_open() and (potion.potion_name == STARTER_POTION or unlocked_potions.has(potion.potion_name))


func unlocked_potion_list() -> Array[Potion]:
	var result: Array[Potion] = []
	for potion in load_potions():
		if is_potion_unlocked(potion):
			result.append(potion)
	return result


# {"Green Ooze": 4} etc: the materials part of a potion's unlock cost.
func potion_unlock_materials(potion: Potion) -> Dictionary:
	return {POTION_UNLOCK_MATERIAL: POTION_UNLOCK_COSTS[potion.rarity][1]}


func potion_unlock_gold(potion: Potion) -> int:
	return POTION_UNLOCK_COSTS[potion.rarity][0]


func can_unlock_potion(potion: Potion) -> bool:
	return potions_open() and not is_potion_unlocked(potion) \
		and gold >= potion_unlock_gold(potion) and has_materials(potion_unlock_materials(potion))


func unlock_potion(potion: Potion) -> bool:
	if not can_unlock_potion(potion):
		return false
	gold -= potion_unlock_gold(potion)
	spend_materials(potion_unlock_materials(potion))
	unlocked_potions.append(potion.potion_name)
	save_game()
	return true


func potion_upgrade_stage(potion: Potion, upgrade: String) -> int:
	return int(potion_upgrades.get(potion.potion_name, {}).get(upgrade, 0))


# Gold for the next stage of an upgrade, or -1 if it's maxed out.
func potion_upgrade_cost(potion: Potion, upgrade: String) -> int:
	var stage := potion_upgrade_stage(potion, upgrade)
	var costs: Array = POTION_UPGRADES[upgrade]
	return costs[stage] if stage < costs.size() else -1


func buy_potion_upgrade(potion: Potion, upgrade: String) -> bool:
	var cost := potion_upgrade_cost(potion, upgrade)
	if not is_potion_unlocked(potion) or cost < 0 or gold < cost:
		return false
	gold -= cost
	if not potion_upgrades.has(potion.potion_name):
		potion_upgrades[potion.potion_name] = {}
	potion_upgrades[potion.potion_name][upgrade] = potion_upgrade_stage(potion, upgrade) + 1
	save_game()
	return true


# A copy of the potion with your Stronger upgrade applied. The original
# (loaded from potions/) is shared, so we never change it: duplicate() makes
# a new one just for this drop. Heal/Block/Damage go x1.5 then x2 (rounded
# up); at stage 2 Energy, Draw and Roll Bonus also get +1.
func strengthened(potion: Potion, stage: int = -1) -> Potion:
	if stage < 0:
		stage = potion_upgrade_stage(potion, STRONGER)
	if stage == 0:
		return potion
	var copy: Potion = potion.duplicate()
	var factor := 1.0 + 0.5 * stage
	copy.heal = ceili(potion.heal * factor)
	copy.block = ceili(potion.block * factor)
	copy.damage = ceili(potion.damage * factor)
	if stage >= 2:
		for stat in ["energy", "draw", "roll_bonus"]:
			if potion.get(stat) > 0:
				copy.set(stat, potion.get(stat) + 1)
	return copy


# How often a potion drops compared to others: its rarity weight (Common 60,
# Uncommon 30, Rare 10) times 1 + its More Common stage.
func potion_drop_weight(potion: Potion) -> int:
	return Enchant.RARITY_WEIGHTS[potion.rarity] * (1 + potion_upgrade_stage(potion, MORE_COMMON))


# Pick a random unlocked potion (weighted), already strengthened.
# null if the Alchemist isn't built yet.
func roll_dropped_potion() -> Potion:
	var choices := unlocked_potion_list()
	if choices.is_empty():
		return null
	var total := 0
	for potion in choices:
		total += potion_drop_weight(potion)
	var roll := randi_range(1, total)
	for potion in choices:
		roll -= potion_drop_weight(potion)
		if roll <= 0:
			return strengthened(potion)
	return strengthened(choices[-1])


func find_enchant(enchant_name: String) -> Enchant:
	for enchant in load_enchants():
		if enchant.enchant_name == enchant_name:
			return enchant
	return null


func find_potion(potion_name: String) -> Potion:
	for potion in load_potions():
		if potion.potion_name == potion_name:
			return potion
	return null


# A dropped enchant: 1 random enchant to choose from, plus 1 more per
# Enchant Choice (the Enchanter's second stage). No repeats.
func roll_enchant_choices() -> Array[Enchant]:
	var choices: Array[Enchant] = []
	var pool := load_enchants().duplicate()
	for i in 1 + town_bonus(TownBuilding.ENCHANT_CHOICE):
		var enchant := Enchant.pick_random(pool)
		if enchant == null:
			break
		choices.append(enchant)
		pool.erase(enchant)
	return choices


# The cards in your deck that this enchant can go on this run (by deck
# index): not Vanished, not already enchanted, and the enchant fits.
func enchantable_cards(enchant: Enchant) -> Array[int]:
	var found: Array[int] = []
	for i in deck.size():
		if not vanished.has(i) and not run_enchants.has(i) and enchant.fits(deck[i]):
			found.append(i)
	return found


func enchant_card(deck_index: int, enchant: Enchant) -> void:
	run_enchants[deck_index] = enchant


# Your max HP in a fight: your class's, plus Max HP talents, plus Heavy Pack
# (+Amount for every 2 cards above 20 in your deck).
func player_max_hp() -> int:
	var per_two := talent_bonus(character_class, Talent.HP_PER_EXTRA_CARDS)
	return character_class.max_hp + talent_bonus(character_class, Talent.MAX_HP) \
		+ maxi(deck.size() - 20, 0) / 2 * per_two


# --- Room cards ---------------------------------------------------------------

# Is this map card in the place's deck? Cards start Unlocked (the sheet's
# Unlocked column), or a quest or a Map unlocks them.
func is_room_unlocked(area: Area, card: RoomCard) -> bool:
	return card.unlocked or unlocked_rooms.get(area.display_name, []).has(card.room_name)


# A Map: unlock a random locked room card for this area (saved straight
# away: what you learn from a map stays, even if you die). null if none are left.
func unlock_random_room(area: Area) -> RoomCard:
	# Quest rooms are left out: only their quest unlocks them.
	var locked := area.cards().filter(func(card: RoomCard) -> bool: return not card.quest_only and not is_room_unlocked(area, card))
	if locked.is_empty():
		return null
	var card: RoomCard = locked.pick_random()
	if not unlocked_rooms.has(area.display_name):
		unlocked_rooms[area.display_name] = []
	unlocked_rooms[area.display_name].append(card.room_name)
	save_game()
	return card


# Called by the Character Select screen. A new class means a new deck,
# so we throw the old one away and start from that class's starter deck.
func choose_class(new_class: CharacterClass) -> void:
	character_class = new_class
	deck = _load_saved_deck(new_class)
	if deck.is_empty():
		deck = make_starter_deck()
		fix_deck_foils(true)  # A deck the game built: your foil copies go in.
	else:
		fix_deck_foils()


# The deck you last built for this class, from saved_decks. Any card the class
# can't use any more (or that you don't own enough of) is left out.
# Its foil copies go back into deck_foils.
func _load_saved_deck(for_class: CharacterClass) -> Array[CardData]:
	var read := _read_deck_names(saved_decks.get(for_class.display_name, []))
	deck_foils = read.foils
	var cards: Array[CardData] = read.cards
	return _keep_allowed(cards, for_class)


# ---------------------------------------------------------------------------
# Talents
# ---------------------------------------------------------------------------

# Every talent in this class's tree, from talents/<class>/. Read once, then remembered.
func talents_for(for_class: CharacterClass) -> Array[Talent]:
	if for_class == null:
		var none: Array[Talent] = []
		return none
	if not _talents.has(for_class.display_name):
		var list: Array[Talent] = []
		var folder := TALENTS_FOLDER + for_class.resource_path.get_file().get_basename() + "/"
		for file_name in ResourceLoader.list_directory(folder):
			if file_name.ends_with(".tres"):
				list.append(load(folder + file_name))
		# Tree by tree, then top row first, then left to right.
		list.sort_custom(func(a: Talent, b: Talent) -> bool:
			if a.tree_index != b.tree_index:
				return a.tree_index < b.tree_index
			return a.tier < b.tier if a.tier != b.tier else a.column < b.column)
		_talents[for_class.display_name] = list
	return _talents[for_class.display_name]


# The names of this class's trees, in tab order: ["Jack of All Trades", "Master of None", "Pack Rat"].
func trees_for(for_class: CharacterClass) -> Array[String]:
	var trees: Array[String] = []
	for talent in talents_for(for_class):
		if not trees.has(talent.tree):
			trees.append(talent.tree)
	return trees


func find_talent(for_class: CharacterClass, talent_name: String) -> Talent:
	for talent in talents_for(for_class):
		if talent.talent_name == talent_name:
			return talent
	return null


# How many ranks of this talent the class has learned (0 = none).
# A spec talent counts as rank 1 while its tree is the class's spec.
func talent_rank(talent: Talent) -> int:
	if talent.is_spec:
		return 1 if class_specs.get(talent.class_display_name, "") == talent.tree else 0
	return talent_ranks.get(talent.class_display_name, {}).get(talent.talent_name, 0)


# This class's specs (from data/talents/specs.csv), in order. Empty = no specs.
func specs_for(for_class: CharacterClass) -> Array[Talent]:
	var specs: Array[Talent] = []
	for talent in talents_for(for_class):
		if talent.is_spec:
			specs.append(talent)
	return specs


# The class's spec (a tree name), or "" before you pick one.
func spec_of(for_class: CharacterClass) -> String:
	return class_specs.get(for_class.display_name, "")


# Pick a spec: its spec talent turns on for free. Changing spec gives back
# every talent point too, so you can try a different build.
func set_spec(for_class: CharacterClass, tree_name: String) -> void:
	if spec_of(for_class) == tree_name:
		return
	class_specs[for_class.display_name] = tree_name
	_talents_changed()
	reset_talents(for_class)  # Also saves, and fixes the deck for the new rules.


# Points: 1 per level after level 1 (the CLASS's own talent points), plus every
# Legacy Talent Point (from quests, shared by all classes), minus what's spent.
func talent_points_earned(for_class: CharacterClass) -> int:
	return class_talent_points(for_class) + legacy_talent_points


# A class's own talent points: 1 for each level after level 1.
func class_talent_points(for_class: CharacterClass) -> int:
	return class_level(for_class) - 1


# Points spent in this class's talents. Pass a tree (and a tier) to count only those.
func talent_points_spent(for_class: CharacterClass, only_tree: String = "", only_tier: int = 0) -> int:
	var spent := 0
	for talent in talents_for(for_class):
		if talent.is_spec:
			continue  # Spec talents are free.
		if (only_tree.is_empty() or talent.tree == only_tree) and (only_tier == 0 or talent.tier == only_tier):
			spent += talent_rank(talent) * talent.cost
	return spent


func talent_points_left(for_class: CharacterClass) -> int:
	return talent_points_earned(for_class) - talent_points_spent(for_class)


# Why can't you learn the next rank of this talent? A short reason for the
# talent screen, or "" if you can. Checks every rule from the sheet.
func why_cant_learn(talent: Talent) -> String:
	var for_class := _class_named(talent.class_display_name)
	var rank := talent_rank(talent)
	if talent.is_spec:
		return "Specs are picked on the Spec screen, not with points"
	if rank >= talent.max_ranks:
		return "Max rank"
	if SPEC_TREE_ONLY and talent.tree != spec_of(for_class):
		return "Only your spec's tree" if not spec_of(for_class).is_empty() else "Pick a spec first"
	# Choice Group and Locks Out: has another talent shut this one out?
	for other in talents_for(for_class):
		if other == talent or talent_rank(other) == 0:
			continue
		var same_group := not talent.choice_group.is_empty() and other.choice_group == talent.choice_group
		if same_group or other.locks_out.has(talent.talent_name) or talent.locks_out.has(other.talent_name):
			return "You picked %s" % other.talent_name
	if talent.tier_unlock > 0 and talent.tier > 1:
		var in_tier_above := talent_points_spent(for_class, talent.tree, talent.tier - 1)
		if in_tier_above < talent.tier_unlock:
			return "Spend %d point(s) in Tier %d first" % [talent.tier_unlock, talent.tier - 1]
	if talent.points_in_tree > 0 and talent_points_spent(for_class, talent.tree) < talent.points_in_tree:
		return "Spend %d point(s) in %s first" % [talent.points_in_tree, talent.tree]
	if not talent.needs.is_empty():
		var have: Array[String] = []
		for needed in talent.needs:
			var needed_talent := find_talent(for_class, needed)
			if needed_talent and talent_rank(needed_talent) > 0:
				have.append(needed)
		var enough := not have.is_empty() if talent.needs_any else have.size() == talent.needs.size()
		if not enough:
			return "Needs %s" % (" or " if talent.needs_any else " and ").join(talent.needs)
	if talent_points_left(for_class) < talent.cost:
		return "No talent points left"
	return ""


# Spend points on the next rank. Returns false if a rule says no.
func learn_talent(talent: Talent) -> bool:
	if not why_cant_learn(talent).is_empty():
		return false
	if not talent_ranks.has(talent.class_display_name):
		talent_ranks[talent.class_display_name] = {}
	talent_ranks[talent.class_display_name][talent.talent_name] = talent_rank(talent) + 1
	_talents_changed()
	save_game()
	return true


# Take back every point in this class's tree (free, for now).
func reset_talents(for_class: CharacterClass) -> void:
	talent_ranks.erase(for_class.display_name)
	_talents_changed()
	if for_class == character_class:
		# Cards a talent let into the deck might not be allowed any more.
		deck = _keep_allowed(deck, for_class)
	save_game()


# The total of one effect from every talent the class has learned, e.g.
# talent_bonus(knight, Talent.ENERGY). Pass a card to only count talents whose
# School matches it, or a school to only count talents for that school
# ("All" talents always count).
#
# The deck builder asks this many times for every card on screen, so answers
# without a card are remembered in _bonus_cache until the talents change.
func talent_bonus(for_class: CharacterClass, effect: String, card: CardData = null, school: int = -1) -> int:
	var key := "%s|%s|%d" % [for_class.display_name, effect, school]
	if card == null and _bonus_cache.has(key):
		return _bonus_cache[key]
	var total := 0
	for talent in talents_for(for_class):
		total += talent.effect_amount(effect, talent_rank(talent), card, school)
	if card == null:
		_bonus_cache[key] = total
	return total


# Talents or specs changed: forget the remembered talent_bonus() answers.
func _talents_changed() -> void:
	_bonus_cache.clear()


# The lowest Copy Limit from a learned talent (Pack Rat: 1), or 0 for none.
func talent_copy_limit(for_class: CharacterClass) -> int:
	var limit := 0
	for talent in talents_for(for_class):
		var amount := talent.effect_amount(Talent.COPY_LIMIT, talent_rank(talent))
		if amount > 0:
			limit = amount if limit == 0 else mini(limit, amount)
	return limit


# The first talent in this class's tree that opens up a school, for the deck
# builder to say "Needs talent: Jack of All Trades". null if there isn't one.
func talent_that_opens(for_class: CharacterClass, school: int) -> Talent:
	for talent in talents_for(for_class):
		if talent.opens_school(school):
			return talent
	return null


func _talent_could_open(card: CardData) -> bool:
	if card.is_class_card() and not card.class_only.has(character_class.display_name):
		return false
	for school in CardData.School.values():
		if card.has_school(school) and talent_that_opens(character_class, school):
			return true
	return false


func is_class_unlocked(for_class: CharacterClass) -> bool:
	return for_class.is_unlocked(load_all_cards())


func _class_named(display_name: String) -> CharacterClass:
	for each_class in load_classes():
		if each_class.display_name == display_name:
			return each_class
	return null


# The cards of `cards` that still follow every deck rule, in the same order.
func _keep_allowed(cards: Array[CardData], for_class: CharacterClass) -> Array[CardData]:
	var kept: Array[CardData] = []
	for card in cards:
		if for_class.can_add_to(kept, card):
			kept.append(card)
	return kept


# "★ Talent point ready!" (or "★ 2 talent points ready!"), or "" with none to spend.
func talent_points_text(for_class: CharacterClass) -> String:
	var points := talent_points_left(for_class)
	if points <= 0 or talents_for(for_class).is_empty():
		return ""
	return "★ Talent point ready!" if points == 1 else "★ %d talent points ready!" % points


# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------
# Everything you keep between runs is written to one small JSON file.
# "user://" is a folder Godot gives every game for its own files. On Windows
# it's %APPDATA%\Godot\app_userdata\Card Game\ (Project > Open User Data
# Folder in the editor takes you there). JSON is the same format Python's
# json module reads and writes.
#
# What's saved: gold, your collection, Essence, class Exp, unopened packs,
# talents and the last deck you built for each class. NOT saved: a run in progress.
# Quit in the middle of a run and you start a new one next time.
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 8  # Bump this if the save format changes. 2 = the town starts empty (quests). 3 = Guild Hall first, Stone for the Inn. 4 = first cards come at the end of the training. 5 = Guild Hall stands, the Inn's Stone and Hops quests bring the Adventurer. 6 = the Abandoned Farm's map cards, and the Adventurer arrives with the Inn. 7 = rarity copy limits and Essence (no card Exp). 8 = foils, binders, the rare pity counter and spec levels (class Exp goes into specs).


func save_game() -> void:
	if character_class:
		saved_decks[character_class.display_name] = deck_names()
	var data := {
		"version": SAVE_VERSION,
		"gold": gold,
		"collection": collection,
		"essence": essence,
		"foils": foils,
		"rare_pity": rare_pity,
		"binder_claimed": binder_claimed,
		"explorer_bonus": explorer_bonus,
		"spec_exp": spec_exp,
		"track_claimed": track_claimed,
		"plans": plans,
		"shop_stock": shop_stock,
		"trips_done": trips_done,
		"shop_stock_trip": shop_stock_trip,
		"booster_packs": booster_packs,
		"decks": saved_decks,
		"talents": talent_ranks,
		"specs": class_specs,
		"legacy_talent_points": legacy_talent_points,
		"monsters_slain": monsters_slain,
		"bestiary": bestiary,
		"cleared_areas": cleared_areas,
		"unlocked_rooms": unlocked_rooms,
		"town": town_stages,
		"pending_enchants": pending_enchants,
		"pending_potions": pending_potions,
		"unlocked_flasks": unlocked_flasks,
		"unlocked_potions": unlocked_potions,
		"potion_upgrades": potion_upgrades,
		"flask_upgrades": flask_upgrades,
		"chosen_flask": chosen_flask,
		"tutorial_done": tutorial_done,
		"materials": materials,
		"blueprints": blueprints,
		"active_quests": active_quests,
		"quest_progress": quest_progress,
		"unseen_quests": unseen_quests,
		"quests_done": quests_done,
		"unlocked_features": unlocked_features,
		"seen_guides": seen_guides,
		"story_beats": story_beats,
		"packed_torches": packed_torches,
		"area_exp": area_exp,
		"area_perks": area_perks,
		"packed_tools": packed_tools,
		"journal": journal,
		"scavenge_finds": scavenge_finds,
		"map_cards_off": map_cards_off,
		"loadouts": loadouts,
		"last_loadout": last_loadout,
		"class": character_class.display_name if character_class else "",
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Couldn't save the game: %s" % error_string(FileAccess.get_open_error()))
		return
	# "\t" indents it, so you can open the file and read it yourself.
	file.store_string(JSON.stringify(data, "\t"))


# Read the save file, if there is one. Returns false if there isn't (or it's broken).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		push_warning("The save file couldn't be read, so you start fresh.")
		return false
	if int(data.get("version", 1)) < SAVE_VERSION:
		push_warning("This save is from an older version of the game, so you start fresh.")
		return false
	# JSON stores every number as a float (3.0), so int() turns them back.
	gold = int(data.get("gold", 0))
	collection = _whole_numbers(data.get("collection", {}))
	var saved_essence = data.get("essence", {})
	essence = _whole_numbers(saved_essence) if saved_essence is Dictionary else {}
	foils = _whole_numbers(_dict_or_empty(data.get("foils", {})))
	rare_pity = int(data.get("rare_pity", 0))
	binder_claimed = _whole_numbers(_dict_or_empty(data.get("binder_claimed", {})))
	explorer_bonus = _whole_numbers(_dict_or_empty(data.get("explorer_bonus", {})))
	track_claimed = _whole_numbers(_dict_or_empty(data.get("track_claimed", {})))
	plans = _whole_numbers(_dict_or_empty(data.get("plans", {})))
	shop_stock.assign(data.get("shop_stock", []))
	trips_done = int(data.get("trips_done", 0))
	shop_stock_trip = int(data.get("shop_stock_trip", -1))
	spec_exp.clear()
	var saved_spec_exp := _dict_or_empty(data.get("spec_exp", {}))
	for class_key in saved_spec_exp:
		if saved_spec_exp[class_key] is Dictionary:
			spec_exp[class_key] = _whole_numbers(saved_spec_exp[class_key])
	booster_packs = _whole_numbers(data.get("booster_packs", {}))
	saved_decks = data.get("decks", {})
	talent_ranks.clear()
	var saved_talents: Dictionary = data.get("talents", {})
	for class_name_key in saved_talents:
		talent_ranks[class_name_key] = _whole_numbers(saved_talents[class_name_key])
	legacy_talent_points = int(data.get("legacy_talent_points", data.get("bonus_talent_points", 0)))
	monsters_slain = int(data.get("monsters_slain", 0))
	bestiary.clear()
	var saved_book = data.get("bestiary", {})
	if saved_book is Dictionary:
		for monster in saved_book:
			var entry: Dictionary = saved_book[monster]
			var seen: Array[String] = []
			seen.assign(entry.get("seen", []))
			bestiary[monster] = {"seen": seen, "kills": int(entry.get("kills", 0))}
	cleared_areas.assign(data.get("cleared_areas", []))
	var saved_rooms = data.get("unlocked_rooms", {})
	unlocked_rooms = saved_rooms if saved_rooms is Dictionary else {}
	var saved_town = data.get("town", {})
	town_stages = _whole_numbers(saved_town) if saved_town is Dictionary else {}
	pending_enchants.assign(data.get("pending_enchants", []))
	pending_potions.assign(data.get("pending_potions", []))
	unlocked_flasks.assign(data.get("unlocked_flasks", []))
	flask_upgrades.clear()
	var saved_flasks = data.get("flask_upgrades", {})
	if saved_flasks is Dictionary:
		for flask_name in saved_flasks:
			if saved_flasks[flask_name] is Dictionary:
				flask_upgrades[flask_name] = _whole_numbers(saved_flasks[flask_name])
	chosen_flask = str(data.get("chosen_flask", ""))
	unlocked_potions.assign(data.get("unlocked_potions", []))
	potion_upgrades.clear()
	var saved_potions = data.get("potion_upgrades", {})
	if saved_potions is Dictionary:
		for potion_name in saved_potions:
			if saved_potions[potion_name] is Dictionary:
				potion_upgrades[potion_name] = _whole_numbers(saved_potions[potion_name])
	tutorial_done = bool(data.get("tutorial_done", false))
	var saved_materials = data.get("materials", {})
	materials = _whole_numbers(saved_materials) if saved_materials is Dictionary else {}
	blueprints.assign(data.get("blueprints", []))
	active_quests.assign(data.get("active_quests", []))
	var saved_progress = data.get("quest_progress", {})
	quest_progress = _whole_numbers(saved_progress) if saved_progress is Dictionary else {}
	unseen_quests.assign(data.get("unseen_quests", []))
	# A save from when there was one quest at a time.
	if data.has("active_quest") and not str(data.active_quest).is_empty() and active_quests.is_empty():
		active_quests.append(str(data.active_quest))
		quest_progress[str(data.active_quest)] = int(saved_progress) if not saved_progress is Dictionary else 0
		if not bool(data.get("quest_seen", true)):
			unseen_quests.append(str(data.active_quest))
	# Packs from before booster pack sizes: they become Small ones.
	if booster_packs.has("Basic Booster"):
		add_packs(PACKS[0].name, booster_packs["Basic Booster"])
		booster_packs.erase("Basic Booster")
	quests_done.assign(data.get("quests_done", []))
	# Quests added to quests.csv after you saved: start the ones whose
	# "Starts After" quest you've already handed in.
	for done_name in quests_done:
		_start_quests_after(done_name)
	unlocked_features.assign(data.get("unlocked_features", []))
	# ...and new blueprint/room/unlock rewards on quests you already handed in
	# (e.g. the Flask quest now also gives the Tailor blueprint).
	for quest in load_quests():
		if quests_done.has(quest.quest_name):
			give_rewards(quest.rewards, true)
	seen_guides.assign(data.get("seen_guides", []))
	story_beats.assign(data.get("story_beats", []))
	# Quests whose Starts After is a milestone you've already reached.
	for beat in story_beats:
		_start_quests_after(beat)
	var saved_specs = data.get("specs", {})
	class_specs = saved_specs if saved_specs is Dictionary else {}  # Ignore a broken entry.
	_talents_changed()
	packed_torches = clampi(int(data.get("packed_torches", 2)), 0, MAX_PACKED_TORCHES)
	var saved_area_exp = data.get("area_exp", {})
	area_exp = _whole_numbers(saved_area_exp) if saved_area_exp is Dictionary else {}
	var saved_tools = data.get("packed_tools", {})
	packed_tools = _whole_numbers(saved_tools) if saved_tools is Dictionary else {}
	journal.assign(data.get("journal", []))
	var saved_finds = data.get("scavenge_finds", {})
	scavenge_finds = saved_finds if saved_finds is Dictionary else {}
	var saved_perks = data.get("area_perks", {})
	area_perks = saved_perks if saved_perks is Dictionary else {}
	var saved_off = data.get("map_cards_off", {})
	map_cards_off = saved_off if saved_off is Dictionary else {}
	loadouts.clear()
	for loadout in data.get("loadouts", []):
		if loadout is Dictionary:
			loadouts.append(loadout)
	var saved_last = data.get("last_loadout", {})
	last_loadout = saved_last if saved_last is Dictionary else {}
	# The class you played last (its deck comes from saved_decks).
	var last_class := _class_named(str(data.get("class", "")))
	if last_class and is_class_unlocked(last_class):
		choose_class(last_class)
	# A card added to the spreadsheet as Unlocked after you saved still
	# shows up in your collection (once you've had your starter cards).
	for card in load_all_cards():
		if tutorial_done and card.unlocked and owned(card) == 0:
			collection[card.card_name] = clampi(card.copies, 1, card.copy_limit())
	return true


# A saved value that should be a Dictionary, or {} if it's missing or broken.
func _dict_or_empty(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


# {"Strike": 3.0} -> {"Strike": 3}
func _whole_numbers(numbers: Dictionary) -> Dictionary:
	var result := {}
	for key in numbers:
		result[key] = int(numbers[key])
	return result


# The Reset Save button: delete the save file and start over as a new player.
func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	start_fresh()


# Godot sends this when you close the game window: one last save on the way out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


# Every class, loaded from the classes/ folder, in their sort_order.
# Read once and remembered, like load_all_cards().
func load_classes() -> Array[CharacterClass]:
	if _classes.is_empty():
		for file_name in ResourceLoader.list_directory(CLASSES_FOLDER):
			if file_name.ends_with(".tres"):
				_classes.append(load(CLASSES_FOLDER + file_name))
		_classes.sort_custom(func(a: CharacterClass, b: CharacterClass) -> bool:
			return a.sort_order < b.sort_order)
	return _classes


# Is this area open on the map? Open from the start, or its Unlock After
# area has been cleared (you beat that area's boss).
func is_area_unlocked(area: Area) -> bool:
	if area.coming_later or not adventurers_here():
		return false  # Still being built, or nobody to send out yet (the Adventurer comes with the Inn).
	return area.unlocked or (not area.unlock_after.is_empty() and cleared_areas.has(area.unlock_after))


# Does this place have a first-trip board (Deck = Guide in its map card sheet)?
func has_guide_rooms(area: Area) -> bool:
	return area.cards().any(func(card: RoomCard) -> bool: return card.deck_part == RoomCard.DECK_GUIDE)


# Until you've come home from it once, a trip to the Farm is the FIRST TRIP:
# a set board with tips (dungeon.gd), for the Innkeeper's Stone and Hops.
func is_guided_run(area: Area) -> bool:
	return adventurers_here() and has_guide_rooms(area) and not story_beats.has(FIRST_TRIP)


# Talents and specs stay hidden until a quest unlocks them (after the first boss).
func talents_open() -> bool:
	return unlocked_features.has(TALENTS_FEATURE)


# Has an adventurer come to town yet? The first one checks into the Inn as
# soon as it's built ("Unlock Adventurer", town.gd). Until then no class is
# playable: you're the Architect, running the town.
func adventurers_here() -> bool:
	return unlocked_features.has(ADVENTURER_FEATURE)


# You beat this area's boss. Returns the areas that just opened because of it.
func clear_area(area: Area) -> Array[Area]:
	var opened: Array[Area] = []
	if area == null or cleared_areas.has(area.display_name):
		return opened
	var locked_before := load_areas().filter(func(a: Area) -> bool: return not is_area_unlocked(a))
	cleared_areas.append(area.display_name)
	for other: Area in locked_before:
		if is_area_unlocked(other):
			opened.append(other)
	save_game()
	return opened


# An enemy by name ("Slimeling"), for summons and splits. null if there's none.
# --- The monster book (the Dojo) ---------------------------------------------

# You met this monster at `place` ("Abandoned Farm, Floor 1"): it goes in the book.
func see_monster(monster: String, place: String) -> void:
	var seen: Array[String] = book_entry(monster).seen
	if not place.is_empty() and not seen.has(place):
		seen.append(place)


# You beat one: +1 kill, and its Monster Exp.
func kill_monster(monster: String) -> void:
	book_entry(monster).kills += 1


# The monster's page in the book (a new, empty one the first time).
func book_entry(monster: String) -> Dictionary:
	if not bestiary.has(monster):
		var seen: Array[String] = []
		bestiary[monster] = {"seen": seen, "kills": 0}
	return bestiary[monster]


func monster_exp(monster: String) -> int:
	return int(bestiary.get(monster, {}).get("kills", 0)) * MONSTER_EXP_PER_KILL


# Monster Level 1 to MONSTER_LEVELS.size() + 1.
func monster_level(monster: String) -> int:
	var total := monster_exp(monster)
	var level := 1
	for needed in MONSTER_LEVELS:
		if total >= needed:
			level += 1
	return level


# Monster Exp needed for the next Monster Level (-1 = max level).
func monster_next_level_exp(monster: String) -> int:
	var level := monster_level(monster)
	return MONSTER_LEVELS[level - 1] if level - 1 < MONSTER_LEVELS.size() else -1


func find_enemy(enemy_name: String) -> EnemyData:
	load_enemies()
	return _enemies_by_name.get(enemy_name.to_lower())


# Every monster file (read once, then remembered).
func load_enemies() -> Array:
	if _enemies_by_name.is_empty():
		for file_name in ResourceLoader.list_directory(ENEMIES_FOLDER):
			if file_name.ends_with(".tres"):
				var enemy: EnemyData = load(ENEMIES_FOLDER + file_name)
				_enemies_by_name[enemy.display_name.to_lower()] = enemy
	return _enemies_by_name.values()


# Every area, loaded from the areas/ folder, in their sort_order (the order along the road).
# Read once, then remembered (like the cards). Returns a copy, so callers can add to it.
var _areas: Array[Area] = []
func load_areas() -> Array[Area]:
	if _areas.is_empty():
		for file_name in ResourceLoader.list_directory(AREAS_FOLDER):
			if file_name.ends_with(".tres"):
				_areas.append(load(AREAS_FOLDER + file_name))
		_areas.sort_custom(func(a: Area, b: Area) -> bool: return a.sort_order < b.sort_order)
	return _areas.duplicate()


# Every card in the game (one of each), loaded from the cards/ folder.
# Character Select uses this to count owned cards for class unlocks.
# The cards don't change while the game runs, so the folder is only read the
# first time; after that the same list is handed back. Don't change the list
# you get (loop over it, or make your own list from it).
# Every event (data/dungeons/events.csv -> dungeon_events/). Read once.
var _events: Array[DungeonEvent] = []
func load_events() -> Array[DungeonEvent]:
	if _events.is_empty():
		for file_name in ResourceLoader.list_directory(CardImporter.EVENTS_FOLDER):
			if file_name.ends_with(".tres"):
				_events.append(load(CardImporter.EVENTS_FOLDER + file_name))
	return _events


func find_event(event_name: String) -> DungeonEvent:
	for event in load_events():
		if event.event_name == event_name:
			return event
	return null


func load_all_cards() -> Array[CardData]:
	if _all_cards.is_empty():
		for file_name in ResourceLoader.list_directory(CARDS_FOLDER):
			if file_name.ends_with(".tres"):
				_all_cards.append(load(CARDS_FOLDER + file_name))
	return _all_cards


# Every card you OWN that the chosen class is allowed to build with (one of each),
# plus ones a talent could open up (the deck builder shows them as "Needs talent").
# Sorted by school, then name, so schools sit together.
func load_card_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in load_all_cards():
		if owned(card) > 0 and (character_class == null or character_class.can_use(card) or _talent_could_open(card)):
			pool.append(card)
	# sort_custom() takes a function that answers "should a come before b?".
	# `func(a, b): ...` is a lambda: a small function with no name (like Python's lambda).
	pool.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.schools != b.schools:
			return a.schools < b.schools
		return a.card_name < b.card_name)
	return pool


# The suggested starting deck for the chosen class: every card it can use,
# as many times as the Copies column says, but never more than the class
# allows (so a Copies of 3 still gives the Adventurer just 1).
# Used when you pick a class, and by the deck builder's Starter Deck button.
func make_starter_deck() -> Array[CardData]:
	var starter: Array[CardData] = []
	for card in load_card_pool():
		for i in mini(card.copies, character_class.max_copies_of(card)):
			# can_add_to() checks every deck rule, including "locked cards
			# can't be added" and the deck-size and per-school limits.
			if character_class.can_add_to(starter, card):
				starter.append(card)
	return starter


# For testing a scene on its own (F6): if nothing was picked yet, use the
# first class and its starter deck, so the scene still has something to show.
# --- Place progression -----------------------------------------------------------
# Every trip gives the place Exp (DungeonRun.award_area_exp()). Each level up
# gives an Explorer point (to spend on that place's perks) and a booster pack.

func area_level(area: Area) -> int:
	var total: int = area_exp.get(area.display_name, 0)
	var level := 1
	while level < AREA_MAX_LEVEL and total >= area_exp_for_next(level):
		total -= area_exp_for_next(level)
		level += 1
	return level


# Exp from `level` to the next one.
func area_exp_for_next(level: int) -> int:
	return AREA_FIRST_LEVEL_EXP + AREA_LEVEL_EXP_STEP * (level - 1)


# Where the bar is: (Exp into this level, Exp this level needs). (0, 0) at the top level.
func area_exp_progress(area: Area) -> Vector2i:
	var total: int = area_exp.get(area.display_name, 0)
	var level := 1
	while level < AREA_MAX_LEVEL and total >= area_exp_for_next(level):
		total -= area_exp_for_next(level)
		level += 1
	if level >= AREA_MAX_LEVEL:
		return Vector2i.ZERO
	return Vector2i(total, area_exp_for_next(level))


# Add Exp. Returns the new levels reached (each gave a point and a pack).
func add_area_exp(area: Area, amount: int) -> Array[int]:
	var before := area_level(area)
	area_exp[area.display_name] = area_exp.get(area.display_name, 0) + maxi(amount, 0)
	var reached: Array[int] = []
	for level in range(before + 1, area_level(area) + 1):
		reached.append(level)
		add_packs(AREA_LEVEL_PACK, 1)
	save_game()
	return reached


func area_perk_list(area: Area) -> Array[AreaPerk]:
	return AreaPerk.load_sheet(area.perk_sheet)


# The perks the Perks screen shows: the ones whose Requires is met (plus any
# you already own). Perks for things you haven't unlocked yet stay hidden, so
# a new player isn't offered Water Skins before they've ever seen a flask.
func shown_area_perks(area: Area) -> Array[AreaPerk]:
	return area_perk_list(area).filter(func(perk: AreaPerk) -> bool:
		return has_area_perk(area, perk) or perk_requirement_met(area, perk))


# Have you unlocked what this perk is about? (Its Requires column.)
func perk_requirement_met(area: Area, perk: AreaPerk) -> bool:
	var need := perk.requires.to_lower()
	if need.is_empty():
		return true
	if need == "flask":
		return current_flask() != null  # null = no flask brewed yet.
	if need == "potions":
		return potions_open()
	if need.begins_with("map card"):
		var card_name := perk.requires.get_slice(":", 1).strip_edges()
		for card in area.cards():
			if card.room_name == card_name:
				return is_room_unlocked(area, card)
		return false
	push_warning("Perk %s: unknown Requires '%s' (use Flask, Potions or Map Card: <name>)" % [perk.perk_name, perk.requires])
	return true


# --- Scavenge finds (the "?" on map cards) ---------------------------------------

func _finds_key(area: Area, card_name: String) -> String:
	return "%s/%s" % [area.display_name, card_name]


# Have you ever found this item on this kind of card?
func knows_find(area: Area, card_name: String, item: String) -> bool:
	return scavenge_finds.get(_finds_key(area, card_name), []).has(item)


# You just found it. Returns true if it's NEW (its "?" turns into an icon).
# Saved straight away: what you learn about the farm stays, even if you die.
func learn_find(area: Area, card_name: String, item: String) -> bool:
	if item.is_empty() or knows_find(area, card_name, item):
		return false
	var key := _finds_key(area, card_name)
	var list: Array = scavenge_finds.get(key, [])
	list.append(item)
	scavenge_finds[key] = list
	save_game()
	return true


func owned_area_perks(area: Area) -> Array[AreaPerk]:
	var owned_names: Array = area_perks.get(area.display_name, [])
	return area_perk_list(area).filter(func(perk: AreaPerk) -> bool: return owned_names.has(perk.perk_name))


func has_area_perk(area: Area, perk: AreaPerk) -> bool:
	return area_perks.get(area.display_name, []).has(perk.perk_name)


# Explorer points: 1 per level after the first, minus what you've spent.
func explorer_points(area: Area) -> int:
	var spent := 0
	for perk in owned_area_perks(area):
		spent += perk.cost
	return area_level(area) - 1 + explorer_bonus.get(area.display_name, 0) - spent


# Why you can't buy it ("" = you can).
func why_cant_buy_perk(area: Area, perk: AreaPerk) -> String:
	if has_area_perk(area, perk):
		return "You have it"
	if not perk.needs.is_empty() and not area_perks.get(area.display_name, []).has(perk.needs):
		return "Needs %s first" % perk.needs
	if explorer_points(area) < perk.cost:
		return "Needs %d Explorer point%s" % [perk.cost, "" if perk.cost == 1 else "s"]
	return ""


func buy_area_perk(area: Area, perk: AreaPerk) -> bool:
	if not why_cant_buy_perk(area, perk).is_empty():
		return false
	var list: Array = area_perks.get(area.display_name, [])
	list.append(perk.perk_name)
	area_perks[area.display_name] = list
	if perk.effect == AreaPerk.UNLOCK_CARD:  # Like a Map: the card is yours for good.
		var rooms_list: Array = unlocked_rooms.get(area.display_name, [])
		if not rooms_list.has(perk.target):
			rooms_list.append(perk.target)
		unlocked_rooms[area.display_name] = rooms_list
	save_game()
	return true


# Add up one effect over the place's perks you own (Target-matched if a name is given).
func area_perk_total(area: Area, effect: String, thing_name: String = "") -> int:
	if area == null:
		return 0
	var total := 0
	for perk in owned_area_perks(area):
		if perk.effect == effect and (thing_name.is_empty() or perk.fits(thing_name)):
			total += perk.amount
	return total


# --- Loadouts -----------------------------------------------------------------
# A LOADOUT is everything you pick before an expedition: class, spec, talents,
# deck, flask, torches and which of your map cards go in. Saved by name on the
# Prepare screen; "Same as last time" is the one you last set out with.

func current_loadout(loadout_name: String = "") -> Dictionary:
	var ranks: Dictionary = talent_ranks.get(character_class.display_name, {})
	var flask := current_flask()
	return {
		"name": loadout_name,
		"class": character_class.display_name,
		"spec": spec_of(character_class),
		"talents": ranks.duplicate(),
		"deck": deck_names(),
		"flask": flask.flask_name if flask else "",
		"torches": packed_torches,
		"tools": packed_tools.duplicate(),
		"map_cards_off": map_cards_off.duplicate(true),
	}


# Save the current setup under a name (the same name replaces the old one).
# Returns false if there's no room for a new one.
func save_loadout(loadout_name: String) -> bool:
	var loadout := current_loadout(loadout_name)
	for i in loadouts.size():
		if loadouts[i].get("name", "") == loadout_name:
			loadouts[i] = loadout
			save_game()
			return true
	if loadouts.size() >= MAX_LOADOUTS:
		return false
	loadouts.append(loadout)
	save_game()
	return true


func delete_loadout(index: int) -> void:
	if index >= 0 and index < loadouts.size():
		loadouts.remove_at(index)
		save_game()


# Put a loadout back on. Anything that can't be used any more (a class that's
# locked, a card you no longer own, a flask you don't have) is skipped.
# Returns a list of what was skipped, as text (empty = everything fit).
func apply_loadout(loadout: Dictionary) -> Array[String]:
	var skipped: Array[String] = []
	var for_class := _class_named(str(loadout.get("class", "")))
	if for_class == null or not is_class_unlocked(for_class):
		return ["the class %s" % loadout.get("class", "?")]
	choose_class(for_class)
	var spec := str(loadout.get("spec", ""))
	if not spec.is_empty() and specs_open() and spec != spec_of(for_class):
		set_spec(for_class, spec)  # Changing spec gives the talent points back...
	# ...and then the loadout's talents go back on, if you have the points.
	var ranks = loadout.get("talents", {})
	if ranks is Dictionary and spec == spec_of(for_class):
		var before: Dictionary = talent_ranks.get(for_class.display_name, {}).duplicate()
		talent_ranks[for_class.display_name] = _whole_numbers(ranks)
		_talents_changed()
		if talent_points_left(for_class) < 0:
			talent_ranks[for_class.display_name] = before  # Not enough points: keep what you had.
			_talents_changed()
			skipped.append("its talents (not enough points)")
	var names: Array = loadout.get("deck", [])
	var read := _read_deck_names(names)
	var cards: Array[CardData] = read.cards
	deck = _keep_allowed(cards, for_class)
	deck_foils = read.foils
	fix_deck_foils()
	if deck.size() < names.size():
		skipped.append("%d card%s you can't use now" % [names.size() - deck.size(), "" if names.size() - deck.size() == 1 else "s"])
	var flask := find_flask(str(loadout.get("flask", "")))
	if flask and is_flask_unlocked(flask):
		chosen_flask = flask.flask_name
	packed_torches = clampi(int(loadout.get("torches", 2)), 0, MAX_PACKED_TORCHES)
	var saved_tools = loadout.get("tools", {})
	packed_tools = _whole_numbers(saved_tools) if saved_tools is Dictionary else {}
	var off = loadout.get("map_cards_off", {})
	if off is Dictionary:
		map_cards_off = off.duplicate(true)
	save_game()
	return skipped


# Is this map card (one of Yours) taken out of the deck?
func is_map_card_off(area: Area, card: RoomCard) -> bool:
	return map_cards_off.get(area.display_name, []).has(card.room_name)


func set_map_card_off(area: Area, card: RoomCard, off: bool) -> void:
	var list: Array = map_cards_off.get(area.display_name, [])
	list.erase(card.room_name)
	if off:
		list.append(card.room_name)
	map_cards_off[area.display_name] = list


func ensure_ready() -> void:
	if character_class == null:
		choose_class(load_classes()[0])
	elif deck.is_empty():
		deck = make_starter_deck()
		fix_deck_foils(true)
	if current_area == null:
		current_area = load_areas()[0]  # The first place on the road (the Abandoned Farm).
	if dungeon == null:
		dungeon = DungeonRun.new(current_area)
		dungeon.start()
