# character_select.gd
#
# The first screen (scenes/character_select.tscn): pick a class.
#
# There's one panel per class file in classes/, built here in code. So a new
# class shows up on its own: no need to touch this script or the scene.
# Picking a class saves it in GameState and moves on to the deck builder.
extends Control

const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"

@onready var class_list: HBoxContainer = %ClassList


func _ready() -> void:
	for character_class in GameState.load_classes():
		class_list.add_child(make_class_panel(character_class))


# Build one class's panel: name, description, rules, and a Choose button.
func make_class_panel(character_class: CharacterClass) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 400)
	# A StyleBoxFlat is a simple coloured box with rounded corners. It's the same
	# thing card.tscn uses for its background, just made in code this time.
	var style := StyleBoxFlat.new()
	style.bg_color = character_class.color
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)  # Space between the edge and what's inside.
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = character_class.display_name
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var description_label := Label.new()
	description_label.text = character_class.description
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Wrap long lines.
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	box.add_child(description_label)

	var rules_label := Label.new()
	rules_label.text = character_class.get_rules_text()  # Made from the class's numbers.
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.add_theme_font_size_override("font_size", 18)
	rules_label.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Push the button to the bottom.
	box.add_child(rules_label)

	var choose_button := Button.new()
	choose_button.text = "Choose %s" % character_class.display_name
	choose_button.custom_minimum_size = Vector2(0, 48)
	choose_button.add_theme_font_size_override("font_size", 22)
	# bind() remembers which class this button is for (see deck_builder.gd).
	choose_button.pressed.connect(_on_class_chosen.bind(character_class))
	box.add_child(choose_button)

	return panel


func _on_class_chosen(character_class: CharacterClass) -> void:
	GameState.choose_class(character_class)  # Also gives you that class's starter deck.
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)
