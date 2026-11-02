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
# Each stage opens with a big intro banner (unlock_banner.gd), then SPOTLIGHTS
# (screen_guide.gd) dim the screen and point at the real thing each turn:
# a card, its dice, your Energy, End Turn... The first time something special
# happens (a Critical, a Wild roll, Armor...), a KEYWORD POP-UP celebrates it.
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

# Each stage: its title, goal and intro banner (icon, text), the SPOTLIGHTS
# for each turn ("spots": turn -> steps; see show_spots()), what it taught
# ("learned", for the Stage Complete banner), the practice deck, the order you
# draw it in ("draw", first card first; the rest come after, shuffled), dice
# to fix ("rig": card name -> the first die's number for the first copy drawn,
# or a list of numbers for the first few copies), the enemies, and the HP you start with (-1 = full).
#
# A spotlight step is {"at": what to point at, "text": what to say}. "at" can be:
#   "enemy"         the first enemy        "energy"   your Energy
#   "card:Strike"   that card in your hand  "end turn" the End Turn button
#   "dice:Strike"   that card's dice (the   "block"    your Block (and Armor)
#                   rigged copy if there is) "hp"       your HP
const STAGES := [
	{
		"title": "Stage 1: Attack!",
		"goal": "Defeat the Training Dummy.",
		"icon": "res://icons/attack.svg",
		"intro": "Time to learn how a fight works: play cards, roll dice, hit hard. Knock down the Training Dummy!",
		"learned": "Energy, dice, Criticals, card Schools and Reroll.",
		"spots": {
			1: [
				{"at": "enemy", "text": "This is a Training Dummy. Bring its HP down to 0 to win. It won't hit back... yet."},
				{"at": "card:Strike", "text": "This is STRIKE, an Attack card. To play it, DRAG it onto the dummy."},
				{"at": "energy", "text": "Every card costs ENERGY: the number in its top-left corner. You get 3 Energy every turn."},
				{"at": "dice:Strike", "text": "Dice cards ROLL when you draw them. This Strike rolled a 3, the top number of its d3: a CRITICAL! It deals +1 Damage. Play it first!"},
				{"at": "end turn", "text": "Out of Energy? Press END TURN. The enemy takes its turn, then you draw a fresh hand."},
			],
			2: [
				{"at": "card:Punch", "text": "New cards! Every card has a SCHOOL. PUNCH is Strength (red): big dice, big hits."},
				{"at": "card:Kick", "text": "KICK is Agility (green): quick and cheap. Neutral cards (grey) fit any deck."},
				{"at": "card:Reroll", "text": "Don't like a roll? Play REROLL, then click a card in your hand to roll its dice again."},
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
		"icon": "res://icons/block.svg",
		"intro": "This dummy hits back! Learn to Block its attacks and soak up the damage.",
		"learned": "Block, Wild cards, roll bonuses and Armor.",
		"spots": {
			1: [
				{"at": "enemy", "text": "Look under the dummy's name: it will ATTACK 6 this turn. Enemies always show you what they're about to do."},
				{"at": "card:Full Guard", "text": "FULL GUARD gives you Block. It's WILD: its die rolls when you PLAY it, not when you draw it. Riskier, but its Crit gives you 1 Energy back."},
				{"at": "block", "text": "Your BLOCK shows here. Block soaks up damage before your HP does. Get it to 6 before you End Turn!"},
			],
			2: [
				{"at": "card:Master of None", "text": "MASTER OF NONE costs 0 and gives +1 to your NEXT roll."},
				{"at": "dice:Fortify", "text": "This Fortify rolled a 5 on its d6. Play Master of None first: +1 turns that 5 into a 6, a CRITICAL! Fortify's crit gives you +1 ARMOR."},
			],
			3: [
				{"at": "block", "text": "Your Block fades at the start of each turn, but your ARMOR keeps that much of it. That's why you still have some!"},
			],
		},
		# Turn 1: only Full Guards. Turn 2: Master of None and Fortify arrive together.
		"deck": {"Master of None": 1, "Fortify": 2, "Full Guard": 7},
		"draw": ["Full Guard", "Full Guard", "Full Guard", "Full Guard", "Full Guard",
			"Master of None", "Fortify", "Fortify", "Full Guard", "Full Guard"],
		# The first Fortify rolls 5 (a crit with Master of None), the second a
		# plain 3, so the lesson isn't spoiled by a lucky natural 6.
		"rig": {"Fortify": [5, 3]},
		"enemies": ["Sparring Dummy"],
		"hp": -1,
	},
	{
		"title": "Stage 3: Heal!",
		"goal": "Heal 6 HP.",
		"icon": "res://icons/heal.svg",
		"intro": "Ouch, you're hurt! Patch yourself up, and learn how to make every heal count.",
		"learned": "Healing, Advantage and Vanish.",
		"spots": {
			1: [
				{"at": "hp", "text": "You're down to 13 HP. Heal 6 to finish the training."},
				{"at": "card:Insight", "text": "INSIGHT gives your next roll ADVANTAGE: it rolls twice and keeps the better one. Play it first!"},
				{"at": "card:Bandage", "text": "BANDAGE heals d3. Drag it into the middle of the screen. Careful: it VANISHES once played."},
			],
		},
		"deck": {"Insight": 1, "Bandage": 5},
		"draw": ["Insight", "Bandage", "Bandage", "Bandage", "Bandage", "Bandage"],
		"rig": {},
		"enemies": ["Training Dummy"],
		"hp": 13,
	},
]

# The KEYWORD POP-UPS: the first time each thing happens in a fight, a big
# gold word pops up over the battle with a line on what just happened.
const KEYWORDS := {
	"crit": ["CRITICAL!", "A die landed on its top number, so the card's Crit effect kicks in too."],
	"reroll": ["REROLL!", "New dice, new chances. Rerolling can't make things worse than a fresh roll."],
	"wild": ["WILD!", "Wild cards roll the moment you play them. You never know what you'll get!"],
	"armor": ["ARMOR UP!", "Armor keeps that much of your Block from fading each turn, for the rest of the fight."],
	"advantage": ["ADVANTAGE!", "Rolled twice, kept the better one. Great before a big roll."],
	"vanish": ["VANISH!", "That card is gone for the rest of this RUN, not just this fight. Use Vanish cards wisely."],
}

var battle: Node  # The battle screen this panel sits on (battle.gd).
var progress_label: Label
var intro_open := false  # The stage's intro banner is up: spotlights wait for it.
var spots_waiting := false  # A turn's spotlights wait for the intro banner to close.
var spotted_turns: Array[int] = []  # Turns whose spotlights already showed.
var keywords_seen: Array[String] = []  # Keyword pop-ups already shown this stage.
var keyword_queue: Array[String] = []  # Waiting to pop up (one at a time).
var keyword_layer: Control  # The keyword pop-up on screen (null when none).
var rigged := {}  # Card name -> how many copies we've already fixed this stage.
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
	if stage == 1:
		# Playing the training (again): show every spotlight again. (Restarting a
		# stage after losing keeps them seen, so they don't repeat.)
		GameState.seen_guides.assign(GameState.seen_guides.filter(
			func(guide_name: String) -> bool: return not guide_name.begins_with("training")))
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
	progress_label = make_label("", 18, Color(0.55, 0.95, 0.55))
	box.add_child(progress_label)
	start_hp = GameState.run_hp if GameState.run_hp > 0 else GameState.player_max_hp()
	refresh()
	show_intro.call_deferred()  # Once the battle screen is up.


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(336, 0)
	return label


# --- The intro banner, spotlights and keyword pop-ups ----------------------------

# The stage's big intro banner: "STAGE 1: ATTACK!".
func show_intro() -> void:
	var info: Dictionary = STAGES[GameState.tutorial_stage - 1]
	intro_open = true
	UnlockBanner.show_in(battle, info.title.to_upper(), "Adventurer training  ·  %d of %d" % [GameState.tutorial_stage, STAGES.size()],
		load(info.icon), info.intro + "\n\nGoal: " + info.goal, "Let's fight!", func() -> void:
			intro_open = false
			if spots_waiting:
				spots_waiting = false
				show_spots(battle.turn))


# battle.gd: your new hand is dealt and its dice have landed.
func turn_ready() -> void:
	if won:
		return
	if intro_open:
		spots_waiting = true  # After the intro banner.
	else:
		show_spots(battle.turn)


# This turn's spotlights: the screen dims, a glowing box points at each thing
# in turn, with a line of text and a Next button (screen_guide.gd).
func show_spots(turn: int) -> void:
	var spots: Dictionary = STAGES[GameState.tutorial_stage - 1].spots
	if not spots.has(turn) or spotted_turns.has(turn):
		return
	spotted_turns.append(turn)
	var steps := []
	for spot: Dictionary in spots[turn]:
		var target := spot_target(spot.at)
		if target:  # (A card you don't have in hand right now is skipped.)
			steps.append({"target": target, "text": spot.text})
	ScreenGuide.start(battle, "training %d turn %d" % [GameState.tutorial_stage, turn], steps)


# What a spotlight's "at" points at on the battle screen (null = not there).
func spot_target(at: String) -> Control:
	match at:
		"enemy":
			return battle.enemy_views[0] if not battle.enemy_views.is_empty() else null
		"energy":
			return battle.energy_label
		"end turn":
			return battle.end_turn_button
		"block":
			return battle.player_block_label
		"hp":
			return battle.player_hp_label
	var card_name := at.get_slice(":", 1)
	var view := hand_card(card_name, at.begins_with("dice:"))
	if view == null:
		return null
	return view.dice_row if at.begins_with("dice:") else view


# A card in your hand by name. rigged = prefer the copy whose die we fixed.
func hand_card(card_name: String, rigged_one: bool) -> Card:
	var found: Card = null
	var rig: Dictionary = STAGES[GameState.tutorial_stage - 1].get("rig", {})
	for view: Card in battle.hand_box.get_children():
		if view.card_data.card_name != card_name:
			continue
		if found == null:
			found = view
		if rigged_one and rig.has(card_name) and not view.card_data.roll_result.is_empty():
			var first: int = rig[card_name][0] if rig[card_name] is Array else rig[card_name]
			var dice: Array = view.card_data.roll_result.values()[0]
			if not dice.is_empty() and dice[0] == first:
				return view
	return found


# battle.gd: a card was just played. Pop up anything special that happened,
# the first time it happens this stage.
func card_played(card: CardData, result: Dictionary, had_advantage: bool) -> void:
	var happened: Array[String] = []
	if had_advantage:  # First: it explains the roll you just saw.
		happened.append("advantage")
	if result.crits > 0:
		happened.append("crit")
	if card.reroll > 0:
		happened.append("reroll")
	if card.wild and card.has_dice():
		happened.append("wild")
	if result.armor > 0:
		happened.append("armor")
	if card.vanish and result.keep == 0:
		happened.append("vanish")
	for keyword in happened:
		if not keywords_seen.has(keyword):
			keywords_seen.append(keyword)
			keyword_queue.append(keyword)
	if keyword_layer == null:
		show_next_keyword()


# A big gold word pops in over the battle, with sparkles and a line of text.
func show_next_keyword() -> void:
	if keyword_queue.is_empty() or won:
		return
	var keyword: String = keyword_queue.pop_front()
	var words: Array = KEYWORDS[keyword]
	keyword_layer = ColorRect.new()
	(keyword_layer as ColorRect).color = Color(0, 0, 0, 0)
	keyword_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keyword_layer.mouse_filter = Control.MOUSE_FILTER_STOP  # Read it first.
	battle.add_child(keyword_layer)
	keyword_layer.create_tween().tween_property(keyword_layer, "color:a", 0.78, 0.2)
	var screen: Vector2 = battle.get_viewport_rect().size
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	keyword_layer.add_child(box)
	var word := make_label(words[0], 76, GOLD)
	word.autowrap_mode = TextServer.AUTOWRAP_OFF
	word.custom_minimum_size = Vector2.ZERO
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_color_override("font_outline_color", Color(0.35, 0.18, 0))
	word.add_theme_constant_override("outline_size", 14)
	box.add_child(word)
	var line := make_label(words[1], 20, Color.WHITE)
	line.custom_minimum_size = Vector2(560, 0)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_color_override("font_outline_color", Color.BLACK)
	line.add_theme_constant_override("outline_size", 6)
	box.add_child(line)
	var ok := Button.new()
	ok.text = "Got it!"
	ok.theme_type_variation = &"PrimaryButton"
	ok.custom_minimum_size = Vector2(160, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_close_keyword)
	box.add_child(ok)
	box.reset_size()
	box.position = (screen - box.size) / 2
	box.pivot_offset = box.size / 2
	# Slam in: big and see-through, then bounce down to size.
	box.scale = Vector2(2.2, 2.2)
	box.modulate.a = 0
	var tween := box.create_tween().set_parallel()
	tween.tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "modulate:a", 1.0, 0.2)
	# A burst of gold sparkles behind the word.
	var sparkles := CPUParticles2D.new()
	sparkles.position = screen / 2 - Vector2(0, 40)
	sparkles.amount = 50
	sparkles.one_shot = true
	sparkles.explosiveness = 0.95
	sparkles.lifetime = 1.2
	sparkles.spread = 180
	sparkles.initial_velocity_min = 180
	sparkles.initial_velocity_max = 420
	sparkles.gravity = Vector2(0, 300)
	sparkles.scale_amount_min = 3
	sparkles.scale_amount_max = 6
	sparkles.color = GOLD
	keyword_layer.add_child(sparkles)
	keyword_layer.move_child(sparkles, 0)  # Behind the words.
	sparkles.emitting = true


func _close_keyword() -> void:
	if keyword_layer:
		keyword_layer.queue_free()
		keyword_layer = null
	show_next_keyword()


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
	if not rig.has(card.card_name) or card.roll_result.is_empty():
		return
	# One number = the first copy only; a list = one number per copy, in draw order.
	var numbers: Array = rig[card.card_name] if rig[card.card_name] is Array else [rig[card.card_name]]
	var done: int = rigged.get(card.card_name, 0)
	if done >= numbers.size():
		return
	rigged[card.card_name] = done + 1
	var key: String = card.roll_result.keys()[0]  # "attack 0", "block"...
	var dice: Array = card.roll_result[key]
	if not dice.is_empty():
		dice[0] = numbers[done]


# Called whenever the battle screen updates: show progress, check stage 3.
func refresh() -> void:
	if battle == null or won:
		return
	var before := progress_label.text
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
	# Progress changed: give it a little gold flash.
	if progress_label.text != before and not before.is_empty():
		progress_label.modulate = Color(2, 1.7, 0.6)
		progress_label.create_tween().tween_property(progress_label, "modulate", Color.WHITE, 0.6)


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
	_close_keyword_now()
	var info: Dictionary = STAGES[GameState.tutorial_stage - 1]
	var last := GameState.tutorial_stage >= STAGES.size()
	# A short pause so you see the last hit land, then the banner.
	await get_tree().create_timer(0.6).timeout
	var title := "STAGE %d COMPLETE!" % GameState.tutorial_stage if not last else "TRAINING COMPLETE!"
	var text: String = "You learned: " + info.learned
	if last:
		text = "You know how to attack, block and heal. Time for a real adventure!\n\n" + text
	var button := "Next Stage →"
	if last:
		button = "Claim your cards →" if not GameState.tutorial_done else "Start Playing →"
	UnlockBanner.show_in(battle, title, info.title, load(info.icon), text, button, _on_next)


# Stage won while a keyword pop-up is up: take it down (the banner is next).
func _close_keyword_now() -> void:
	keyword_queue.clear()
	if keyword_layer:
		keyword_layer.queue_free()
		keyword_layer = null


func _on_next() -> void:
	if GameState.tutorial_stage >= STAGES.size():
		var first_time := not GameState.tutorial_done
		finish()
		if first_time:
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
