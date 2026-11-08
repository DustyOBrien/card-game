# dungeon_run.gd
#
# The rules of one EXPEDITION into a place (the Abandoned Farm). It happens
# on a 5 x 5 BOARD of map cards (room_card.gd), like a tabletop game:
#
#   1. THE MAP DECK. 40 cards: the place's 20 base cards, plus your own map
#      cards (up to 20, from quests and Maps). Empty slots are filled with
#      the place's basic Filler cards, so it's always 40.
#   2. THE DEAL. You start in the middle. The other 24 squares get a card
#      FACE DOWN: 23 from the deck, plus one hidden CAMPFIRE. The other 17
#      wait in the draw pile, so every board is a different mix. (Is the
#      Old Well on this board at all? You'll have to look.)
#   3. EXPLORING. Step onto a face-down card next to you to flip it. You can
#      walk back over cards that are Safe (or that you've made safe).
#        Safe     nothing to fear (and maybe some loot)
#        Unsafe   always a fight, and DANGER goes up by 1
#        Explore  a choice: open the shed with a key, or break it open...
#   4. THE CAMPFIRE. Find it to Return to Town with your loot, or Go Deeper:
#      every card on the board is shuffled back into the deck (beaten
#      Unsafe cards come back Unsafe), a fresh board is dealt one FLOOR
#      down, and a new campfire is hidden on it. Your burnt-out campfire is
#      where you start, so the only way home is to find the next one!
#      Cards with VANISH (mini bosses, the very best loot) don't come back.
#   5. DANGER. Every 3 danger gives every enemy +1 Strength (it never goes
#      down by itself, so the longer you stay, the harder it gets). Deeper
#      floors also shuffle in tougher cards, and from Floor 3 the Boss is on
#      every board. Beat it and the place is cleared.
#   Die, and you lose what you found (except what's in your Save Sack).
#
# This file is only rules and numbers: dungeon.gd draws it on screen, and
# battle.gd asks it which enemies to fight. GameState.dungeon holds the one
# that's in progress. (Like Combatant, keeping rules apart from the screen
# makes both easier to follow and to test.)
class_name DungeonRun
extends RefCounted

const SIZE := 5  # The board is SIZE x SIZE squares.
const START := Vector2i(2, 2)  # The middle square.
const DECK_SIZE := 40  # Cards in the map deck.
const YOUR_SLOTS := 20  # How many of your own map cards fit in it.
const DANGER_PER_STRENGTH := 3  # Danger for each +1 enemy Strength (the Mapmaker adds more).
const KEY_CHANCE := 25  # % chance a fight drops a small key.
const BREAK_CHANCE := 40  # % chance that breaking a locked chest open works (no key needed, but loud).
# % chance a won fight drops an enchant / a potion, by card kind.
const ENCHANT_CHANCE := {RoomCard.Type.FIGHT: 35, RoomCard.Type.HARD_FIGHT: 60, RoomCard.Type.MINI_BOSS: 100}
const POTION_CHANCE := {RoomCard.Type.FIGHT: 25, RoomCard.Type.HARD_FIGHT: 35, RoomCard.Type.MINI_BOSS: 50}
const PACK_NAME := "Small Farm Booster Pack"  # The pack that "Pack" loot gives you (GameState.PACKS).
const CAMPFIRE_ART := preload("res://art/rooms/campfire.svg")
# The four squares next to a square: right, left, down, up.
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

var area: Area
# The FIRST TRIP to the Farm (the Innkeeper's Stone and Hops): a set board
# (the sheet's Guide rows) and tips as you go (dungeon.gd).
var guided := false
var floor_number := 1  # Each Go Deeper is one floor further down.
var deck: Array[RoomCard] = []  # The draw pile, top = the end.
var gone: Array[RoomCard] = []  # Used cards with Vanish: out of the deck for the rest of the run.
# Every square on the board: Vector2i -> a Dictionary describing it:
#   card:     RoomCard (null for the square you started this floor on)
#   revealed: flipped face up
#   cleared:  safe to walk over (Safe cards, beaten fights, used events...)
#   done:     used up (the loot is taken, the fight is won): Vanish cards leave
#   campfire: a lit campfire is here
#   opened:   a Locked Chest you've opened (or broken)
var rooms := {}
var position := START  # Where you are.
var came_from := START  # The square you stepped from.
var just_flipped := Vector2i(-1, -1)  # The card that flipped on your last step (dungeon.gd animates it).
var total_steps := 0  # Steps this whole run.
var keys := 0  # Small keys: each opens one Locked Chest.
var danger_points := 0  # From Unsafe cards and failed choices. See enemy_strength().

