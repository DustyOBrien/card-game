# card.gd
#
# The script for ONE card on screen (scenes/card.tscn).
# The card is a Button, so Godot already handles hovering and clicking.
# When it's clicked, the card emits its own `played` signal and hands over
# its CardData. The card doesn't know the rules of the game; the battle
# script decides what playing the card actually does.
class_name Card
extends Button

signal played(card_data: CardData)

var card_data: CardData

# @onready means "fill this in when the node is ready", because child nodes
# don't exist yet when the script is first created.
# The % symbol finds a child node marked "Access as Unique Name" in the editor.
@onready var cost_label: Label = %CostLabel
@onready var school_label: Label = %SchoolLabel
@onready var name_label: Label = %NameLabel
@onready var type_label: Label = %TypeLabel
@onready var effect_label: Label = %EffectLabel


func _ready() -> void:
	# `pressed` is a signal every Button has. Connect it to our function.
	pressed.connect(_on_pressed)


# Called by the battle script right after the card is added to the hand.
func setup(data: CardData) -> void:
	card_data = data
	cost_label.text = str(data.cost)
	school_label.text = data.get_school_text()
	name_label.text = data.card_name
	type_label.text = data.get_type_text()
	effect_label.text = data.effect
	# self_modulate tints only the card background, not the text on it.
	self_modulate = data.color


func _on_pressed() -> void:
	played.emit(card_data)
