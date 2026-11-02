# tutorial.gd
#
# The Adventurer's TRAINING: three short fights against Training Dummies,
# using the normal battle screen (battle.gd) with this panel on top. It
# starts when the first Adventurer arrives (after the Inn is built).
#   Stage 1, Attack: Strikes (dice on cards, a guaranteed Critical), then on
#                    turn 2 Punch, Kick and Reroll (card Schools, rerolls)
#   Stage 2, Block:  turn 1 Full Guard (Wild cards), turn 2 Master of None
#                    and Fortify ("+ next roll" bonuses, Armor)
#   Stage 3, Heal:   Bandage and Insight (healing, Advantage, Vanish)
# Each stage draws its cards in a set order ("draw"), and can fix one die
# ("rig") so the lesson always shows up. At the end: the NEW CARDS screen
# (your first cards), then the Spec screen and the Deck Builder.
# Skip ends it at any time (you still get the cards), and the Tutorial
# button on Character Select plays it again.
#
# How it plugs in: Tutorial.begin(1) swaps in a practice deck and the
# dummies, remembering your real class/deck/run so finish() can put them
# back. battle.gd sees GameState.tutorial_stage > 0, adds this panel, and
# tells it when cards are drawn, when enemies die, when the enemy turn ends,
# and when the screen updates. Nothing in the tutorial gives gold or Exp.
class_name Tutorial
extends PanelContainer

const BATTLE_SCENE := "res://scenes/battle.tscn"
const AFTER_SCENE := "res://scenes/character_select.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"  # Back to town after the training, for the Innkeeper's news.
const SPEC_SCENE := "res://scenes/spec_select.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CARD_SCENE := preload("res://scenes/card.tscn")
const CLEAN_TURNS_NEEDED := 2  # Stage 2: enemy turns in a row with no damage.
const HEAL_NEEDED := 6  # Stage 3.
const GOLD := Color(1, 0.84, 0.35)

# Each stage: its title and goal, tips for each turn ("tips": turn -> lines;
# later turns keep the last ones), the practice deck, the order you draw it
# in ("draw", first card first; the rest come after, shuffled), dice to fix
# ("rig": card name -> the first die's number, for the first copy drawn),
# the enemies, and the HP you start with (-1 = full).
const STAGES := [
	{
		"title": "Stage 1: Attack!",
		"goal": "Defeat the Training Dummy.",
		"tips": {
			1: [
				"Drag a Strike onto the dummy to attack. Each card costs Energy (top-left number). You get 3 every turn.",
				"Dice cards ROLL when you draw them: the number on the die is what the card will do. Strike rolls a d3 (1 to 3).",
				"A die that lands on its TOP number is a CRITICAL! One of your Strikes rolled a 3: it adds its Crit effect (+1 Damage). Look for the gold die.",
				"Out of Energy? Press End Turn.",
			],
			2: [
				"New cards! Each card belongs to a SCHOOL: Punch is Strength (red), Kick is Agility (green). Neutral cards (grey) fit any deck.",
				"Each school plays differently. Strength hits hard with big dice; Agility is quick and cheap.",
				"REROLL (an Adventurer class card) lets you roll a card in your hand again. Don't like Punch's number? Play Reroll, then click Punch.",
				"Crits on Punch and Kick add +2 Damage.",
			],
		},
		"deck": {"Strike": 7, "Punch": 1, "Kick": 1, "Reroll": 1},
		"draw": ["Strike", "Strike", "Strike", "Strike", "Strike", "Punch", "Kick", "Reroll"],
		"rig": {"Strike": 3},
		"enemies": ["Training Dummy"],
		"hp": -1,
	},
	{
		"title": "Stage 2: Block!",
		"goal": "Take NO damage for 2 enemy turns in a row.",
		"tips": {
			1: [
				"This dummy will Attack 6 (see under its name). Block soaks up damage before your HP.",
				"Full Guard is WILD: it doesn't roll when drawn, it rolls when you PLAY it (d6 Block). Riskier, but its Crit gives you 1 Energy back.",
			],
			2: [
				"Fortify (Wisdom, purple) rolls d6 Block. It rolled a 5... play MASTER OF NONE first: its +1 goes on your next roll, so that 5 becomes a 6: a CRITICAL!",
				"Fortify's Critical gives you +1 ARMOR for this fight. Armor keeps that much of your leftover Block at the start of each turn (the Adventurer has 3).",
			],
			3: [
				"Your Block from last turn mostly faded, but your Armor kept some of it. Check the Block number next to your HP.",
			],
		},
		# Turn 1: only Full Guards. Turn 2: Master of None and Fortify arrive together.
		"deck": {"Master of None": 1, "Fortify": 2, "Full Guard": 7},
		"draw": ["Full Guard", "Full Guard", "Full Guard", "Full Guard", "Full Guard",
			"Master of None", "Fortify", "Fortify", "Full Guard", "Full Guard"],
		"rig": {"Fortify": 5},
		"enemies": ["Sparring Dummy"],
		"hp": -1,
	},
	{
		"title": "Stage 3: Heal!",
		"goal": "Heal 6 HP.",
		"tips": {
			1: [
				"You're hurt (look at your HP). Bandage heals d3: drag it into the middle of the screen.",
				"INSIGHT (Intellect, blue) gives your next roll ADVANTAGE: roll the dice twice and keep the better one. Play Insight, then a Bandage.",
				"Bandage and Insight VANISH: once played, they're gone for the rest of the run (not just this fight). Healing is precious!",
			],
		},
		"deck": {"Insight": 1, "Bandage": 5},
		"draw": ["Insight", "Bandage", "Bandage", "Bandage", "Bandage", "Bandage"],
		"rig": {},
		"enemies": ["Training Dummy"],
		"hp": 13,
	},
]

