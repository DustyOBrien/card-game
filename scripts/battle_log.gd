# battle_log.gd
#
# The Battle Log panel on the right of the battle: a running list of
# everything that happens, newest at the bottom.
#
# It uses a RichTextLabel, a Label that understands "BBCode" tags for colour
# and bold, e.g. "[color=red]Slime[/color] takes [b]4[/b] damage".
# The Copy button puts the whole log on your clipboard, so you can paste a
# game into a message or a note.
class_name BattleLog
extends PanelContainer

# Colours used by the battle script for different kinds of lines.
const TURN_COLOR := Color(1, 0.85, 0.3)
const PLAYER_COLOR := Color(0.6, 0.85, 1.0)
const ENEMY_COLOR := Color(1.0, 0.55, 0.45)
const CRIT_COLOR := Color(1.0, 0.6, 0.2)
const DIM_COLOR := Color(1, 1, 1, 0.6)

@onready var text: RichTextLabel = %LogText
@onready var copy_button: Button = %CopyLogButton


func _ready() -> void:
	copy_button.pressed.connect(_on_copy_pressed)


func clear() -> void:
	text.clear()


# Add one line. `color` is optional: leave it out for plain white.
func add(line: String, color: Color = Color.WHITE) -> void:
	# to_html() turns a Color into "ffcc44" style text that BBCode understands.
	# Dice like "[3]" would look like a BBCode tag, so "[" is written as [lb] ("left bracket").
	line = line.replace("[", "[lb]")
	text.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), line])


# A heading line for the start of each turn.
func add_turn(number: int) -> void:
	text.append_text("\n[b][color=#%s]Turn %d[/color][/b]\n" % [TURN_COLOR.to_html(false), number])


func _on_copy_pressed() -> void:
	# get_parsed_text() is the log without the BBCode tags.
	DisplayServer.clipboard_set(text.get_parsed_text().strip_edges())
	copy_button.text = "Copied!"
	await get_tree().create_timer(1.0).timeout
	copy_button.text = "Copy"
