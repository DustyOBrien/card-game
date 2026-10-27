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
const SHOP_SCENE := "res://scenes/shop.tscn"

const HAND_SIZE := 5  # Cards drawn at the start of each turn.
const MAX_ENERGY := 3  # Energy you get each turn (before talents).
const DEAL_TIME := 0.2  # Seconds between cards as they're dealt into your hand.
const PREVIEW_COLOR := Color(1, 0.85, 0.3)  # Tint for numbers a dragged card would change.
const DEFAULT_ENEMY := preload("res://enemies/slime.tres")  # If an area has no encounters yet.

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

@onready var fight_label: Label = %FightLabel  # "Plains · Fight 2 / 5"
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

	start_battle()


# ---------------------------------------------------------------------------
# Battle flow
# ---------------------------------------------------------------------------

func start_battle() -> void:
	fight_id += 1
	game_over = false
	busy = false
	game_over_screen.visible = false
	GameState.ensure_ready()
	player.max_hp = GameState.character_class.max_hp  # Each class has its own HP...
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
		draw_pile.append(card)
	draw_pile.shuffle()
	dice_tray.hide()
	# The fight happens in the area you picked on the map.
	area_background.texture = GameState.current_area.background

	turn = 0
	# Set once per fight. (Winning moves the count on straight away, so
	# working it out again later would show the NEXT fight's number.)
	fight_label.text = "%s  ·  Fight %d / %d" % [GameState.current_area.display_name,
		GameState.current_fight(), GameState.FIGHTS_PER_RUN]
	battle_log.clear()
	message_label.text = "%s appear%s!" % [enemy_names(), "s" if enemy_views.size() == 1 else ""]
	var enemy_list: Array[String] = []
	for view in enemy_views:
		enemy_list.append("%s (%d HP)" % [view.data.display_name, view.data.max_hp])
	battle_log.add("%s, fight %d of %d: %s" % [GameState.current_area.display_name,
		GameState.current_fight(), GameState.FIGHTS_PER_RUN, ", ".join(enemy_list)], BattleLog.ENEMY_COLOR)
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
	var encounter: Array[EnemyData] = GameState.current_encounter()
	if encounter.is_empty():
		encounter = [DEFAULT_ENEMY]
	for enemy_data in encounter:
		var view := EnemyView.new()
		enemy_row.add_child(view)
		view.setup(enemy_data)
		# bind() adds `view` to the call, so we know WHICH enemy died.
		view.combatant.died.connect(_on_enemy_died.bind(view))
		view.combatant.stats_changed.connect(queue_update_ui)
		view.start_idle()
		enemy_views.append(view)
	play_zone.enemy_views = enemy_views


func living_enemies() -> Array[EnemyView]:
	return enemy_views.filter(func(view: EnemyView) -> bool: return view.is_alive())


# "Slime", "2 Slimelings" or "Slimeling and Slime", for messages.
func enemy_names() -> String:
	var names: Array[String] = []
	for view in enemy_views:
		names.append(view.data.display_name)
	if names.size() > 1 and names.count(names[0]) == names.size():
		return "%d %ss" % [names.size(), names[0]]
	if names.size() == 1:
		return "A " + names[0]
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]


func start_player_turn() -> void:
	var leftover := player.block
	player.clear_block()  # Your Armor saves up to that much of it (0 if you have none).
	energy = max_energy
	turn += 1
	battle_log.add_turn(turn)
	# Decide now what each enemy will do, so the player can plan around it.
	for view in living_enemies():
		view.choose_attack()
		battle_log.add("%s intends to attack for %d" % [view.data.display_name, view.next_attack], BattleLog.ENEMY_COLOR)
	if player.armor > 0 and leftover > 0:
		battle_log.add("Your Armor saves %d of your %d leftover Block" % [player.block, leftover])
	busy = true
	var my_fight := fight_id
	await draw_cards(HAND_SIZE)  # Wait for the cards to be dealt and their dice to land.
	if my_fight != fight_id:
		return  # That fight ended while the cards were dealt; a new one has started.
	busy = false
	if not game_over:
		end_turn_button.disabled = false
	update_ui()


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
	await enemy_turn()  # `await` waits for enemy_turn() to finish.
	if my_fight != fight_id:
		return
	busy = false
	if not game_over:
		start_player_turn()