var battle: Node  # The battle screen this panel sits on (battle.gd).
var progress_label: Label
var popup: PanelContainer
var tips_box: VBoxContainer
var tips_turn := -1  # The turn the tips on screen are for.
var rigged: Array[String] = []  # Cards whose die we already fixed this stage.
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
	tips_box = VBoxContainer.new()
	tips_box.add_theme_constant_override("separation", 4)
	box.add_child(tips_box)
	show_tips(1)
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


# The tips for this turn (a later turn with no tips of its own keeps the last ones).
func show_tips(for_turn: int) -> void:
	var tips: Dictionary = STAGES[GameState.tutorial_stage - 1].tips
	var best := -1
	for turn_number: int in tips:
		if turn_number <= for_turn and turn_number > best:
			best = turn_number
	if best == tips_turn or best < 0:
		return
	tips_turn = best
	for old in tips_box.get_children():
		old.queue_free()
	if best > 1:
		tips_box.add_child(make_label("NEW THIS TURN:", 14, GOLD))
	for tip: String in tips[best]:
		tips_box.add_child(make_label("•  " + tip, 13, Color(1, 1, 1, 0.85)))
	# A little flash so the new tips get noticed.
	tips_box.modulate = Color(1.6, 1.4, 0.8)
	create_tween().tween_property(tips_box, "modulate", Color.WHITE, 0.8)


# --- What battle.gd tells us ---------------------------------------------------

# The fight is about to start: put the draw pile in the stage's order. The
# draw pile is drawn from the END, so the first card to draw goes last.
func arrange_draw_pile(draw_pile: Array[CardData]) -> void:
	var order: Array = STAGES[GameState.tutorial_stage - 1].get("draw", [])
	var picked: Array[CardData] = []
	for card_name: String in order:
		for card in draw_pile:
			if card.card_name == card_name and not picked.has(card):
				picked.append(card)
				break
	for card in picked:
		draw_pile.erase(card)
	picked.reverse()
	draw_pile.append_array(picked)


# A card was just drawn and rolled: fix its first die if the stage says so
# (only the first copy), so the lesson (a Critical...) always happens.
func rig_roll(card: CardData) -> void:
	var rig: Dictionary = STAGES[GameState.tutorial_stage - 1].get("rig", {})
	if not rig.has(card.card_name) or rigged.has(card.card_name) or card.roll_result.is_empty():
		return
	rigged.append(card.card_name)
	var key: String = card.roll_result.keys()[0]  # "attack 0", "block"...
	var dice: Array = card.roll_result[key]
	if not dice.is_empty():
		dice[0] = rig[card.card_name]


# Called whenever the battle screen updates: show progress, check stage 3.
func refresh() -> void:
	if battle == null or won:
		return
	if battle.turn > 0:
		show_tips(battle.turn)
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
		var first_time := not GameState.tutorial_done
		finish()
		if first_time:
			popup.queue_free()
			show_new_cards()
		else:
			get_tree().change_scene_to_file(after_scene())
	else:
		begin(GameState.tutorial_stage + 1)
		get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_skip() -> void:
	var first_time := not GameState.tutorial_done
	finish()
	if first_time:
		show_new_cards()  # Skipping still gives you your first cards.
	else:
		get_tree().change_scene_to_file(after_scene())


# The big NEW CARDS UNLOCKED screen: your starter cards pop in one by one.
# Then on to the Spec screen.
func show_new_cards() -> void:
	var given: Array[CardData] = GameState.give_starter_cards()
	# The Adventurer builds a deck from these after picking a spec (spec_select.gd).
	GameState.character_class = GameState.load_classes()[0]
	GameState.deck.clear()
	GameState.save_game()
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	var delay := 0.9
	for card in given:
		row.add_child(_mini_card(card, delay))
		delay += 0.12
	UnlockBanner.show_in(battle, "NEW CARDS UNLOCKED!", "", null,
		"Your first cards! They're in your collection now: build your deck from them.",
		"Choose a Specialization →", func() -> void: get_tree().change_scene_to_file(SPEC_SCENE), row)


# One small card for the NEW CARDS screen, with "x3" under it. It pops in after `delay`.
func _mini_card(card: CardData, delay: float) -> Control:
	const SCALE := 0.62
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	var frame := Control.new()  # A Card is big: scale it down inside a fixed-size frame.
	var view: Control = CARD_SCENE.instantiate()
	frame.add_child(view)
	view.setup.call_deferred(card)  # Once it's on screen (its labels need to be ready).
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.scale = Vector2.ONE * SCALE
	frame.custom_minimum_size = view.custom_minimum_size * SCALE if view.custom_minimum_size != Vector2.ZERO else Vector2(80, 112)
	holder.add_child(frame)
	var count := make_label("x%d" % GameState.owned(card), 16, GOLD)
	count.custom_minimum_size = Vector2(0, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(count)
	holder.modulate.a = 0
	holder.create_tween().tween_property(holder, "modulate:a", 1.0, 0.25).set_delay(delay)
	return holder


# Where to go when the tutorial ends: town if there's a quest story waiting
# (or no Inn yet), otherwise Character Select.
static func after_scene() -> String:
	# Back to town if there's a new quest to read (the Innkeeper's first job).
	var unread := not GameState.unseen_quests.is_empty()
	return TOWN_SCENE if not GameState.adventurers_here() or unread else AFTER_SCENE
