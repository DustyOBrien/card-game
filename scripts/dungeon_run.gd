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
#   6. TORCHES (scouting). Light a face-down card anywhere on the board to
#      see what it is before you step on it. Then the torch makes a BURNOUT
#      roll on a d4: 2+ to keep burning, then 3+, then 4+, and the 4th time
#      it always burns out. So a torch scouts 1 to 4 cards (about 2.2).
#   7. SCAVENGING (push your luck). Some Safe cards (walls, fields, hay) can
#      be scavenged. The first try always works. Then roll a d6: 3+, 4+, 5+,
#      6+. Each success raises your LUCK for that spot, and Luck picks the
#      loot table: Luck 0-1 Common, 2 Uncommon, 3+ Rare (about an 11%
#      chance to get that far). A fail ends scavenging there and Danger +1.
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
# DANGER: every DANGER_PER_CARD danger shuffles a bad Danger card into the
# map deck (and swaps one onto the board). Every second time, enemies also
# get +1 Strength. The Mapmaker makes both come slower.
const DANGER_PER_CARD := 3
const DANGER_CARDS_PER_STRENGTH := 2  # So enemies get +1 Strength every 6 danger.
# The BACKPACK: materials and torches take space, gold, cards, packs and keys
# don't. Each slot holds a stack of up to BACKPACK_STACK of the same thing.
# The Tailor sews on more slots.
const BACKPACK_SLOTS := 6
const BACKPACK_STACK := 5
const TORCH := "Torch"  # The backpack's name for your torches.
# TOOLS you drag onto cards (interaction.gd). They take backpack space too.
const CROWBAR := "Crowbar"
const BOMB := "Bomb"
const TOOLS := [CROWBAR, BOMB]
const KEY_CHANCE := 25  # % chance a fight drops a small key.
const BREAK_CHANCE := 40  # % chance that breaking a locked chest open works (no key needed, but loud).
# % chance a won fight drops an enchant / a potion, by card kind.
const ENCHANT_CHANCE := {RoomCard.Type.FIGHT: 35, RoomCard.Type.HARD_FIGHT: 60, RoomCard.Type.MINI_BOSS: 100}
# BOSS PACKS (card doc: bosses and mini bosses drop packs): every Boss and
# Mini Boss drops one of these on top of its own loot...
const BOSS_PACKS := {RoomCard.Type.MINI_BOSS: "Small", RoomCard.Type.BOSS: "Medium"}
# ...and has this % chance of a PLAN (crafts a Rare or Legendary from this
# place's binder). Low on purpose until Hard Mode exists (card doc).
const PLAN_CHANCE := {RoomCard.Type.MINI_BOSS: 3, RoomCard.Type.BOSS: 10}
const POTION_CHANCE := {RoomCard.Type.FIGHT: 25, RoomCard.Type.HARD_FIGHT: 35, RoomCard.Type.MINI_BOSS: 50}
# Torches: how many you set out with, and the burnout roll (a d4) each time
# the lit torch scouts a card: 2+ the 1st time, 3+ the 2nd... 5+ = always out.
const STARTING_TORCHES := 2
const TORCH_DIE := 4
const TORCH_TARGETS: Array[int] = [2, 3, 4, 5]
# Scavenging: the d6 roll for each try at one spot. 0 = always works (the
# first try). After the last one, the spot is picked clean.
const SCAVENGE_DIE := 6
const SCAVENGE_TARGETS: Array[int] = [0, 3, 4, 5, 6]
const LUCK_NAMES := ["Common", "Common", "Uncommon", "Rare"]  # Luck 3 and up = Rare.
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
#   scouted:  lit by a torch: you can see its face, but it hasn't flipped yet
#   scavenges: how many times you've scavenged it (its Luck = this - 1)
var rooms := {}
var position := START  # Where you are.
var came_from := START  # The square you stepped from.
var just_flipped := Vector2i(-1, -1)  # The card that flipped on your last step (dungeon.gd animates it).
var total_steps := 0  # Steps this whole run.
var keys := 0  # Small keys: each opens one Locked Chest.
var danger_points := 0  # From Unsafe cards and failed choices. See enemy_strength().
var torches := 0  # Torches in your pack (the lit one counts until it burns out).
var torch_uses := 0  # Cards the lit torch has scouted so far.
var tools := {}  # Crowbars and bombs you carry: {"Crowbar": 1}.
var roamer_square := Vector2i(-1, -1)  # Where the roaming mini boss is (face down), or (-1, -1).
var roamer_beaten := false  # Beaten this trip: it doesn't come back.
var last_roamer_news := ""  # "You hear stomping nearby..." (dungeon.gd shows it once).