# Every enemy still standing takes its turn, left to right.
func enemy_turn() -> void:
	message_label.text = "Enemy turn..."
	# Pause for a moment so the player can see what's happening.
	# create_timer() makes a one-shot timer; we wait for its `timeout` signal.
	await get_tree().create_timer(0.5).timeout

	for view in living_enemies():
		var enemy := view.combatant
		var leftover := enemy.block
		enemy.clear_block()  # Enemies with Armor keep some of their Block too.
		if enemy.armor > 0 and leftover > 0:
			battle_log.add("%s's Armor saves %d Block" % [enemy.display_name, enemy.block], BattleLog.ENEMY_COLOR)
		view.show_attack()
		var blocked := mini(player.block, view.next_attack)  # Worked out before Block is used up.
		var log_line := "%s attacks for %d" % [enemy.display_name, view.next_attack]
		if blocked > 0:
			log_line += ": %d blocked, you take %d" % [blocked, view.next_attack - blocked]
		# Logged BEFORE take_damage(): if this hit defeats you, `died` fires inside
		# take_damage() and its "Defeat" line should come after this one.
		var hp_after := maxi(player.hp - (view.next_attack - blocked), 0)
		battle_log.add(log_line + " (HP %d/%d)" % [hp_after, player.max_hp], BattleLog.ENEMY_COLOR)
		player.take_damage(view.next_attack)
		if game_over:
			return  # The attack defeated the player.
		message_label.text = "%s attacks for %d!" % [enemy.display_name, view.next_attack]
		await get_tree().create_timer(0.45).timeout


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
	var result := CardRoller.resolve(card, card.roll_result, get_bonuses())

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
			view.combatant.take_damage(hit)
			view.show_hurt()
	if game_over:
		# The fight is over, so the rest of the card (draws, heals...) doesn't matter.
		put_away(card, result.keep > 0)  # But a Vanish card still Vanishes.
		busy = false
		return
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


# The bonuses waiting right now, in the form CardRoller.resolve() wants.
func get_bonuses() -> Dictionary:
	return {"roll": next_roll_bonus, "attack": next_attack_bonus, "defense": next_defense_bonus}


# What this card would do if played now, at worst and at best:
# [low result, high result]. Once the card has rolled, both are the same.
# Used for the previews, so they always match what playing it really does.
func get_outcomes(card: CardData) -> Array[Dictionary]:
	if card.is_rolled():
		var rolled := CardRoller.resolve(card, card.roll_result, get_bonuses())
		return [rolled, rolled]
	return [CardRoller.resolve(card, CardRoller.fixed_roll(card, false), get_bonuses()),
		CardRoller.resolve(card, CardRoller.fixed_roll(card, true), get_bonuses())]


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
	if not card.critical.is_empty():
		if card.is_rolled() and outcomes[0].crits > 0:
			var times := " (x%d)" % outcomes[0].crits if outcomes[0].crits > 1 else ""
			lines.append("CRIT! %s%s" % [card.critical, times])  # Already rolled a crit.
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
func refresh_hand() -> void:
	# Remove the old card nodes. queue_free() deletes a node safely at the
	# end of the current frame.
	for child in hand_box.get_children():
		child.queue_free()
	# ...and create a fresh one for every card in the hand.
	for card_data in hand:
		add_card_view(card_data)
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


