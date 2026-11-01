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

# --- The run --------------------------------------------------------------
# A "run" is one trip into an area's dungeon (see dungeon_run.gd): explore
# rooms, beat Mini Bosses, and beat the Boss, Leave at a campfire, or die.
# Your HP carries over from one fight to the next. Then you go back to town,
# and from there you start a new run with full HP.
const GOLD_MIN := 1  # Gold each enemy drops (a random amount between these).
const GOLD_MAX := 5

var gold := 0  # Kept between runs, and saved (see "Saving" below).
var dungeon: DungeonRun  # The dungeon in progress (null between runs).
var run_gold := 0  # Gold you took home from the last run, for the shop's summary.
var run_hp := -1  # Your HP between fights. -1 = start the next fight at full HP.
# Room cards you've unlocked with Maps, per area: {"Plains": ["Slime Den"]}.
var unlocked_rooms := {}
# Booster packs bought in the shop and not opened yet, by name: {"Basic Booster": 2}.
var booster_packs := {}

# --- Town, enchants and potions ---------------------------------------------
# The town (scenes/town.tscn): buildings you restore with gold. Saved.
const TOWN_FOLDER := "res://town/"
const ENCHANTS_FOLDER := "res://enchants/"
const POTIONS_FOLDER := "res://potions/"
const FLASKS_FOLDER := "res://flasks/"
const BASE_SACK_SLOTS := 2  # Save Sack slots before the Tailor.
const BASE_GOLD_STACK := 5  # Gold one Save Sack slot holds before the Tailor.
const BASE_POTION_SLOTS := 3  # Potions you can carry before the Alchemist.
const ENCHANT_PRICE := 15  # At the Enchanter.
const POTION_PRICE := 8  # At the Alchemist.
const MAP_PRICE := 25  # At the Mapmaker.
var town_stages := {}  # Building name -> stage restored: {"Tailor": 2}
# Bought in town for your next run (names): they go into the dungeon when it starts.
var pending_enchants: Array[String] = []
var pending_potions: Array[String] = []
# Flasks (flask.gd): which ones you've unlocked (ones that cost 0 are always
# unlocked), the upgrade stages you've bought per flask, and the one you're
# taking into your next run. All saved.
var unlocked_flasks: Array[String] = []
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
const MAX_COPIES := 3  # The most copies of one card you can own (and put in a deck).
# The chance of each rarity for every card in a pack. They add up to 100.
const PACK_ODDS := {CardData.Rarity.COMMON: 60, CardData.Rarity.UNCOMMON: 30, CardData.Rarity.RARE: 10, CardData.Rarity.SUPER: 0}  # Super cards never come from packs.
const CARDS_PER_PACK := 3
var collection := {}

# --- Card Exp ------------------------------------------------------------------
# Opening a copy of a card you already own 3 of gives that card 1 Exp instead.
# Enough Exp levels it up, and the level counts for EVERY copy of it.
# CARD_LEVEL_EXP[n] is the total Exp needed for level n + 1:
#   Level 1 at 0, Level 2 at 3, Level 3 at 3 + 5 = 8.
const CARD_LEVEL_EXP: Array[int] = [0, 3, 8]
var card_exp := {}  # {"Strike": 4}

# --- Class Exp -----------------------------------------------------------------
# Each class levels up on its own. Leveling up is how a class gets its class
# cards (see CharacterClass.level_cards and data/class_cards.csv).
const CLASS_MAX_LEVEL := 25
# Every enemy gives its own Exp (EnemyData.exp: 10 for most, more for bosses)...
const EXP_PER_RUN := 25  # ...plus this for beating all of them.
const FIRST_LEVEL_EXP := 100  # Exp from level 1 to level 2...
const LEVEL_EXP_STEP := 50  # ...and each level after needs this much more.
var class_exp := {}  # Total Exp per class name: {"Knight": 140}

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
var bonus_talent_points := 0  # Extra points every class gets (none yet).
var _bonus_cache := {}  # Remembered talent_bonus() totals (see there).
var talents_return_scene := "res://scenes/character_select.tscn"  # Where the Talents screen's Back goes.

