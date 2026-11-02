# battle.gd
#
# The "brain" of the game. It is attached to the root node of
# scenes/battle.tscn and runs the whole fight:
#
#   1. Player turn: reset energy, Armor saves some leftover Block, draw 5 cards
#      (their dice roll as they're drawn), play cards.
#   2. Player clicks "End Turn": the hand goes to the discard pile.
#   3. Enemy turn: every enemy still standing attacks, left to right.
#   4. Back to step 1, until you or all the enemies are defeated.
#
# A fight can have several enemies (an "encounter", see encounter.gd). Each one
# is an EnemyView (enemy_view.gd) in the row at the top of the screen.
extends Control

# preload() loads a file once, when the script loads. These are the
# "blueprints" we use to build the deck and the cards on screen.
const CARD_SCENE := preload("res://scenes/card.tscn")
const TOWN_SCENE := "res://scenes/town.tscn"  # Where you go when the run is over.
const POTION_ICON := preload("res://art/potions/potion.svg")
const FLASK_ICON := preload("res://art/potions/flask.svg")
# The player bar's icons (HP, Block, Energy, Gold, draw pile, discard pile).
const BAR_ICONS := {
	"hp": preload("res://icons/hp.svg"),
	"block": preload("res://icons/block.svg"),
	"energy": preload("res://icons/energy.svg"),
	"gold": preload("res://icons/gold.svg"),
	"draw": preload("res://icons/draw.svg"),
	"discard": preload("res://icons/discard.svg"),
}
const DUNGEON_SCENE := "res://scenes/dungeon.tscn"
const VICTORY_SCENE := "res://scenes/victory.tscn"  # The WIN screen after a final Boss.

const HAND_SIZE := 5  # Cards drawn at the start of each turn (before talents).
const MAX_ENERGY := 3  # Energy you get each turn (before talents).
const DEAL_TIME := 0.2  # Seconds between cards as they're dealt into your hand.
const PREVIEW_COLOR := Color(1, 0.85, 0.3)  # Tint for numbers a dragged card would change.
const DEFAULT_ENEMY := preload("res://enemies/slime.tres")  # If an area has no encounters yet.
const MAX_ENEMIES := 4  # Summons stop once this many enemies are standing.
# The enemy row is centred on the screen, and the Battle Log sits on the
# right, so a row wider than this would go under the log. Wider rows shrink.
const ENEMY_ROW_MAX_WIDTH := 680.0

# The three card piles. `Array[CardData]` means "a list that only holds CardData".
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var energy := 0
var max_energy := MAX_ENERGY  # MAX_ENERGY plus Energy talents (set in start_battle()).
# Bonuses waiting for your next Attack / Defense card (from Rage and Brace).
var next_attack_bonus := 0
var next_defense_bonus := 0
var next_roll_bonus := 0  # Added to every die of the next card that rolls (Master of None).
var next_roll_advantage := false  # The next card that rolls gets Advantage (Insight).
var choosing_reroll := false  # true while Gamble waits for you to click a card in your hand.

# Sent when you click a card to re-roll (see choose_rerolls()).
signal reroll_picked(card: CardData)
var enemy_views: Array[EnemyView] = []  # Every enemy in this fight, left to right (dead ones too).
var fight_gold := 0  # Gold dropped by the enemies beaten in this fight.
var fight_exp := 0  # Class Exp from the enemies beaten in this fight (bosses give more).
var fight_materials := {}  # Materials dropped in this fight, for the victory panel.
# Names of the cards played at least once this fight. Pack Rat's talents
# (Flawless first play, Fresh Find) only work on a card's FIRST play.
var played_this_fight := {}
var game_over := false
var turn := 0  # Turn number, for the battle log.
var dragged_card: CardData = null  # The card being dragged right now, if any.
var dragged_damage := Vector2i.ZERO  # Its damage per enemy, smallest and biggest (worked out once per drag).
var busy := false  # true while cards are dealt or dice roll, so you can't play two cards at once.
# Goes up by 1 every fight. Code that waits (`await`) checks it afterwards: if
# the fight it started in is over and a new one has begun, it stops instead of
# dealing cards into the new fight. (A talent can win a fight while your hand
# is still being dealt, and you can press Next Fight before the dealing ends.)
var fight_id := 0
var _ui_update_queued := false  # See queue_update_ui().

# References to nodes in the scene. $Name finds a direct child by name;
# %Name finds any node marked as a "unique name" anywhere in this scene.
@onready var player: Combatant = $Player

@onready var fight_label: Label = %FightLabel  # "Plains · Tier 1 · Danger 0"
@onready var enemy_row: HBoxContainer = %EnemyRow  # The EnemyViews go in here.
@onready var message_label: Label = %MessageLabel
@onready var player_hp_label: Label = %PlayerHpLabel
@onready var player_block_label: Label = %PlayerBlockLabel
@onready var energy_label: Label = %EnergyLabel
@onready var piles_label: Label = %PilesLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var hand_box: HBoxContainer = %Hand
@onready var game_over_screen: ColorRect = %GameOverScreen
@onready var result_label: Label = %ResultLabel
@onready var reward_label: Label = %RewardLabel
@onready var continue_button: Button = %ContinueButton
@onready var gold_label: Label = %GoldLabel
@onready var play_zone: PlayZone = %PlayZone
@onready var play_zone_hint: Control = %PlayZoneHint
@onready var hint_label: Label = %HintLabel
@onready var dice_tray: DiceTray = %DiceTray  # Where the dice tumble (dice_tray.gd).
@onready var battle_log: BattleLog = %BattleLog  # The list of what happened (battle_log.gd).
@onready var area_background: TextureRect = %AreaBackground  # The picture of the area you're in.

var exp_bar: ExpBar  # Your class's Exp bar on the victory panel (made in _ready).
var tutorial: Tutorial = null  # The tutorial's panel, while the tutorial runs (tutorial.gd).


func _ready() -> void:
	# Hook up signals: "when X happens, call this function".
	player.stats_changed.connect(queue_update_ui)
	player.died.connect(_on_player_died)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	play_zone.card_dropped.connect(_on_card_played)  # Dropping a card plays it.
	# The Exp bar on the victory panel, just above the Continue button.
	exp_bar = ExpBar.new()
	exp_bar.custom_minimum_size = Vector2(320, 22)
	continue_button.add_sibling(exp_bar)
	exp_bar.get_parent().move_child(exp_bar, continue_button.get_index())
	set_process(false)  # _process() is only needed while dragging an attack.
	build_player_bar()
	# Your flask and potions, bottom-left. Built in code; refreshed in update_ui().
	var item_bar := HBoxContainer.new()
	item_bar.add_theme_constant_override("separation", 14)
	item_bar.position = Vector2(32, 344)  # Left of the battlefield, clear of a big hand.
	add_child(item_bar)
	item_bar.get_parent().move_child(item_bar, game_over_screen.get_index())  # Under the end screen.
	flask_button = make_flask_button()
	if flask_button:
		item_bar.add_child(flask_button)
	potion_bar = HBoxContainer.new()
	potion_bar.add_theme_constant_override("separation", 6)
	item_bar.add_child(potion_bar)

	if GameState.tutorial_stage > 0:
		tutorial = Tutorial.new()
		tutorial.battle = self
		add_child(tutorial)
	start_battle()


# ---------------------------------------------------------------------------
# Potions (see potion.gd): click one on your turn to drink it.
# ---------------------------------------------------------------------------

var potion_bar: HBoxContainer
var _potion_count := -1  # How many potion buttons are showing (rebuild only when it changes).
var flask_button: Button  # null if you have no flask (pressing F6 on this scene).
var flask_charge_label: Label


# The flask button: a bottle tinted the flask's colour, with its charges
# ("1/2") in a little badge at the bottom-right.
func make_flask_button() -> Button:
	var dungeon := GameState.dungeon
	if dungeon == null or dungeon.flask == null:
		return null
	var button := Button.new()
	button.icon = FLASK_ICON
	button.expand_icon = true
	button.custom_minimum_size = Vector2(64, 64)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, dungeon.flask.color)
	button.pressed.connect(drink_flask)
	flask_charge_label = Label.new()
	flask_charge_label.add_theme_font_size_override("font_size", 14)
	flask_charge_label.add_theme_constant_override("outline_size", 4)
	flask_charge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	flask_charge_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	flask_charge_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	flask_charge_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	flask_charge_label.position -= Vector2(4, 0)
	button.add_child(flask_charge_label)
	return button


