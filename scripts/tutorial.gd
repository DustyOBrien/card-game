# tutorial.gd
#
# The Adventurer's TRAINING: three short fights against Training Dummies,
# using the normal battle screen (battle.gd) with this panel on top. It
# starts when the first Adventurer arrives (after the Inn is built).
#
# Dusty's first playtest: "make it more scripted, with clear goals in each
# section", and the old blocking stage (take no damage 2 turns in a row,
# with random dice) was a mess. So now every stage is a SCRIPT of GOALS:
#   - The panel lists the stage's goals: ✓ done, ▶ the one you're on, ○ next.
#   - Each goal can SPOTLIGHT things (screen_guide.gd) when it starts.
#   - Each goal says which cards you may play right now ("only"); the rest
#     are greyed out, so you can't wander off the script. End Turn only
#     works when a goal asks for it ("end_turn").
#   - Dice are RIGGED ("rig": card name -> the first die's number, one per
#     copy in draw order) and the draw order is fixed ("draw"), so every
#     goal always works out. Even a Reroll is rigged ("rig_reroll"), and
#     Wild cards are rigged when you play them.
# Showing one card from each School stayed in (Dusty liked it):
#   Stage 1, Attack: Strike (crit), Reroll, Punch (Strength), Kick (Agility)
#   Stage 2, Block:  Guard, Master of None, Fortify (Wisdom), Full Guard (Wild)
#   Stage 3, Heal:   Insight (Intellect), Bandage (Advantage, Vanish)
# The first time something special happens (a Critical, a Wild roll,
# Armor...), a KEYWORD POP-UP celebrates it. At the end: the NEW CARDS
# screen (your first cards), then the Spec screen and the Deck Builder.
# Skip ends it at any time (you still get the cards), and the Tutorial
# button on Character Select plays it again.
#
# How it plugs in: Tutorial.begin(1) swaps in a practice deck and the
# dummies, remembering your real class/deck/run so finish() can put them
# back. battle.gd sees GameState.tutorial_stage > 0, adds this panel, and
# asks it what may be played (allows_play / allows_end_turn /
# allows_reroll_pick), and tells it when cards are drawn and played,
# when enemies die and when the enemy turn ends. Nothing in the tutorial
# gives gold or Exp.
class_name Tutorial
extends PanelContainer

const BATTLE_SCENE := "res://scenes/battle.tscn"
const AFTER_SCENE := "res://scenes/character_select.tscn"
const TOWN_SCENE := "res://scenes/town.tscn"  # Back to town after the training, for the Innkeeper's news.
const SPEC_SCENE := "res://scenes/spec_select.tscn"
const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CARD_SCENE := preload("res://scenes/card.tscn")
const GOLD := Color(1, 0.84, 0.35)
const DONE_COLOR := Color(0.55, 0.95, 0.55)