# What you've found, given to you when you Return to Town or beat the Boss.
var found_gold := 0
var found_packs := 0
var found_materials := {}  # Materials found this run: {"Green Ooze": 3}. Lost if you die (unless sacked).
var found_cards: Array[CardData] = []

# The SAVE SACK: what's in it survives if you die. Each slot holds one
# thing: {"kind": "pack"}, {"kind": "card", "card": CardData},
# {"kind": "gold", "amount": 5} (up to GameState.gold_stack() gold) or
# {"kind": "material", "name": "Green Ooze", "amount": 3} (a stack of the same size).
# Things move between the Found list and the sack (put_in_sack / take_out_of_sack).
var sack: Array[Dictionary] = []

# Enchants waiting to be put on a card. Each drop is a list of choices
# (usually 1; the Enchanter's upgrade makes it 2): pick one, then a card.
var enchant_drops: Array = []
var potions: Array[Potion] = []  # Potions you carry (drink them in a fight).
# Your flask (flask.gd), set by GameState.start_run(). It starts full.
var flask: Flask = null
var flask_stats := {}  # What it does this run (Flask.stats()).
var flask_charges := 0

var seen_events: Array[String] = []  # Events met this run (each one only once if there are enough).
var fights_won := 0
var result := ""  # "" while exploring, then "left", "won" or "died".
var history: Array[String] = []  # The expedition's log, newest last.

# The card you're fighting on right now (for battle.gd).
var fight_square := Vector2i(-1, -1)
var fight_enemies: Array[EnemyData] = []


# Making a DungeonRun doesn't deal anything yet (duels and the training
# make one just to hold their fight). GameState.start_run() calls start().
func _init(for_area: Area) -> void:
	area = for_area


# Build the map deck and deal the first board.
func start() -> void:
	guided = GameState.is_guided_run(area)
	if not guided:
		_build_deck()
	_deal()
	add_log("You set out for the %s." % area.display_name)


# --- The map deck --------------------------------------------------------------

# The place's base cards + your map cards (up to YOUR_SLOTS) + Filler up to
# DECK_SIZE, shuffled. Cards that need a Map or a quest are left out until
# you have them.
func _build_deck() -> void:
	deck.clear()
	var yours: Array[RoomCard] = []
	var filler: Array[RoomCard] = []
	for card in area.cards():
		if not GameState.is_room_unlocked(area, card) or _event_finished(card):
			continue
		for i in card.copies:
			match card.deck_part:
				RoomCard.DECK_BASE:
					if card.floor_from <= 1:
						deck.append(card)
				RoomCard.DECK_YOURS:
					yours.append(card)
				RoomCard.DECK_FILLER:
					filler.append(card)
	deck.append_array(yours.slice(0, YOUR_SLOTS))
	# Fill the empty slots, taking the Filler cards in turn.
	var next := 0
	while deck.size() < DECK_SIZE and not filler.is_empty():
		deck.append(filler[next % filler.size()])
		next += 1
	deck.shuffle()


# Cards that join the deck when you reach this floor ("Floor" in the sheet).
func _add_floor_cards() -> void:
	for card in area.cards():
		if card.deck_part == RoomCard.DECK_BASE and card.floor_from == floor_number \
				and GameState.is_room_unlocked(area, card):
			for i in card.copies:
				deck.append(card)


# A card whose event gives a blueprint you already have (the trapped
# Enchanter, once you've freed them) never comes back.
func _event_finished(card: RoomCard) -> bool:
	if card.event_name.is_empty():
		return false
	var event := GameState.find_event(card.event_name)
	if event == null:
		return false
	var names := event.blueprints()
	return not names.is_empty() and names.all(func(n: String) -> bool: return GameState.blueprints.has(n))


# The campfire hidden on every board (the sheet's Campfire row, or a plain one).
func campfire_card() -> RoomCard:
	for card in area.cards():
		if card.deck_part == RoomCard.DECK_CAMPFIRE:
			return card
	var card := RoomCard.new()
	card.room_name = "Campfire"
	card.type = RoomCard.Type.CAMPFIRE
	card.art = CAMPFIRE_ART
	return card


# The place's Boss card (null if it has none).
func boss_card() -> RoomCard:
	for card in area.cards():
		if card.deck_part == RoomCard.DECK_BOSS:
			return card
	return null


# Is the Boss on this floor's board?
func boss_here() -> bool:
	var boss := boss_card()
	return boss != null and not guided and floor_number >= boss.floor_from


# --- Dealing the board -----------------------------------------------------------

# Every square but the start, in reading order (left to right, top to bottom).
func board_squares() -> Array[Vector2i]:
	var squares: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if Vector2i(x, y) != START:
				squares.append(Vector2i(x, y))
	return squares