func refresh_flask() -> void:
	if flask_button == null:
		return
	var dungeon := GameState.dungeon
	var max_charges: int = dungeon.flask_stats[Flask.CHARGES]
	flask_charge_label.text = "%d/%d" % [dungeon.flask_charges, max_charges]
	flask_button.disabled = busy or game_over or dungeon.flask_charges <= 0
	flask_button.tooltip_text = "%s  (%d / %d charges)\n%s\n%s" % [dungeon.flask.flask_name,
		dungeon.flask_charges, max_charges, Flask.effect_text(dungeon.flask_stats),
		"Click to drink." if dungeon.flask_charges > 0 else "Empty: it refills on your next run."]


# Take a sip: roll the heal die (plus its bonus) and/or gain Energy.
func drink_flask() -> void:
	var dungeon := GameState.dungeon
	if busy or game_over or dungeon == null or dungeon.flask == null or dungeon.flask_charges <= 0:
		return
	var stats := dungeon.flask_stats
	var sip := dungeon.sip_flask()  # Rolls the heal and uses the charge (see dungeon_run.gd).
	battle_log.add("You drink from your %s" % dungeon.flask.flask_name, BattleLog.PLAYER_COLOR)
	if sip.heal > 0:
		player.heal(sip.heal)
		var bonus_text := (" + %d" % stats[Flask.ROLL_BONUS]) if stats[Flask.ROLL_BONUS] > 0 else ""
		battle_log.add("d%d rolled %d%s: you heal %d (HP %d/%d)" % [stats[Flask.HEAL_DIE], sip.roll, bonus_text,
			sip.heal, player.hp, player.max_hp])
	if sip.energy > 0:
		energy += sip.energy
		battle_log.add("You gain %d energy" % sip.energy)
	if sip.kept:
		battle_log.add("Lucky! The flask is still full (%d%% chance)" % stats[Flask.SAVE_CHANCE])
	refresh_hand()
	queue_update_ui()


func refresh_potions() -> void:
	var potions: Array[Potion] = GameState.dungeon.potions if GameState.dungeon else ([] as Array[Potion])
	if potions.size() != _potion_count:
		_potion_count = potions.size()
		for old in potion_bar.get_children():
			old.queue_free()
		for i in potions.size():
			var button := Button.new()
			button.icon = POTION_ICON
			button.expand_icon = true
			button.custom_minimum_size = Vector2(56, 56)
			# The bottle picture is white, so these colours tint it the potion's colour.
			for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				button.add_theme_color_override(state, potions[i].color)
			button.tooltip_text = "%s\n%s\nClick to drink it." % [potions[i].potion_name, potions[i].effect_text()]
			button.pressed.connect(drink_potion.bind(i))
			potion_bar.add_child(button)
	for button: Button in potion_bar.get_children():
		button.disabled = busy or game_over


func drink_potion(index: int) -> void:
	var potions := GameState.dungeon.potions
	if busy or game_over or index >= potions.size():
		return
	var potion: Potion = potions[index]
	potions.remove_at(index)
	battle_log.add("You drink a %s" % potion.potion_name, BattleLog.PLAYER_COLOR)
	if potion.heal > 0:
		player.heal(potion.heal)
		battle_log.add("You heal %d (HP %d/%d)" % [potion.heal, player.hp, player.max_hp])
	if potion.block > 0:
		player.gain_block(potion.block)
		battle_log.add("You gain %d Block (Block %d)" % [potion.block, player.block])
	if potion.energy > 0:
		energy += potion.energy
		battle_log.add("You gain %d energy" % potion.energy)
	if potion.advantage:
		next_roll_advantage = true
		battle_log.add("Your next roll has Advantage")
	if potion.roll_bonus > 0:
		next_roll_bonus += potion.roll_bonus
		battle_log.add("Your next roll gets +%d" % next_roll_bonus)
	if potion.damage > 0:
		for view in living_enemies():
			battle_log.add("%s takes %d damage (HP %d/%d)" % [view.data.display_name, potion.damage,
				view.hp_after(potion.damage), view.combatant.max_hp])
			view.combatant.take_damage(potion.damage)
			view.show_hurt()
	if potion.draw > 0 and not game_over:
		busy = true
		await draw_cards(potion.draw)
		busy = false
	refresh_hand()
	queue_update_ui()


# ---------------------------------------------------------------------------
# Battle flow
# ---------------------------------------------------------------------------

func start_battle() -> void:
	fight_id += 1
	game_over = false
	busy = false
	game_over_screen.visible = false
	GameState.ensure_ready()
	player.max_hp = GameState.player_max_hp()  # Each class has its own HP (plus Heavy Pack)...
	player.armor = GameState.character_class.armor  # ...and Armor.
	player.reset()
	if GameState.run_hp > 0:
		player.hp = GameState.run_hp  # Later fights in a run keep the HP you had left.
	make_enemies()
	max_energy = MAX_ENERGY + talent_energy()

	next_attack_bonus = 0
	next_defense_bonus = 0
	next_roll_bonus = 0
	next_roll_advantage = false
	choosing_reroll = false
	played_this_fight.clear()

	# The deck you built in the deck builder is waiting in GameState (an autoload,
	# see game_state.gd). ensure_ready() above gives you a starter deck if there
	# isn't one, e.g. when you press F6 to run only this scene.
	hand.clear()
	refresh_hand()  # Also remove the old fight's cards from the screen.
	discard_pile.clear()
	# We give every card its OWN copy (card.duplicate()), so two Strikes can
	# each remember their own dice roll. The deck you built stays untouched
	# for the next battle.
	draw_pile.clear()
	for i in GameState.deck.size():
		if GameState.vanished.has(i):
			continue  # This card Vanished earlier in the run.
		# leveled() swaps in the card's level 2 or 3 version once it has leveled up.
		var card: CardData = GameState.leveled(GameState.deck[i]).duplicate()
		# set_meta() tags the copy with where it came from in the deck,
		# so if it Vanishes we know which deck card to leave out next fight.
		card.set_meta("deck_index", i)
		# An enchant on this card for the run (see enchant.gd) changes the copy.
		if GameState.run_enchants.has(i):
			GameState.run_enchants[i].apply_to(card)
		draw_pile.append(card)
	# Super cards found this run (dungeon_run.gd). Their "deck index" carries
	# on after your real deck's, so Vanish works for them too.
	if GameState.dungeon:
		for j in GameState.dungeon.super_cards.size():
			var index := GameState.deck.size() + j
			if not GameState.vanished.has(index):
				var super_card: CardData = GameState.dungeon.super_cards[j].duplicate()
				super_card.set_meta("deck_index", index)
				draw_pile.append(super_card)
	draw_pile.shuffle()
	if tutorial:
		tutorial.arrange_draw_pile(draw_pile)  # The training draws its cards in a set order.
	dice_tray.hide()
	# The fight happens in the area you picked on the map.
	area_background.texture = GameState.current_area.background

	turn = 0
	var dungeon := GameState.dungeon
	fight_label.text = "%s  ·  Tier %d  ·  Danger %d" % [GameState.current_area.display_name,
		dungeon.tier, dungeon.danger()]
	if tutorial:
		fight_label.text = "Training Grounds"
	battle_log.clear()
	message_label.text = "%s appear%s!" % [enemy_names(), "s" if enemy_views.size() == 1 else ""]
	var enemy_list: Array[String] = []
	for view in enemy_views:
		enemy_list.append("%s (%d HP)" % [view.data.display_name, view.data.max_hp])
	battle_log.add("%s, tier %d: %s" % [GameState.current_area.display_name,
		dungeon.tier, ", ".join(enemy_list)], BattleLog.ENEMY_COLOR)
	if dungeon.danger() > 0:
		battle_log.add("Danger %d: every enemy has +%d Strength" % [dungeon.danger(), dungeon.danger()], BattleLog.ENEMY_COLOR)
	battle_log.add("You are the %s (HP %d/%d, %d gold)" % [GameState.character_class.display_name,
		player.hp, player.max_hp, GameState.gold], BattleLog.PLAYER_COLOR)
	if not GameState.vanished.is_empty():
		battle_log.add("%d card(s) have Vanished this run" % GameState.vanished.size(), BattleLog.DIM_COLOR)
	start_player_turn()


