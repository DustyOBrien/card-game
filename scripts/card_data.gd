# card_data.gd
#
# A CardData describes ONE kind of card: its name, cost, and what it does.
# It extends Resource, which is Godot's word for "a chunk of data you can
# save as a file". Each card type lives in its own .tres file in the
# cards/ folder (strike.tres, defend.tres). Open one in the Godot editor
# and you can change its numbers in the Inspector without touching code.
#
# `class_name CardData` gives this type a global name, so any other script
# can write `CardData` (like using a class you imported in Python).
class_name CardData
extends Resource

# @export makes a variable show up in the Inspector so you can edit it there.
@export var card_name: String = "New Card"
@export var cost: int = 1
@export var damage: int = 0  # Damage dealt to the enemy when played.
@export var block: int = 0  # Block gained by the player when played.
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE  # Tint used when drawing the card.
