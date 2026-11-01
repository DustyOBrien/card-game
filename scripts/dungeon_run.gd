# dungeon_run.gd
#
# The rules of one trip into a dungeon. A run happens on a 5 x 5 grid of
# squares. You start in the middle. Every other square is blank until you
# step onto it: then you draw a card from the area's ROOM DECK, and that's
# what the room is (a fight, a chest, a campfire...).
#
# How a dungeon goes:
#   1. The deck starts with the area's Tier 1 room cards, shuffled.
#   2. Beating a Mini Boss forces a campfire. Resting there shuffles every
#      room back into the deck, plus the next tier's harder (and richer)
#      cards. The last tier's Mini Boss shuffles in the Boss room instead.
#   3. Beat the Boss and the area is cleared. You can also Leave at any
#      campfire with what you found. Die, and you lose what you found
#      (you keep your Exp).
#   4. DANGER: every step makes noise. Every STEPS_PER_DANGER steps since
#      your last rest, enemies get +1 Strength. Resting resets it.
#
# This file is only rules and numbers: dungeon.gd draws it on screen, and
# battle.gd asks it which enemies to fight. GameState.dungeon holds the one
# that's in progress. (Like Combatant, keeping rules apart from the screen
# makes both easier to follow and to test.)
class_name DungeonRun
extends RefCounted

const SIZE := 5  # The grid is SIZE x SIZE squares.
const START := Vector2i(2, 2)  # The middle square.
const STEPS_PER_DANGER := 6  # Steps (since the last rest) for each +1 enemy Strength (the Mapmaker adds more).
const KEY_CHANCE := 25  # % chance a fight drops a small key.
# % chance a won fight drops an enchant / a potion, by room type.
const ENCHANT_CHANCE := {RoomCard.Type.FIGHT: 35, RoomCard.Type.HARD_FIGHT: 60, RoomCard.Type.MINI_BOSS: 100}
const POTION_CHANCE := {RoomCard.Type.FIGHT: 25, RoomCard.Type.HARD_FIGHT: 35, RoomCard.Type.MINI_BOSS: 50}
const REST_HEAL := 0.3  # Resting heals this much of your max HP.
const PACK_NAME := "Basic Booster"  # The pack that "Pack" loot gives you.
# The four squares next to a square: right, left, down, up.
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

var area: Area
var tier := 1  # Which tier's cards are in the deck.
var max_tier := 1  # The area's last tier.
var deck: Array[RoomCard] = []  # The room cards still to draw, top = the end.
# Every explored square: Vector2i -> a Dictionary describing the room there:
#   card: RoomCard (null for the start square)
#   cleared: safe to walk through (the fight is won, the treasure taken...)
#   opened: a Locked Chest you've opened
#   done: this card never goes back into the deck (a beaten Mini Boss, an opened chest)
#   campfire: a campfire is here (also after a Mini Boss)
var rooms := {}
var walls := {}  # Squares that are dead ends (the deck ran out): Vector2i -> true.
var position := START  # Where you are.
var came_from := START  # The square you stepped from (where Back off takes you).
var steps := 0  # Steps since the last rest (danger).
var total_steps := 0  # Steps this whole run.
var keys := 0  # Small keys: each opens one Locked Chest.
var boss_unlocked := false  # The Boss room is in the deck.
var tier_up_waiting := false  # A Mini Boss was beaten: the next rest adds the next tier.

# What you've found, given to you when you Leave or beat the Boss.
var found_gold := 0
var found_packs := 0
var found_cards: Array[CardData] = []

# The SAVE SACK: what's in it survives if you die. Each slot holds one
# thing: {"kind": "pack"}, {"kind": "card", "card": CardData} or
# {"kind": "gold", "amount": 5} (up to GameState.gold_stack() gold).
# Things move between the Found list and the sack (put_in_sack / take_out_of_sack).
var sack: Array[Dictionary] = []

# Enchants waiting to be put on a card. Each drop is a list of choices
# (usually 1; the Enchanter's upgrade makes it 2): pick one, then a card.
var enchant_drops: Array = []
var potions: Array[Potion] = []  # Potions you carry (drink them in a fight).
# Your flask (flask.gd), set by GameState.start_run(). Its charges come back
# when you Rest at a campfire.
var flask: Flask = null
var flask_stats := {}  # What it does this run (Flask.stats()).
var flask_charges := 0

