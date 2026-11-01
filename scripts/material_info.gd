# material_info.gd
#
# A MATERIAL: Lumber, Green Ooze... Enemies drop them (the Drops column in
# enemies.csv), and buildings, flasks and quests use them. Like gold, what
# you find in the dungeon only counts once you get home (or if it's in your
# Save Sack). At home they're kept in GameState.materials (the Bank).
#
# From data/progression/materials.csv -> materials/*.tres.
class_name MaterialInfo
extends Resource

@export var material_name: String = "Material"
@export_multiline var description: String = ""
@export var color: Color = Color.WHITE  # Tints the icon (and names on screen).
@export var icon: Texture2D


# "Lumber 5; Green Ooze 2" -> {"Lumber": 5, "Green Ooze": 2}. The number is
# the last word, so names can have spaces. No number means 1.
static func parse_costs(text: String) -> Dictionary:
	var costs := {}
	for part in text.split(";", false):
		var words := part.strip_edges().split(" ", false)
		if words.is_empty():
			continue
		var amount := 1
		if words.size() > 1 and words[-1].is_valid_int():
			amount = words[-1].to_int()
			words.remove_at(words.size() - 1)
		var material_name := " ".join(words)
		costs[material_name] = costs.get(material_name, 0) + amount
	return costs


# {"Lumber": 5} -> "5 Lumber".
static func costs_text(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for material_name in costs:
		parts.append("%d %s" % [costs[material_name], material_name])
	return ", ".join(parts)