# The last deck you built for each class, as card names: {"Knight": ["Strike", ...]}.
# Picking that class again gives you this deck back instead of the starter deck.
var saved_decks := {}

# Remembered lists, so the cards/ folder is only read once (see load_all_cards()).
var _all_cards: Array[CardData] = []
var _super_cards: Array[CardData] = []
var _cards_by_name := {}  # "Strike" -> its CardData, for find_card().
var _classes: Array[CharacterClass] = []  # For load_classes().
var _talents := {}  # Class name -> its Array[Talent], for talents_for().
var _enemies_by_name := {}  # "Slime" -> its EnemyData, for find_enemy().

const ENEMIES_FOLDER := "res://enemies/"
# Areas whose boss you've beaten (finished a run there): ["Plains"].
# An area with Unlock After = "Plains" opens once the Plains is in here.
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
var active_quest := ""  # The quest you're on ("" = none). See quest.gd.
var quest_progress := 0  # Kills / rooms / tier counted for it.
var quest_seen := false  # false = town shows the quest's story popup.
var quests_done: Array[String] = []
# Parts of the game a quest has opened up ("Unlock Talents" reward), e.g. ["Talents"].
var unlocked_features: Array[String] = []
var seen_guides: Array[String] = []  # Screen guides you've seen (screen_guide.gd): each shows once.
const TALENTS_FEATURE := "Talents"
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
	card_exp.clear()
	class_exp.clear()
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
	chosen_flask = ""
	tutorial_done = false  # A new player sees the tutorial again.
	materials.clear()
	blueprints.clear()
	quests_done.clear()
	unlocked_features.clear()
	seen_guides.clear()
	active_quest = ""
	start_quest(first_quest_name())  # The King's letter: 5 Lumber and the Inn blueprint.
	bonus_talent_points = 0
	character_class = null
	deck.clear()
	start_run()
	# Your first cards come at the end of the Adventurer's training
	# (give_starter_cards(), called by tutorial.gd).
	# Every class starts at level 1, so it gets its level 1 class cards now.
	for character_class in load_classes():
		_give_level_cards(character_class, 1)


# The starter cards (cards.csv Unlocked = TRUE, as many as Copies), given
# at the end of the training. Returns them all for the NEW CARDS screen,
# even ones you already had (so the screen is never empty). If you already
# own more copies than the starter amount, you keep them.
func give_starter_cards() -> Array[CardData]:
	var given: Array[CardData] = []
	for card in load_all_cards():
		if card.unlocked:
			collection[card.card_name] = maxi(owned(card), clampi(card.copies, 1, MAX_COPIES))
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


# Add one copy of a card to your collection. Once you own 3, it gives the
# card 1 Exp instead. Returns what happened, for the screen to show:
#   {"card": CardData, "new": true/false, "owned": 2, "exp": false, "level_up": false}
func add_card(card: CardData) -> Dictionary:
	var result := {"card": card, "new": owned(card) == 0, "exp": false, "level_up": false}
	if owned(card) < MAX_COPIES:
		collection[card.card_name] = owned(card) + 1
	else:
		var level_before := card_level(card)
		card_exp[card.card_name] = card_exp.get(card.card_name, 0) + 1
		result.exp = true
		result.level_up = card_level(card) > level_before
	# Write down the numbers NOW. If the same card comes out twice in one pack,
	# the shop shows each one with the numbers it had at that moment, not the
	# final numbers after the whole pack was opened.
	result.owned = owned(card)
	result.level = card_level(card)
	result.exp_text = card_exp_text(card)
	return result


# Open one booster pack: CARDS_PER_PACK cards, each one added to your
# collection with add_card(). Returns what you got, for the shop to show.
# Any card can come out, even one you already own 3 of (that's how cards get Exp).
func open_pack() -> Array[Dictionary]:
	var opened: Array[Dictionary] = []
	for i in CARDS_PER_PACK:
		var card := _pick_pack_card()
		if card:  # null only if there are no cards that can come from packs at all.
			opened.append(add_card(card))
	save_game()
	return opened