# What you've found, given to you when you Return to Town or beat the Boss.
var found_gold := 0
var found_packs := 0
# Bigger packs from bosses and mini bosses: {"Medium Farm Booster Pack": 1}.
# Like everything found, lost if you die (they can't go in the Save Sack).
var found_boss_packs := {}
var found_plans: Array[String] = []  # Plans from bosses (card names). Lost if you die too.
var found_materials := {}  # Materials found this run: {"Green Ooze": 3}. Lost if you die (unless sacked). In the backpack.
# Things that didn't fit in the backpack: {"Hay": 2}. dungeon.gd asks what to
# drop to make room, or leaves them behind (leave_behind()).
var left_over := {}
var danger_cards_added := 0  # Danger cards shuffled in so far this run.
var last_danger_card: RoomCard = null  # The newest one (dungeon.gd shows it), null once shown.
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
var cards_flipped := 0  # For the place's Exp at the end of the trip.
var area_exp_result := {}  # What the trip gave the place (award_area_exp()), for the end screens.
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
	torches = STARTING_TORCHES if guided else GameState.packed_torches  # Packed on the Prepare screen.
	if not guided:
		_build_deck()
		keys += GameState.area_perk_total(area, AreaPerk.START_KEY)  # Starter Kit perks.
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
					if not GameState.is_map_card_off(area, card):  # Left out on the Prepare screen.
						yours.append(card)
				RoomCard.DECK_FILLER:
					filler.append(card)
	deck.append_array(yours.slice(0, YOUR_SLOTS))
	# Fill the empty slots, taking the Filler cards in turn.
	var next := 0
	while deck.size() < DECK_SIZE and not filler.is_empty():
		deck.append(filler[next % filler.size()])
		next += 1
	_swap_perk_cards()
	deck.shuffle()


# Farm perks like Clear the Weeds: some copies of a bad card become a better
# one (a Deck "Perk" row in the sheet).
func _swap_perk_cards() -> void:
	for perk in GameState.owned_area_perks(area):
		if perk.effect != AreaPerk.SWAP_CARD:
			continue
		var better: RoomCard = null
		for card in area.cards():
			if card.room_name == perk.into:
				better = card
		if better == null:
			push_warning("%s: no map card called '%s' to swap in" % [perk.perk_name, perk.into])
			continue
		var left := perk.amount
		for i in deck.size():
			if left > 0 and deck[i].room_name == perk.target:
				deck[i] = better
				left -= 1


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
	if not guided:
		_deal_guards()
		_deal_roamer()
	position = START
	came_from = START
	just_flipped = Vector2i(-1, -1)


# GUARDS: a card with a Guards column (the Guarded Hoard) gets its guards
# dealt on up to 2 of the squares next to it.
func _deal_guards() -> void:
	for square: Vector2i in rooms.keys():
		var card: RoomCard = rooms[square].card
		if card == null or card.guards.is_empty():
			continue
		var guard := find_card(card.guards)
		if guard == null:
			push_warning("%s: no map card called '%s' to guard it" % [card.room_name, card.guards])
			continue
		var spots: Array[Vector2i] = []
		for direction in DIRECTIONS:
			var next := square + direction
			if rooms.has(next) and rooms[next].card != null and not rooms[next].campfire \
					and rooms[next].card.deck_part not in [RoomCard.DECK_BOSS, RoomCard.DECK_LINKED] \
					and rooms[next].card.guards.is_empty():
				spots.append(next)
		spots.shuffle()
		for next in spots.slice(0, RoomCard.GUARD_COUNT):
			if _returns_to_deck(rooms[next].card):
				deck.append(rooms[next].card)
			rooms[next].card = guard
	deck.shuffle()


# Are any of this card's guards still standing next to it?
func guards_standing(square: Vector2i) -> int:
	var card: RoomCard = rooms[square].card
	if card == null or card.guards.is_empty():
		return 0
	var count := 0
	for direction in DIRECTIONS:
		var next := square + direction
		if rooms.has(next) and rooms[next].card != null and rooms[next].card.room_name == card.guards and not rooms[next].cleared:
			count += 1
	return count


# THE ROAMER: from its Floor on, the place's Roamer card (a mini boss) is
# dealt face down. Every step you take, it moves to a face-down square next
# to it (see _roam()). Flip it and you fight it. Beat it and it's gone.
func roamer_card() -> RoomCard:
	for card in area.cards():
		if card.deck_part == RoomCard.DECK_ROAMER:
			return card
	return null


func _deal_roamer() -> void:
	roamer_square = Vector2i(-1, -1)
	var roamer := roamer_card()
	if roamer == null or roamer_beaten or floor_number < roamer.floor_from:
		return
	roamer_square = _swap_onto_board(roamer)
	if roamer_square.x >= 0:
		add_log("Heavy footsteps... the %s roams this floor." % roamer.room_name)


func roamer_here() -> bool:
	return roamer_square.x >= 0 and rooms.has(roamer_square) and not rooms[roamer_square].revealed


