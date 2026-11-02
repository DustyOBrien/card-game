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
# % chance a won fight drops a SUPER card (run-only, see card_data.gd). Super rare!
const SUPER_CARD_CHANCE := {RoomCard.Type.MINI_BOSS: 25}
const REST_HEAL := 0.3  # Resting heals this much of your max HP.
const PACK_NAME := "Small Plains Booster Pack"  # The pack that "Pack" loot gives you (GameState.PACKS).
# The four squares next to a square: right, left, down, up.
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

var area: Area
var tier := 1  # Which tier's cards are in the deck.
# The guided first run (before the Inn): only the area's Guide rooms, no
# enemies, and dungeon.gd shows tips as you go.
var guided := false
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
# Super cards you found: they join your deck for the rest of THIS run only.
var super_cards: Array[CardData] = []
# Your flask (flask.gd), set by GameState.start_run(). Its charges come back
# when you Rest at a campfire.
var flask: Flask = null
var flask_stats := {}  # What it does this run (Flask.stats()).
var flask_charges := 0

var seen_events: Array[String] = []  # Events met this run (each one only once if there are enough).
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
	guided = GameState.is_guided_run(area)
	if guided:
		_add_tier(RoomCard.GUIDE_TIER)
		max_tier = RoomCard.GUIDE_TIER  # No tiers to go deeper into.
	else:
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
	if number == RoomCard.GUIDE_TIER:
		deck.reverse()  # Draw them in the sheet's order (the deck is drawn from the end).
	else:
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
		add_log("The room deck is empty. The other paths are dead ends.")


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
		RoomCard.Type.EVENT:
			if room.done:
				return "walk"
			if not room.has("event"):
				room.event = pick_event()
			if room.event == null:
				room.cleared = true  # No events in the sheet: just an empty room.
				room.done = true
				return "empty"
			return "event"
		RoomCard.Type.LOCKED_CHEST:
			return "chest"
		RoomCard.Type.TREASURE:
			room.cleared = true
			room.done = true
			add_log("Treasure! %s" % take_loot(card))
			return "treasure"
	room.cleared = true  # Empty.
	return "empty"


# --- Events -------------------------------------------------------------------

# A random event for this area and tier, preferring ones you haven't seen this run.
func pick_event() -> DungeonEvent:
	var fitting := GameState.load_events().filter(func(e: DungeonEvent) -> bool: return e.fits(area.display_name, tier))
	var fresh := fitting.filter(func(e: DungeonEvent) -> bool: return not seen_events.has(e.event_name))
	var pool := fresh if not fresh.is_empty() else fitting
	if pool.is_empty():
		return null
	var event: DungeonEvent = pool.pick_random()
	seen_events.append(event.event_name)
	return event


# Is this choice left out completely? (Enchants, before the Enchanter is built.)
func choice_hidden(event: DungeonEvent, index: int) -> bool:
	for effect in DungeonEvent.split_effects(event.effects[index]):
		if effect.strip_edges().to_lower().begins_with("enchant") and not GameState.enchants_open():
			return true
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
			"flask":
				if flask == null:
					return "You have no flask"
				if flask_charges >= flask_stats[Flask.CHARGES]:
					return "Your flask is already full"
	return ""


