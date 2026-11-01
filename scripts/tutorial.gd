# tutorial.gd
#
# The quick TUTORIAL: three short fights against Training Dummies, using
# the normal battle screen (battle.gd) with this panel on top.
#   Stage 1: defeat the dummies   (how to play attack cards, Energy, End Turn)
#   Stage 2: take no damage       (Block, Armor, reading enemy intents)
#   Stage 3: heal what you lost   (Ability cards, Vanish, Criticals)
# It starts by itself the first time you open the game (character_select.gd),
# Skip ends it at any time, and the Tutorial button on Character Select
# plays it again.
#
# How it plugs in: Tutorial.begin(1) swaps in a practice deck and the
# dummies, remembering your real class/deck/run so finish() can put them
# back. battle.gd sees GameState.tutorial_stage > 0, adds this panel, and
# tells it when enemies die, when the enemy turn ends, and when the screen
# updates. Nothing in the tutorial gives gold, Exp or cards.
class_name Tutorial
extends PanelContainer

const BATTLE_SCENE := "res://scenes/battle.tscn"
const AFTER_SCENE := "res://scenes/character_select.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"  # A new player goes to town next, for the King's letter.
const CLEAN_TURNS_NEEDED := 2  # Stage 2: enemy turns in a row with no damage.
const HEAL_NEEDED := 8  # Stage 3.
const GOLD := Color(1, 0.84, 0.35)

# Each stage: what it's called, the goal, a few tips, the practice deck,
# the enemies, and the HP you start with (-1 = full).
const STAGES := [
	{
		"title": "Stage 1: Attack!",
		"goal": "Defeat both Training Dummies.",
		"tips": [
			"Your cards are at the bottom. The number in a card's top-left corner is its Energy cost. You get 3 Energy every turn.",
			"DRAG an attack card (Strike) onto a dummy to hit it. The die on the card is the damage it will do.",
			"Out of Energy? Press End Turn to draw a fresh hand.",
		],
		"deck": {"Strike": 4, "Heavy Strike": 2},
		"enemies": ["Training Dummy", "Training Dummy"],
		"hp": -1,
	},
	{
		"title": "Stage 2: Block!",
		"goal": "Take NO damage for 2 enemy turns in a row.",
		"tips": [
			"Enemies show what they'll do next under their name: this dummy will Attack 6.",
			"Defense cards give Block, which soaks up damage before your HP. Drag a Guard into the middle of the screen.",
			"Your Armor keeps 3 Block for you each turn. Get your Block to 6 or more, then press End Turn.",
		],
		"deck": {"Guard": 4, "Full Guard": 2},
		"enemies": ["Sparring Dummy"],
		"hp": -1,
	},
	{
		"title": "Stage 3: Heal!",
		"goal": "Heal 8 HP.",
		"tips": [
			"You're hurt (look at your HP). Ability cards like Bandage heal you: drag one into the middle of the screen.",
			"A card with Vanish is gone for the rest of the run once you play it, so use them wisely.",
			"A die that rolls its highest number is a CRITICAL and does a little extra (Crit: +1 Heal).",
		],
		"deck": {"Bandage": 6, "First Aid": 2},
		"enemies": ["Training Dummy"],
		"hp": 13,
	},
]

var battle: Node  # The battle screen this panel sits on (battle.gd).
var progress_label: Label
var popup: PanelContainer
var clean_turns := 0
var start_hp := 0
var won := false


# --- Starting and finishing (static: called from other screens) ----------------

# Start (or move on to) a stage. Saves your real setup the first time.
static func begin(stage: int) -> void:
	if GameState.tutorial_stage == 0:
		GameState.tutorial_backup = {"class": GameState.character_class, "deck": GameState.deck.duplicate(),
			"dungeon": GameState.dungeon, "run_hp": GameState.run_hp, "vanished": GameState.vanished.duplicate(),
			"enchants": GameState.run_enchants.duplicate()}
	GameState.tutorial_stage = stage
	var info: Dictionary = STAGES[stage - 1]
	GameState.character_class = GameState.load_classes()[0]  # The Adventurer.
	var practice: Array[CardData] = []
	for card_name in info.deck:
		var card := GameState.find_card(card_name)
		if card:
			for i in info.deck[card_name]:
				practice.append(card)
	GameState.deck = practice
	GameState.vanished.clear()
	GameState.run_enchants.clear()
	GameState.run_hp = info.hp
	if GameState.current_area == null:
		GameState.current_area = GameState.load_areas()[0]
	var practice_run := DungeonRun.new(GameState.current_area)
	for enemy_name in info.enemies:
		var enemy := GameState.find_enemy(enemy_name)
		if enemy:
			practice_run.fight_enemies.append(enemy)
	GameState.dungeon = practice_run


# Done or skipped: put your real class, deck and run back, and never auto-start again.
static func finish() -> void:
	var backup: Dictionary = GameState.tutorial_backup
	if not backup.is_empty():
		GameState.character_class = backup["class"]
		GameState.deck = backup.deck
		GameState.dungeon = backup.dungeon
		GameState.run_hp = backup.run_hp
		GameState.vanished = backup.vanished
		GameState.run_enchants = backup.enchants
	GameState.tutorial_backup = {}
	GameState.tutorial_stage = 0
	GameState.tutorial_done = true
	GameState.save_game()