# Make the enemies for this fight: the area's encounter for this fight number,
# one EnemyView each, side by side.
func make_enemies() -> void:
	for view in enemy_views:
		enemy_row.remove_child(view)
		view.queue_free()
	enemy_views.clear()
	fight_gold = 0
	fight_exp = 0
	fight_materials.clear()
	var encounter: Array[EnemyData] = GameState.current_encounter()
	if encounter.is_empty():
		encounter = [DEFAULT_ENEMY]
	for enemy_data in encounter:
		add_enemy(enemy_data)
	play_zone.enemy_views = enemy_views


# Put one enemy on screen. `hp` > 0 for enemies from a split (they keep the
# HP that was left). `at` = its place in the row (-1 = on the right).
func add_enemy(enemy_data: EnemyData, hp: int = 0, at: int = -1) -> EnemyView:
	var view := EnemyView.new()
	enemy_row.add_child(view)
	view.setup(enemy_data, hp)
	# Danger: the longer you wander the dungeon without resting, the stronger they are.
	view.combatant.strength = GameState.dungeon.danger() if GameState.dungeon else 0
	if at >= 0:
		enemy_row.move_child(view, at)
	# bind() adds `view` to the call, so we know WHICH enemy died.
	view.combatant.died.connect(_on_enemy_died.bind(view))
	view.combatant.stats_changed.connect(queue_update_ui)
	view.start_idle()
	enemy_views.append(view)  # The same list play_zone has, so it sees new enemies too.
	fit_enemy_row()
	return view


# Shrink the enemies if the row would be too wide (a boss and its summons).
func fit_enemy_row() -> void:
	var width := 0.0
	for view in enemy_views:
		width += view.full_width()
	var separation := 24
	width += separation * maxi(enemy_views.size() - 1, 0)
	var compact := width > ENEMY_ROW_MAX_WIDTH
	enemy_row.add_theme_constant_override("separation", 10 if compact else separation)
	for view in enemy_views:
		view.set_compact(compact)


func living_enemies() -> Array[EnemyView]:
	return enemy_views.filter(func(view: EnemyView) -> bool: return view.is_alive())


# "Slime", "2 Slimelings" or "Slimeling and Slime", for messages.
func enemy_names() -> String:
	var names: Array[String] = []
	for view in enemy_views:
		names.append(view.data.display_name)
	if names.size() > 1 and names.count(names[0]) == names.size():
		# "Dummy" -> "Dummies", "Slime" -> "Slimes", "Wolf" -> "Wolves".
		var plural := names[0] + "s"
		if names[0].ends_with("y"):
			plural = names[0].trim_suffix("y") + "ies"
		elif names[0].ends_with("f"):
			plural = names[0].trim_suffix("f") + "ves"
		return "%d %s" % [names.size(), plural]
	if names.size() == 1:
		if enemy_views[0].data.is_boss:
			return "The boss, the " + names[0] + ","  # "The boss, the Slime King, appears!"
		return ("An " if names[0][0] in "AEIOU" else "A ") + names[0]
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]


func start_player_turn() -> void:
	var leftover := player.block
	player.clear_block()  # Your Armor saves up to that much of it (0 if you have none).
	energy = max_energy
	turn += 1
	battle_log.add_turn(turn)
	# Decide now what each enemy will do, so the player can plan around it.
	for view in living_enemies():
		view.choose_move()
		var move_name := "Split" if view.splitting else view.move.move_name
		battle_log.add("%s intends to %s (%s)" % [view.data.display_name, move_name, view.intent_text()], BattleLog.ENEMY_COLOR)
	if player.armor > 0 and leftover > 0:
		battle_log.add("Your Armor saves %d of your %d leftover Block" % [player.block, leftover])
	if turn == 1:
		apply_fight_start_talents()
	busy = true
	var my_fight := fight_id
	# Wait for the cards to be dealt and their dice to land. Hand Size talents draw more.
	await draw_cards(HAND_SIZE + GameState.talent_bonus(GameState.character_class, Talent.HAND_SIZE))
	if my_fight != fight_id:
		return  # That fight ended while the cards were dealt; a new one has started.
	busy = false
	if not game_over:
		end_turn_button.disabled = false
	update_ui()
	if tutorial:
		tutorial.turn_ready()  # The training points things out on the new hand.


func _on_end_turn_pressed() -> void:
	if game_over or busy:
		return
	end_turn_button.disabled = true
	dice_tray.hide()  # Clear this turn's dice.

	# Everything left in your hand goes to the discard pile.
	battle_log.add("You end your turn" + (" (%d cards discarded)" % hand.size() if not hand.is_empty() else ""), BattleLog.DIM_COLOR)
	discard_pile.append_array(hand)
	hand.clear()
	refresh_hand()

	busy = true  # Nothing can be played (or End Turn pressed again) during the enemy's turn.
	var my_fight := fight_id
	var hp_before := player.hp
	await enemy_turn()  # `await` waits for enemy_turn() to finish.
	if my_fight != fight_id:
		return
	busy = false
	if tutorial:
		tutorial.after_enemy_turn(hp_before - player.hp)
	if not game_over:
		start_player_turn()


# Every enemy still standing takes its turn, left to right.
func enemy_turn() -> void:
	message_label.text = "Enemy turn..."
	# Enemy Block runs out now, at the start of THEIR turn (Armor saves some).
	# It's done for all of them first, so Block one enemy gives another
	# (the Mushroom's Spore Shield) lasts through your next turn.
	for view in living_enemies():
		var leftover := view.combatant.block
		view.combatant.clear_block()
		if view.combatant.armor > 0 and leftover > 0:
			battle_log.add("%s's Armor saves %d Block" % [view.data.display_name, view.combatant.block], BattleLog.ENEMY_COLOR)
	# Pause for a moment so the player can see what's happening.
	# create_timer() makes a one-shot timer; we wait for its `timeout` signal.
	await get_tree().create_timer(0.5).timeout

	# living_enemies() makes a new list, so enemies summoned during this turn
	# wait until next turn to act.
	for view in living_enemies():
		if game_over:
			return
		if not view.is_alive():
			continue
		if view.splitting:
			split_enemy(view)
		else:
			do_move(view)
		if game_over:
			return  # An attack defeated the player.
		await get_tree().create_timer(0.45).timeout


# One enemy does the move it showed as its intent.
func do_move(view: EnemyView) -> void:
	var enemy := view.combatant
	var move := view.move
	var who := view.data.display_name
	if move == null:
		return
	if move.attacks():
		view.show_attack()
		for damage in view.hit_damages():  # Each hit goes through your Block on its own.
			var blocked := mini(player.block, damage)  # Worked out before Block is used up.
			var log_line := "%s: %s attacks for %d" % [move.move_name, who, damage]
			if blocked > 0:
				log_line += ": %d blocked, you take %d" % [blocked, damage - blocked]
			# Logged BEFORE take_damage(): if this hit defeats you, `died` fires inside
			# take_damage() and its "Defeat" line should come after this one.
			var hp_after := maxi(player.hp - (damage - blocked), 0)
			battle_log.add(log_line + " (HP %d/%d)" % [hp_after, player.max_hp], BattleLog.ENEMY_COLOR)
			player.take_damage(damage)
			if game_over:
				return
		message_label.text = "%s: %s attacks for %s!" % [who, move.move_name,
			" + ".join(view.hit_damages().map(func(d: int) -> String: return str(d)))]
	else:
		view.show_glow(EnemyView.INTENT_COLORS[move.kind()])
		message_label.text = "%s uses %s" % [who, move.move_name]
	if move.block > 0:
		enemy.gain_block(move.block)
		battle_log.add("%s: %s gains %d Block" % [move.move_name, who, move.block], BattleLog.ENEMY_COLOR)
	if move.strength > 0:
		enemy.gain_strength(move.strength)
		battle_log.add("%s: %s gains %d Strength (Strength %d)" % [move.move_name, who, move.strength, enemy.strength], BattleLog.ENEMY_COLOR)
	if move.heal > 0:
		enemy.heal(move.heal)
		battle_log.add("%s: %s heals %d (HP %d/%d)" % [move.move_name, who, move.heal, enemy.hp, enemy.max_hp], BattleLog.ENEMY_COLOR)
	if move.ally_block > 0:
		for other in living_enemies():
			if other != view:
				other.combatant.gain_block(move.ally_block)
				other.show_glow(EnemyView.INTENT_COLORS.block)
		battle_log.add("%s: %s gives the other enemies %d Block" % [move.move_name, who, move.ally_block], BattleLog.ENEMY_COLOR)
	if move.ally_strength > 0:
		for other in living_enemies():
			other.combatant.gain_strength(move.ally_strength)
			other.show_glow(EnemyView.INTENT_COLORS.buff)
		battle_log.add("%s: every enemy gains %d Strength" % [move.move_name, move.ally_strength], BattleLog.ENEMY_COLOR)
	if not move.summon.is_empty():
		summon_enemies(view, move.summon, move.summon_count)


