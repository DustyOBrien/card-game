# dice.gd
#
# Reads and rolls dice written the way tabletop games write them:
#   "d6"     one six-sided die              (1 to 6)
#   "2d3"    two three-sided dice, added    (2 to 6)
#   "d6+2"   one six-sided die, plus 2      (3 to 8)
#   "2d6-1"  two six-sided dice, minus 1    (1 to 11)
#
# Every function here is `static`: you call it on the class itself, like
# Dice.roll("2d3+2"), without making a Dice object first. (Like a Python
# module full of functions.)
class_name Dice
extends RefCounted

# A RegEx (regular expression) is a pattern for matching text. This one means:
# "maybe a number, then d, then a number, then maybe + or - and a number".
# The parts in ( ) are "groups" we can read back out afterwards.
const PATTERN := "^(\\d*)d(\\d+)([+-]\\d+)?$"


# Is this text a dice formula we understand? Blank text is "no dice".
static func is_valid(text: String) -> bool:
	return parse(text).size() > 0


# "2d3+2" -> {"count": 2, "sides": 3, "bonus": 2}. Bad text gives {}.
static func parse(text: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile(PATTERN)
	var found := regex.search(text.strip_edges().to_lower().replace(" ", ""))
	if found == null:
		return {}
	var count_text := found.get_string(1)
	return {
		"count": 1 if count_text.is_empty() else count_text.to_int(),  # "d6" means "1d6".
		"sides": found.get_string(2).to_int(),
		"bonus": found.get_string(3).to_int(),  # "" -> 0, "+2" -> 2, "-1" -> -1
	}


# Roll the dice. Returns each die AND the total, so we can show the working:
# {"dice": [2, 3], "bonus": 2, "total": 7}
static func roll(text: String) -> Dictionary:
	var dice := parse(text)
	var results: Array[int] = []
	for i in dice.count:
		results.append(randi_range(1, dice.sides))
	var total: int = dice.bonus
	for value in results:
		total += value
	return {"dice": results, "bonus": dice.bonus, "total": maxi(total, 0)}


# The lowest possible total: every die rolls a 1.
static func min_total(text: String) -> int:
	var dice := parse(text)
	return maxi(dice.count + dice.bonus, 0)


# The highest possible total: every die rolls its top number.
static func max_total(text: String) -> int:
	var dice := parse(text)
	return dice.count * dice.sides + dice.bonus


# Shows the working, e.g. "[2] [3] + 2 = 7"
static func describe_roll(result: Dictionary) -> String:
	var parts: Array[String] = []
	for value in result.dice:
		parts.append("[%d]" % value)
	var text := " ".join(parts)
	if result.bonus > 0:
		text += " + %d" % result.bonus
	elif result.bonus < 0:
		text += " - %d" % -result.bonus
	return "%s = %d" % [text, result.total]