# Deal a fresh board, every card face down. The first trip deals its Guide
# cards in the sheet's order; otherwise it's 23 from the deck plus the
# campfire (and the Boss from its floor on), shuffled onto the squares.
func _deal() -> void:
	rooms.clear()
	var squares := board_squares()
	var cards: Array[RoomCard] = []
	if guided:
		for card in area.cards():
			if card.deck_part == RoomCard.DECK_GUIDE:
				cards.append(card)
	else:
		var fixed: Array[RoomCard] = [campfire_card()]
		if boss_here():
			fixed.append(boss_card())
		while cards.size() < squares.size() - fixed.size() and not deck.is_empty():
			cards.append(deck.pop_back())
		cards.append_array(fixed)
		cards.shuffle()
	for i in squares.size():
		if i < cards.size():
			rooms[squares[i]] = {"card": cards[i], "revealed": false, "cleared": false, "done": false,
				"campfire": cards[i].type == RoomCard.Type.CAMPFIRE, "opened": false}
		else:
			# The deck ran out: bare, trampled ground.
			rooms[squares[i]] = {"card": null, "revealed": true, "cleared": true, "done": true, "campfire": false, "opened": false}
	# Where you start. On Floor 1 it's the way back to town (a campfire);
	# deeper down it's the campfire you just used, burnt out.
	rooms[START] = {"card": null, "revealed": true, "cleared": true, "done": true,
		"campfire": floor_number == 1, "opened": false, "start": true}
	position = START
	came_from = START
	just_flipped = Vector2i(-1, -1)


# --- Moving ------------------------------------------------------------------

func in_grid(square: Vector2i) -> bool:
	return square.x >= 0 and square.y >= 0 and square.x < SIZE and square.y < SIZE


func is_revealed(square: Vector2i) -> bool:
	return rooms.has(square) and rooms[square].revealed


# Walkable without trouble: face up and cleared.
func is_safe(square: Vector2i) -> bool:
	return rooms.has(square) and rooms[square].revealed and rooms[square].cleared


# Every square you can step to from where you are, walking over safe squares
# only: square -> {"steps": how many steps, "from": the last safe square on
# the way}. You can step onto any card next to a safe square you can reach:
# a face-down one (it flips) or a face-up one. This is a "breadth-first
# search": find every square 1 step away, then every square 2 steps away,
# and so on. The board is tiny, so one search answers every square at once
# (the dungeon screen asks once per redraw).
func reachable() -> Dictionary:
	var found := {}
	var queue: Array[Vector2i] = [position]
	var seen := {position: 0}
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		for direction in DIRECTIONS:
			var next := here + direction
			if not in_grid(next) or seen.has(next):
				continue
			seen[next] = seen[here] + 1
			found[next] = {"steps": seen[next], "from": here}
			if is_safe(next):
				queue.append(next)  # Only walk ON over squares that are safe.
	return found


func can_move_to(square: Vector2i) -> bool:
	return result.is_empty() and reachable().has(square)


# Walk to a square (flipping it if it's face down). Returns what happened
# there, for the dungeon screen:
#   "walk"     onto a card you've already dealt with
#   "fight"    an Unsafe card: a fight (fight_enemies says who)
#   "chest"    a Locked Chest (a key, break it open, or leave it for later)
#   "treasure" loot, taken right away
#   "event"    an Explore card with choices (dungeon.gd shows them)
#   "campfire" Return to Town or Go Deeper
#   "empty"    a Safe card with nothing on it
#   ""         you can't go there
func move_to(square: Vector2i) -> String:
	var reach := reachable()
	if not reach.has(square) or not result.is_empty():
		return ""
	total_steps += reach[square].steps
	came_from = reach[square].from
	position = square
	just_flipped = Vector2i(-1, -1)
	if not rooms[square].revealed:
		_flip(square)
	return _enter(square)


# Turn a card face up. Unsafe cards raise danger the moment you find them.
func _flip(square: Vector2i) -> void:
	var room: Dictionary = rooms[square]
	room.revealed = true
	just_flipped = square
	var card: RoomCard = room.card
	add_log("You flip over: %s" % card.room_name)
	if card.tile == RoomCard.Tile.UNSAFE:
		raise_danger(1)