# Copy all the numbers into the labels. Called whenever something changes.
func update_ui() -> void:
	gold_label.text = "Gold %d" % GameState.gold
	for view in enemy_views:
		view.refresh()

	player_hp_label.text = "HP %d / %d" % [player.hp, player.max_hp]
	player_block_label.text = "Block %d" % player.block
	if player.armor > 0:
		player_block_label.text += "  (Armor %d)" % player.armor
	# Show waiting Rage / Brace bonuses next to your Block.
	if next_attack_bonus > 0:
		player_block_label.text += "   Next Attack +%d" % next_attack_bonus
	if next_defense_bonus > 0:
		player_block_label.text += "   Next Defense +%d" % next_defense_bonus
	if next_roll_bonus > 0:
		player_block_label.text += "   Next roll +%d" % next_roll_bonus
	if next_roll_advantage:
		player_block_label.text += "   Advantage"
	energy_label.text = "Energy %d / %d" % [energy, max_energy]
	piles_label.text = "Draw pile %d   Discard %d" % [draw_pile.size(), discard_pile.size()]

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
			card.show_crits(CardRoller.resolve(card.card_data, card.card_data.roll_result, get_bonuses()).rolls)

	show_drag_preview()


# While a card is being dragged, show "before -> after" on the numbers it
# would change, in gold, so you can see what will happen before you drop it.
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
		player_hp_label.text = "HP %d → %s / %d" % [player.hp, range_text(Vector2i(low, high)), player.max_hp]
		player_hp_label.modulate = PREVIEW_COLOR
	if outcomes[1].block > 0:
		var block := outcome_range(outcomes, "block")
		player_block_label.text = "Block %d → %s" % [player.block, range_text(Vector2i(player.block + block.x, player.block + block.y))]
		player_block_label.modulate = PREVIEW_COLOR
	var energy_after := energy - card.cost + card.energy
	if energy_after != energy:
		energy_label.text = "Energy %d → %d / %d" % [energy, energy_after, max_energy]
		energy_label.modulate = PREVIEW_COLOR


# One enemy is defeated. It drops some gold; once they're ALL down, you win.
func _on_enemy_died(view: EnemyView) -> void:
	view.show_defeated()
	var loot := randi_range(GameState.GOLD_MIN, GameState.GOLD_MAX)
	GameState.gold += loot
	GameState.run_gold += loot
	fight_gold += loot
	battle_log.add("The %s is defeated and drops %d gold (you have %d)" % [view.data.display_name, loot, GameState.gold],
		BattleLog.TURN_COLOR)
	GameState.save_game()  # So the gold is kept even if you close the game mid-fight.
	if not living_enemies().is_empty():
		update_ui()
		return  # Still more to beat.

	GameState.fights_won += 1
	GameState.run_hp = player.hp  # Carry your HP into the next fight.
	var reward := "You found %d gold!" % fight_gold

	# Class Exp: some for every enemy beaten, and a bonus for finishing the run.
	var exp_gain := GameState.EXP_PER_ENEMY * enemy_views.size()
	if GameState.is_run_over():
		exp_gain += GameState.EXP_PER_RUN
	# Remember where the bar was, so it can fill up from there.
	var before_level := GameState.class_level(GameState.character_class)
	var before_progress := GameState.class_exp_progress(GameState.character_class)
	var level_ups := GameState.add_class_exp(exp_gain)
	battle_log.add("You gain %d Exp" % exp_gain, BattleLog.TURN_COLOR)

	if GameState.is_run_over():
		end_battle("Run complete!", reward + "\nYou won all %d fights." % GameState.FIGHTS_PER_RUN, "Go to the Shop →")
	else:
		end_battle("Victory!", reward, "Next Fight →  (%d / %d)" % [GameState.current_fight(), GameState.FIGHTS_PER_RUN])
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
	GameState.run_died = true
	exp_bar.hide()  # No Exp for losing (you kept the Exp from the fights you won).
	end_battle("Defeat...", "You won %d fight(s) and earned %d gold this run." % [GameState.fights_won, GameState.run_gold], "Go to the Shop →")


# The button on the end-of-fight panel: the next fight, or the shop once the run is over.
func _on_continue_pressed() -> void:
	if GameState.is_run_over():
		get_tree().change_scene_to_file(SHOP_SCENE)
	else:
		start_battle()


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