# Each stage: its title and intro banner (icon, text), what it taught
# ("learned", for the Stage Complete banner), the practice deck, the order
# you draw it in ("draw", first card first), the rigged dice, the enemies,
# the HP you start with (-1 = full), and its GOALS, in order.
#
# A goal:
#   "text"      what the goal list says
#   "turn"      the turn it starts on (it waits for that turn's hand)
#   "spots"     spotlights when it starts: [{"at": ..., "text": ...}]
#   "do"        what finishes it:
#                 "play"      play the card "card" (with "roll": only the
#                             copy whose first die rolled that number)
#                 "play_all"  play every card in "cards"
#                 "spend"     use up all your Energy
#                 "reroll"    Reroll the card "card"
#                 "block"     have "amount" Block
#                 "heal"      heal "amount" HP since the fight started
#                 "end_turn"  press End Turn (done once the enemy's turn is over)
#                 "kill"      defeat every enemy
#   "only"      the cards you may play while it's on (["*"] = any). Leave
#               it out and no card can be played (an End Turn goal).
#   "end_turn"  true = End Turn works while it's on.
#
# A spotlight's "at" can be:
#   "enemy"         the first enemy        "energy"   your Energy
#   "card:Strike"   that card in your hand  "end turn" the End Turn button
#   "dice:Strike"   that card's dice (the   "block"    your Block (and Armor)
#                   rigged copy if there is) "hp"       your HP
const STAGES := [
	{
		"title": "Stage 1: Attack!",
		"icon": "res://icons/attack.svg",
		"intro": "Time to learn how a fight works: play cards, roll dice, hit hard. Knock down the Training Dummy!",
		"learned": "Energy, dice, Criticals, Reroll, and the Strength and Agility schools.",
		"deck": {"Strike": 7, "Punch": 1, "Kick": 1, "Reroll": 1},
		"draw": ["Strike", "Strike", "Strike", "Strike", "Strike", "Punch", "Kick", "Reroll", "Strike", "Strike"],
		# Turn 1: one Strike crits (3 on a d3), the others roll 1. Turn 2: Punch
		# rolls a sad 1 (so you Reroll it into a 6), Kick rolls 2. That's
		# 4 + 1 + 1 + 8 + 2 = 16 damage: exactly the dummy's HP.
		"rig": {"Strike": [3, 1, 1, 1, 1, 2, 2], "Punch": [1], "Kick": [2]},
		"rig_reroll": {"Punch": 6},
		"enemies": ["Training Dummy"],
		"hp": -1,
		"goals": [
			{"text": "Play the Strike that rolled a CRITICAL", "turn": 1, "do": "play", "card": "Strike", "roll": 3, "only": ["Strike"],
				"spots": [
					{"at": "enemy", "text": "This is a Training Dummy. Bring its HP down to 0 to win. It won't hit back... yet."},
					{"at": "dice:Strike", "text": "Cards with dice ROLL when you draw them. This Strike rolled a 3, the top number of its d3: a CRITICAL! A crit adds the card's bonus (+1 Damage)."},
					{"at": "card:Strike", "text": "Play it: DRAG the card up onto the dummy and let go."},
				]},
			{"text": "Use up your Energy: play 2 more Strikes", "turn": 1, "do": "spend", "only": ["Strike"],
				"spots": [
					{"at": "energy", "text": "Every card costs ENERGY (the number in its top-left corner). You get 3 every turn. You have 2 left: spend them on Strikes."},
				]},
			{"text": "Press End Turn", "turn": 1, "do": "end_turn", "end_turn": true,
				"spots": [
					{"at": "end turn", "text": "Out of Energy? Press END TURN. The enemy takes its turn, then you draw a fresh hand of 5."},
				]},
			{"text": "Punch rolled a 1: Reroll it", "turn": 2, "do": "reroll", "card": "Punch", "only": ["Reroll"],
				"spots": [
					{"at": "card:Punch", "text": "New cards! Every card has a SCHOOL. PUNCH is Strength (red): big dice, big hits. But this one rolled a 1..."},
					{"at": "card:Kick", "text": "KICK is Agility (green): quick and cheap. Strike and Reroll are Neutral (grey): they fit any deck."},
					{"at": "card:Reroll", "text": "Bad roll? Play REROLL (drag it up), then CLICK Punch to roll its dice again."},
				]},
			{"text": "Play Punch (Strength) and Kick (Agility)", "turn": 2, "do": "play_all", "cards": ["Punch", "Kick"], "only": ["Punch", "Kick"],
				"spots": [
					{"at": "dice:Punch", "text": "A 6! The top of its d6: another CRITICAL (+2 Damage). Now hit the dummy with Punch and Kick!"},
				]},
			{"text": "Knock down the Training Dummy", "turn": 2, "do": "kill", "only": ["*"], "end_turn": true, "spots": []},
		],
	},
	{
		"title": "Stage 2: Block!",
		"icon": "res://icons/block.svg",
		"intro": "This dummy hits back! Learn to BLOCK its attacks: Block soaks up damage before your HP does.",
		"learned": "Enemy intents, Block, roll bonuses, Armor, and Wild cards (and the Wisdom school).",
		# Turn 1: three Guards. Turn 2: Master of None, Fortify and a Guard. Turn 3:
		# Full Guard. The Strikes are only there to fill your hand.
		"deck": {"Guard": 4, "Master of None": 1, "Fortify": 1, "Full Guard": 1, "Strike": 8},
		"draw": ["Guard", "Guard", "Guard", "Strike", "Strike",
			"Master of None", "Fortify", "Guard", "Strike", "Strike",
			"Full Guard", "Strike", "Strike", "Strike", "Strike"],
		# Guards: 2 + 2 + 2 = 6 Block on turn 1, then a crit (3) on turn 2.
		# Fortify rolls 5: +1 from Master of None makes it a 6, a CRITICAL.
		# Full Guard (Wild) is rigged when you play it: a 6.
		"rig": {"Guard": [2, 2, 2, 3], "Fortify": [5], "Full Guard": [6]},
		"enemies": ["Sparring Dummy"],  # In Order: Swing 6, Heavy Swing 8, Swing 6.
		"hp": -1,
		"goals": [
			{"text": "Get 6 Block", "turn": 1, "do": "block", "amount": 6, "only": ["Guard"],
				"spots": [
					{"at": "enemy", "text": "Look under the dummy's name: it will ATTACK for 6 this turn. Enemies always show what they're about to do, so you can plan."},
					{"at": "card:Guard", "text": "GUARD gives you Block. Drag it up anywhere above your hand to play it. (Attacking can wait!)"},
					{"at": "block", "text": "Your BLOCK shows here. Block soaks up damage before your HP does. Play all 3 Guards to get 6 Block: enough to stop the whole hit."},
				]},
			{"text": "End Turn and block the hit", "turn": 1, "do": "end_turn", "end_turn": true,
				"spots": [
					{"at": "end turn", "text": "6 Block vs. 6 damage. Press END TURN and watch your Block soak it all up!"},
				]},
			{"text": "Play Master of None (+1 to your next roll)", "turn": 2, "do": "play", "card": "Master of None", "only": ["Master of None"],
				"spots": [
					{"at": "enemy", "text": "HEAVY SWING 8: it hits harder this turn. You'll need 8 Block."},
					{"at": "dice:Fortify", "text": "FORTIFY (Wisdom, purple) rolled a 5 on its d6. So close to a crit..."},
					{"at": "card:Master of None", "text": "MASTER OF NONE costs 0 and gives +1 to your NEXT roll. Play it first!"},
				]},
			{"text": "Play Fortify: 5 + 1 = 6, a CRITICAL!", "turn": 2, "do": "play", "card": "Fortify", "only": ["Fortify"],
				"spots": [
					{"at": "dice:Fortify", "text": "See the glow? +1 turns its 5 into a 6: a CRITICAL! Fortify's crit gives you +1 ARMOR. Play it!"},
				]},
			{"text": "Get 8 Block", "turn": 2, "do": "block", "amount": 8, "only": ["Guard"],
				"spots": [
					{"at": "card:Guard", "text": "This Guard rolled a 3: a crit, +1 Block. That's 6 + 4 = 10 Block. More than enough!"},
				]},
			{"text": "End Turn and block the hit", "turn": 2, "do": "end_turn", "end_turn": true, "spots": []},
			{"text": "Play Full Guard (a Wild card)", "turn": 3, "do": "play", "card": "Full Guard", "only": ["Full Guard"],
				"spots": [
					{"at": "block", "text": "You KEPT 2 Block from last turn! Block fades at the start of each turn, but your ARMOR saves up to that much. Fortify's crit made your Armor 4."},
					{"at": "card:Full Guard", "text": "FULL GUARD is WILD: its die rolls when you PLAY it, not when you draw it. Riskier, but it rolls a d6! Play it."},
				]},
			{"text": "End Turn and block the hit", "turn": 3, "do": "end_turn", "end_turn": true, "spots": []},
		],
	},
	{
		"title": "Stage 3: Heal!",
		"icon": "res://icons/heal.svg",
		"intro": "Ouch, you're hurt! Patch yourself up, and learn how to make every heal count.",
		"learned": "Healing, Advantage, Vanish, and the Intellect school.",
		"deck": {"Insight": 1, "Bandage": 5},
		"draw": ["Insight", "Bandage", "Bandage", "Bandage", "Bandage", "Bandage"],
		# The first Bandage rolls a 1 (Advantage gives it a second chance), then
		# 3, 2, 3: any two of those heal at least 6 with the first.
		"rig": {"Bandage": [1, 3, 2, 3]},
		"enemies": ["Training Dummy"],
		"hp": 13,
		"goals": [
			{"text": "Play Insight: your next roll gets Advantage", "turn": 1, "do": "play", "card": "Insight", "only": ["Insight"],
				"spots": [
					{"at": "hp", "text": "You're down to 13 HP. Time to heal!"},
					{"at": "card:Insight", "text": "INSIGHT (Intellect, blue) gives your next roll ADVANTAGE: it rolls twice and keeps the better one. Play it first!"},
				]},
			{"text": "Play the Bandage that rolled a 1", "turn": 1, "do": "play", "card": "Bandage", "roll": 1, "only": ["Bandage"],
				"spots": [
					{"at": "dice:Bandage", "text": "This Bandage rolled a 1. With Advantage it rolls again and keeps the better one. Drag it into the middle of the screen. Careful: Bandages VANISH once played."},
				]},
			{"text": "Heal 6 HP", "turn": 1, "do": "heal", "amount": 6, "only": ["Bandage"],
				"spots": [
					{"at": "hp", "text": "Keep going: play more Bandages until you've healed 6 HP."},
				]},
		],
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
var goal_box: VBoxContainer  # The goal list.
var goal_rows: Array[Label] = []
var goal := 0  # Which goal you're on (an index into the stage's "goals").
var goal_started := -1  # The goal whose spotlights have shown.
var intro_open := false  # The stage's intro banner is up: spotlights wait for it.
var hand_turn := 0  # The last turn whose hand is dealt (goals wait for their turn's hand).
var played: Array[String] = []  # Cards played for a "play_all" goal.
var rerolled: Array[String] = []  # Cards Rerolled this stage.
var keywords_seen: Array[String] = []  # Keyword pop-ups already shown this stage.
var keyword_queue: Array[String] = []  # Waiting to pop up (one at a time).
var keyword_layer: Control  # The keyword pop-up on screen (null when none).
var rigged := {}  # Card name -> how many copies we've already fixed this stage.
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
	box.add_child(make_label("GOALS", 14, Color(1, 1, 1, 0.6)))
	goal_box = VBoxContainer.new()
	goal_box.add_theme_constant_override("separation", 3)
	box.add_child(goal_box)
	for step: Dictionary in info.goals:
		var row := make_label("", 16, Color.WHITE)
		goal_box.add_child(row)
		goal_rows.append(row)
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


# --- The goals --------------------------------------------------------------------

func goals() -> Array:
	return STAGES[GameState.tutorial_stage - 1].goals


# The goal you're on ({} once they're all done).
func current_goal() -> Dictionary:
	return goals()[goal] if goal < goals().size() else {}


# Is this goal done? ("play" goals are ticked in card_played(), and
# "end_turn" goals in after_enemy_turn(), so they say no here.)
func goal_met(step: Dictionary) -> bool:
	if step.is_empty() or battle.turn < step.get("turn", 1):
		return false
	match step.do:
		"spend":
			return battle.energy <= 0
		"block":
			return battle.player.block >= step.amount
		"heal":
			return healed() >= step.amount
		"kill":
			return battle.living_enemies().is_empty()
		"play_all":
			return step.cards.all(func(card_name: String) -> bool: return played.has(card_name))
		"reroll":
			return rerolled.has(step.card)
	return false


# HP healed since the stage started (before turn 1 your HP isn't set yet).
func healed() -> int:
	return maxi(battle.player.hp - start_hp, 0) if battle.turn > 0 else 0


# The goal you're on is done: tick it (with a little gold flash), move to
# the next one, and keep going while the next ones are done too (a hit that
# defeats the dummy finishes "play Punch and Kick" AND "knock it down").
# The last one wins the stage.
func complete_goal() -> void:
	if won or goal >= goals().size():
		return
	var row := goal_rows[goal]
	goal += 1
	played.clear()
	refresh()
	row.modulate = Color(2, 1.8, 0.7)
	row.create_tween().tween_property(row, "modulate", Color.WHITE, 0.6)
	if goal >= goals().size():
		stage_won.call_deferred()  # After the card finishes.
		return
	if goal_met(current_goal()):
		complete_goal()
		return
	battle.update_ui()  # Grey out the cards the new goal doesn't use.
	start_goal()


# Show the goal's spotlights, once its turn's hand is dealt, the intro
# banner is gone and no keyword pop-up is up. (If it's too early,
# turn_ready() or _close_keyword() calls this again.)
func start_goal() -> void:
	if won or goal >= goals().size() or goal_started == goal:
		return
	var step := current_goal()
	if intro_open or keyword_layer != null or hand_turn < step.get("turn", 1):
		return
	goal_started = goal
	var steps := []
	for spot: Dictionary in step.get("spots", []):
		var target := spot_target(spot.at)
		if target:  # (A card you don't have in hand right now is skipped.)
			steps.append({"target": target, "text": spot.text})
	ScreenGuide.start(battle, "training %d goal %d" % [GameState.tutorial_stage, goal], steps)


# --- What battle.gd asks -------------------------------------------------------------

# May this card be played right now? Only the ones the goal you're on uses.
func allows_play(card: CardData) -> bool:
	if won:
		return false
	var step := current_goal()
	if step.is_empty():
		return true
	var only: Array = step.get("only", [])
	if only.has("*"):
		return true
	if not only.has(card.card_name):
		return false
	# "Play the Strike that rolled a 3": only that copy.
	if step.has("roll") and step.get("card", "") == card.card_name:
		return first_die(card) == step.roll
	return true


func allows_end_turn() -> bool:
	return not won and current_goal().get("end_turn", false)


# Reroll: which card may you click? The one the goal is about.
func allows_reroll_pick(card: CardData) -> bool:
	var step := current_goal()
	return step.get("do", "") != "reroll" or step.card == card.card_name


# The number on a card's first die (-1 if it hasn't rolled).
func first_die(card: CardData) -> int:
	if card.roll_result.is_empty():
		return -1
	var dice: Array = card.roll_result.values()[0]
	return dice[0] if not dice.is_empty() else -1


# The goal list: ✓ done (green), ▶ the one you're on (gold), ○ still to come.
# Block and heal goals show how far along you are.
func refresh() -> void:
	if battle == null or goal_box == null:
		return
	for i in goals().size():
		var step: Dictionary = goals()[i]
		var row := goal_rows[i]
		var text: String = step.text
		if i == goal and step.do == "block":
			text += "  (%d/%d)" % [mini(battle.player.block, step.amount), step.amount]
		elif i == goal and step.do == "heal":
			text += "  (%d/%d)" % [mini(healed(), step.amount), step.amount]
		if i < goal or won:
			row.text = "✓  " + text
			row.add_theme_color_override("font_color", DONE_COLOR)
		elif i == goal:
			row.text = "▶  " + text
			row.add_theme_color_override("font_color", GOLD)
		else:
			row.text = "○  " + text
			row.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))


