# play_zone.gd
#
# The invisible area above your hand in battle. Drop a card here to play it.
# It's the "drop" half of Godot's drag and drop (card.gd is the "drag" half).
# It doesn't play the card itself: it just tells the battle with a signal.
#
# Most cards can be dropped anywhere in the zone. A single-target attack has
# to be dropped ON the enemy it should hit, when there's more than one enemy
# left to choose from. AoE and Random attacks can go anywhere.
class_name PlayZone
extends Control

# `target` is the enemy the card was dropped on (null if it wasn't on one).
signal card_dropped(card_data: CardData, target: EnemyView)

const TARGET_MARGIN := 24.0  # Extra pixels around an enemy that still count as "on" it.

var enemy_views: Array[EnemyView] = []  # The battle fills this in at the start of each fight.


func living_enemies() -> Array[EnemyView]:
	return enemy_views.filter(func(view: EnemyView) -> bool: return view.is_alive())


# Does this card have to be dropped on an enemy? Only single-target attacks,
# and only when there's a choice to make.
func needs_target(card: CardData) -> bool:
	return card.deals_damage() and card.target == CardData.Target.SINGLE and living_enemies().size() > 1


# Is this point on the screen inside the drop zone?
func is_over_zone(screen_point: Vector2) -> bool:
	return get_global_rect().has_point(screen_point)


# The living enemy at this point on the screen, or null.
func enemy_at(screen_point: Vector2) -> EnemyView:
	for view in living_enemies():
		if view.has_point(screen_point, TARGET_MARGIN):
			return view
	return null


# Godot asks this over and over while you drag over the zone:
# "would you accept this if it were dropped right here?"
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is CardData:
		return false  # Only cards, nothing else.
	if needs_target(data):
		# at_position is measured from this zone's corner; adding our
		# global_position turns it into a point on the screen.
		return enemy_at(global_position + at_position) != null
	return true


# The card was let go over the zone (and _can_drop_data said yes).
func _drop_data(at_position: Vector2, data: Variant) -> void:
	card_dropped.emit(data, enemy_at(global_position + at_position))