# Call in more enemies, up to MAX_ENEMIES standing at once.
func summon_enemies(summoner: EnemyView, enemy_name: String, count: int) -> void:
	var enemy_data := GameState.find_enemy(enemy_name)
	if enemy_data == null:
		push_warning("%s tries to summon '%s', but there's no enemy with that name" % [summoner.data.display_name, enemy_name])
		return
	var called := 0
	for i in count:
		if living_enemies().size() >= MAX_ENEMIES:
			break
		add_enemy(enemy_data)
		called += 1
	if called > 0:
		battle_log.add("%s calls %d %s%s!" % [summoner.data.display_name, called, enemy_name, "s" if called > 1 else ""], BattleLog.ENEMY_COLOR)
	else:
		battle_log.add("%s calls for help, but there's no room" % summoner.data.display_name, BattleLog.DIM_COLOR)


# A splitting enemy (the Big Slime) turns into smaller ones, in the same
# spot, each with the HP it had left.
func split_enemy(view: EnemyView) -> void:
	var child_data := GameState.find_enemy(view.data.split_into)
	if child_data == null:
		push_warning("%s splits into '%s', but there's no enemy with that name" % [view.data.display_name, view.data.split_into])
		view.splitting = false
		return
	var hp := view.combatant.hp
	var spot := view.get_index()
	battle_log.add("%s splits into %d %ss with %d HP each!" % [view.data.display_name,
		view.data.split_count, child_data.display_name, hp], BattleLog.ENEMY_COLOR)
	message_label.text = "%s splits!" % view.data.display_name
	enemy_views.erase(view)
	enemy_row.remove_child(view)
	view.queue_free()
	for i in view.data.split_count:
		add_enemy(child_data, hp, spot + i)
	fit_enemy_row()


# ---------------------------------------------------------------------------
# Cards
# ---------------------------------------------------------------------------

# Deal cards into your hand one at a time. Dice cards roll as they're drawn,
# and you watch their dice tumble on the card (Wild cards wait until you play
# them). Call it with `await`: it returns once every die has landed.
func draw_cards(amount: int) -> void:
	var my_fight := fight_id
	var drawn: Array[String] = []
	var rolled_any := false
	for i in amount:
		# Out of cards? Shuffle the discard pile to make a new draw pile.
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break  # No cards anywhere, stop drawing.
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			draw_pile.shuffle()
			battle_log.add("Discard pile shuffled into the draw pile", BattleLog.DIM_COLOR)
		var card: CardData = draw_pile.pop_back()
		card.roll_result = {}  # Forget any old roll.
		apply_draw_talents(card)
		if card.rolls_on_draw():
			# A card with its own Advantage / Disadvantage uses it right away.
			card.roll_result = CardRoller.roll(card, CardRoller.mode_for(card, false))
			if tutorial:
				tutorial.rig_roll(card)  # The training can fix a die (a sure Critical).
		hand.append(card)
		var view := add_card_view(card)
		update_ui()
		if card.is_rolled():
			rolled_any = true
			view.roll_dice()  # No `await`: the next card is dealt while these dice tumble.
			drawn.append("%s %s" % [card.card_name, roll_text(card)])  # e.g. "Strike [3]"
		else:
			drawn.append(card.card_name + (" (Wild)" if card.wild and card.has_dice() else ""))
		await get_tree().create_timer(DEAL_TIME).timeout
		if game_over or my_fight != fight_id:
			return  # The fight ended mid-deal (a talent's damage can win it).
	if rolled_any:
		await get_tree().create_timer(Card.ROLL_TIME).timeout  # Let the last dice land.
		if my_fight != fight_id:
			return
	if not drawn.is_empty():
		battle_log.add("You draw " + ", ".join(drawn), BattleLog.DIM_COLOR)
	update_ui()


# ---------------------------------------------------------------------------
# Talents (see talent.gd and the Talents screen)
# ---------------------------------------------------------------------------

# Extra Energy each turn from talents: Energy, and Energy If Only Neutral
# when every card in your deck is Neutral.
func talent_energy() -> int:
	var cls := GameState.character_class
	var bonus := GameState.talent_bonus(cls, Talent.ENERGY)
	if GameState.deck.all(func(card: CardData) -> bool: return card.is_neutral()):
		bonus += GameState.talent_bonus(cls, Talent.ENERGY_IF_ONLY_NEUTRAL)
	return bonus


# How many different schools your deck has. Neutral counts as one.
func deck_school_count() -> int:
	var schools := 0  # The school flags, added together with | (bitwise OR).
	var has_neutral := false
	for card in GameState.deck:
		schools |= card.schools
		has_neutral = has_neutral or card.is_neutral()
	var count := 1 if has_neutral else 0
	for school: int in CardData.School.values():
		if school != 0 and schools & school:
			count += 1
	return count


# Talents that trigger once, at the start of a fight (after the first draw).
func apply_fight_start_talents() -> void:
	var cls := GameState.character_class
	# Collector: Block for every different school in your deck.
	var block := GameState.talent_bonus(cls, Talent.START_BLOCK_PER_SCHOOL) * deck_school_count()
	if block > 0:
		player.gain_block(block)
		battle_log.add("Talent: %d school(s) in your deck give you %d Block (Block %d)" % [
			deck_school_count(), block, player.block], BattleLog.PLAYER_COLOR)


# Is this the first time this card is played this fight?
func is_first_play(card: CardData) -> bool:
	return not played_this_fight.has(card.card_name)


# Talents that trigger when a card is drawn.
func apply_draw_talents(card: CardData) -> void:
	var cls := GameState.character_class
	# A discount only lasts the turn: put the real cost back first.
	if card.has_meta("base_cost"):
		card.cost = card.get_meta("base_cost")
		card.remove_meta("base_cost")
	# Cost Discount Chance: e.g. 20 = a 20% chance it costs 1 less this turn.
	# randi_range(1, 100) <= 20 is true 20 times out of 100.
	var discount_chance := GameState.talent_bonus(cls, Talent.COST_DISCOUNT_CHANCE, card)
	if card.cost > 0 and discount_chance > 0 and randi_range(1, 100) <= discount_chance:
		card.set_meta("base_cost", card.cost)
		card.cost -= 1
		battle_log.add("Talent: %s costs 1 less this turn" % card.card_name, BattleLog.PLAYER_COLOR)
	# Draw Damage Chance: 1 damage to every enemy.
	var damage_chance := GameState.talent_bonus(cls, Talent.DRAW_DAMAGE_CHANCE, card)
	if damage_chance > 0 and randi_range(1, 100) <= damage_chance:
		battle_log.add("Talent: drawing %s deals 1 damage to all enemies" % card.card_name, BattleLog.PLAYER_COLOR)
		for view in living_enemies():
			battle_log.add("%s takes 1 damage (HP %d/%d)" % [view.data.display_name, view.hp_after(1), view.combatant.max_hp])
			view.combatant.take_damage(1)
			view.show_hurt()


# A card's rolled dice as text for the log: {"attack 0": [3], "attack 1": [1]} -> "[3] [1]"
func roll_text(card: CardData) -> String:
	var parts: Array[String] = []
	for values: Array in card.roll_result.values():
		for value: int in values:
			parts.append("[%d]" % value)
	return " ".join(parts)