func _enter(square: Vector2i) -> String:
	var room: Dictionary = rooms[square]
	if room.campfire:
		room.cleared = true  # Campfires are safe to walk through.
		return "campfire"
	var card: RoomCard = room.card
	if card == null:
		return "walk"
	if card.is_fight():
		if room.cleared:
			return "walk"
		fight_square = square
		fight_enemies = card.pick_encounter()
		return "fight"
	match card.type:
		RoomCard.Type.LOCKED_CHEST:
			# You can walk past a chest you can't open yet, and come back with a key.
			room.cleared = true
			return "walk" if room.done else "chest"
		RoomCard.Type.EVENT:
			if room.done:
				return "walk"
			if not room.has("event"):
				room.event = GameState.find_event(card.event_name) if not card.event_name.is_empty() else pick_event()
			if room.event == null:
				room.cleared = true  # No events in the sheet: just an empty card.
				room.done = true
				return "empty"
			return "event"
		RoomCard.Type.TREASURE:
			if room.done:
				return "walk"
			room.cleared = true
			room.done = true
			add_log("Treasure! %s" % take_loot(card))
			return "treasure"
		RoomCard.Type.CAMPFIRE:
			return "walk"  # A campfire that's gone out.
	# Empty.
	room.cleared = true
	room.done = true
	return "empty" if square == just_flipped else "walk"


# --- Events -------------------------------------------------------------------

# A random event for this place and floor, preferring ones you haven't seen this run.
func pick_event() -> DungeonEvent:
	var fitting := GameState.load_events().filter(func(e: DungeonEvent) -> bool: return e.fits(area.display_name, floor_number))
	var fresh := fitting.filter(func(e: DungeonEvent) -> bool: return not seen_events.has(e.event_name))
	var pool := fresh if not fresh.is_empty() else fitting
	if pool.is_empty():
		return null
	var event: DungeonEvent = pool.pick_random()
	seen_events.append(event.event_name)
	return event


# Is this choice left out completely? (Enchants, before the Enchanter is built.)
func choice_hidden(event: DungeonEvent, index: int) -> bool:
	var words: Array[String] = []
	for effect in DungeonEvent.split_effects(event.effects[index]):
		words.append(effect.strip_edges().to_lower().get_slice(" ", 0))
	if words.has("enchant") and not GameState.enchants_open():
		return true
	# A choice that only buys a potion ("Pay 10; Potion") is hidden until the
	# Alchemist is built. If something else happens too (like the Toothy
	# Chest's gold), it stays; the Potion part just gives nothing.
	if words.has("potion") and not GameState.potions_open():
		return words.all(func(w: String) -> bool: return w == "potion" or w == "pay")
	return false


# Can you pick this choice? "" = yes, otherwise why not ("Needs 10 gold").
func choice_blocked(event: DungeonEvent, index: int) -> String:
	for effect in DungeonEvent.split_effects(event.effects[index]):
		var words := effect.split(" ", false)
		match words[0].to_lower():
			"pay":
				var cost := words[1].to_int() if words.size() > 1 else 0
				if found_gold < cost:
					return "Needs %d found gold (you have %d)" % [cost, found_gold]
			"use":  # "Use Key"
				if keys <= 0:
					return "You need a small key"
			"flask":
				if flask == null:
					return "You have no flask"
				if flask_charges >= flask_stats[Flask.CHARGES]:
					return "Your flask is already full"
	return ""


# Make a choice in the event where you're standing. Roll its Chance, do its
# effects, and finish the card. Returns {"text": what happened, "fight": true
# if it started a fight (fight_enemies is set)}.
func choose(index: int) -> Dictionary:
	var room: Dictionary = rooms[position]
	var event: DungeonEvent = room.event
	var worked := randi_range(1, 100) <= event.chances[index]
	var effect_text: String = event.effects[index] if worked else event.fail_effects[index]
	var story: String = event.results[index] if worked else event.fail_results[index]
	room.done = true
	room.cleared = true
	var outcome := apply_effects(DungeonEvent.split_effects(effect_text))
	add_log("%s: %s" % [event.event_name, event.choice_labels[index]] + (" (%s)" % ", ".join(outcome.lines) if not outcome.lines.is_empty() else ""))
	var text := story
	if not outcome.lines.is_empty():
		text += ("\n" if not text.is_empty() else "") + "\n".join(outcome.lines)
	if outcome.fight:
		room.cleared = false  # Blocks the way until you win.
		fight_square = position
	if outcome.come_back:
		room.done = false  # Not finished: step on it again to have another go.
	return {"text": text, "fight": outcome.fight, "blueprint": outcome.blueprint}


