# map_cards.gd
#
# Reads a place's MAP CARD sheet (data/dungeons/farm_cards.csv) into
# RoomCards (room_card.gd). One row per card, columns:
#
#   Place       the area it belongs to ("Abandoned Farm")
#   Deck        Guide / Base / Filler / Yours / Campfire / Boss (see room_card.gd)
#   Card        its name on the card
#   Tile        Safe / Unsafe / Explore
#   Kind        Empty, Treasure, Fight, Hard Fight, Locked Chest, Event,
#               Campfire, Mini Boss or Boss
#   Copies      how many go in the deck
#   Unlocked    Yes / No (a Map from a chest unlocks it) / Quest (a quest does)
#   Encounters  fights: "Small Slime | Small Slime, Small Slime" (one group is picked)
#   Loot        "Stone 1-2 | Gold 1-3" (one is picked)
#   Event       Event cards: the event in events.csv (blank = a random one)
#   Vanish      Yes = gone for the rest of the run once it's used
#   Floor       it joins the deck when you reach this floor (blank = 1)
#   Art         the picture, from the art/ folder: "map_cards/barn.svg"
#   Text        the flavour text on the card
#   Notes       just for you: the game ignores it
#
# Unlike the other sheets, this one is read when the game runs (not by the
# importer), so a change shows up the next time you press Play. The sheet is
# read once and remembered.
class_name MapCards
extends RefCounted

const ART_FOLDER := "res://art/"

static var _sheets := {}  # Sheet path -> Array[RoomCard], read once.


# Every card in the sheet, in its order.
static func load_sheet(path: String) -> Array[RoomCard]:
	if _sheets.has(path):
		return _sheets[path]
	var cards: Array[RoomCard] = []
	var types := {}  # "hard fight" -> RoomCard.Type.HARD_FIGHT
	for type in RoomCard.TYPE_NAMES:
		types[RoomCard.TYPE_NAMES[type].to_lower()] = type
	var tiles := {}  # "unsafe" -> RoomCard.Tile.UNSAFE
	for tile in RoomCard.TILE_NAMES:
		tiles[RoomCard.TILE_NAMES[tile].to_lower()] = tile
	for row in CardImporter._read_sheet(path):
		var card := RoomCard.new()
		card.room_name = row.get("card", "Card")
		var kind: String = row.get("kind", "empty").to_lower()
		if not types.has(kind):
			push_warning("%s: %s has Kind '%s'. Use one of: %s" % [path.get_file(), card.room_name, row.get("kind", ""), ", ".join(RoomCard.TYPE_NAMES.values())])
			continue
		card.type = types[kind]
		var tile_text: String = row.get("tile", "").to_lower()
		card.tile = tiles[tile_text] if tiles.has(tile_text) else RoomCard.tile_for_type(card.type)
		card.deck_part = row.get("deck", RoomCard.DECK_BASE).capitalize()
		card.copies = maxi(CardImporter._to_int(row.get("copies", ""), 1), 1)
		var unlocked_text: String = row.get("unlocked", "").to_lower()
		card.quest_only = unlocked_text == "quest"
		card.unlocked = false if card.quest_only else CardImporter._parse_yes_no(unlocked_text, true)
		card.vanish = CardImporter._parse_yes_no(row.get("vanish", ""), false)
		card.floor_from = maxi(CardImporter._to_int(row.get("floor", ""), 1), 1)
		card.text = row.get("text", "")
		card.event_name = row.get("event", "")
		var art_name: String = row.get("art", "")
		var art_path := ART_FOLDER + art_name
		if not art_name.is_empty():
			if ResourceLoader.exists(art_path):
				card.art = load(art_path)
			else:
				push_warning("%s: %s's Art '%s' isn't in the art/ folder" % [path.get_file(), card.room_name, art_name])
		for group_text in row.get("encounters", "").split("|", false):
			var encounter := Encounter.new()
			for enemy_name in CardImporter._parse_list(group_text):
				var enemy := GameState.find_enemy(enemy_name)
				if enemy:
					encounter.enemies.append(enemy)
				else:
					push_warning("%s: %s has '%s', which isn't in enemies.csv" % [path.get_file(), card.room_name, enemy_name])
			if not encounter.enemies.is_empty():
				card.encounters.append(encounter)
		if card.is_fight() and card.encounters.is_empty():
			push_warning("%s: %s is a fight with no Encounters" % [path.get_file(), card.room_name])
		for loot_text in row.get("loot", "").split("|", false):
			if not loot_text.strip_edges().is_empty():
				card.loot.append(loot_text.strip_edges())
		cards.append(card)
	_sheets[path] = cards
	return cards