# Called when a card is dropped on the play zone (see play_zone.gd).
# `target` is the enemy it was dropped on, or null.
func _on_card_played(card: CardData, target: EnemyView = null) -> void:
	if busy or game_over or card.cost > energy:
		return
	if not hand.has(card):
		return  # Only cards really in your hand can be played.

	busy = true  # Until this card is done, nothing else can be played.
	energy -= card.cost
	message_label.text = ""
	battle_log.add("You play %s (%d energy)" % [card.card_name, card.cost], BattleLog.PLAYER_COLOR)
	# Take the card out of your hand FIRST, so effects like "discard 2 cards"
	# can't pick the card you're playing.
	hand.erase(card)
	refresh_hand()

	# Check this BEFORE healing, otherwise healing could fill you up first.
	var was_at_full_hp := player.hp == player.max_hp
	var had_advantage := next_roll_advantage and card.has_dice()  # For the training's ADVANTAGE! pop-up.

	# Dice cards: roll now, unless the card already rolled when it was drawn.
	# Wild cards roll here, so their dice tumble in the dice tray. Cards that
	# rolled when drawn just show their dice there, already landed.
	var animate := not card.is_rolled()
	if card.has_dice() and not card.is_rolled():
		card.roll_result = CardRoller.roll(card, CardRoller.mode_for(card, next_roll_advantage))
	elif card.has_dice() and next_roll_advantage and CardRoller.mode_for(card, true) == CardRoller.ADVANTAGE \
			and not card.advantage:
		# It already rolled when drawn, and now has Advantage: roll a second set
		# and keep the higher dice. Show the new dice tumbling.
		CardRoller.add_advantage(card)
		animate = true
	if card.has_dice():
		var mode := CardRoller.mode_for(card, next_roll_advantage)
		if mode == CardRoller.ADVANTAGE:
			battle_log.add("    Advantage: 2 dice each, keep the higher", BattleLog.DIM_COLOR)
		elif mode == CardRoller.DISADVANTAGE:
			battle_log.add("    Disadvantage: 2 dice each, keep the lower", BattleLog.DIM_COLOR)
	# Add the modifiers and check for crits (see card_roller.gd).
	var bonuses := get_bonuses(card)
	var result := CardRoller.resolve(card, card.roll_result, bonuses)
	if card.has_dice() and bonuses.get("flawless", false) and not card.flawless:
		battle_log.add("    First play: Flawless (every die is a Critical)", BattleLog.CRIT_COLOR)
	if card.has_dice() and bonuses.get("first_play", 0) > 0:
		battle_log.add("    First play: +%d to every die" % bonuses.first_play, BattleLog.DIM_COLOR)
	played_this_fight[card.card_name] = true

	# Show the roll. `await` pauses here until the animation is done.
	if card.has_dice():
		await dice_tray.play(card.card_name, result.rolls, animate)
		for line: String in result.lines:  # e.g. "Hit 1: [3] + 1 = 4  CRIT!"
			battle_log.add("    " + line, BattleLog.CRIT_COLOR if line.ends_with("!") else Color.WHITE)
		if game_over:
			put_away(card, result.keep > 0)
			busy = false
			return
		next_roll_bonus = 0  # Used up by this roll...
		next_roll_advantage = false  # ...and so is Advantage.

	# Apply each effect the card has. A card can have several.
	var damage_dealt := 0  # For Leech.
	for hit: int in result.hits:  # Each hit goes through the enemy's Block on its own.
		if game_over:
			break  # An earlier hit already won the fight.
		var targets := pick_targets(card, target)
		if targets.is_empty():
			battle_log.add("    Hit wasted: its target is already defeated", BattleLog.DIM_COLOR)
		for view in targets:
			# Log first, for the same reason as in enemy_turn(): a killing hit's
			# "defeated" line is added inside take_damage().
			battle_log.add("%s takes %d damage (HP %d/%d)" % [view.data.display_name, hit,
				view.hp_after(hit), view.combatant.max_hp])
			var hp_before := view.combatant.hp
			view.combatant.take_damage(hit)
			damage_dealt += hp_before - view.combatant.hp
			view.show_hurt()
	if game_over:
		# The fight is over, so the rest of the card (draws, heals...) doesn't matter.
		put_away(card, result.keep > 0)  # But a Vanish card still Vanishes.
		busy = false
		return
	if card.leech > 0 and damage_dealt > 0:
		# Leech: heal part of the damage this card dealt (rounded up).
		var leeched := ceili(damage_dealt * card.leech / 100.0)
		player.heal(leeched)
		battle_log.add("Leech: you heal %d (HP %d/%d)" % [leeched, player.hp, player.max_hp], BattleLog.PLAYER_COLOR)
	if card.has_type(CardData.CardType.ATTACK):
		next_attack_bonus = 0  # An Attack card uses up the waiting attack bonus (Rage).
	if result.block > 0:
		player.gain_block(result.block)
		battle_log.add("You gain %d Block (Block %d)" % [result.block, player.block])
	if card.has_type(CardData.CardType.DEFENSE):
		next_defense_bonus = 0  # A Defense card uses up the waiting block bonus (Brace).
	if result.heal > 0:
		player.heal(result.heal)
		battle_log.add("You heal %d (HP %d/%d)" % [result.heal, player.hp, player.max_hp])
	if result.armor > 0:  # A crit like Fortify's: more Armor for the rest of this fight.
		player.armor += result.armor
		battle_log.add("Critical! Your Armor goes up to %d for this fight" % player.armor)
	energy += card.energy + result.energy
	if card.energy + result.energy > 0:
		battle_log.add("You gain %d energy" % (card.energy + result.energy))
	if card.lose_hp > 0:
		player.lose_hp(card.lose_hp)
		battle_log.add("You lose %d HP (HP %d/%d)" % [card.lose_hp, player.hp, player.max_hp])
		if game_over:
			put_away(card, result.keep > 0)
			busy = false
			return  # That was the last of your HP.
	if card.draw_if_full_hp > 0 and was_at_full_hp:
		await draw_cards(card.draw_if_full_hp)
	# Save bonuses for later cards.
	next_attack_bonus += card.next_attack_bonus
	next_defense_bonus += card.next_defense_bonus
	next_roll_bonus += result.roll_bonus  # Master of None's +1, or Pump Up's rolled d3.
	if result.roll_bonus > 0:
		battle_log.add("Your next roll gets +%d" % next_roll_bonus)
	if card.gain_advantage or result.advantage > 0:
		next_roll_advantage = true
		battle_log.add("Your next roll has Advantage")
	if card.next_attack_bonus > 0:
		battle_log.add("Your next Attack gets +%d" % next_attack_bonus)
	if card.next_defense_bonus > 0:
		battle_log.add("Your next Defense gets +%d" % next_defense_bonus)
	if card.discard > 0:
		discard_random_cards(card.discard)
	if card.draw + result.draw > 0:
		await draw_cards(card.draw + result.draw)
	if card.reroll > 0:
		await choose_rerolls(card.reroll)
	if result.crits > 0:
		# e.g. "Critical! Draw 1 (x2)   Discarded Guard"
		var crit_text := "Critical! %s" % card.critical
		if result.crits > 1:
			crit_text += " (x%d)" % result.crits
		battle_log.add(crit_text, BattleLog.CRIT_COLOR)
		if message_label.text.begins_with("Discarded"):
			crit_text += "   " + message_label.text
		message_label.text = crit_text

	put_away(card, result.keep > 0)
	busy = false
	refresh_hand()
	if tutorial:
		tutorial.card_played(card, result, had_advantage)  # CRITICAL!, WILD!... the first time.


# Who does one hit of this card land on?
#   AoE (Target ALL): every enemy still standing.
#   Random: one random enemy still standing.
#   Single: the enemy you dropped it on, and only that one. If Multi Strike's
#           first hit defeats it, the second hit is wasted (like in Slay the Spire).
func pick_targets(card: CardData, target: EnemyView) -> Array[EnemyView]:
	var living := living_enemies()
	if living.is_empty():
		return []
	match card.target:
		CardData.Target.ALL:
			return living
		CardData.Target.RANDOM:
			return [living.pick_random()]
	if target == null:
		return [living[0]]  # Dropped anywhere with only one enemy left: that one.
	if not target.is_alive():
		return []  # Its target is already defeated.
	return [target]


# A played card is done: into the discard pile, or gone for the run if it Vanishes.
# `keep` = a Critical said "Dont Vanish" (First Aid), so this time it stays.
func put_away(card: CardData, keep: bool = false) -> void:
	card.roll_result = {}  # It rolls again next time.
	card.dropped_dice = {}
	if card.vanish and keep:
		battle_log.add("Critical! %s doesn't Vanish this time" % card.card_name, BattleLog.CRIT_COLOR)
	if card.vanish and not keep:
		# Gone for the rest of the run: it doesn't go to the discard pile, and
		# GameState leaves it out of the next fights' decks too.
		if card.has_meta("deck_index"):
			GameState.vanished.append(card.get_meta("deck_index"))
		battle_log.add("%s Vanishes for the rest of the run" % card.card_name, BattleLog.DIM_COLOR)
		if message_label.text.is_empty() and not game_over:
			message_label.text = "%s Vanished" % card.card_name
	else:
		discard_pile.append(card)  # The played card goes to the discard pile like everything else.