# Do a list of effects (see dungeon_event.gd). Returns {"lines": what happened, "fight": bool}.
func apply_effects(list: Array[String]) -> Dictionary:
	var lines: Array[String] = []
	var fight := false
	var come_back := false
	var blueprint := ""  # The building whose blueprint you got, if any.
	var max_hp := GameState.player_max_hp()
	for effect in list:
		var words := effect.split(" ", false)
		var word := words[0].to_lower()
		var number := words[-1].to_int() if words.size() > 1 else 0
		match word:
			"heal":
				var before := GameState.run_hp if GameState.run_hp > 0 else max_hp
				GameState.run_hp = mini(before + number, max_hp)
				lines.append("Healed %d (HP %d/%d)" % [GameState.run_hp - before, GameState.run_hp, max_hp])
			"lose":  # "Lose HP 4"
				var before := GameState.run_hp if GameState.run_hp > 0 else max_hp
				GameState.run_hp = maxi(before - number, 1)  # An event never kills you.
				lines.append("Lost %d HP (HP %d/%d)" % [before - GameState.run_hp, GameState.run_hp, max_hp])
			"pay":
				found_gold -= mini(number, found_gold)
				lines.append("Paid %d gold" % number)
			"flask":
				if flask:
					flask_charges = mini(flask_charges + 1, flask_stats[Flask.CHARGES])
					lines.append("Flask %d/%d" % [flask_charges, flask_stats[Flask.CHARGES]])
			"danger":
				raise_danger(number)
				lines.append("Danger +%d" % number)
			"calm":
				danger_points = 0
				lines.append("Danger back to 0")
			"use":  # "Use Key"
				keys = maxi(keys - 1, 0)
				lines.append("Used a small key (%d left)" % keys)
			"blueprint":  # Yours right away: rescuing someone isn't loot you can lose.
				blueprint = effect.substr(10).strip_edges()
				GameState.give_rewards("Blueprint " + blueprint)
				GameState.save_game()
				lines.append("Blueprint: %s! Build it back in town." % blueprint)
			"come":  # "Come Back"
				come_back = true  # (The event's Result text says so.)
			"fight":
				fight_enemies.clear()
				for enemy_name in effect.substr(5).split(",", false):
					var enemy := GameState.find_enemy(enemy_name.strip_edges())
					if enemy:
						fight_enemies.append(enemy)
					else:
						push_warning("events.csv: no enemy called '%s'" % enemy_name.strip_edges())
				fight = not fight_enemies.is_empty()
			_:
				# Everything else is a loot word, like a chest: Gold 5-10, Key, Potion...
				var loot_card := RoomCard.new()
				loot_card.loot = PackedStringArray([effect])
				lines.append("You get " + take_loot(loot_card))
	return {"lines": lines, "fight": fight, "come_back": come_back, "blueprint": blueprint}


# --- Danger ------------------------------------------------------------------

func raise_danger(amount: int) -> void:
	var strength_before := enemy_strength()
	danger_points += amount
	if enemy_strength() > strength_before:
		add_log("Danger %d! Every enemy now has +%d Strength." % [danger_points, enemy_strength()])


# Danger points (shown on the danger meter).
func danger() -> int:
	return danger_points


func danger_per_strength() -> int:
	return DANGER_PER_STRENGTH + GameState.town_bonus(TownBuilding.DANGER_STEPS)


# The Strength every enemy gets: +1 for every danger_per_strength() danger.
func enemy_strength() -> int:
	return danger_points / danger_per_strength()


# How much more danger until enemies get stronger again.
func danger_to_next() -> int:
	return danger_per_strength() - danger_points % danger_per_strength()


# --- Cards -------------------------------------------------------------------

# The fight in fight_square was won. Returns "won" for the Boss, or "".
func win_fight() -> String:
	fights_won += 1
	if not rooms.has(fight_square):
		return ""  # A fight that isn't on the board (a duel, or the battle scene run on its own with F6).
	var room: Dictionary = rooms[fight_square]
	var card: RoomCard = room.card
	room.cleared = true  # Safe now, until it's shuffled back in.
	room.done = true
	if card == null:
		return ""
	GameState.record_for_quest(Quest.CLEAR_ROOM, card.room_name)
	if not card.loot.is_empty() and card.is_fight():
		add_log("Reward: %s" % take_loot(card))
	if randi_range(1, 100) <= KEY_CHANCE:
		keys += 1
		add_log("You found a small key!")
	if GameState.enchants_open() and randi_range(1, 100) <= ENCHANT_CHANCE.get(card.type, 0):
		add_log("An enchant! %s" % _drop_enchant())
	if GameState.potions_open() and randi_range(1, 100) <= POTION_CHANCE.get(card.type, 0):
		add_log("A potion! %s" % _drop_potion())
	if card.type == RoomCard.Type.BOSS:
		result = "won"
		add_log("You beat the boss! The %s is cleared." % area.display_name)
		return "won"
	return ""