# One random card for a pack. First roll its rarity (60 / 30 / 10), then pick
# any card of that rarity. If the spreadsheet has no cards of some rarity, its
# odds are shared out among the rarities that do have cards.
# Class cards never come from packs: classes get them by leveling up.
func _pick_pack_card() -> CardData:
	var by_rarity := {}  # Rarity -> the cards of that rarity.
	for card in load_all_cards():
		if card.is_class_card():
			continue
		if not by_rarity.has(card.rarity):
			by_rarity[card.rarity] = []
		by_rarity[card.rarity].append(card)
	# Add up the odds of the rarities that have cards, and pick one.
	var total := 0
	for rarity in by_rarity:
		total += PACK_ODDS[rarity]
	if total == 0:
		return null  # No pack cards in the spreadsheet (randi_range(1, 0) would go wrong).
	var roll := randi_range(1, total)
	for rarity in by_rarity:
		roll -= PACK_ODDS[rarity]
		if roll <= 0:
			return by_rarity[rarity].pick_random()
	return null


# A card's level (1 to 3), from its Exp.
func card_level(card: CardData) -> int:
	var exp_total: int = card_exp.get(card.card_name, 0)
	var level := 1
	for i in CARD_LEVEL_EXP.size():
		if exp_total >= CARD_LEVEL_EXP[i]:
			level = i + 1
	return level


# e.g. "Exp 1 / 3" (towards the next level), or "Max level".
func card_exp_text(card: CardData) -> String:
	var level := card_level(card)
	if level >= CARD_LEVEL_EXP.size():
		return "Max level"
	return "Exp %d / %d" % [card_exp.get(card.card_name, 0), CARD_LEVEL_EXP[level]]


# The version of a card you actually play with: its level 2 or 3 file from
# cards/levels/ once it's leveled up. If that level isn't in the level sheet
# yet, it falls back to the highest level that is (or the level 1 card).
func leveled(card: CardData) -> CardData:
	var base_name := card.resource_path.get_file().get_basename()  # "strike"
	for level in range(card_level(card), 1, -1):  # e.g. 3, then 2
		var path := CardImporter.LEVELS_FOLDER + "%s_lv%d.tres" % [base_name, level]
		if ResourceLoader.exists(path):
			return load(path)
	return card


# How much Exp it takes to go from `level` to the next one: 100, 150, 200...
func exp_for_next_level(level: int) -> int:
	return FIRST_LEVEL_EXP + LEVEL_EXP_STEP * (level - 1)


# A class's level, worked out from its total Exp.
func class_level(character_class: CharacterClass) -> int:
	var exp_left: int = class_exp.get(character_class.display_name, 0)
	var level := 1
	while level < CLASS_MAX_LEVEL and exp_left >= exp_for_next_level(level):
		exp_left -= exp_for_next_level(level)
		level += 1
	return level


# Progress towards the next level, for the Exp bar: Vector2i(40, 150) means
# "40 of the 150 Exp needed". At the max level it's Vector2i(0, 0).
func class_exp_progress(character_class: CharacterClass) -> Vector2i:
	var level := class_level(character_class)
	if level >= CLASS_MAX_LEVEL:
		return Vector2i.ZERO
	var exp_left: int = class_exp.get(character_class.display_name, 0)
	for i in range(1, level):
		exp_left -= exp_for_next_level(i)
	return Vector2i(exp_left, exp_for_next_level(level))


# Give the chosen class some Exp. Returns one entry per level gained, with the
# class cards it unlocked: [{"level": 2, "cards": [add_card() results]}]
func add_class_exp(amount: int) -> Array[Dictionary]:
	var level_ups: Array[Dictionary] = []
	var level_before := class_level(character_class)
	class_exp[character_class.display_name] = class_exp.get(character_class.display_name, 0) + amount
	for level in range(level_before + 1, class_level(character_class) + 1):
		level_ups.append({"level": level, "cards": _give_level_cards(character_class, level)})
	save_game()
	return level_ups


