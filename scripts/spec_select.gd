# spec_select.gd
#
# The Spec screen (scenes/spec_select.tscn), right after you choose a class:
# pick one of the class's specs (data/talents/specs.csv). A spec is like a
# talent you get for free, and it decides how the class builds its deck:
# the Adventurer's Pack Rat holds a huge deck, but only 1 copy of each card.
#
# One panel per spec, built here in code (like Character Select).
extends Control

const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const PANEL_SIZE := Vector2(300, 360)
const CURRENT_COLOR := Color(1, 0.82, 0.3)  # Gold border on the spec you have now.

@onready var title_label: Label = %TitleLabel
@onready var spec_list: HBoxContainer = %SpecList
@onready var back_button: Button = %BackButton


func _ready() -> void:
	GameState.ensure_ready()  # For running this scene on its own with F6.
	var character_class := GameState.character_class
	title_label.text = "Choose Your %s Spec" % character_class.display_name
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE))
	for spec in GameState.specs_for(character_class):
		spec_list.add_child(make_spec_panel(character_class, spec))
	add_explanation()


# A box under the title saying what a spec is (the first time it's a big deal).
func add_explanation() -> void:
	var label: Label = $Margin/Layout/HelpLabel
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.65))
	label.text = "A SPECIALIZATION is a free bonus that sets how your %s plays and builds its deck. You can change it any time from the Deck Builder.%s" % [
		GameState.character_class.display_name,
		"" if GameState.talents_open() else " (Talent trees for each spec come later.)"]



func make_spec_panel(character_class: CharacterClass, spec: Talent) -> Control:
	var is_current := GameState.spec_of(character_class) == spec.tree
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = character_class.color.darkened(0.15)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	if is_current:
		style.border_color = CURRENT_COLOR
		style.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = spec.talent_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 28)
	box.add_child(name_label)

	var description := Label.new()
	description.text = spec.rules
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 17)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Push the button down.
	box.add_child(description)

	# How many talent points are in this spec's tree (talents can mix trees).
	var spent := GameState.talent_points_spent(character_class, spec.tree)
	if spent > 0:
		var spent_label := Label.new()
		spent_label.text = "%d talent point(s) in this tree" % spent
		spent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spent_label.add_theme_font_size_override("font_size", 14)
		spent_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		box.add_child(spent_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 20)
	if not GameState.is_spec_open(spec):
		# Locked (specs.csv Unlocked = No): greyed out with a padlock line.
		button.text = "🔒 Locked"
		button.disabled = true
		button.tooltip_text = "Unlocked later in your adventure."
		panel.modulate = Color(0.6, 0.6, 0.6)
	else:
		button.text = "Keep %s" % spec.talent_name if is_current else "Choose"
		button.theme_type_variation = &"PrimaryButton" if not is_current else &""
		button.pressed.connect(_on_spec_chosen.bind(character_class, spec))
	box.add_child(button)
	return panel


func _on_spec_chosen(character_class: CharacterClass, spec: Talent) -> void:
	GameState.set_spec(character_class, spec.tree)  # Gives talent points back if it changed.
	# Too small to play (your very first deck, before you had a spec)? Build
	# the starter deck again, now the spec says which school cards fit.
	if GameState.deck.size() < character_class.min_deck_size:
		GameState.deck = GameState.make_starter_deck()
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)