# Open a Locked Chest with a small key. Returns what was inside ("" = you can't).
func open_chest(square: Vector2i) -> String:
	var room: Dictionary = rooms[square]
	if keys <= 0 or room.done:
		return ""
	keys -= 1
	room.opened = true
	room.done = true
	var text := take_loot(room.card)
	add_log("You unlock %s: %s" % [room.card.room_name, text])
	return text


# Break a Locked Chest open: no key needed, but it's loud. BREAK_CHANCE % it
# works. If it doesn't, danger goes up and the chest is ruined (its loot is
# lost). Returns {"worked": bool, "text": what happened}.
func break_chest(square: Vector2i) -> Dictionary:
	var room: Dictionary = rooms[square]
	if room.done:
		return {"worked": false, "text": ""}
	room.done = true
	room.opened = true
	if randi_range(1, 100) <= BREAK_CHANCE:
		var text := take_loot(room.card)
		add_log("You smash %s open: %s" % [room.card.room_name, text])
		return {"worked": true, "text": text}
	room.ruined = true
	raise_danger(1)
	add_log("CRASH! %s falls apart, and everything inside is ruined. Danger +1." % room.card.room_name)
	return {"worked": false, "text": "The lock holds... then the whole thing collapses. Whatever was inside is ruined, and that was LOUD (Danger +1)."}


# --- The campfire ---------------------------------------------------------------

# Can the campfire you're standing at take you deeper? (The start of Floor 1
# is the way into town, and the first trip only goes home.)
func can_go_deeper() -> bool:
	return not guided and rooms.has(position) and not rooms[position].get("start", false)


# GO DEEPER: every card on the board goes back into the deck (used Vanish
# cards are gone for the run instead), the next floor's cards are shuffled
# in, and a fresh board is dealt. You start on this campfire, now burnt out:
# a new one is hidden somewhere on the new board.
# (No healing for now: Camper perks will add that later.)
func go_deeper() -> void:
	for square: Vector2i in rooms:
		var room: Dictionary = rooms[square]
		var card: RoomCard = room.card
		if card == null or card.deck_part in [RoomCard.DECK_CAMPFIRE, RoomCard.DECK_BOSS, RoomCard.DECK_GUIDE]:
			continue  # The campfire and the Boss are dealt fresh each floor.
		if card.vanish and room.done:
			gone.append(card)
			continue
		deck.append(card)
	floor_number += 1
	_add_floor_cards()
	deck.shuffle()
	_deal()
	GameState.record_for_quest(Quest.REACH_TIER, "", floor_number)
	add_log("Floor %d! The cards are shuffled and dealt again. Find the next campfire!" % floor_number)
	if boss_here():
		add_log("The %s is somewhere on this board..." % boss_card().room_name)


# Leave (at a campfire): keep what you found.
func leave() -> void:
	result = "left"
	add_log("You head back to town.")


# You lose what you found, but keep what's in the Save Sack. Returns what
# the sack saved, as text ("nothing" if it was empty).
func die() -> String:
	result = "died"
	found_gold = 0
	found_packs = 0
	found_cards.clear()
	found_materials.clear()
	_empty_sack()  # The sack's contents become the only thing "found"...
	var saved := loot_text()
	claim_loot()  # ...and you take them home.
	add_log("You were defeated. Your Save Sack kept: %s." % saved if GameState.sack_open() else "You were defeated, and lost what you found.")
	return saved


# --- The deck list ------------------------------------------------------------------

# What's still out there: one entry per card name, with how many you
# haven't seen yet (face down on the board, or still in the draw pile) and
# how many there are in all. For the dungeon screen's "Map Deck" list.
#   [{"card": RoomCard, "unseen": 1, "total": 2}, ...] Safe first, then Explore, then Unsafe.
func deck_summary() -> Array[Dictionary]:
	var by_name := {}
	var add := func(card: RoomCard, unseen: bool) -> void:
		if not by_name.has(card.room_name):
			by_name[card.room_name] = {"card": card, "unseen": 0, "total": 0}
		by_name[card.room_name].total += 1
		if unseen:
			by_name[card.room_name].unseen += 1
	for card in deck:
		add.call(card, true)
	for square: Vector2i in rooms:
		var card: RoomCard = rooms[square].card
		if card != null:
			add.call(card, not rooms[square].revealed)
	var order := {RoomCard.Tile.SAFE: 0, RoomCard.Tile.EXPLORE: 1, RoomCard.Tile.UNSAFE: 2}
	var list: Array[Dictionary] = []
	list.assign(by_name.values())
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.card.tile != b.card.tile:
			return order[a.card.tile] < order[b.card.tile]
		return a.card.room_name < b.card.room_name)
	return list