# Gamble: you click a card in your hand, and its dice roll again. Only cards
# that already rolled (not Wild ones) can be picked. `await` waits for the
# reroll_picked signal, which _on_hand_card_clicked() sends.
func choose_rerolls(count: int) -> void:
	for i in count:
		if not hand.any(can_reroll):
			battle_log.add("No rolled cards in your hand to re-roll", BattleLog.DIM_COLOR)
			message_label.text = "Nothing to re-roll"
			return
		choosing_reroll = true
		message_label.text = "Click a card in your hand to re-roll its dice"
		update_ui()
		var picked: CardData = await reroll_picked
		choosing_reroll = false
		var before := roll_text(picked)
		picked.roll_result = CardRoller.roll(picked, CardRoller.mode_for(picked, false))
		battle_log.add("You re-roll %s: %s → %s" % [picked.card_name, before, roll_text(picked)])
		message_label.text = ""
		for view: Card in hand_box.get_children():
			if view.card_data == picked:
				await view.roll_dice()  # Watch the new dice tumble on the card.
		update_ui()


# Can Gamble re-roll this card? Only cards that rolled when drawn.
func can_reroll(card: CardData) -> bool:
	return card.is_rolled() and not card.wild


func _on_hand_card_clicked(card: CardData) -> void:
	if choosing_reroll and can_reroll(card):
		reroll_picked.emit(card)


# The bonuses waiting right now for this card, in the form CardRoller.resolve() wants.
# Pack Rat's first-play talents only count if the card hasn't been played this fight.
func get_bonuses(card: CardData) -> Dictionary:
	var bonuses := {"roll": next_roll_bonus, "attack": next_attack_bonus, "defense": next_defense_bonus}
	if is_first_play(card):
		var cls := GameState.character_class
		bonuses.first_play = GameState.talent_bonus(cls, Talent.FIRST_PLAY_BONUS, card)
		bonuses.flawless = GameState.talent_bonus(cls, Talent.FIRST_PLAY_FLAWLESS, card) > 0
	return bonuses


# What this card would do if played now, at worst and at best:
# [low result, high result]. Once the card has rolled, both are the same.
# Used for the previews, so they always match what playing it really does.
func get_outcomes(card: CardData) -> Array[Dictionary]:
	if card.is_rolled():
		var rolled := CardRoller.resolve(card, card.roll_result, get_bonuses(card))
		return [rolled, rolled]
	return [CardRoller.resolve(card, CardRoller.fixed_roll(card, false), get_bonuses(card)),
		CardRoller.resolve(card, CardRoller.fixed_roll(card, true), get_bonuses(card))]


# One number from both outcomes, e.g. outcome_range(outcomes, "block") -> Vector2i(1, 4)
func outcome_range(outcomes: Array[Dictionary], what: String) -> Vector2i:
	if what == "damage":
		return Vector2i(CardRoller.total_damage(outcomes[0]), CardRoller.total_damage(outcomes[1]))
	return Vector2i(outcomes[0][what], outcomes[1][what])


# An enemy's HP after this much damage, as text: "18", or "14–17" before the
# dice roll. Most damage leaves the LEAST HP, so the order flips.
func hp_after_text(view: EnemyView, damage: Vector2i) -> String:
	return range_text(Vector2i(view.hp_after(damage.y), view.hp_after(damage.x)))


# Vector2i(5, 5) -> "5",  Vector2i(4, 8) -> "4–8"
func range_text(values: Vector2i) -> String:
	if values.x == values.y:
		return str(values.x)
	return "%d–%d" % [values.x, values.y]


# The text in the banner above a dragged card, one effect per line.
func describe_card(card: CardData) -> String:
	var lines: Array[String] = []
	var outcomes := get_outcomes(card)
	if card.deals_damage():
		var damage := outcome_range(outcomes, "damage")
		var damage_text := "Deal %s damage" % range_text(damage)
		if card.attack.size() > 1:
			damage_text += " (%d hits)" % card.attack.size()
		var living := living_enemies()
		if card.target == CardData.Target.ALL:
			damage_text += " to ALL enemies"
		elif card.target == CardData.Target.RANDOM and living.size() > 1:
			damage_text += " to random enemies"
		lines.append(damage_text)
		if living.size() == 1:
			lines.append("%s: %d → %s HP" % [living[0].data.display_name, living[0].combatant.hp, hp_after_text(living[0], damage)])
		elif card.target == CardData.Target.SINGLE and living.size() > 1:
			lines.append("Drop it on the enemy to hit")
	if outcomes[1].block > 0:
		lines.append("Gain %s Block" % range_text(outcome_range(outcomes, "block")))
	if outcomes[1].heal > 0:
		lines.append("Heal %s HP" % range_text(outcome_range(outcomes, "heal")))
	if card.energy > 0:
		lines.append("Gain %d Energy" % card.energy)
	if card.lose_hp > 0:
		lines.append("Lose %d HP" % card.lose_hp)
	if card.draw_if_full_hp > 0 and player.hp == player.max_hp:
		lines.append("Draw %d (full HP)" % card.draw_if_full_hp)
	if card.draw > 0:
		lines.append("Draw %d" % card.draw)
	if card.discard > 0:
		lines.append("Discard %d at random" % card.discard)
	if card.next_attack_bonus > 0:
		lines.append("Next Attack +%d" % card.next_attack_bonus)
	if card.next_defense_bonus > 0:
		lines.append("Next Defense +%d" % card.next_defense_bonus)
	if not card.next_roll_bonus.is_empty():
		lines.append("Next roll +%s" % range_text(outcome_range(outcomes, "roll_bonus")))
	if card.gain_advantage:
		lines.append("Next roll: Advantage")
	if card.reroll > 0:
		lines.append("Re-roll %d card(s) in your hand" % card.reroll)
	if card.has_dice():
		var mode := CardRoller.mode_for(card, next_roll_advantage)
		if mode == CardRoller.ADVANTAGE:
			lines.append("Advantage: roll 2, keep the higher")
		elif mode == CardRoller.DISADVANTAGE:
			lines.append("Disadvantage: roll 2, keep the lower")
	if card.has_dice() and (card.flawless or get_bonuses(card).get("flawless", false)):
		lines.append("Flawless: every die crits" + ("" if card.flawless else " (first play)"))
	if not card.critical.is_empty():
		# outcomes[0] is the worst case, so crits there are certain: it already
		# rolled a crit, or it's Flawless.
		if outcomes[0].crits > 0:
			var times := " (x%d)" % outcomes[0].crits if outcomes[0].crits > 1 else ""
			lines.append("CRIT! %s%s" % [card.critical, times])
		else:
			lines.append("Crit: %s" % card.critical)
	if card.has_dice() and not card.is_rolled():
		lines.append("Wild: rolls when played")
	if card.vanish:
		lines.append("Vanishes for the run")
	return "\n".join(lines)


# Godot tells every node when a drag starts and ends. We use that to show
# the drop zone and to preview the card's effect on the HP and Block numbers.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data = get_viewport().gui_get_drag_data()  # What's being dragged.
		if data is CardData:
			dragged_card = data
			# Work out the damage once, not every frame.
			dragged_damage = outcome_range(get_outcomes(data), "damage")
			set_process(data.deals_damage())  # Only an attack needs the per-frame previews.
			play_zone_hint.visible = true
			if play_zone.needs_target(data):
				hint_label.text = "Drop on an enemy to attack it"
			elif data.deals_damage() and data.target == CardData.Target.ALL:
				hint_label.text = "Drop here to hit ALL enemies"
			elif data.deals_damage() and data.target == CardData.Target.RANDOM and living_enemies().size() > 1:
				hint_label.text = "Drop here to hit random enemies"
			elif data.deals_damage():
				hint_label.text = "Drop here to attack the %s" % living_enemies()[0].data.display_name
			else:
				hint_label.text = "Drop here to play"
			update_ui()
	elif what == NOTIFICATION_DRAG_END:
		dragged_card = null
		set_process(false)
		play_zone_hint.visible = false
		update_ui()


# _process() runs every frame, but only while you drag an attack (set_process()
# turns it on and off above). It lights up the enemies that letting go right
# here would hit, and previews the damage on their bars.
func _process(_delta: float) -> void:
	if dragged_card != null:
		show_enemy_previews(get_global_mouse_position())