# Make a choice in the event where you're standing. Roll its Chance, do its
# effects, and finish the room. Returns {"text": what happened, "fight": true
# if it started a fight (fight_enemies is set, like an ambush)}.
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
		text += ("
" if not text.is_empty() else "") + "
".join(outcome.lines)
	if outcome.fight:
		room.cleared = false  # Blocks the way until you win.
		fight_square = position
	return {"text": text, "fight": outcome.fight}


# Do a list of effects (see dungeon_event.gd). Returns {"lines": what happened, "fight": bool}.
func apply_effects(list: Array[String]) -> Dictionary:
	var lines: Array[String] = []
	var fight := false
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
				steps += number * steps_per_danger()
				lines.append("Danger +%d" % number)
			"calm":
				steps = 0
				lines.append("Danger back to 0")
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
	return {"lines": lines, "fight": fight}


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
	GameState.record_for_quest(Quest.CLEAR_ROOM, card.room_name)
	if not card.loot.is_empty():
		add_log("Reward: %s" % take_loot(card))
	if randi_range(1, 100) <= KEY_CHANCE:
		keys += 1
		add_log("You found a small key!")
	if GameState.enchants_open() and randi_range(1, 100) <= ENCHANT_CHANCE.get(card.type, 0):
		add_log("An enchant! %s" % _drop_enchant())
	if randi_range(1, 100) <= POTION_CHANCE.get(card.type, 0):
		add_log("A potion! %s" % _drop_potion())
	if randi_range(1, 100) <= SUPER_CARD_CHANCE.get(card.type, 0):
		add_log("★ A SUPER CARD! %s" % _drop_super_card())
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
#
# GO DEEPER (heal = false) is the same move without the resting: no healing,
# Vanished cards stay gone, the flask stays as it is. For now campfires only
# offer Return to Town, plus Go Deeper after a Mini Boss (Dusty, 2026-11-01).
func rest(heal := true) -> int:
	var max_hp := GameState.player_max_hp()
	var hp_before := GameState.run_hp if GameState.run_hp > 0 else max_hp
	var hp_after := mini(hp_before + ceili(max_hp * REST_HEAL), max_hp) if heal else hp_before
	GameState.run_hp = hp_after
	if heal:
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
	if heal:
		add_log("You rest: HP %d → %d. Vanished cards are back. The rooms shift..." % [hp_before, hp_after])
	else:
		add_log("You head deeper. The rooms shift...")
	if tier_up_waiting:
		tier_up_waiting = false
		if tier < max_tier:
			_add_tier(tier + 1)
			GameState.record_for_quest(Quest.REACH_TIER, "", tier)
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
	found_materials.clear()
	_empty_sack()  # The sack's contents become the only thing "found"...
	var saved := loot_text()
	claim_loot()  # ...and you take them home.
	add_log("You were defeated. Your Save Sack kept: %s." % saved if GameState.sack_open() else "You were defeated, and lost what you found.")
	return saved


# --- Loot ----------------------------------------------------------------------

# Pick one of the card's loot entries and add it to what you've found.
# Returns what you got, as text: "12 gold", "a card: Strike", "a Map!"...
func take_loot(card: RoomCard) -> String:
	if card == null or card.loot.is_empty():
		return "nothing"
	# No enchants (or their loot) until the Enchanter is built.
	var entries := Array(card.loot).filter(func(e: String) -> bool:
		return GameState.enchants_open() or not e.strip_edges().to_lower().begins_with("enchant"))
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
			return "a %s pack" % PACK_NAME
		"key":
			keys += 1
			return "a small key"
		"enchant":
			return "an enchant: " + _drop_enchant()
		"potion":
			return _drop_potion()
		"super":  # "Super Card"
			return "a Super card: " + _drop_super_card()
		"map":
			var room := GameState.unlock_random_room(area)
			if room == null:
				found_gold += 10  # Every room is already unlocked.
				return "an old map of rooms you know (10 gold instead)"
			return "a Map! New room for the %s: %s" % [area.display_name, room.room_name]
	# A material: "Stone 2", "Stone 1-3" or "Green Ooze 2" (the name can have spaces).
	var last := words[-1].split("-")
	var material_name := " ".join(words.slice(0, -1)) if words.size() > 1 and last[0].is_valid_int() else entry.strip_edges()
	if GameState.find_material(material_name):
		var amount := randi_range(last[0].to_int(), last[-1].to_int()) if words.size() > 1 and last[0].is_valid_int() else 1
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


# A random Super card you don't have yet this run, straight into your deck.
func _drop_super_card() -> String:
	var choices := GameState.load_super_cards().filter(func(c: CardData) -> bool: return not super_cards.has(c))
	if choices.is_empty():
		choices = GameState.load_super_cards()
	if choices.is_empty():
		return "nothing"
	var card: CardData = choices.pick_random()
	super_cards.append(card)
	return "%s (in your deck until the run ends)" % card.card_name


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


# Give the player everything found (after Leaving or beating the Boss).
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


# The guided run's goal: what the Inn needs ({"Stone": 5}).
func guide_needs() -> Dictionary:
	var inn := GameState.find_building("Inn")
	return inn.materials_for_next(GameState.town_stage(inn)) if inn else {}


# Do you have it all (counting what's already in the Bank)?
func guide_goal_met() -> bool:
	var needs := guide_needs()
	for material_name in needs:
		if material_total(material_name) + GameState.material_count(material_name) < needs[material_name]:
			return false
	return true


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