# After each of your steps: the roamer moves to a face-down square next to
# it (if there is one). Its whole square swaps with that one, so a scouted
# roamer stays scouted: a torch lets you track it.
func _roam() -> void:
	if not roamer_here():
		return
	var spots: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var next := roamer_square + direction
		if rooms.has(next) and not rooms[next].revealed and rooms[next].card != null and not rooms[next].campfire \
				and rooms[next].card.deck_part not in [RoomCard.DECK_BOSS, RoomCard.DECK_LINKED]:
			spots.append(next)
	if spots.is_empty():
		return
	var next: Vector2i = spots.pick_random()
	var moved: Dictionary = rooms[roamer_square]
	rooms[roamer_square] = rooms[next]
	rooms[next] = moved
	roamer_square = next
	if (roamer_square - position).abs().x + (roamer_square - position).abs().y == 1:
		last_roamer_news = "Something heavy stomps right next to you..."
		add_log(last_roamer_news)


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
#   "guarded"  treasure with its guards still standing next to it
#   "scavenge" a card you can scavenge (dungeon.gd offers it)
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
	var what := _enter(square)
	if square == roamer_square:
		roamer_square = Vector2i(-1, -1)  # Found it: now it's a fight, not a roamer.
	else:
		_roam()
	return what


# Turn a card face up. Unsafe cards raise danger the moment you find them.
func _flip(square: Vector2i) -> void:
	var room: Dictionary = rooms[square]
	room.revealed = true
	cards_flipped += 1
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
			if guards_standing(square) > 0:
				return "guarded"  # Beat the guards next to it first.
			room.done = true
			add_log("Treasure! %s" % take_loot(card))
			return "treasure"
		RoomCard.Type.CAMPFIRE:
			return "walk"  # A campfire that's gone out.
	# Empty.
	room.cleared = true
	if can_scavenge(square):
		return "scavenge" if square == just_flipped else "walk"
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
			"use":  # "Use Key" / "Use Torch"
				if words.size() > 1 and words[1].to_lower() == "torch":
					if torches <= 0:
						return "You need a torch"
				elif keys <= 0:
					return "You need a small key"
			"drop":  # "Drop 3": throw away supplies from your backpack.
				if found_materials.is_empty():
					return "Your backpack has no supplies to throw in"
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
func apply_effects(list: Array[String], at: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if at.x < 0:
		at = position  # Events happen where you stand; tools on the card you used them on.
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
			"drop":  # "Drop 3": that many supplies, picked at random from your backpack.
				var dropped := {}
				for i in number:
					if found_materials.is_empty():
						break
					var material_name: String = found_materials.keys().pick_random()
					add_found_material(material_name, -1)
					dropped[material_name] = dropped.get(material_name, 0) + 1
				lines.append("Lost " + (MaterialInfo.costs_text(dropped) if not dropped.is_empty() else "nothing"))
			"use":  # "Use Key" / "Use Torch"
				if words.size() > 1 and words[1].to_lower() == "torch":
					torches = maxi(torches - 1, 0)
					torch_uses = 0
					lines.append("Used a torch (%d left)" % torches)
				else:
					keys = maxi(keys - 1, 0)
					lines.append("Used a small key (%d left)" % keys)
			"blueprint":  # Yours right away: rescuing someone isn't loot you can lose.
				blueprint = effect.substr(10).strip_edges()
				GameState.give_rewards("Blueprint " + blueprint)
				GameState.save_game()
				lines.append("Blueprint: %s! Build it back in town." % blueprint)
			"come":  # "Come Back"
				come_back = true  # (The event's Result text says so.)
			"open":  # A tool opened it like a chest.
				var opened: Dictionary = rooms[at]
				opened.opened = true
				opened.done = true
				opened.cleared = true
				lines.append("Inside: " + take_loot(opened.card))
			"clear":  # A tool dealt with a fight card: no fight.
				rooms[at].cleared = true
				rooms[at].done = true
				GameState.record_for_quest(Quest.CLEAR_ROOM, rooms[at].card.room_name)
				lines.append("%s: dealt with" % rooms[at].card.room_name)
			"destroy":
				rooms[at].done = true
				rooms[at].cleared = true
				rooms[at].ruined = true
				lines.append("%s is ruined" % rooms[at].card.room_name)
			"secret":  # The card becomes the place's Secret card, face up.
				var secret: RoomCard = null
				for card in area.cards():
					if card.deck_part == RoomCard.DECK_SECRET:
						secret = card
				if secret:
					rooms[at] = {"card": secret, "revealed": true, "cleared": true, "done": false,
						"campfire": false, "opened": false}
					lines.append("Found: %s!" % secret.room_name)
			"add":  # "Add Sealed Vault": a card joins the board, face down.
				var added := find_card(effect.substr(4).strip_edges())
				if added:
					var where := _swap_onto_board(added)
					lines.append("%s is somewhere on the board now" % added.room_name if where.x >= 0 \
						else "%s is shuffled into the map deck" % added.room_name)
				else:
					push_warning("No map card called '%s' to add" % effect.substr(4))
			"fight":
				fight_enemies.clear()
				for enemy_name in effect.substr(5).split(",", false):
					var enemy := GameState.find_enemy(enemy_name.strip_edges())
					if enemy:
						fight_enemies.append(enemy)
					else:
						push_warning("events.csv: no enemy called '%s'" % enemy_name.strip_edges())
				fight = not fight_enemies.is_empty()
				if fight:
					fight_square = at
			_:
				# Everything else is a loot word, like a chest: Gold 5-10, Key, Potion...
				# "Pack | Card | Potion" = one of them, picked at random.
				var loot_card := RoomCard.new()
				loot_card.loot = CardImporter._parse_list(effect.replace("|", ","))
				lines.append("You get " + take_loot(loot_card))
	return {"lines": lines, "fight": fight, "come_back": come_back, "blueprint": blueprint}


# --- Tools and hidden interactions ------------------------------------------------
# Drag a tool (Crowbar, Bomb, Torch) onto a face-up card next to you (or
# under you). interactions.csv says what happens. See interaction.gd.

# The tool tricks this card has (the card shows how many).
func tricks_on(square: Vector2i) -> Array[Interaction]:
	if not rooms.has(square) or rooms[square].card == null:
		return []
	return Interaction.for_card(rooms[square].card.room_name)


# Can you use this tool on this square now?
func can_use_tool(tool_name: String, square: Vector2i) -> bool:
	return why_not_tool(tool_name, square).is_empty()


# Why not ("" = you can).
func why_not_tool(tool_name: String, square: Vector2i) -> String:
	if not result.is_empty():
		return "The trip is over"
	if guided:
		return "Not on your first trip"
	if carried(tool_name) <= 0:
		return "You have no %s" % tool_name.to_lower()
	if not rooms.has(square) or not rooms[square].revealed or rooms[square].card == null or rooms[square].campfire:
		return "Use tools on face-up cards"
	var distance := (square - position).abs()
	if distance.x + distance.y > 1:
		return "Get next to it first"
	if rooms[square].get("tried", []).has(tool_name):
		return "You already tried your %s here" % tool_name.to_lower()
	var trick := Interaction.find(rooms[square].card.room_name, tool_name)
	if trick and trick.effect.to_lower().begins_with("open") and rooms[square].done:
		return "It's already open"
	return ""


# Use a tool on a card. Returns {"found": false} when nothing happens (the
# tool isn't used up), or {"found": true, "worked", "text", "fight", "new"
# (first time you found this trick), "used" (the tool is gone)}.
func use_tool(tool_name: String, square: Vector2i) -> Dictionary:
	if not can_use_tool(tool_name, square):
		return {}
	var room: Dictionary = rooms[square]
	var tried: Array = room.get("tried", [])
	tried.append(tool_name)
	room.tried = tried
	var card: RoomCard = room.card
	var trick := Interaction.find(card.room_name, tool_name)
	if trick == null:
		add_log("You try your %s on the %s. Nothing happens." % [tool_name.to_lower(), card.room_name])
		return {"found": false, "text": "Nothing happens. (Your %s is fine.)" % tool_name.to_lower()}
	var is_new := not GameState.journal.has(trick.key())
	if is_new:
		GameState.journal.append(trick.key())
		GameState.save_game()
	var worked := randi_range(1, 100) <= trick.chance
	var used := trick.used_up == Interaction.ALWAYS or (trick.used_up == Interaction.ON_FAIL and not worked)
	if used:
		if tool_name == TORCH:
			torches -= 1
			torch_uses = 0
		else:
			_add_tool(tool_name, -1)
	var outcome := apply_effects(DungeonEvent.split_effects(trick.effect if worked else trick.fail_effect), square)
	var text: String = trick.result if worked else trick.fail_result
	if not outcome.lines.is_empty():
		text += ("\n" if not text.is_empty() else "") + "\n".join(outcome.lines)
	if outcome.fight:
		rooms[square].cleared = false
		rooms[square].done = false
	add_log("%s on the %s: %s" % [tool_name, card.room_name, ", ".join(outcome.lines) if not outcome.lines.is_empty() else ("it worked" if worked else "it didn't work")])
	return {"found": true, "worked": worked, "text": text, "fight": outcome.fight, "new": is_new, "used": used}


# Treasure you're standing on that you couldn't take when you got here (its
# guards were still up), or that a tool just turned up under you.
func can_take_treasure(square: Vector2i) -> bool:
	if not result.is_empty() or not rooms.has(square):
		return false
	var room: Dictionary = rooms[square]
	return room.revealed and room.card != null and room.card.type == RoomCard.Type.TREASURE \
		and not room.done and guards_standing(square) == 0


# Take it. Returns what you got ("" = you can't).
func take_treasure(square: Vector2i) -> String:
	if not can_take_treasure(square):
		return ""
	var room: Dictionary = rooms[square]
	room.done = true
	room.cleared = true
	var text := take_loot(room.card)
	add_log("Treasure! %s" % text)
	return text


# --- Torches -----------------------------------------------------------------

# TORCH SWAP: a card your torch showed you (still face down) can go back into
# the map deck, and a new face-down card is drawn in its place. Shuffling
# cards around is noisy: Danger +1 (TORCH_SWAP_DANGER).
const TORCH_SWAP_DANGER := 1

func can_swap_scouted(square: Vector2i) -> bool:
	if guided or not result.is_empty() or not rooms.has(square) or deck.is_empty():
		return false
	var room: Dictionary = rooms[square]
	return not room.revealed and room.get("scouted", false) and _returns_to_deck(room.card) \
		and not room.campfire and square != roamer_square


# Swap it. Returns the new card (face down, not scouted), or null.
func swap_scouted(square: Vector2i) -> RoomCard:
	if not can_swap_scouted(square):
		return null
	var old: RoomCard = rooms[square].card
	var new_card: RoomCard = deck.pop_back()
	deck.append(old)
	deck.shuffle()
	rooms[square] = {"card": new_card, "revealed": false, "cleared": false, "done": false,
		"campfire": false, "opened": false}
	raise_danger(TORCH_SWAP_DANGER)
	add_log("You shuffle the %s back into the map deck and a new card takes its place. Danger +%d." % [old.room_name, TORCH_SWAP_DANGER])
	return new_card


# Can you light up this square with a torch? (Face down and not scouted yet.)
func can_scout(square: Vector2i) -> bool:
	return torches > 0 and result.is_empty() and rooms.has(square) \
		and not rooms[square].revealed and not rooms[square].get("scouted", false) \
		and rooms[square].card != null


# What the lit torch needs on its next burnout roll (5 on a d4 = it burns out).
func torch_need() -> int:
	return TORCH_TARGETS[mini(torch_uses, TORCH_TARGETS.size() - 1)]


# SCOUT a face-down card with your torch: you see its face (it stays face
# down until you step on it, so no Danger yet). Then the burnout roll.
# Returns {"roll": 3, "need": 2, "kept": true}, or {} if you can't.
func scout(square: Vector2i) -> Dictionary:
	if not can_scout(square):
		return {}
	var room: Dictionary = rooms[square]
	room.scouted = true
	var need := torch_need()
	var roll := randi_range(1, TORCH_DIE)
	var kept := roll >= need
	if kept:
		torch_uses += 1
	else:
		torches -= 1
		torch_uses = 0
	var card: RoomCard = room.card
	add_log("Your torch lights up: %s (%s). Burnout roll %d (needed %d+): %s" % [card.room_name, card.tile_name(), roll, need,
		"still burning." if kept else "it burns out. %d torch%s left." % [torches, "" if torches == 1 else "es"]])
	return {"roll": roll, "need": need, "kept": kept}


# --- Scavenging -----------------------------------------------------------------

# Can you scavenge here (now, or by coming back)?
func can_scavenge(square: Vector2i) -> bool:
	if not rooms.has(square):
		return false
	var room: Dictionary = rooms[square]
	var card: RoomCard = room.card
	return card != null and card.can_scavenge() and not room.get("scavenge_over", false) \
		and room.get("scavenges", 0) < SCAVENGE_TARGETS.size()


# The Luck you have at a spot: one less than the tries so far (the free
# first try doesn't count). It goes up with every success.
func scavenge_luck(square: Vector2i) -> int:
	return maxi(rooms[square].get("scavenges", 0) - 1, 0)


# What the next try at a spot needs on the d6 (0 = it always works).
func scavenge_need(square: Vector2i) -> int:
	return SCAVENGE_TARGETS[mini(rooms[square].get("scavenges", 0), SCAVENGE_TARGETS.size() - 1)]


# The Luck the next try would find things at, if it works.
func next_scavenge_luck(square: Vector2i) -> int:
	return rooms[square].get("scavenges", 0)


# Scavenge where you stand. Returns {"roll", "need", "worked", "luck",
# "text" (what you found), "over" (the spot is finished)}, or {} if you can't.
func scavenge() -> Dictionary:
	if not can_scavenge(position) or not result.is_empty():
		return {}
	var room: Dictionary = rooms[position]
	var card: RoomCard = room.card
	var tries: int = room.get("scavenges", 0)
	var need := scavenge_need(position)
	var roll := randi_range(1, SCAVENGE_DIE) if need > 0 else 0
	var worked := need == 0 or roll >= need
	if not worked:
		room.scavenge_over = true
		room.done = true
		raise_danger(1)
		add_log("Scavenging %s: rolled %d (needed %d+). Nothing but noise! Danger +1." % [card.room_name, roll, need])
		return {"roll": roll, "need": need, "worked": false, "luck": scavenge_luck(position), "text": "", "over": true}
	var luck := tries  # The free try finds at Luck 0, the next at 1...
	room.scavenges = tries + 1
	var loot_card := RoomCard.new()
	loot_card.loot = card.scavenge_table(luck)
	var text := take_loot(loot_card)
	var over := not can_scavenge(position)
	if over:
		room.done = true  # Picked clean.
	add_log("Scavenging %s (Luck %d, %s): %s%s" % [card.room_name, luck, luck_name(luck), text,
		"" if need == 0 else " (rolled %d, needed %d+)" % [roll, need]])
	return {"roll": roll, "need": need, "worked": true, "luck": luck, "text": text, "over": over}


static func luck_name(luck: int) -> String:
	return LUCK_NAMES[mini(luck, LUCK_NAMES.size() - 1)]


# --- Danger ------------------------------------------------------------------

func raise_danger(amount: int) -> void:
	var strength_before := enemy_strength()
	var cards_before := danger_points / danger_per_card()
	danger_points += amount
	if enemy_strength() > strength_before:
		add_log("Danger %d! Every enemy now has +%d Strength." % [danger_points, enemy_strength()])
	if not guided:
		for i in danger_points / danger_per_card() - cards_before:
			_add_danger_card()


# Danger points (shown on the danger meter).
func danger() -> int:
	return danger_points


# Danger for each Danger card (the Mapmaker adds more).
func danger_per_card() -> int:
	return DANGER_PER_CARD + GameState.town_bonus(TownBuilding.DANGER_STEPS)


func danger_per_strength() -> int:
	return danger_per_card() * DANGER_CARDS_PER_STRENGTH


# The Strength every enemy gets: +1 for every danger_per_strength() danger.
func enemy_strength() -> int:
	return danger_points / danger_per_strength()


# How much more danger until the next Danger card.
func danger_to_next() -> int:
	return danger_per_card() - danger_points % danger_per_card()


# Will the next Danger card also make enemies stronger?
func next_danger_adds_strength() -> bool:
	return (danger_points + danger_to_next()) % danger_per_strength() == 0


# This place's Danger cards (Deck "Danger" in the sheet), one entry per Copy
# so more Copies = more likely.
func danger_pool() -> Array[RoomCard]:
	var pool: Array[RoomCard] = []
	for card in area.cards():
		if card.deck_part == RoomCard.DECK_DANGER and card.floor_from <= floor_number:
			for i in card.copies:
				pool.append(card)
	return pool


# A DANGER CARD: a bad card goes into the map deck. If a card on the board
# is still face down (and not scouted), the Danger card takes its place right
# away, and that card goes back into the deck.
func _add_danger_card() -> void:
	var pool := danger_pool()
	if pool.is_empty():
		return
	var card: RoomCard = pool.pick_random()
	danger_cards_added += 1
	last_danger_card = card
	if _swap_onto_board(card).x < 0:
		add_log("Danger %d! A Danger card is shuffled into the map deck: %s." % [danger_points, card.room_name])
	else:
		add_log("Danger %d! A Danger card sneaks onto the board, face down: %s." % [danger_points, card.room_name])


# Put a card onto a random face-down (not scouted) square of the board; the
# card that was there goes back into the deck. If there's no such square, the
# card goes into the deck. Returns the square, or (-1, -1).
func _swap_onto_board(card: RoomCard) -> Vector2i:
	var spots: Array[Vector2i] = []
	for square: Vector2i in rooms:
		var room: Dictionary = rooms[square]
		var here: RoomCard = room.card
		if here != null and not room.revealed and not room.get("scouted", false) and not room.campfire \
				and here.deck_part not in [RoomCard.DECK_BOSS, RoomCard.DECK_ROAMER, RoomCard.DECK_LINKED] \
				and square != roamer_square:
			spots.append(square)
	if spots.is_empty():
		deck.append(card)
		deck.shuffle()
		return Vector2i(-1, -1)
	var square: Vector2i = spots.pick_random()
	if _returns_to_deck(rooms[square].card):
		deck.append(rooms[square].card)
		deck.shuffle()
	rooms[square].card = card
	return square


# Linked, Roamer and Secret cards belong to the board they're on: they never
# go into the deck.
func _returns_to_deck(card: RoomCard) -> bool:
	return card != null and card.deck_part not in [RoomCard.DECK_CAMPFIRE, RoomCard.DECK_BOSS, RoomCard.DECK_GUIDE,
		RoomCard.DECK_LINKED, RoomCard.DECK_ROAMER, RoomCard.DECK_SECRET]


# A card of this place by name (any Deck), or null.
func find_card(card_name: String) -> RoomCard:
	for card in area.cards():
		if card.room_name == card_name:
			return card
	return null


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
	if card.deck_part == RoomCard.DECK_ROAMER:
		roamer_beaten = true
	if not card.loot.is_empty() and card.is_fight():
		add_log("Reward: %s" % take_loot(card))
	if randi_range(1, 100) <= KEY_CHANCE:
		keys += 1
		add_log("You found a small key!")
	if GameState.enchants_open() and randi_range(1, 100) <= ENCHANT_CHANCE.get(card.type, 0):
		add_log("An enchant! %s" % _drop_enchant())
	if GameState.potions_open() and randi_range(1, 100) <= POTION_CHANCE.get(card.type, 0):
		add_log("A potion! %s" % _drop_potion())
	if BOSS_PACKS.has(card.type):
		var pack_name: String = GameState.find_pack(BOSS_PACKS[card.type]).name
		found_boss_packs[pack_name] = found_boss_packs.get(pack_name, 0) + 1
		add_log("The %s drops a %s!" % ["Boss" if card.type == RoomCard.Type.BOSS else "Mini Boss", pack_name])
	if randi_range(1, 100) <= PLAN_CHANCE.get(card.type, 0):
		var plan_card := GameState.random_plan_card(area)
		if plan_card:
			found_plans.append(plan_card.card_name)
			add_log("A PLAN! You can craft a %s with it (in the Binder)." % plan_card.card_name)
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
		if not _returns_to_deck(card):
			continue  # The campfire and the Boss are dealt fresh each floor; linked cards stay with their board.
		if card.vanish and room.done:
			gone.append(card)
			continue
		deck.append(card)
	floor_number += 1
	_campfire_perks()
	_add_floor_cards()
	deck.shuffle()
	_deal()
	GameState.record_for_quest(Quest.REACH_TIER, "", floor_number)
	add_log("Floor %d! The cards are shuffled and dealt again. Find the next campfire!" % floor_number)
	if boss_here():
		add_log("The %s is somewhere on this board..." % boss_card().room_name)


# Camper perks: a rest at the campfire before you go down.
func _campfire_perks() -> void:
	var heal := GameState.area_perk_total(area, AreaPerk.CAMPFIRE_HEAL)
	if heal > 0:
		var max_hp := GameState.player_max_hp()
		var before := GameState.run_hp if GameState.run_hp > 0 else max_hp
		GameState.run_hp = mini(before + heal, max_hp)
		add_log("You rest by the fire: +%d HP (HP %d/%d)." % [GameState.run_hp - before, GameState.run_hp, max_hp])
	var sips := GameState.area_perk_total(area, AreaPerk.CAMPFIRE_FLASK)
	if sips > 0 and flask:
		flask_charges = mini(flask_charges + sips, flask_stats[Flask.CHARGES])
		add_log("You refill your flask at the stream: %d/%d." % [flask_charges, flask_stats[Flask.CHARGES]])
	if GameState.area_perk_total(area, AreaPerk.CAMPFIRE_VANISHED) > 0 and not GameState.vanished.is_empty():
		add_log("Second Wind: %d Vanished card%s come back." % [GameState.vanished.size(), "" if GameState.vanished.size() == 1 else "s"])
		GameState.vanished.clear()
	# Clean Camp: throw Danger cards out of the map deck.
	var cleanup := GameState.area_perk_total(area, AreaPerk.CAMPFIRE_REMOVE)
	var thrown: Array[String] = []
	for i in cleanup:
		var bad := -1
		for k in deck.size():
			if deck[k].deck_part == RoomCard.DECK_DANGER:
				bad = k
				break
		if bad < 0:
			break
		thrown.append(deck[bad].room_name)
		deck.remove_at(bad)
	if not thrown.is_empty():
		add_log("You clean up camp: %s thrown out of the map deck." % ", ".join(thrown))


# THE PLACE'S EXP for this trip: 1 per card you flipped, 3 per fight won, 10
# per floor below the first, and 10 more for getting home (or beating the
# Boss). Die and you get half. Called once, from claim_loot().
func area_exp_earned() -> int:
	var total := cards_flipped + fights_won * 3 + (floor_number - 1) * 10
	if result == "died":
		return total / 2
	return total + 10


func award_area_exp() -> void:
	if not area_exp_result.is_empty():
		return  # Already given.
	var amount := area_exp_earned()
	var level_before := GameState.area_level(area)
	var levels := GameState.add_area_exp(area, amount)
	area_exp_result = {"exp": amount, "level_before": level_before, "levels": levels}
	add_log("%s Exp +%d%s" % [area.display_name, amount,
		"  Level %d! +%d Explorer point%s and a Farm Booster Pack." % [levels.back(), levels.size(), "" if levels.size() == 1 else "s"] if not levels.is_empty() else ""])


# "Abandoned Farm Exp +32 · Level 3! +1 Explorer point, +1 Small Farm Booster Pack" (for the end screens).
func area_exp_text() -> String:
	if area_exp_result.is_empty():
		return ""
	var text := "%s Exp +%d" % [area.display_name, area_exp_result.exp]
	var levels: Array = area_exp_result.levels
	if not levels.is_empty():
		text += "  ·  Level %d! +%d Explorer point%s, +%d %s" % [levels.back(), levels.size(), "" if levels.size() == 1 else "s",
			levels.size(), GameState.AREA_LEVEL_PACK]
	return text


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
	found_boss_packs.clear()
	found_plans.clear()
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
		"torch":
			if pack_item(TORCH, 1) == 0:
				return "a torch (no room in your backpack)"
			return "a torch"
		"crowbar", "bomb":
			var tool_name := words[0].capitalize()
			if pack_item(tool_name, 1) == 0:
				return "a %s (no room in your backpack)" % tool_name.to_lower()
			return "a %s!" % tool_name.to_lower()
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
		var fits := pack_item(material_name, amount)
		if fits < amount:
			return "%d %s (only %d fit%s in your backpack)" % [amount, material_name, fits, "s" if fits == 1 else ""]
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


# --- The Backpack ----------------------------------------------------------------

func backpack_slots() -> int:
	return BACKPACK_SLOTS + GameState.town_bonus(TownBuilding.BACKPACK_SLOTS)


# How many of something you carry (TORCH = your torches).
func carried(item_name: String) -> int:
	if item_name == TORCH:
		return torches
	if item_name in TOOLS:
		return tools.get(item_name, 0)
	return found_materials.get(item_name, 0)


# Slots that many of one thing fill: 1-5 = 1 slot, 6-10 = 2...
static func stacks(amount: int) -> int:
	return ceili(amount / float(BACKPACK_STACK))


func backpack_used() -> int:
	var used := stacks(torches)
	for tool_name in tools:
		used += stacks(tools[tool_name])
	for material_name in found_materials:
		used += stacks(found_materials[material_name])
	return used


# What's in the backpack, one entry per slot: [{"name": "Stone", "amount": 5}, {"name": "Stone", "amount": 2}...]
func backpack_contents() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var names: Array = []
	if torches > 0:
		names.append(TORCH)
	names.append_array(tools.keys().filter(func(t: String) -> bool: return tools[t] > 0))
	names.append_array(found_materials.keys())
	for item_name: String in names:
		var left := carried(item_name)
		while left > 0:
			list.append({"name": item_name, "amount": mini(left, BACKPACK_STACK)})
			left -= BACKPACK_STACK
	return list


# How many more of something fit: the gap on its top stack plus the free slots.
func backpack_room(item_name: String) -> int:
	var top_gap := (BACKPACK_STACK - carried(item_name) % BACKPACK_STACK) % BACKPACK_STACK
	return top_gap + maxi(backpack_slots() - backpack_used(), 0) * BACKPACK_STACK


# Put something you found in the backpack. What doesn't fit goes to
# left_over (dungeon.gd asks what to do with it). Returns how many fit.
func pack_item(item_name: String, amount: int) -> int:
	var fits := mini(amount, backpack_room(item_name))
	if item_name == TORCH:
		torches += fits
	elif item_name in TOOLS:
		_add_tool(item_name, fits)
	elif fits > 0:
		add_found_material(item_name, fits)
	if amount > fits:
		left_over[item_name] = left_over.get(item_name, 0) + amount - fits
	return fits


# Throw away one slot's worth of something (the top stack: the part-full one
# if there is one) to make room. Returns how many you dropped.
func drop_stack(item_name: String) -> int:
	var have := carried(item_name)
	if have <= 0:
		return 0
	var amount := have % BACKPACK_STACK if have % BACKPACK_STACK != 0 else BACKPACK_STACK
	if item_name == TORCH:
		torches -= amount
		if torches <= 0:
			torch_uses = 0
	elif item_name in TOOLS:
		_add_tool(item_name, -amount)
	else:
		add_found_material(item_name, -amount)
	add_log("You drop %d %s to make room." % [amount, item_name])
	return amount


func _add_tool(tool_name: String, amount: int) -> void:
	tools[tool_name] = maxi(tools.get(tool_name, 0) + amount, 0)
	if tools[tool_name] == 0:
		tools.erase(tool_name)


# Try again to fit what was left over (after dropping something).
func repack_left_over() -> void:
	var waiting := left_over.duplicate()
	left_over.clear()
	for item_name: String in waiting:
		pack_item(item_name, waiting[item_name])


# Leave what didn't fit where it is.
func leave_behind() -> void:
	for item_name: String in left_over:
		add_log("No room: you leave %d %s behind." % [left_over[item_name], item_name])
	left_over.clear()


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
		"material": pack_item(item.name, item.amount)


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


# At the end of the run (home, or dead): no backpack limits any more.
func _empty_sack() -> void:
	for item in sack:
		match item.kind:
			"pack": found_packs += 1
			"gold": found_gold += item.amount
			"card": found_cards.append(item.card)
			"material": add_found_material(item.name, item.amount)
	sack.clear()
	left_over.clear()


# Give the player everything found (after Returning to Town or beating the Boss).
# The place's Exp is given here too (also when you die: die() calls this).
func claim_loot() -> void:
	award_area_exp()
	_empty_sack()
	GameState.gold += found_gold
	GameState.run_gold += found_gold
	if found_packs > 0:
		GameState.add_packs(PACK_NAME, found_packs)
	for pack_name in found_boss_packs:
		GameState.add_packs(pack_name, found_boss_packs[pack_name])
	for card_name in found_plans:
		GameState.plans[card_name] = GameState.plans.get(card_name, 0) + 1
	GameState.trip_ended()  # The Shop restocks after every trip.
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
	for pack_name in found_boss_packs:
		parts.append("%d %s" % [found_boss_packs[pack_name], pack_name])
	for card_name in found_plans:
		parts.append("a Plan: " + card_name)
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
