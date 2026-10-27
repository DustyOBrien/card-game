# character_select.gd
#
# The first screen (scenes/character_select.tscn): pick a class.
#
# There's one panel per class file in classes/, built here in code. So a new
# class shows up on its own: no need to touch this script or the scene.
# Picking a class saves it in GameState and moves on to the deck builder.
extends Control

const DECK_BUILDER_SCENE := "res://scenes/deck_builder.tscn"
const TALENTS_SCENE := "res://scenes/talents.tscn"
const POINT_READY_COLOR := Color(1, 0.82, 0.3)

@onready var class_list: HBoxContainer = %ClassList


const PANEL_SIZE := Vector2(224, 480)
const EMBLEM_SIZE := Vector2(96, 96)
const LOCKED_TINT := Color(0.5, 0.5, 0.5)  # Locked classes are drawn darker.
const UNLOCK_TEXT_COLOR := Color(1, 0.85, 0.3)


func _ready() -> void:
	# Every card in the game, so each class can count its unlocked cards.
	var all_cards := GameState.load_all_cards()
	for character_class in GameState.load_classes():
		class_list.add_child(make_class_panel(character_class, all_cards))
	add_reset_button()


# The Reset Save button in the top corner, for testing from the start.
# It asks first with a ConfirmationDialog: a small pop-up window with OK and
# Cancel buttons. Its `confirmed` signal only fires if you press OK.
func add_reset_button() -> void:
	var reset_button := Button.new()
	reset_button.text = "Reset Save"
	reset_button.tooltip_text = "Start over: lose your cards, gold and Exp"
	# Anchor it to the top-right corner of the screen, 24 pixels in.
	reset_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	reset_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Grow to the left, staying on screen.
	add_child(reset_button)

	var confirm := ConfirmationDialog.new()
	confirm.title = "Reset Save?"
	confirm.dialog_text = "This deletes your save: every card you found, your gold,\nand all card and class Exp. You start again as a new player."
	confirm.ok_button_text = "Reset"
	add_child(confirm)
	reset_button.pressed.connect(confirm.popup_centered)
	confirm.confirmed.connect(_on_reset_confirmed)


func _on_reset_confirmed() -> void:
	GameState.reset_save()
	get_tree().reload_current_scene()  # Rebuild this screen: locked classes lock again.


# Build one class's panel: name, emblem, description, rules, and a button.
func make_class_panel(character_class: CharacterClass, all_cards: Array[CardData]) -> Control:
	var unlocked := character_class.is_unlocked(all_cards)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	# A StyleBoxFlat is a simple coloured box with rounded corners. It's the same
	# thing card.tscn uses for its background, just made in code this time.
	var style := StyleBoxFlat.new()
	style.bg_color = character_class.color
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)  # Space between the edge and what's inside.
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = character_class.display_name
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	# A TextureRect shows an image. These settings shrink the emblem to fit
	# EMBLEM_SIZE without stretching it out of shape.
	var emblem := TextureRect.new()
	emblem.texture = character_class.emblem
	emblem.custom_minimum_size = EMBLEM_SIZE
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(emblem)

	var description_label := Label.new()
	description_label.text = character_class.description
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Wrap long lines.
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.add_theme_font_size_override("font_size", 15)
	description_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	box.add_child(description_label)

	var rules_label := Label.new()
	rules_label.text = character_class.get_rules_text()  # Made from the class's numbers.
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.add_theme_font_size_override("font_size", 13)
	rules_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	rules_label.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Push the bottom part down.
	box.add_child(rules_label)

	# The class's level and Exp.
	var exp_bar := ExpBar.new()
	exp_bar.custom_minimum_size = Vector2(0, 22)
	box.add_child(exp_bar)
	exp_bar.show_class(character_class)

	if not unlocked:
		# Say how to unlock it, with progress: "Unlock 12 Strength cards (6 / 12)".
		var unlock_label := Label.new()
		unlock_label.text = character_class.get_unlock_text(all_cards)
		unlock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlock_label.add_theme_font_size_override("font_size", 15)
		unlock_label.add_theme_color_override("font_color", UNLOCK_TEXT_COLOR)
		box.add_child(unlock_label)

	var choose_button := Button.new()
	choose_button.custom_minimum_size = Vector2(0, 44)
	choose_button.add_theme_font_size_override("font_size", 20)
	if unlocked:
		choose_button.text = "Choose"
		# bind() remembers which class this button is for (see deck_builder.gd).
		choose_button.pressed.connect(_on_class_chosen.bind(character_class))
		box.add_child(make_talents_button(character_class))
	else:
		choose_button.text = "Locked"
		choose_button.disabled = true
		# self_modulate darkens the panel's background only, so the unlock
		# text on top stays bright and easy to read.
		panel.self_modulate = LOCKED_TINT
		emblem.modulate = Color(0.4, 0.4, 0.4)
	box.add_child(choose_button)

	return panel


# The Talents button. When there are points to spend it turns gold and says
# so, like "Talent point ready!", so a level up is hard to miss.
func make_talents_button(character_class: CharacterClass) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.add_theme_font_size_override("font_size", 15)
	var ready := GameState.talent_points_text(character_class)
	if not ready.is_empty():
		button.text = ready
		button.add_theme_color_override("font_color", POINT_READY_COLOR)
		button.add_theme_color_override("font_hover_color", POINT_READY_COLOR)
	else:
		button.text = "Talents"
	button.pressed.connect(_on_talents_pressed.bind(character_class))
	return button


func _on_talents_pressed(character_class: CharacterClass) -> void:
	GameState.choose_class(character_class)
	GameState.talents_return_scene = scene_file_path  # Come back here.
	get_tree().change_scene_to_file(TALENTS_SCENE)


func _on_class_chosen(character_class: CharacterClass) -> void:
	GameState.choose_class(character_class)  # Also gives you that class's starter deck.
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)
