class_name MissionHud
extends CanvasLayer

# Greybox HUD: a run clock (top left), a line for events (rest saved, double jump, shortcut,
# exit time) and the debug keys. The debug keys live here too, gated by `debug_keys`:
#   F1-F3  go to rest pad 1-3 (and save it)
#   F12    double jump on / off
# See docs/specs/internals-map.md.

@export var debug_keys := true
## Seconds an event line stays up.
@export var message_time := 3.0

var _clock := 0.0
var _running := true
var _message_left := 0.0
var _clock_label: Label
var _message_label: Label

## The MissionHud of the mission `node` belongs to, or null.
static func of(node: Node) -> MissionHud:
	var mission := MissionMap.of(node)
	if mission == null:
		return null
	for child in mission.get_children():
		if child is MissionHud:
			return child
	return null

## Shows `text` on the HUD of `node`'s mission, if it has one.
static func say(node: Node, text: String) -> void:
	var hud := of(node)
	if hud != null:
		hud.show_message(text)

func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 20)
	add_child(box)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override(&"font_size", 22)
	box.add_child(_clock_label)
	_message_label = Label.new()
	_message_label.add_theme_font_size_override(&"font_size", 28)
	box.add_child(_message_label)
	if debug_keys:
		var keys := Label.new()
		keys.text = "F1-F3 rest pads   F12 double jump"
		keys.modulate = Color(1, 1, 1, 0.45)
		box.add_child(keys)

func _process(delta: float) -> void:
	if _running:
		_clock += delta
	_clock_label.text = clock_text(_clock)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message_label.text = ""

func show_message(text: String, seconds := -1.0) -> void:
	_message_label.text = text
	_message_left = message_time if seconds < 0.0 else seconds

## Stops the clock and shows the run time until the scene is reloaded.
func finish() -> void:
	if not _running:
		return
	_running = false
	show_message("EXIT - %s" % clock_text(_clock), 1e9)

static func clock_text(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds) / 60, fmod(seconds, 60.0)]

func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var mission := MissionMap.of(self)
	if mission == null or mission.pilot == null:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F1, KEY_F2, KEY_F3:
			var want := (event as InputEventKey).physical_keycode - KEY_F1 + 1
			for pad in get_tree().get_nodes_in_group(&"rest_pad"):
				if pad.index == want and MissionMap.of(pad) == mission:
					mission.set_checkpoint(pad)
					mission.respawn()
					show_message("REST %d" % want)
		KEY_F12:
			var on := int(mission.pilot.get("air_jumps")) == 0
			mission.pilot.set("air_jumps", 1 if on else 0)
			show_message("DOUBLE JUMP %s" % ("ON" if on else "OFF"))
		_:
			return
	get_viewport().set_input_as_handled()