# --- The intro banner, spotlights and keyword pop-ups ----------------------------

# The stage's big intro banner: "STAGE 1: ATTACK!", with its goals.
func show_intro() -> void:
	var info: Dictionary = STAGES[GameState.tutorial_stage - 1]
	var goal_list: Array[String] = []
	for step: Dictionary in info.goals:
		goal_list.append("•  " + step.text)
	intro_open = true
	UnlockBanner.show_in(battle, info.title.to_upper(), "Adventurer training  ·  %d of %d" % [GameState.tutorial_stage, STAGES.size()],
		load(info.icon), info.intro + "\n\nYour goals:\n" + "\n".join(goal_list), "Let's go!", func() -> void:
			intro_open = false
			start_goal())


# battle.gd: your new hand is dealt and its dice have landed.
func turn_ready() -> void:
	if won:
		return
	hand_turn = battle.turn
	if goal_met(current_goal()):
		complete_goal()  # (Armor's leftover Block could already be enough.)
	else:
		start_goal()


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
	var view := hand_card(card_name, true)  # The rigged copy, if there is one (the crit Strike).
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
	# Did that finish the goal you're on?
	var step := current_goal()
	if step.get("do", "") == "play_all" and step.cards.has(card.card_name) and not played.has(card.card_name):
		played.append(card.card_name)
	if step.get("do", "") == "play" and step.card == card.card_name and battle.turn >= step.get("turn", 1):
		complete_goal()
	elif goal_met(step):
		complete_goal()
	else:
		refresh()


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
	if keyword_layer == null:
		start_goal()  # The next goal's spotlights were waiting for the pop-ups.


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