# How many cards are still face down on the board.
func face_down_count() -> int:
	return rooms.values().filter(func(room: Dictionary) -> bool: return not room.revealed).size()


# --- Loot ----------------------------------------------------------------------

# Rock Hound talents: a % chance for 1 extra of a material you pick up.
func _material_find_bonus() -> int:
	if GameState.character_class == null:
		return 0
	return GameState.talent_bonus(GameState.character_class, Talent.MATERIAL_FIND_CHANCE)


# Pick one of the card's loot entries and add it to what you've found.
# Returns what you got, as text: "12 gold", "a card: Strike", "a Map!"...
func take_loot(card: RoomCard) -> String:
	if card == null or card.loot.is_empty():
		return "nothing"
	# No enchants until the Enchanter is built, no potions until the Alchemist.
	var entries := Array(card.loot).filter(func(e: String) -> bool:
		var word := e.strip_edges().to_lower()
		if word.begins_with("enchant"):
			return GameState.enchants_open()
		if word.begins_with("potion"):
			return GameState.potions_open()
		return true)
	if entries.is_empty():
		return "nothing"
	var entry: String = entries.pick_random()
	var words := entry.strip_edges().split(" ", false)
	match words[0].to_lower():
		"gold":
			# "Gold 5-10" or "Gold 8".
			var amounts := words[1].split("-") if words.size() > 1 else PackedStringArray(["5"])
			var amount := randi_range(amounts[0].to_int(), amounts[-1].to_int())
			found_gold += amount
			return "%d gold" % amount
		"card":
			var found := GameState._pick_pack_card()
			if found == null:
				return "nothing"
			found_cards.append(found)
			return "a card: %s" % found.card_name
		"pack":
			found_packs += 1
			return "a %s" % PACK_NAME
		"key":
			keys += 1
			return "a small key"
		"enchant":
			return "an enchant: " + _drop_enchant()
		"potion":
			return _drop_potion()
		"map":
			var room := GameState.unlock_random_room(area)
			if room == null:
				found_gold += 5  # Every card is already unlocked.
				return "an old map of places you know (5 gold instead)"
			return "a Map! A new map card for the %s: %s" % [area.display_name, room.room_name]
	# A material: "Stone 2", "Stone 1-3" or "Green Ooze 2" (the name can have spaces).
	var last := words[-1].split("-")
	var material_name := " ".join(words.slice(0, -1)) if words.size() > 1 and last[0].is_valid_int() else entry.strip_edges()
	if GameState.find_material(material_name):
		var amount := randi_range(last[0].to_int(), last[-1].to_int()) if words.size() > 1 and last[0].is_valid_int() else 1
		if not guided and randi_range(1, 100) <= _material_find_bonus():
			amount += 1  # Rock Hound: a sharp eye for good finds.
		add_found_material(material_name, amount)
		return "%d %s" % [amount, material_name]
	return entry


func _drop_enchant() -> String:
	var choices := GameState.roll_enchant_choices()
	if choices.is_empty():
		return "nothing"
	enchant_drops.append(choices)
	var names: Array[String] = []
	for enchant in choices:
		names.append(enchant.enchant_name)
	return " or ".join(names) + " (put it on a card from the dungeon screen)"


func _drop_potion() -> String:
	var potion := GameState.roll_dropped_potion()  # Only unlocked potions, with your upgrades.
	if potion == null:
		return "nothing"
	if add_potion(potion):
		return potion.potion_name
	return "%s, but your potion slots are full, so you leave it" % potion.potion_name


func add_potion(potion: Potion) -> bool:
	if potions.size() >= GameState.potion_slots():
		return false
	potions.append(potion)
	return true


# --- The Save Sack ---------------------------------------------------------------

# Move one thing from Found into a free sack slot: kind is "pack", "gold"
# or "card" (with which card). Gold fills the slot up to the gold stack.
func put_in_sack(kind: String, card: CardData = null, material_name: String = "") -> bool:
	if sack.size() >= GameState.sack_slots():
		return false
	match kind:
		"pack":
			if found_packs <= 0:
				return false
			found_packs -= 1
			sack.append({"kind": "pack"})
		"gold":
			var amount := mini(found_gold, GameState.gold_stack())
			if amount <= 0:
				return false
			found_gold -= amount
			sack.append({"kind": "gold", "amount": amount})
		"card":
			if not found_cards.has(card):
				return false
			found_cards.erase(card)
			sack.append({"kind": "card", "card": card})
		"material":
			var amount := mini(found_materials.get(material_name, 0), GameState.gold_stack())
			if amount <= 0:
				return false
			add_found_material(material_name, -amount)
			sack.append({"kind": "material", "name": material_name, "amount": amount})
		_:
			return false
	return true


