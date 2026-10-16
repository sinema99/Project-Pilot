extends Node3D

# Cutscene shot 2: pilot9 in the cockpit seat inside the screen sphere. See
# docs/specs/cutscene-cockpit.md. A static hold for now; the AnimationPlayer's `shot` animation
# sets the length and is where motion goes later.
#
# Plays once on load and holds the last frame. R restarts, Esc quits.

## Emitted when the shot reaches its last frame. Later shots chain off this.
signal finished

const SHOT := &"shot"

@export var autoplay := true
## pilot9's one-sided white edge light (docs/specs/pilot9-rim-light.md), on his meshes only.
@export var rim_light := true
@export var rim_light_material: Material = preload("res://resources/pilot_rim_light.tres")

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var pilot: Node3D = $Seat/Pilot


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	animation_player.animation_finished.connect(_on_animation_finished)
	if rim_light:
		for mi in pilot.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = rim_light_material
	if autoplay:
		restart()


## Plays the shot from its first frame.
func restart() -> void:
	animation_player.stop()
	animation_player.play(SHOT)
	animation_player.seek(0.0, true)


func _on_animation_finished(anim: StringName) -> void:
	if anim == SHOT:
		finished.emit()


# _input, not _unhandled_input: the UI autoload reads Esc in its own _input to open the pause
# menu. The current scene sits after the autoloads, so it sees the key first and consumes it.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		get_viewport().set_input_as_handled()
		restart()
	elif key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		get_tree().quit()