# Add the class cards a class gets at `level` to your collection.
func _give_level_cards(character_class: CharacterClass, level: int) -> Array[Dictionary]:
	var given: Array[Dictionary] = []
	for card_name in character_class.level_cards.get(level, PackedStringArray()):
		var card := find_card(card_name)
		if card:
			given.append(add_card(card))
	return given


# The level 1 card with this name, or null.
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


func first_quest_name() -> String:
	return load_quests()[0].quest_name if not load_quests().is_empty() else ""


func current_quest() -> Quest:
	return find_quest(active_quest) if not active_quest.is_empty() else null


# Start a quest: hand out its Start Gift, and town shows its story next visit.
func start_quest(quest_name: String) -> void:
	var quest := find_quest(quest_name)
	active_quest = quest.quest_name if quest else ""
	quest_progress = 0
	quest_seen = false
	if quest:
		give_rewards(quest.start_gift)


# How far along the active quest is, and how much it needs: Vector2i(3, 5).
func quest_status() -> Vector2i:
	var quest := current_quest()
	if quest == null:
		return Vector2i.ZERO
	match quest.objective:
		Quest.BUILD:
			var building := find_building(quest.target)
			return Vector2i(mini(town_stage(building) if building else 0, 1), 1)
		Quest.HAVE:
			return Vector2i(mini(material_count(quest.target), quest.amount), quest.amount)
		Quest.BREW:
			var flask := find_flask(quest.target)
			return Vector2i(1 if flask and is_flask_unlocked(flask) else 0, 1)
	return Vector2i(mini(quest_progress, quest.amount), quest.amount)


func quest_ready() -> bool:
	var status := quest_status()
	return current_quest() != null and status.x >= status.y


# Count something for the active quest: a kill, a beaten room, a tier reached.
func record_for_quest(objective: String, target: String, value: int = 1) -> void:
	var quest := current_quest()
	if quest == null or quest.objective != objective:
		return
	if objective == Quest.REACH_TIER:
		quest_progress = maxi(quest_progress, value)
	elif quest.target.to_lower() == target.to_lower():
		quest_progress += value


# Nothing to do here yet: quests are handed in at the Inn (town.gd).
func check_quest() -> void:
	pass


# Hand in the active quest: rewards, then the next quest starts. Returns
# what you got, one line each.
func complete_quest() -> Array[String]:
	var quest := current_quest()
	if quest == null or not quest_ready():
		return []
	quests_done.append(quest.quest_name)
	var lines := give_rewards(quest.rewards)
	start_quest(quest.next_quest)
	save_game()
	return lines


# "Gold 20; Pack 1; Material Lumber 5; Blueprint Alchemist; Room Plains: Big Slime Nest"
func give_rewards(text: String) -> Array[String]:
	var lines: Array[String] = []
	for part in text.split(";", false):
		var reward := part.strip_edges()
		var words := reward.split(" ", false)
		if words.is_empty():
			continue
		var rest := reward.substr(words[0].length()).strip_edges()
		match words[0].to_lower():
			"gold":
				gold += rest.to_int()
				lines.append("%d gold" % rest.to_int())
			"pack":
				var count := maxi(rest.to_int(), 1)
				booster_packs[DungeonRun.PACK_NAME] = booster_packs.get(DungeonRun.PACK_NAME, 0) + count
				lines.append("%d Booster Pack%s" % [count, "s" if count > 1 else ""])
			"material":
				var costs := MaterialInfo.parse_costs(rest)
				for material_name in costs:
					add_material(material_name, costs[material_name])
				lines.append(MaterialInfo.costs_text(costs))
			"blueprint":
				if not blueprints.has(rest):
					blueprints.append(rest)
				lines.append("Blueprint: " + rest)
			"room":  # "Room Plains: Blue Slime Patch"
				var area_name := rest.get_slice(":", 0).strip_edges()
				var room_name := rest.get_slice(":", 1).strip_edges()
				if not unlocked_rooms.has(area_name):
					unlocked_rooms[area_name] = []
				if not unlocked_rooms[area_name].has(room_name):
					unlocked_rooms[area_name].append(room_name)
				lines.append("New room in the %s: %s" % [area_name, room_name])
			"unlock":  # "Unlock Talents": opens up a part of the game.
				if not unlocked_features.has(rest):
					unlocked_features.append(rest)
				lines.append("%s unlocked!" % rest)
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
		if not vanished.has(i) and not run_enchants.has(i) and enchant.fits(leveled(deck[i])):
			found.append(i)
	return found


