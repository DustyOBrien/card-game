# combatant.gd
#
# A Combatant is anything that fights: the player or an enemy.
# It only tracks numbers (HP and Block). It does NOT draw anything on screen.
# Instead it sends out signals when something changes, and the battle
# script listens for those signals and updates the labels.
#
# Keeping "game rules" separate from "what's on screen" like this makes
# both halves easier to understand and change.
class_name Combatant
extends Node

# Signals are announcements. Other nodes can connect to them, and the
# connected function runs every time we call `.emit()`.
signal stats_changed  # HP or Block changed.
signal died  # HP reached 0.

@export var display_name: String = "Fighter"
@export var max_hp: int = 50

var hp: int = 0
var block: int = 0
# Armor is Block that doesn't go away: at the start of each turn your Block
# resets to your Armor instead of to 0. The player's comes from their class.
var armor: int = 0


# _ready() runs once, when the node enters the scene. Think of it like __init__.
func _ready() -> void:
	reset()


# Put this combatant back to full health (used when a battle starts).
func reset() -> void:
	hp = max_hp
	block = 0
	stats_changed.emit()


func take_damage(amount: int) -> void:
	if hp == 0:
		return  # Already defeated. (Multi Strike's 2nd hit mustn't make it "die" twice.)
	# Block soaks up damage first, then the rest comes off HP.
	var blocked := mini(block, amount)  # mini() = min() for ints
	block -= blocked
	var remaining := amount - blocked
	hp = maxi(hp - remaining, 0)  # Never go below 0.
	stats_changed.emit()
	if hp == 0:
		died.emit()


# Losing HP (from your own cards) skips Block and goes straight to HP.
func lose_hp(amount: int) -> void:
	if hp == 0:
		return
	hp = maxi(hp - amount, 0)
	stats_changed.emit()
	if hp == 0:
		died.emit()


func gain_block(amount: int) -> void:
	block += amount
	stats_changed.emit()


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)  # Can't heal above max HP.
	stats_changed.emit()


# In Slay the Spire, Block goes away at the start of your next turn.
# Here it drops back to your Armor (0 if you have none).
func clear_block() -> void:
	block = armor
	stats_changed.emit()


func is_dead() -> bool:
	return hp <= 0
