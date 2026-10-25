# dice.gd
#
# Reads and rolls dice written the way tabletop games write them:
#   "d6"     one six-sided die              (1 to 6)
#   "2d3"    two three-sided dice, added    (2 to 6)
#   "d6+2"   one six-sided die, plus 2      (3 to 8)
#   "2d6-1"  two six-sided dice, minus 1    (1 to 11)
#   "6"      no dice, just 6                (always 6)
#
# Every function here is `static`: you call it on the class itself, like
# Dice.parse("2d3+2"), without making a Dice object first. (Like a Python
# module full of functions.)
class_name Dice
extends RefCounted

# A RegEx (regular expression) is a pattern for matching text. This one means:
# "maybe a number, then d, then a number, then maybe + or - and a number".
# The parts in ( ) are "groups" we can read back out afterwards.
const PATTERN := "^(\\d*)d(\\d+)([+-]\\d+)?$"

# `static var` is shared by every use of the class (like a Python class
# variable). The battle reads the same few formulas ("d3", "d6") hundreds of
# times a second while you drag a card, so we compile the RegEx only once and
# remember every formula we've already read.
static var _regex: RegEx
static var _cache := {}


# Is this text a dice formula we understand? Blank text is "no dice".
static func is_valid(text: String) -> bool:
	return parse(text).size() > 0


# "2d3+2" -> {"count": 2, "sides": 3, "bonus": 2}. "6" -> {"count": 0, "sides": 0, "bonus": 6}.
# Bad or blank text gives {}.
# Don't change the Dictionary you get back: it's shared through the cache.
static func parse(text: String) -> Dictionary:
	if not _cache.has(text):
		_cache[text] = _read(text)
	return _cache[text]


# The actual reading, done once per formula (parse() remembers the answer).
static func _read(text: String) -> Dictionary:
	text = text.strip_edges()
	if text.is_valid_int():
		return {"count": 0, "sides": 0, "bonus": text.to_int()}  # A plain number: no dice to roll.
	if _regex == null:
		_regex = RegEx.new()
		_regex.compile(PATTERN)
	var found := _regex.search(text.to_lower().replace(" ", ""))
	if found == null:
		return {}
	var count_text := found.get_string(1)
	return {
		"count": 1 if count_text.is_empty() else count_text.to_int(),  # "d6" means "1d6".
		"sides": found.get_string(2).to_int(),
		"bonus": found.get_string(3).to_int(),  # "" -> 0, "+2" -> 2, "-1" -> -1
	}


# Does this formula have any dice in it? ("d3" yes, "6" no.)
static func has_dice(text: String) -> bool:
	var dice := parse(text)
	return dice.size() > 0 and dice.count > 0


# Just the dice, no bonus: "2d3+2" -> [2, 3]. "6" -> [].
static func roll_dice(text: String) -> Array[int]:
	var dice := parse(text)
	var results: Array[int] = []
	if dice.is_empty():
		return results
	for i in dice.count:
		results.append(randi_range(1, dice.sides))
	return results