var fights_won := 0
var result := ""  # "" while in the dungeon, then "left", "won" or "died".
var history: Array[String] = []  # The dungeon's log, newest last.

# The room you're fighting in right now (for battle.gd).
var fight_square := Vector2i(-1, -1)
var fight_enemies: Array[EnemyData] = []


func _init(for_area: Area) -> void:
	area = for_area
	for card in area.rooms:
		max_tier = maxi(max_tier, card.tier)
	rooms[START] = {"card": null, "cleared": true, "done": true, "campfire": false}
	_add_tier(1)
	add_log("You enter the %s." % area.display_name)


# --- The deck --------------------------------------------------------------

# Shuffle every card of this tier into the deck (as many as its Copies),
# leaving out cards that still need a Map.
func _add_tier(number: int) -> void:
	tier = number
	for card in area.rooms:
		if card.tier == number and GameState.is_room_unlocked(area, card):
			for i in maxi(card.copies, 1):
				deck.append(card)
	deck.shuffle()


func _add_boss() -> void:
	for card in area.rooms:
		if card.type == RoomCard.Type.BOSS:
			deck.append(card)
	deck.shuffle()
	boss_unlocked = true


# --- Moving ------------------------------------------------------------------

func in_grid(square: Vector2i) -> bool:
	return square.x >= 0 and square.y >= 0 and square.x < SIZE and square.y < SIZE


func is_explored(square: Vector2i) -> bool:
	return rooms.has(square)


# Walkable without a fight: explored and cleared (or the start).
func is_safe(square: Vector2i) -> bool:
	return rooms.has(square) and rooms[square].cleared


# Every square you can step to from where you are, walking through safe
# squares only: square -> {"steps": how many steps, "from": the last safe
# square on the way (where Back off takes you)}. A square you can step to is
# a blank square next to the explored area (that's exploring) or any
# explored room. This is a "breadth-first search": find every square 1 step
# away, then every square 2 steps away, and so on. The grid is tiny, so one
# search answers every square at once (the dungeon screen asks once per redraw).
func reachable() -> Dictionary:
	var found := {}
	var queue: Array[Vector2i] = [position]
	var seen := {position: 0}
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		for direction in DIRECTIONS:
			var next := here + direction
			if not in_grid(next) or walls.has(next) or seen.has(next):
				continue
			seen[next] = seen[here] + 1
			found[next] = {"steps": seen[next], "from": here}
			if is_safe(next):
				queue.append(next)  # Only walk ON through rooms that are safe.
	return found


# How many steps to `target`, or -1 if you can't get there.
func steps_to(target: Vector2i) -> int:
	var reach := reachable()
	return reach[target].steps if reach.has(target) else -1


func can_move_to(square: Vector2i) -> bool:
	return result.is_empty() and steps_to(square) > 0


# Walk to a square. Returns what happened there, for the dungeon screen:
#   "walk"     back into a room you've cleared (or a campfire)
#   "fight"    a fight: see who it is, then Fight or Back off (fight_enemies says who)
#   "ambush"   a fight that starts straight away (no backing off)
#   "chest"    a Locked Chest (open it with a key, or leave it for later)
#   "treasure" loot, taken right away
#   "campfire" Rest or Leave
#   "empty"    nothing here
#   ""         you can't go there
func move_to(square: Vector2i) -> String:
	var reach := reachable()
	if not reach.has(square) or not result.is_empty():
		return ""
	steps += reach[square].steps
	total_steps += reach[square].steps
	came_from = reach[square].from
	position = square
	if not rooms.has(square):
		_reveal(square)
	return _enter(square)


# Draw a room card for a blank square.
func _reveal(square: Vector2i) -> void:
	var card: RoomCard = deck.pop_back()
	rooms[square] = {"card": card, "cleared": false, "done": false, "campfire": card.type == RoomCard.Type.CAMPFIRE}
	add_log("You find: %s" % card.room_name)
	if deck.is_empty():
		# No cards left: every other blank square is a dead end until you rest.
		for y in SIZE:
			for x in SIZE:
				var other := Vector2i(x, y)
				if not rooms.has(other):
					walls[other] = true
		add_log("The room deck is empty. The other paths are blocked until you rest.")


