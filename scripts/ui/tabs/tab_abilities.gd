extends VBoxContainer

# The ABILITIES tab - the only tab in the shell with real content, which is the
# point: an empty window cannot validate a look. See docs/specs/ui-shell.md.
#
# BASE KIT reads live off pilot9's exported ability gates. TECH is the four
# unlocks from docs/game-overview.md, hardcoded and locked, because nothing
# persists them yet.
#
# This is the first coupling between the UI layer and gameplay state in the
# project, and the shape of it - a group lookup, null-safe, read-only - is what a
# future save system inherits.

# label, the exported property on pilot9, description
const BASE_KIT := [
	["WALK", "can_walk", "Hold to move at walking pace."],
	["DOUBLE JUMP", "air_jumps", "A second jump while airborne."],
	["SLIDE", "can_slide", "Crouch at speed to slide."],
	["SLIDE BUFFER", "can_buffer_slide", "A slide pressed early still fires on landing."],
	["SLIDE HOLD", "can_hold_slide", "Hold crouch to stay in the slide."],
	["AUTO-SLIDE", "can_auto_slide", "Steep ground starts the slide for you."],
	["MANTLE", "can_climb", "Pull up onto a ledge between 0.9 and 1.9 m."],
]

const TECH := [
	["DOUBLE JUMP", "Found in map 1."],
	["AIR DASH", "Found in map 2."],
	["WALL-RUN", "Found in map 3."],
	["RAIL GRIND", "Found in map 4."],
]

const LOCKED := "LOCKED"
const UNLOCKED := "UNLOCKED"

func _ready() -> void:
	add_theme_constant_override("separation", 6)

# Nothing here takes focus, so the row-navigation hints would be a lie.
func hints() -> Array:
	return [
		{"key": "Q/E", "label": "TAB"},
		{"key": "ESC", "label": "CLOSE"},
	]

# Rebuilt every time the tab is shown rather than once at _ready, so the rows
# cannot go stale against a player that was spawned later or replaced.
func focus_first() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	# Null on the main menu and in a headless test. Every row renders locked
	# rather than the tab refusing to draw.
	var player := get_tree().get_first_node_in_group(&"player")

	_add_header("BASE KIT")
	for entry: Array in BASE_KIT:
		_add_row(entry[0], entry[2], _reads_true(player, entry[1]))

	_add_spacer()
	_add_header("TECH")
	for entry: Array in TECH:
		_add_row(entry[0], entry[1], false)

# air_jumps is an int and the rest are bools, so the gate is "is this truthy",
# not "is this true" - an int 0 and a false both mean the verb is off.
func _reads_true(player: Node, property: String) -> bool:
	if player == null:
		return false
	var value: Variant = player.get(property)
	if value is bool:
		return value
	if value is int:
		return value > 0
	return false

func _add_header(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"SectionHeader"
	label.text = text
	add_child(label)

func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	add_child(spacer)

func _add_row(name: String, description: String, unlocked: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)

	# Locked rows dim per-label rather than by modulating the row: the
	# description is already the dim variation, and modulating would dim it twice.
	var name_label := Label.new()
	name_label.theme_type_variation = &"Body" if unlocked else &"BodyDim"
	name_label.text = name
	name_label.custom_minimum_size.x = 220
	row.add_child(name_label)

	var description_label := Label.new()
	description_label.theme_type_variation = &"BodyDim"
	description_label.text = description
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(description_label)

	var status := Label.new()
	status.theme_type_variation = &"Body" if unlocked else &"BodyDim"
	status.text = UNLOCKED if unlocked else LOCKED
	row.add_child(status)