# Which enemies would this drag hit if you let go at `mouse`? Lights them up
# and shows the damage on their health bars:
#   blinking = HP the attack will surely take, striped = HP it might take.
func show_enemy_previews(mouse: Vector2) -> void:
	var card := dragged_card
	var living := living_enemies()
	var hovered := play_zone.enemy_at(mouse)
	var in_zone := play_zone.is_over_zone(mouse)
	for view in enemy_views:
		var hit := false
		var maybe := false  # A Random attack MIGHT hit this one.
		if view.is_alive():
			match card.target:
				CardData.Target.ALL:
					hit = in_zone
				CardData.Target.RANDOM:
					hit = in_zone
					maybe = living.size() > 1
				_:
					hit = view == hovered or (living.size() == 1 and in_zone)
		view.set_targeted(hit)
		if hit:
			var low := view.hp_after(dragged_damage.y)
			var high := view.combatant.hp if maybe else view.hp_after(dragged_damage.x)
			view.health_bar.set_preview(low, high, "%d → %s" % [view.combatant.hp,
				range_text(Vector2i(low, high))])
		else:
			view.health_bar.clear_preview()


# Throw `amount` random cards from the hand into the discard pile.
func discard_random_cards(amount: int) -> void:
	var discarded: Array[String] = []
	for i in amount:
		if hand.is_empty():
			break  # Nothing left to discard.
		var index := randi() % hand.size()  # A random position in the hand.
		var card: CardData = hand.pop_at(index)  # Remove it from the hand...
		discard_pile.append(card)  # ...and put it on the discard pile.
		discarded.append(card.card_name)
	refresh_hand()
	if not discarded.is_empty():
		message_label.text = "Discarded " + ", ".join(discarded)
		battle_log.add("You discard " + ", ".join(discarded) + " at random")


# Rebuild the row of card buttons so it matches the `hand` array.
# Cards still in your hand keep their card node (making one is slow-ish, and
# the old one already shows its dice); only new cards get a new node.
func refresh_hand() -> void:
	var views := {}  # CardData -> its Card node, for the cards still in hand.
	for child: Card in hand_box.get_children():
		if hand.has(child.card_data):
			views[child.card_data] = child
		else:
			# remove_child() takes it off the screen now; queue_free() deletes
			# it safely at the end of the frame.
			hand_box.remove_child(child)
			child.queue_free()
	for i in hand.size():
		var view: Card = views.get(hand[i])
		if view == null:
			view = add_card_view(hand[i])
		hand_box.move_child(view, i)  # Same order as the hand.
	update_ui()


# Put one card on screen at the end of the hand row.
func add_card_view(card_data: CardData) -> Card:
	var card: Card = CARD_SCENE.instantiate()
	hand_box.add_child(card)
	card.setup(card_data)
	card.draggable = true  # In battle you drag cards up to play them...
	card.clicked.connect(_on_hand_card_clicked)  # ...and click them only to pick one (Gamble).
	return card


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

# HP and Block change a lot during one card (every hit, every enemy...), and
# each change sends `stats_changed`. Instead of redrawing everything each time,
# this asks for ONE update_ui() at the end of the frame. call_deferred() means
# "run this once the current code has finished".
func queue_update_ui() -> void:
	if _ui_update_queued:
		return  # Already asked for this frame.
	_ui_update_queued = true
	_run_queued_update.call_deferred()


func _run_queued_update() -> void:
	_ui_update_queued = false
	update_ui()


# --- The player bar ------------------------------------------------------------
# The row above your hand: HP, Block, Energy, Gold, buffs, draw/discard piles
# and End Turn. Each number sits next to an icon in a box of FIXED width, and
# the buff text (the one that can get long) is cut off with "..." instead of
# growing. That way nothing can ever push End Turn off the screen.
# (The labels themselves are in battle.tscn; this moves each into its box.)

var armor_label: Label  # "Armor 3", small, next to your Block.
var buffs_label: Label  # "Atk +2 · Def +1 · Roll +1 · Adv"
var discard_label: Label  # The discard pile's count (piles_label is the draw pile's).


func build_player_bar() -> void:
	var bar: HBoxContainer = end_turn_button.get_parent()
	bar.add_theme_constant_override("separation", 14)
	var stat_box := func(label: Label, icon: String, width: float, tip: String) -> HBoxContainer:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.custom_minimum_size = Vector2(width, 0)
		box.tooltip_text = tip
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var picture := TextureRect.new()
		picture.texture = BAR_ICONS[icon]
		picture.custom_minimum_size = Vector2(30, 30)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var index := label.get_index()
		bar.add_child(box)
		bar.move_child(box, index)
		label.reparent(box)
		box.add_child(picture)
		box.move_child(picture, 0)
		# The label fills the rest of the box and cuts off anything too long.
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		return box
	stat_box.call(player_hp_label, "hp", 150, "Your HP. At 0 the run is over.")
	var block_box: HBoxContainer = stat_box.call(player_block_label, "block", 175,
		"Block: stops that much damage. It goes back to your Armor at the start of each turn.")
	stat_box.call(energy_label, "energy", 120, "Energy: playing a card costs its number.")
	stat_box.call(gold_label, "gold", 130, "Gold you have (+ what you've found this run).")
	# Armor, small and grey, under... well, beside the Block number.
	armor_label = Label.new()
	armor_label.add_theme_font_size_override("font_size", 14)
	armor_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 0.8))
	armor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block_box.add_child(armor_label)
	# Buffs: the only part that grows, and it can't push anything (clipped).
	buffs_label = Label.new()
	buffs_label.add_theme_font_size_override("font_size", 17)
	buffs_label.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	buffs_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	buffs_label.add_theme_constant_override("outline_size", 6)
	buffs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buffs_label.custom_minimum_size = Vector2(40, 0)
	buffs_label.clip_text = true
	buffs_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	buffs_label.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(buffs_label)
	bar.move_child(buffs_label, piles_label.get_index())
	# Draw pile and discard pile: one small box each.
	stat_box.call(piles_label, "draw", 72, "Cards in your draw pile.")
	discard_label = piles_label.duplicate()
	piles_label.get_parent().add_sibling(discard_label)
	stat_box.call(discard_label, "discard", 72, "Cards in your discard pile. It's shuffled back into the draw pile when that runs out.")
	end_turn_button.custom_minimum_size.x = 150


# Copy all the numbers into the labels. Called whenever something changes.
func update_ui() -> void:
	refresh_potions()
	refresh_flask()
	gold_label.text = "%d" % GameState.gold
	if GameState.dungeon and GameState.dungeon.found_gold > 0:
		gold_label.text += " +%d" % GameState.dungeon.found_gold
	for view in enemy_views:
		view.refresh()

	player_hp_label.text = "%d/%d" % [player.hp, player.max_hp]
	player_block_label.text = "%d" % player.block
	armor_label.text = "Armor %d" % player.armor if player.armor > 0 else ""
	# Waiting Rage / Brace / roll bonuses, short. The tooltip spells them out.
	var short: Array[String] = []
	var long: Array[String] = []
	if next_attack_bonus > 0:
		short.append("Atk +%d" % next_attack_bonus)
		long.append("Your next Attack does +%d" % next_attack_bonus)
	if next_defense_bonus > 0:
		short.append("Def +%d" % next_defense_bonus)
		long.append("Your next Defense gives +%d Block" % next_defense_bonus)
	if next_roll_bonus > 0:
		short.append("Roll +%d" % next_roll_bonus)
		long.append("Your next roll gets +%d" % next_roll_bonus)
	if next_roll_advantage:
		short.append("Adv")
		long.append("Your next roll has Advantage (roll twice, keep the best)")
	buffs_label.text = " · ".join(short)
	buffs_label.tooltip_text = "\n".join(long)
	energy_label.text = "%d/%d" % [energy, max_energy]
	piles_label.text = "%d" % draw_pile.size()
	discard_label.text = "%d" % discard_pile.size()

	# Grey out cards you can't afford, and tell each card what it would do.
	# (queue_free()d cards wait until the end of the frame, so skip those.)
	for card: Card in hand_box.get_children():
		if card.is_queued_for_deletion():
			continue
		card.disabled = game_over or card.card_data.cost > energy
		if choosing_reroll:
			card.disabled = not can_reroll(card.card_data)  # Only the ones you can pick.
		card.preview_text = describe_card(card.card_data)
		if card.card_data.is_rolled():
			# Light up dice that a bonus (like Master of None's +1) turns into crits.
			card.show_crits(CardRoller.resolve(card.card_data, card.card_data.roll_result, get_bonuses(card.card_data)).rolls)

	show_drag_preview()