func enchant_card(deck_index: int, enchant: Enchant) -> void:
	run_enchants[deck_index] = enchant


# Your max HP in a fight: your class's, plus Heavy Pack (+Amount for every
# 2 cards above 20 in your deck).
func player_max_hp() -> int:
	var per_two := talent_bonus(character_class, Talent.HP_PER_EXTRA_CARDS)
	return character_class.max_hp + maxi(deck.size() - 20, 0) / 2 * per_two


# --- Room cards ---------------------------------------------------------------

# Is this room card in the area's deck? Cards start Unlocked (the sheet's
# Unlocked column), or you find a Map for them.
func is_room_unlocked(area: Area, card: RoomCard) -> bool:
	return card.unlocked or unlocked_rooms.get(area.display_name, []).has(card.room_name)


# A Map: unlock a random locked room card for this area (saved straight
# away: what you learn from a map stays, even if you die). null if none are left.
func unlock_random_room(area: Area) -> RoomCard:
	# Quest rooms are left out: only their quest unlocks them.
	var locked := area.rooms.filter(func(card: RoomCard) -> bool: return not card.quest_only and not is_room_unlocked(area, card))
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


# The deck you last built for this class, from saved_decks. Any card the class
# can't use any more (or that you don't own enough of) is left out.
func _load_saved_deck(for_class: CharacterClass) -> Array[CardData]:
	var cards: Array[CardData] = []
	for card_name in saved_decks.get(for_class.display_name, []):
		var card := find_card(card_name)
		if card:
			cards.append(card)
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


# Points: 1 per level after level 1, plus bonus points, minus what's spent.
func talent_points_earned(for_class: CharacterClass) -> int:
	return class_level(for_class) - 1 + bonus_talent_points


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
# What's saved: gold, your collection, card Exp, class Exp, unopened packs,
# talents and the last deck you built for each class. NOT saved: a run in progress.
# Quit in the middle of a run and you start a new one next time.
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 4  # Bump this if the save format changes. 2 = the town starts empty (quests). 3 = Guild Hall first, Stone for the Inn. 4 = first cards come at the end of the training.