# --- The panel ----------------------------------------------------------------

func _ready() -> void:
	var info: Dictionary = STAGES[GameState.tutorial_stage - 1]
	position = Vector2(16, 16)
	custom_minimum_size = Vector2(360, 0)  # Narrow enough to stay clear of the enemies.
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.92)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := make_label("%s  (%d/%d)" % [info.title, GameState.tutorial_stage, STAGES.size()], 20, GOLD)
	title.custom_minimum_size.x = 0
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var skip := Button.new()
	skip.text = "Skip Tutorial"
	skip.tooltip_text = "Jump straight to the game. (Replay it from Character Select.)"
	skip.pressed.connect(_on_skip)
	header.add_child(skip)
	box.add_child(make_label("Goal: " + info.goal, 16, Color.WHITE))
	for tip in info.tips:
		box.add_child(make_label("•  " + tip, 13, Color(1, 1, 1, 0.8)))
	progress_label = make_label("", 16, Color(0.55, 0.95, 0.55))
	box.add_child(progress_label)
	start_hp = GameState.run_hp if GameState.run_hp > 0 else GameState.player_max_hp()
	refresh()


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(336, 0)
	return label


# --- What battle.gd tells us ---------------------------------------------------

# Called whenever the battle screen updates: show progress, check stage 3.
func refresh() -> void:
	if battle == null or won:
		return
	match GameState.tutorial_stage:
		1:
			progress_label.text = "Dummies left: %d" % battle.living_enemies().size()
		2:
			progress_label.text = "Turns with no damage: %d / %d" % [clean_turns, CLEAN_TURNS_NEEDED]
		3:
			var healed: int = maxi(battle.player.hp - start_hp, 0) if battle.turn > 0 else 0
			progress_label.text = "Healed: %d / %d" % [mini(healed, HEAL_NEEDED), HEAL_NEEDED]
			if healed >= HEAL_NEEDED and battle.turn > 0:  # (Before turn 1 your HP isn't set yet.)
				stage_won.call_deferred()  # After the card finishes.


func enemy_died() -> void:
	refresh()
	if GameState.tutorial_stage == 1 and battle.living_enemies().is_empty():
		stage_won()


# The enemies just finished their turn: how much did you lose?
func after_enemy_turn(damage_taken: int) -> void:
	if GameState.tutorial_stage != 2:
		return
	if damage_taken > 0:
		clean_turns = 0
		battle.message_label.text = "Ouch, %d damage! The count starts over: Block more next time." % damage_taken
	else:
		clean_turns += 1
		battle.message_label.text = "Blocked it all!"
	refresh()
	if clean_turns >= CLEAN_TURNS_NEEDED:
		stage_won()


# Losing in the tutorial just starts the stage again.
func player_died() -> void:
	begin(GameState.tutorial_stage)
	get_tree().change_scene_to_file.call_deferred(BATTLE_SCENE)


# --- Stage done -----------------------------------------------------------------

func stage_won() -> void:
	if won:
		return
	won = true
	battle.game_over = true  # Stops cards and End Turn.
	battle.end_turn_button.disabled = true
	progress_label.text = "Done!"
	var last := GameState.tutorial_stage >= STAGES.size()
	popup = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.07, 0.96)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	style.shadow_color = Color(1, 0.8, 0.3, 0.35)
	style.shadow_size = 16
	popup.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	popup.add_child(box)
	var heading := make_label("Stage %d complete!" % GameState.tutorial_stage if not last else "Training complete!", 32, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var text := "Nice work." if not last else "You know how to attack, block and heal. Time for a real adventure!"
	var body := make_label(text, 18, Color.WHITE)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	var next := Button.new()
	next.text = "Next Stage →" if not last else "Start Playing →"
	next.theme_type_variation = &"PrimaryButton"
	next.custom_minimum_size = Vector2(220, 48)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_on_next)
	box.add_child(next)
	battle.add_child(popup)
	popup.reset_size()
	popup.position = (battle.size - popup.size) / 2
	popup.pivot_offset = popup.size / 2
	popup.scale = Vector2(0.6, 0.6)
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(popup, "scale", Vector2.ONE, 0.3)


func _on_next() -> void:
	if GameState.tutorial_stage >= STAGES.size():
		finish()
		get_tree().change_scene_to_file(after_scene())
	else:
		begin(GameState.tutorial_stage + 1)
		get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_skip() -> void:
	finish()
	get_tree().change_scene_to_file(after_scene())


# Where to go when the tutorial ends: town if there's a quest story waiting
# (or no Inn yet), otherwise Character Select.
static func after_scene() -> String:
	# Back to town if there's a new quest to read (the Innkeeper's first job).
	var unread := GameState.current_quest() != null and not GameState.quest_seen
	return TOWN_SCENE if not GameState.adventurers_here() or unread else AFTER_SCENE
