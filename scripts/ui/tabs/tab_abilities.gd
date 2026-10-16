extends HBoxContainer

# The ABILITIES tab: a list of every ability on the left, and on the right a detail pane for the
# one that is selected. See docs/specs/ui-shell.md and docs/specs/menu-refresh.md.
#
# BASE KIT reads live off pilot9's exported ability gates. TECH is what's left of the unlocks from
# docs/game-overview.md, hardcoded and locked, because nothing persists them yet.
#
# This is the first coupling between the UI layer and gameplay state in the project, and the shape
# of it - a group lookup, null-safe, read-only - is what a future save system inherits.

const AbilityRow := preload("res://scripts/ui/tabs/ability_row.gd")

# label, the exported property on pilot9, description
const BASE_KIT := [
	["WALK", "can_walk", "Hold to move at walking pace."],
	["DOUBLE JUMP", "air_jumps", "A second jump while airborne."],
	["SLIDE", "can_slide", "Crouch at speed to slide."],
	["SLIDE BUFFER", "can_buffer_slide", "A slide pressed early still fires on landing."],
	["SLIDE HOLD", "can_hold_slide", "Hold crouch to stay in the slide."],
	["AUTO-SLIDE", "can_auto_slide", "Steep ground starts the slide for you."],
	["MANTLE", "can_climb", "Pull up onto a ledge between 0.9 and 1.9 m."],
	["DASH", "can_dash", "Vanish and travel flat for half a second."],
	["WALL-RUN", "can_wall_run", "Run along a wall at speed."],
	["WALL-CLIMB", "can_wall_climb", "Run straight at a wall to climb 4 m up it."],
	["RAIL GRIND", "can_rail_grind", "Ride any rail you land on."],
]

# WALL-RUN and AIR DASH removed 2026-09-19 per docs/specs/pilot9-wall-run.md - both are built and
# already unlocked in BASE_KIT above. DOUBLE JUMP below is the same lie one feature earlier and
# is left as found rather than guessed at. RAIL GRIND moved up into BASE_KIT 2026-09-24 per
# docs/specs/pilot9-rail-grind.md; the map-4 unlock gates it once map 4 exists.
const TECH := [
	["DOUBLE JUMP", "Found in map 1."],
]

const LOCKED := "LOCKED"
const UNLOCKED := "UNLOCKED"
const LIST_WIDTH := 500
const DETAIL_FADE := 0.12

var _rows: Array[Control] = []
## Parallel to _rows: {"name", "description", "property"} - property is "" for TECH.
var _entries: Array[Dictionary] = []
var _detail: VBoxContainer
var _detail_name: Label
var _detail_status: Label
var _detail_text: Label
var _fade: Tween

func _ready() -> void:
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = LIST_WIDTH
	list.add_theme_constant_override("separation", 2)
	add_child(list)

	_add_header(list, "BASE KIT")
	for entry: Array in BASE_KIT:
		_add_row(list, entry[0], entry[2], entry[1])
	_add_header(list, "TECH", 12)
	for entry: Array in TECH:
		_add_row(list, entry[0], entry[1], "")

	_build_detail()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

func hints() -> Array:
	return [
		{"key": "W/S", "label": "SELECT"},
		{"key": "ESC", "label": "CLOSE"},
	]

# Re-reads the live gates every time the tab is shown, so the tags cannot go stale against a
# player that was spawned later or replaced.
func refresh() -> void:
	# Null on the main menu and in a headless test. Every row renders locked rather than the tab
	# refusing to draw.
	var player := get_tree().get_first_node_in_group(&"player")
	for i in _rows.size():
		var row := _rows[i] as AbilityRow
		var property: String = _entries[i]["property"]
		row.unlocked = property != "" and _reads_true(player, property)
		row.status_text = UNLOCKED if row.unlocked else LOCKED
	_show_detail(get_viewport().gui_get_focus_owner(), false)

func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()

# air_jumps is an int and the rest are bools, so the gate is "is this truthy", not "is this true"
# - an int 0 and a false both mean the verb is off.
func _reads_true(player: Node, property: String) -> bool:
	if player == null:
		return false
	var value: Variant = player.get(property)
	if value is bool:
		return value
	if value is int:
		return value > 0
	return false

func _add_header(parent: Control, text: String, gap := 0) -> void:
	if gap > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = gap
		parent.add_child(spacer)
	var label := Label.new()
	label.theme_type_variation = &"SectionHeader"
	label.text = text
	parent.add_child(label)

func _add_row(parent: Control, title: String, description: String, property: String) -> void:
	var row := AbilityRow.new()
	row.name = "Row_" + title.replace(" ", "_").replace("-", "_")
	row.text = title
	row.custom_minimum_size.x = LIST_WIDTH
	parent.add_child(row)
	_rows.append(row)
	_entries.append({"name": title, "description": description, "property": property})

func _build_detail() -> void:
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	add_child(_detail)

	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"DialogTitle"
	_detail_name.add_theme_font_size_override(&"font_size", 24)
	_detail.add_child(_detail_name)

	_detail_status = Label.new()
	_detail_status.theme_type_variation = &"HintLabel"
	_detail.add_child(_detail_status)

	_detail_text = Label.new()
	_detail_text.theme_type_variation = &"Body"
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(_detail_text)

func _on_focus_changed(node: Control) -> void:
	_show_detail(node, true)

func _show_detail(node: Control, animate: bool) -> void:
	var index := _rows.find(node)
	if index < 0:
		if _rows.is_empty() or _detail_name.text != "":
			return
		index = 0
	var row := _rows[index] as AbilityRow
	var entry := _entries[index]
	_detail_name.text = entry["name"]
	_detail_status.text = row.status_text
	_detail_text.text = entry["description"]
	if animate and is_visible_in_tree():
		if _fade != null:
			_fade.kill()
		_detail.modulate.a = 0.0
		_fade = create_tween()
		_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_fade.tween_property(_detail, "modulate:a", 1.0, DETAIL_FADE)