# A card was just rolled (when drawn, or a Wild card when played): fix its
# first die if the stage says so, so the lesson (a Critical...) always happens.
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


# Reroll just rolled this card's dice again. The stage can fix that roll too
# ("rig_reroll"), so Punch's sad 1 always becomes a 6.
func rig_reroll(card: CardData) -> void:
	var rig: Dictionary = STAGES[GameState.tutorial_stage - 1].get("rig_reroll", {})
	if rig.has(card.card_name) and not card.roll_result.is_empty() and not rerolled.has(card.card_name):
		var dice: Array = card.roll_result.values()[0]
		if not dice.is_empty():
			dice[0] = rig[card.card_name]
	rerolled.append(card.card_name)


func enemy_died() -> void:
	if battle.living_enemies().is_empty() and goals().any(func(step: Dictionary) -> bool: return step.do == "kill"):
		# Down it goes! Every goal left is done.
		goal = goals().size()
		refresh()
		stage_won()


# The enemies just finished their turn: an End Turn goal is done. (The
# script makes sure your Block is enough, but just in case it wasn't...)
func after_enemy_turn(damage_taken: int) -> void:
	if won:
		return
	battle.message_label.text = "Blocked it all!" if damage_taken == 0 else "Ouch, %d damage! More Block next time." % damage_taken
	if current_goal().get("do", "") == "end_turn":
		complete_goal()


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
	refresh()  # Every goal ticked.
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