func _enter(square: Vector2i) -> String:
	var room: Dictionary = rooms[square]
	if room.campfire:
		room.cleared = true  # Campfires are safe to walk through.
		return "campfire"
	var card: RoomCard = room.card
	if card == null:
		return "walk"
	if card.type == RoomCard.Type.LOCKED_CHEST:
		# You can walk past a chest you can't open yet, and come back with a key.
		room.cleared = true
		return "walk" if room.get("opened", false) else "chest"
	if room.cleared:
		return "walk"
	if card.is_fight():
		fight_square = square
		fight_enemies = card.pick_encounter()
		return "ambush" if card.ambush else "fight"
	match card.type:
		RoomCard.Type.LOCKED_CHEST:
			return "chest"
		RoomCard.Type.TREASURE:
			room.cleared = true
			room.done = true
			add_log("Treasure! %s" % take_loot(card))
			return "treasure"
	room.cleared = true  # Empty.
	return "empty"


# Step back out of a fight you don't want yet, to the square you came from.
# The room stays on the map, unbeaten, and you can't walk through it until
# you beat it. Backing off still makes noise (1 step). Ambushes can't be backed off.
func can_back_off() -> bool:
	if not rooms.has(position) or rooms[position].card == null:
		return false
	var card: RoomCard = rooms[position].card
	return card.is_fight() and not card.ambush and not rooms[position].cleared and position != came_from


func back_off() -> void:
	if not can_back_off():
		return
	add_log("You back away from %s." % rooms[position].card.room_name)
	position = came_from
	steps += 1
	total_steps += 1
	fight_square = Vector2i(-1, -1)
	fight_enemies.clear()


# --- Danger ------------------------------------------------------------------

# +1 enemy Strength for every STEPS_PER_DANGER steps since you last rested.
func danger() -> int:
	return steps / steps_per_danger()


func steps_per_danger() -> int:
	return STEPS_PER_DANGER + GameState.town_bonus(TownBuilding.DANGER_STEPS)


# Steps until danger goes up again.
func steps_to_next_danger() -> int:
	return steps_per_danger() - steps % steps_per_danger()


# --- Rooms -------------------------------------------------------------------

# The fight in fight_square was won. Returns "campfire" if it was a Mini
# Boss (a campfire appears), "won" for the Boss, or "" for a normal fight.
func win_fight() -> String:
	fights_won += 1
	if not rooms.has(fight_square):
		return ""  # A fight that isn't in a room (the battle scene run on its own with F6).
	var room: Dictionary = rooms[fight_square]
	var card: RoomCard = room.card
	room.cleared = true
	if not card.loot.is_empty():
		add_log("Reward: %s" % take_loot(card))
	if randi_range(1, 100) <= KEY_CHANCE:
		keys += 1
		add_log("You found a small key!")
	if randi_range(1, 100) <= ENCHANT_CHANCE.get(card.type, 0):
		add_log("An enchant! %s" % _drop_enchant())
	if randi_range(1, 100) <= POTION_CHANCE.get(card.type, 0):
		add_log("A potion! %s" % _drop_potion())
	match card.type:
		RoomCard.Type.BOSS:
			room.done = true
			result = "won"
			add_log("You beat the boss! The %s is cleared." % area.display_name)
			return "won"
		RoomCard.Type.MINI_BOSS:
			room.done = true  # A beaten Mini Boss never comes back.
			room.campfire = true  # Its room becomes a campfire.
			tier_up_waiting = true
			add_log("The Mini Boss is beaten! A campfire is lit where it fell.")
			return "campfire"
	return ""


func open_chest(square: Vector2i) -> String:
	var room: Dictionary = rooms[square]
	if keys <= 0 or room.get("opened", false):
		return ""
	keys -= 1
	room.opened = true
	room.done = true
	var text := take_loot(room.card)
	add_log("You open the chest: %s" % text)
	return text


