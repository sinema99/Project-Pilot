## ANIME animation for one character: drawn cycles on locomotion and held impact accents, smooth
## everywhere else. Only the skeleton pose is ever held - body rotation, position, the camera and
## the game stay smooth. See docs/specs/anime-animation.md.
##
## Built in code by the character (pilot9, the range dummy): add_child, then setup(). Runs late
## in the frame (process_priority), after the character's own _process. Each frame it picks a
## mode - an accent beats a cycle beats live - and hands it to the pose modifier.
class_name AnimeHold
extends Node

const _PoseHold := preload("res://scripts/anime/anime_pose_hold.gd")
const Mode := _PoseHold.Mode

## Drawings per walk / run cycle, a multiple of 4: contact, down, passing, up on each foot.
@export var drawings_per_cycle := 8
## Ground speed, m/s, below which locomotion is smooth (idle, the start of a walk).
@export var cycle_min_speed := 1.0
## Accent name -> Vector3(delay, soft hold, hard hold), seconds. The delay puts the hold on the
## impact pose rather than the cross-fade frame; accent(name, strength) holds for
## lerp(soft, hard, strength). Landing and vault delays measured by tests/_probe_anime_accents.gd
## (2026-10-21: deepest knee bend 0.25 s after touchdown from 1.5 m and 4 m; the hand plant
## 0.38 s into a 0.9 m vault); the rest are first guesses - the mantle's hands are on the lip from
## its first frame (the entry snap).
@export var accents: Dictionary = {
	&"land": Vector3(0.25, 0.07, 0.15),
	&"wall_kick": Vector3(0.03, 0.08, 0.08),
	&"mantle_grab": Vector3(0.0, 0.1, 0.1),
	&"vault_plant": Vector3(0.38, 0.08, 0.08),
	&"rail_land": Vector3(0.03, 0.07, 0.1),
	&"perfect_reflect": Vector3(0.0, 0.15, 0.15),
	&"hit": Vector3(0.0, 0.1, 0.15),
}

## Locals held during an accent when there is no skeleton (the dummy's wobble).
var inner: Array = []
## Returns true while the character is in its locomotion state, on the ground.
var cycle_state := Callable()
## Returns the character's velocity, world space.
var velocity := Callable()
## -1 follows Settings' ANIMATION row; 0 / 1 force it (tests).
var enabled_override := -1

var skeleton: Skeleton3D = null
var pose_hold: SkeletonModifier3D = null
## The mode picked this frame. Read by tests.
var mode: int = Mode.LIVE

var _accent_at := -1.0
var _accent_until := -1.0
var _accent_started := false
var _accent_valid := Callable()
var _inner_locals: Array[Transform3D] = []

static var _last_toggle_frame := -1


func _init() -> void:
	name = &"AnimeHold"
	process_priority = 1000


func setup(skel: Skeleton3D = null) -> void:
	skeleton = skel
	if skel:
		pose_hold = _PoseHold.new()
		pose_hold.name = &"AnimePoseHold"
		skel.add_child(pose_hold)


func is_enabled() -> bool:
	if enabled_override >= 0:
		return enabled_override == 1
	var settings := get_node_or_null(^"/root/Settings")
	return settings != null and settings.get_value(&"anime_animation") == "anime"


## Holds the pose `delay` from now for a hold between the accent's soft and hard lengths. A new
## accent replaces one still running. `still_on`, if given, is asked when the hold would start:
## false (he has already run out of the landing, say) drops the accent rather than freezing a
## pose from a move he is no longer in.
func accent(accent_name: StringName, strength: float = 1.0, now: float = -1.0,
		still_on: Callable = Callable()) -> void:
	if not accents.has(accent_name) or not is_enabled():
		return
	if now < 0.0:
		now = _now()
	var a: Vector3 = accents[accent_name]
	_accent_at = now + a.x
	_accent_until = _accent_at + lerpf(a.y, a.z, clampf(strength, 0.0, 1.0))
	_accent_started = false
	_accent_valid = still_on


func is_accenting() -> bool:
	return _accent_at >= 0.0


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _process(delta: float) -> void:
	tick(_now(), delta)


## One frame at time `now` (seconds). Split out of _process so tests can drive the clock.
func tick(now: float, delta: float) -> void:
	if not is_enabled():
		_accent_at = -1.0
		_set_mode(Mode.LIVE)
		return
	var m: int = Mode.LIVE
	if _accent_at >= 0.0 and now + delta * 0.5 >= _accent_at:
		if not _accent_started and _accent_valid.is_valid() and not _accent_valid.call():
			_accent_at = -1.0
		elif now < _accent_until:
			m = Mode.HOLD
		else:
			_accent_at = -1.0
	if m == Mode.LIVE and pose_hold and _in_cycle():
		m = Mode.CYCLE
	if m == Mode.HOLD and not _accent_started:
		_accent_started = true
		if pose_hold:
			pose_hold.capture_pending = true
		_inner_locals.resize(inner.size())
		for i in inner.size():
			if is_instance_valid(inner[i]):
				_inner_locals[i] = inner[i].transform
	if m == Mode.HOLD:
		for i in inner.size():
			if is_instance_valid(inner[i]) and i < _inner_locals.size():
				inner[i].transform = _inner_locals[i]
	_set_mode(m)


func _in_cycle() -> bool:
	if not cycle_state.is_valid() or not cycle_state.call():
		return false
	var v: Vector3 = velocity.call() if velocity.is_valid() else Vector3.ZERO
	v.y = 0.0
	if v.length() < cycle_min_speed:
		return false
	if skeleton:
		var local := skeleton.global_basis.inverse() * v
		local.y = 0.0
		pose_hold.travel = local.normalized()
	return true


func _set_mode(m: int) -> void:
	mode = m
	if pose_hold:
		pose_hold.stride.drawings_per_cycle = drawings_per_cycle
		# Always active: LIVE returns at once, and the modifier has to see every mode change to
		# start each cycle on a fresh drawing.
		pose_hold.mode = m


# --- QA key: U flips ANIMATION. Every hold hears it; only the first in a frame acts. ---------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.keycode != KEY_U:
		return
	var frame := Engine.get_process_frames()
	if frame == _last_toggle_frame:
		return
	_last_toggle_frame = frame
	var settings := get_node_or_null(^"/root/Settings")
	if settings:
		settings.set_value(&"anime_animation",
			"smooth" if settings.get_value(&"anime_animation") == "anime" else "anime")
