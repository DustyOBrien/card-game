# play_zone.gd
#
# The invisible area above your hand in battle. Drop a card here to play it.
# It's the "drop" half of Godot's drag and drop (card.gd is the "drag" half).
# It doesn't play the card itself: it just tells the battle with a signal.
class_name PlayZone
extends Control

signal card_dropped(card_data: CardData)


# Godot asks this over and over while you drag over the zone:
# "would you accept this if it were dropped right here?"
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is CardData  # Only cards, nothing else.


# The card was let go over the zone.
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	card_dropped.emit(data)
