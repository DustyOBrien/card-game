# import_cards.gd
#
# HOW TO USE
#   1. Export your spreadsheet as CSV and save it over data/cards.csv.
#   2. In Godot, double-click this file (tools/import_cards.gd) to open it
#      in the Script editor.
#   3. In the Script editor's menu choose File -> Run (or press Ctrl+Shift+X).
#   4. Check the Output panel at the bottom: it lists every card it made.
#
# An EditorScript is a script that runs inside the Godot editor itself
# (not in the game). It's handy for little helper tools like this one.
# The `@tool` line at the top is what allows it to run in the editor.
@tool
extends EditorScript


# _run() is called when you choose File -> Run.
func _run() -> void:
	CardImporter.import_cards()
	# Tell the editor to look at the cards/ folder again so the
	# FileSystem panel shows the new and removed files.
	EditorInterface.get_resource_filesystem().scan()