func save_game() -> void:
	if character_class:
		saved_decks[character_class.display_name] = deck.map(func(card: CardData) -> String: return card.card_name)
	var data := {
		"version": SAVE_VERSION,
		"gold": gold,
		"collection": collection,
		"card_exp": card_exp,
		"class_exp": class_exp,
		"booster_packs": booster_packs,
		"decks": saved_decks,
		"talents": talent_ranks,
		"specs": class_specs,
		"bonus_talent_points": bonus_talent_points,
		"cleared_areas": cleared_areas,
		"unlocked_rooms": unlocked_rooms,
		"town": town_stages,
		"pending_enchants": pending_enchants,
		"pending_potions": pending_potions,
		"unlocked_flasks": unlocked_flasks,
		"flask_upgrades": flask_upgrades,
		"chosen_flask": chosen_flask,
		"tutorial_done": tutorial_done,
		"materials": materials,
		"blueprints": blueprints,
		"active_quest": active_quest,
		"quest_progress": quest_progress,
		"quest_seen": quest_seen,
		"quests_done": quests_done,
		"unlocked_features": unlocked_features,
		"seen_guides": seen_guides,
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
	card_exp = _whole_numbers(data.get("card_exp", {}))
	class_exp = _whole_numbers(data.get("class_exp", {}))
	booster_packs = _whole_numbers(data.get("booster_packs", {}))
	saved_decks = data.get("decks", {})
	talent_ranks.clear()
	var saved_talents: Dictionary = data.get("talents", {})
	for class_name_key in saved_talents:
		talent_ranks[class_name_key] = _whole_numbers(saved_talents[class_name_key])
	bonus_talent_points = int(data.get("bonus_talent_points", 0))
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
	tutorial_done = bool(data.get("tutorial_done", false))
	var saved_materials = data.get("materials", {})
	materials = _whole_numbers(saved_materials) if saved_materials is Dictionary else {}
	blueprints.assign(data.get("blueprints", []))
	active_quest = str(data.get("active_quest", ""))
	quest_progress = int(data.get("quest_progress", 0))
	quest_seen = bool(data.get("quest_seen", true))
	quests_done.assign(data.get("quests_done", []))
	unlocked_features.assign(data.get("unlocked_features", []))
	seen_guides.assign(data.get("seen_guides", []))
	var saved_specs = data.get("specs", {})
	class_specs = saved_specs if saved_specs is Dictionary else {}  # Ignore a broken entry.
	_talents_changed()
	# A card added to the spreadsheet as Unlocked after you saved still
	# shows up in your collection (once you've had your starter cards).
	for card in load_all_cards():
		if tutorial_done and card.unlocked and owned(card) == 0:
			collection[card.card_name] = clampi(card.copies, 1, MAX_COPIES)
	return true


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
	if town_bonus(TownBuilding.INN) == 0:
		# No adventurers until the Inn is built. Before that, only the guided
		# run is open: once you have the Inn's blueprint, you go and get Stone.
		return blueprints.has("Inn") and has_guide_rooms(area)
	return area.unlocked or (not area.unlock_after.is_empty() and cleared_areas.has(area.unlock_after))


# Does this area have rooms for the guided first run (Tier "Guide" in rooms.csv)?
func has_guide_rooms(area: Area) -> bool:
	return area.rooms.any(func(card: RoomCard) -> bool: return card.tier == RoomCard.GUIDE_TIER)


# A run before the Inn is built is the guided one: no enemies, just tips.
func is_guided_run(area: Area) -> bool:
	return town_bonus(TownBuilding.INN) == 0 and has_guide_rooms(area)


# Talents and specs stay hidden until a quest unlocks them (after the first boss).
func talents_open() -> bool:
	return unlocked_features.has(TALENTS_FEATURE)


# Has an adventurer come to town yet? The Inn brings them: until it's built,
# no class is playable and you're busy running the town.
func adventurers_here() -> bool:
	return town_bonus(TownBuilding.INN) > 0


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
func find_enemy(enemy_name: String) -> EnemyData:
	if _enemies_by_name.is_empty():
		for file_name in ResourceLoader.list_directory(ENEMIES_FOLDER):
			if file_name.ends_with(".tres"):
				var enemy: EnemyData = load(ENEMIES_FOLDER + file_name)
				_enemies_by_name[enemy.display_name.to_lower()] = enemy
	return _enemies_by_name.get(enemy_name.to_lower())


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


# The run-only Super cards (data/super_cards.csv -> cards/super/). Not in packs or the collection.
func load_super_cards() -> Array[CardData]:
	if _super_cards.is_empty():
		for file_name in ResourceLoader.list_directory(CardImporter.SUPER_FOLDER):
			if file_name.ends_with(".tres"):
				_super_cards.append(load(CardImporter.SUPER_FOLDER + file_name))
	return _super_cards


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
func ensure_ready() -> void:
	if character_class == null:
		choose_class(load_classes()[0])
	elif deck.is_empty():
		deck = make_starter_deck()
	if current_area == null:
		current_area = load_areas()[0]  # The first area on the road (the Plains).
	if dungeon == null:
		dungeon = DungeonRun.new(current_area)
