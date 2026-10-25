# play_zone.gd
#
# The invisible area above your hand in battle. Drop a card here to play it.
# It's the "drop" half of Godot's drag and drop (card.gd is the "drag" half).
# It doesn't play the card itself: it just tells the battle with a signal.
#
# Every card can be dropped anywhere in the zone. With only one enemy, an
# attack always knows who to hit. When there are several enemies, turn on
# ATTACKS_NEED_TARGET so attacks have to be dropped ON the enemy they hit.
class_name PlayZone
extends Control

signal card_dropped(card_data: CardData)

const ATTACKS_NEED_TARGET := false  # true = attacks must be dropped on the enemy.
const TARGET_MARGIN := 24.0  # Extra pixels around the enemy that still count as "on" it.

var enemy_target: Control  # The battle sets this to the enemy's box.


# Does this card have to be dropped on the enemy?
func needs_target(card: CardData) -> bool:
	return ATTACKS_NEED_TARGET and card.deals_damage()


# Is this point on the screen inside the drop zone?
func is_over_zone(screen_point: Vector2) -> bool:
	return get_global_rect().has_point(screen_point)


# Is this point on the screen over the enemy?
func is_over_enemy(screen_point: Vector2) -> bool:
	# get_global_rect() is the box's rectangle on screen. grow() makes it a
	# bit bigger so you don't have to be pixel-perfect.
	var target_rect := enemy_target.get_global_rect().grow(TARGET_MARGIN)
	return target_rect.has_point(screen_point)


# Godot asks this over and over while you drag over the zone:
# "would you accept this if it were dropped right here?"
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is CardData:
		return false  # Only cards, nothing else.
	if needs_target(data):
		# at_position is measured from this zone's corner; adding our
		# global_position turns it into a point on the screen.
		return is_over_enemy(global_position + at_position)
	return true


# The card was let go over the zone (and _can_drop_data said yes).
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	card_dropped.emit(data)
