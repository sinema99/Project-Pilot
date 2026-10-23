extends SceneTree

# Probe for docs/specs/anime-animation.md: holds `forward` (then `sprint`) on the real trial pilot
# and reports the drawn cycle - drawings per second, which boundaries fire, and the stride signal's
# range - for walk, run and sprint.
#   godot --headless --path . --script tests/_probe_anime_cycle.gd

var _frame := 0
var _pilot: Node = null
var _mod: Node = null
var _phase := ""
var _t0 := 0.0
var _d0 := 0
var _events := {}
var _smin := 0.0
var _smax := 0.0

func _initialize() -> void:
	var scene := (load("res://scenes/trial.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_pilot = scene.get_node("Pilot9")

func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func _begin(phase: String) -> void:
	_phase = phase
	_t0 = _now()
	_d0 = _mod.drawings
	_events = {}
	_smin = 0.0
	_smax = 0.0

func _report() -> void:
	var secs := _now() - _t0
	var n: int = _mod.drawings - _d0
	var speed := Vector3(_pilot.velocity.x, 0, _pilot.velocity.z).length()
	print("%-7s %.1f m/s  %d drawings in %.2f s = %.1f/s  mode %d  s %.2f..%.2f  events %s" % [
		_phase, speed, n, secs, n / secs, _pilot.anime_hold.mode, _smin, _smax, _events])

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 30:
		_mod = _pilot.anime_hold.pose_hold
		_pilot.anime_hold.enabled_override = 1
		Input.action_press(&"forward")
		Input.action_press(&"walk")
	if _frame == 120:
		_begin("walk")
	if _frame == 360:
		_report()
		Input.action_release(&"walk")
	if _frame == 420:
		_begin("run")
	if _frame == 660:
		_report()
		Input.action_press(&"sprint")
	if _frame == 720:
		_begin("sprint")
	if _frame == 960:
		_report()
		return true
	if _mod and _phase != "":
		var e: StringName = _mod.stride.last_event
		if e != &"":
			_events[e] = _events.get(e, 0) + 1
			_mod.stride.last_event = &""
		var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
		var s: float = _mod.stride_signal(skel)
		_smin = minf(_smin, s)
		_smax = maxf(_smax, s)
	return false