# Move a sack slot's contents back into Found.
func take_out_of_sack(slot: int) -> void:
	if slot < 0 or slot >= sack.size():
		return
	var item: Dictionary = sack[slot]
	sack.remove_at(slot)
	match item.kind:
		"pack": found_packs += 1
		"gold": found_gold += item.amount
		"card": found_cards.append(item.card)
		"material": add_found_material(item.name, item.amount)


static func sack_item_text(item: Dictionary) -> String:
	match item.kind:
		"pack": return "Pack"
		"gold": return "%d gold" % item.amount
		"card": return item.card.card_name
		"material": return "%d %s" % [item.amount, item.name]
	return "?"


# Add (or, with a minus amount, take away) found materials.
func add_found_material(material_name: String, amount: int) -> void:
	var total: int = found_materials.get(material_name, 0) + amount
	if total > 0:
		found_materials[material_name] = total
	else:
		found_materials.erase(material_name)


func _empty_sack() -> void:
	while not sack.is_empty():
		take_out_of_sack(0)


# Give the player everything found (after Returning to Town or beating the Boss).
func claim_loot() -> void:
	_empty_sack()
	GameState.gold += found_gold
	GameState.run_gold += found_gold
	if found_packs > 0:
		GameState.add_packs(PACK_NAME, found_packs)
	for card in found_cards:
		GameState.add_card(card)
	for material_name in found_materials:
		GameState.add_material(material_name, found_materials[material_name])
	GameState.save_game()


# How much of a material you have this run: Found plus what's in the Save Sack.
func material_total(material_name: String) -> int:
	var total: int = found_materials.get(material_name, 0)
	for item in sack:
		if item.get("kind", "") == "material" and item.get("name", "") == material_name:
			total += int(item.get("amount", 0))
	return total


# What your quests want you to bring home: {"Stone": 5, "Hops": 3}.
func guide_needs() -> Dictionary:
	return GameState.guide_needs()


# Do you have it all (counting what's already in the Bank)?
func guide_goal_met() -> bool:
	var needs := guide_needs()
	for material_name in needs:
		if material_total(material_name) + GameState.material_count(material_name) < needs[material_name]:
			return false
	return true


# The HUNTING LIST: "Stone 3/5   Hops 0/3" (Bank + found so far), or "" if
# no quest needs anything.
func hunting_text() -> String:
	var parts: Array[String] = []
	var needs := guide_needs()
	for material_name in needs:
		var have := mini(material_total(material_name) + GameState.material_count(material_name), needs[material_name])
		parts.append("%s %d/%d%s" % [material_name, have, needs[material_name], " ✓" if have >= needs[material_name] else ""])
	return "   ".join(parts)


# "23 gold, 1 pack, 2 cards" (or "nothing").
func loot_text() -> String:
	var parts: Array[String] = []
	if found_gold > 0:
		parts.append("%d gold" % found_gold)
	if found_packs > 0:
		parts.append("%d pack%s" % [found_packs, "s" if found_packs > 1 else ""])
	if not found_cards.is_empty():
		parts.append("%d card%s" % [found_cards.size(), "s" if found_cards.size() > 1 else ""])
	for material_name in found_materials:
		parts.append("%d %s" % [found_materials[material_name], material_name])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


# Take one sip of your flask: uses a charge (unless the Save Chance comes
# up) and rolls the heal. Battle and the dungeon screen both use this, then
# do the healing / Energy themselves (they keep HP in different places).
# Returns {} if it's empty, else {"roll": 2, "heal": 3, "energy": 0, "kept": false}.
func sip_flask() -> Dictionary:
	if flask == null or flask_charges <= 0:
		return {}
	var sip := {"roll": 0, "heal": 0, "energy": flask_stats[Flask.ENERGY], "kept": false}
	if flask_stats[Flask.HEAL_DIE] > 0:
		sip.roll = randi_range(1, flask_stats[Flask.HEAL_DIE])
		sip.heal = sip.roll + flask_stats[Flask.ROLL_BONUS]
	sip.kept = flask_stats[Flask.SAVE_CHANCE] > 0 and randi_range(1, 100) <= flask_stats[Flask.SAVE_CHANCE]
	if not sip.kept:
		flask_charges -= 1
	return sip


# Can you drink it on the dungeon map? Only if it heals (Energy is for fights).
func can_sip_on_map() -> bool:
	return flask != null and flask_charges > 0 and flask_stats[Flask.HEAL_DIE] > 0 and result.is_empty()


func add_log(line: String) -> void:
	history.append(line)