# Rest at a campfire: heal (battle HP is in GameState.run_hp), get your
# Vanished cards back, and shuffle every room back into the deck. Rooms
# that are done (a beaten Mini Boss, an opened chest) stay gone. If a Mini
# Boss was just beaten, the next tier's cards (or the Boss) go in too.
# The room you're in stays (its fire burns out); the rest of the map goes blank.
func rest() -> int:
	var max_hp := GameState.player_max_hp()
	var hp_before := GameState.run_hp if GameState.run_hp > 0 else max_hp
	var hp_after := mini(hp_before + ceili(max_hp * REST_HEAL), max_hp)
	GameState.run_hp = hp_after
	GameState.vanished.clear()
	if flask:
		flask_charges = flask_stats[Flask.CHARGES]  # The flask refills.
	for square: Vector2i in rooms.keys():
		var room: Dictionary = rooms[square]
		if square == position:
			continue
		if room.card != null and not room.done:
			deck.append(room.card)
		rooms.erase(square)
	walls.clear()
	var here: Dictionary = rooms[position]
	if here.card != null and not here.done:
		# A Campfire room card: it stays lit for now, but goes back in the deck
		# (it's "done" from now on, so it isn't added twice).
		deck.append(here.card)
		here.done = true
	here.cleared = true
	here.campfire = false  # The fire burns out: each campfire is used once.
	steps = 0
	add_log("You rest: HP %d → %d. Vanished cards are back. The rooms shift..." % [hp_before, hp_after])
	if tier_up_waiting:
		tier_up_waiting = false
		if tier < max_tier:
			_add_tier(tier + 1)
			add_log("Tier %d! Harder rooms (and better loot) are shuffled in." % tier)
		elif not boss_unlocked:
			_add_boss()
			add_log("The way to the Boss is open! Its room is in the deck.")
	deck.shuffle()
	return hp_after - hp_before


# Leave the dungeon (at a campfire): keep what you found.
func leave() -> void:
	result = "left"
	add_log("You leave the dungeon.")


# You lose what you found, but keep what's in the Save Sack. Returns what
# the sack saved, as text ("nothing" if it was empty).
func die() -> String:
	result = "died"
	found_gold = 0
	found_packs = 0
	found_cards.clear()
	_empty_sack()  # The sack's contents become the only thing "found"...
	var saved := loot_text()
	claim_loot()  # ...and you take them home.
	add_log("You were defeated. Your Save Sack kept: %s." % saved)
	return saved


# --- Loot ----------------------------------------------------------------------

# Pick one of the card's loot entries and add it to what you've found.
# Returns what you got, as text: "12 gold", "a card: Strike", "a Map!"...
func take_loot(card: RoomCard) -> String:
	if card == null or card.loot.is_empty():
		return "nothing"
	var entry: String = Array(card.loot).pick_random()
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
			return "a %s pack" % PACK_NAME
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
				found_gold += 10  # Every room is already unlocked.
				return "an old map of rooms you know (10 gold instead)"
			return "a Map! New room for the %s: %s" % [area.display_name, room.room_name]
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
	var potion := Potion.pick_random(GameState.load_potions())
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
func put_in_sack(kind: String, card: CardData = null) -> bool:
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


static func sack_item_text(item: Dictionary) -> String:
	match item.kind:
		"pack": return "Pack"
		"gold": return "%d gold" % item.amount
		"card": return item.card.card_name
	return "?"


func _empty_sack() -> void:
	while not sack.is_empty():
		take_out_of_sack(0)


# Give the player everything found (after Leaving or beating the Boss).
func claim_loot() -> void:
	_empty_sack()
	GameState.gold += found_gold
	GameState.run_gold += found_gold
	if found_packs > 0:
		GameState.booster_packs[PACK_NAME] = GameState.booster_packs.get(PACK_NAME, 0) + found_packs
	for card in found_cards:
		GameState.add_card(card)
	GameState.save_game()


# "23 gold, 1 pack, 2 cards" (or "nothing").
func loot_text() -> String:
	var parts: Array[String] = []
	if found_gold > 0:
		parts.append("%d gold" % found_gold)
	if found_packs > 0:
		parts.append("%d pack%s" % [found_packs, "s" if found_packs > 1 else ""])
	if not found_cards.is_empty():
		parts.append("%d card%s" % [found_cards.size(), "s" if found_cards.size() > 1 else ""])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func add_log(line: String) -> void:
	history.append(line)