# While a card is being dragged, show "before -> after" on the numbers it
# would change, in gold, so you can see what will happen before you drop it.
	if tutorial:
		tutorial.refresh()


func show_drag_preview() -> void:
	var labels: Array[Label] = [player_hp_label, player_block_label, energy_label]
	for label in labels:
		label.modulate = Color.WHITE  # Back to normal colours.
	var card := dragged_card
	if card == null or not card.deals_damage():
		for view in enemy_views:
			view.set_targeted(false)
			view.health_bar.clear_preview()
	if card == null:
		return

	# (The enemies' health bars are previewed in show_enemy_previews(), every
	# frame, because they depend on where the mouse is.)
	var outcomes := get_outcomes(card)
	if outcomes[1].heal > 0 or card.lose_hp > 0:
		var heal := outcome_range(outcomes, "heal")
		var low := maxi(mini(player.hp + heal.x, player.max_hp) - card.lose_hp, 0)
		var high := maxi(mini(player.hp + heal.y, player.max_hp) - card.lose_hp, 0)
		player_hp_label.text = "%d → %s" % [player.hp, range_text(Vector2i(low, high))]
		player_hp_label.modulate = PREVIEW_COLOR
	if outcomes[1].block > 0:
		var block := outcome_range(outcomes, "block")
		player_block_label.text = "%d → %s" % [player.block, range_text(Vector2i(player.block + block.x, player.block + block.y))]
		player_block_label.modulate = PREVIEW_COLOR
	var energy_after := energy - card.cost + card.energy
	if energy_after != energy:
		energy_label.text = "%d → %d" % [energy, energy_after]
		energy_label.modulate = PREVIEW_COLOR


# One enemy is defeated. It drops some gold; once they're ALL down, you win.
func _on_enemy_died(view: EnemyView) -> void:
	view.show_defeated()
	if tutorial:
		tutorial.enemy_died()  # No gold or Exp from dummies.
		return
	# Loot Hound talents add Bonus Gold to every enemy.
	# Bosses drop their Bonus Gold on top.
	var loot := randi_range(GameState.GOLD_MIN, GameState.GOLD_MAX) + view.data.bonus_gold \
		+ GameState.talent_bonus(GameState.character_class, Talent.BONUS_GOLD)
	fight_exp += view.data.exp  # Each enemy's Exp (10 for most, more for bosses).
	# Gold found in the dungeon is only yours once you get out alive
	# (Leave at a campfire, or beat the Boss). See dungeon_run.gd.
	var dungeon := GameState.dungeon
	dungeon.found_gold += loot
	fight_gold += loot
	battle_log.add("The %s is defeated and drops %d gold (%d found so far)" % [view.data.display_name, loot, dungeon.found_gold],
		BattleLog.TURN_COLOR)
	# Materials: each Drops entry is "Green Ooze 100" = its % chance of one.
	for drop in view.data.drops:
		var chance := drop.get_slice(" ", drop.count(" ")).to_int()
		var material_name := drop.trim_suffix(" " + str(chance)).strip_edges()
		if randi_range(1, 100) <= chance:
			dungeon.add_found_material(material_name, 1)
			fight_materials[material_name] = fight_materials.get(material_name, 0) + 1
			battle_log.add("It drops 1 %s!" % material_name, BattleLog.CRIT_COLOR)
	GameState.record_for_quest(Quest.DEFEAT, view.data.display_name)
	if not living_enemies().is_empty():
		update_ui()
		return  # Still more to beat.

	GameState.run_hp = player.hp  # Carry your HP into the next fight.
	var reward := "You found %d gold!" % fight_gold
	if not fight_materials.is_empty():
		reward += "  +" + MaterialInfo.costs_text(fight_materials)
	# The dungeon hands out the room's rewards (keys, loot) and says what's next.
	var log_size := dungeon.history.size()
	var outcome := dungeon.win_fight()
	for line in dungeon.history.slice(log_size):
		reward += "\n" + line
		battle_log.add(line, BattleLog.CRIT_COLOR)

	var exp_gain := fight_exp
	var opened_areas: Array[Area] = []
	if outcome == "won":
		# The Boss: the run is over, you keep your loot, and the next area opens.
		exp_gain += GameState.EXP_PER_RUN
		dungeon.claim_loot()
		reward += "\nYou take home %s." % dungeon.loot_text()
		opened_areas = GameState.clear_area(GameState.current_area)
		for opened in opened_areas:
			reward += "\nThe %s is now open on the map!" % opened.display_name
			battle_log.add("The %s is now open!" % opened.display_name, BattleLog.CRIT_COLOR)
	# Remember where the bar was, so it can fill up from there.
	var before_level := GameState.class_level(GameState.character_class)
	var before_progress := GameState.class_exp_progress(GameState.character_class)
	var level_ups := GameState.add_class_exp(exp_gain)
	battle_log.add("You gain %d Exp" % exp_gain, BattleLog.TURN_COLOR)

	if outcome == "won":
		# The Victory screen (victory.gd) shows this when you press Continue.
		var boss_names: Array[String] = []
		for enemy_view in enemy_views:
			if enemy_view.data.is_boss:
				boss_names.append(enemy_view.data.display_name)
		GameState.last_victory = {"area": GameState.current_area, "opened": opened_areas, "exp": exp_gain,
			"boss": " and ".join(boss_names) if not boss_names.is_empty() else "the Boss"}
		end_battle("%s cleared!" % GameState.current_area.display_name, reward, "Victory! →")
	else:
		end_battle("Victory!", reward, "Back to the Dungeon →")
	show_exp_gain(before_level, before_progress, exp_gain, level_ups)


# Fill the Exp bar on the victory panel, then list any level ups and the
# class cards they gave you.
func show_exp_gain(before_level: int, before_progress: Vector2i, amount: int, level_ups: Array[Dictionary]) -> void:
	exp_bar.show()
	var hero_name := GameState.character_class.display_name
	await exp_bar.play_gain(GameState.character_class, before_level, before_progress, amount)
	for level_up in level_ups:
		var line := "%s reached level %d!" % [hero_name, level_up.level]
		battle_log.add(line, BattleLog.PLAYER_COLOR)
		for item in level_up.cards:
			var card_line := "New class card: %s" % item.card.card_name
			if item.exp:
				card_line = "%s: +1 card Exp" % item.card.card_name  # You already had 3.
			line += "\n" + card_line
			battle_log.add(card_line, BattleLog.PLAYER_COLOR)
		reward_label.text += "\n" + line
	# Each level gives a talent point: make sure the player notices.
	var ready := GameState.talent_points_text(GameState.character_class)
	if not level_ups.is_empty() and not ready.is_empty():
		reward_label.text += "\n" + ready + " Spend it on the Talents screen."
		battle_log.add(ready, BattleLog.CRIT_COLOR)


func _on_player_died() -> void:
	if tutorial:
		tutorial.player_died()
		return
	var dungeon := GameState.dungeon
	var lost := dungeon.loot_text()
	var saved := dungeon.die()
	exp_bar.hide()  # No Exp for losing (you kept the Exp from the fights you won).
	var text := "You won %d fight(s). The dungeon keeps what you found (%s)." % [dungeon.fights_won, lost]
	if GameState.sack_open():
		text += "\nYour Save Sack kept: %s." % saved
	end_battle("Defeat...", text, "Back to Town →")


# The button on the end-of-fight panel: back to the dungeon, or to town once the run is over.
func _on_continue_pressed() -> void:
	if GameState.dungeon.result.is_empty():
		get_tree().change_scene_to_file(DUNGEON_SCENE)
	elif GameState.dungeon.result == "won":
		get_tree().change_scene_to_file(VICTORY_SCENE)
	else:
		get_tree().change_scene_to_file(TOWN_SCENE)


func end_battle(result: String, reward: String, button_text: String) -> void:
	game_over = true
	battle_log.add("\n" + result, BattleLog.TURN_COLOR)
	end_turn_button.disabled = true
	message_label.text = ""
	result_label.text = result
	reward_label.text = reward
	continue_button.text = button_text
	game_over_screen.visible = true
	update_ui()
