class_name KnightBrain
extends Node3D

# The Knight's AI and motion (docs/specs/knight-moveset.md). He floats - he never walks: dormant in
# the drawing's pose until pilot comes near, a wake, then he drifts round pilot at ~18 m and every
# few seconds picks one of three moves (laser, missiles, smash) by distance. Every move is a list
# of timed phases: key poses (KnightPoses) blended on eased curves, his root moved in code.
#
# The brain owns his root transform (position, facing), his lean and his pose. Hits on pilot are
# feedback only (take_hit). Built by BossArena as a child of the KnightBody; `tick()` is the whole
# update so the suite can step it by hand.

enum State { DORMANT, WAKE, FLOAT, LASER, MISSILES, SMASH }

const LASER := &"laser"
const MISSILES := &"missiles"
const SMASH := &"smash"
const MOVES: Array[StringName] = [LASER, MISSILES, SMASH]
## The world (1) and the arena's stop-only wall (10): what stops the beam.
const BEAM_MASK := 1 | 512

@export_group("Waking")
## He wakes when pilot is this close (m, flat).
@export var wake_range := 40.0
@export var wake_time := 1.5
@export var wake_rise := 1.0

@export_group("Floating")
## Metres (flat) he keeps from pilot.
@export var keep_distance := 18.0
## Sideways drift round pilot (m/s), and the seconds between switching sides.
@export var strafe_speed := 4.0
@export var strafe_switch := Vector2(3.0, 6.0)
@export var follow_speed := 7.0
@export var retreat_speed := 6.0
## How quickly his drift velocity changes (m/s^2).
@export var drift_accel := 6.0
## Cruise height: his sabaton tips over the floor (m), swinging between min and max.
@export var cruise_low := 2.0
@export var cruise_high := 4.0
@export var bob_height := 0.15
@export var bob_period := 2.5
## He stays inside this radius (m) round the anchor.
@export var leash := 60.0
## Degrees of lean per m/s of drift, and the most.
@export var lean_per_speed := 2.2
@export var lean_max := 14.0
@export var turn_speed := 4.0

@export_group("Choosing")
## Seconds of floating between moves.
@export var rest_time := Vector2(2.5, 4.0)
## Distance bands (m): under `near` the smash is likely, over `far` the missiles.
@export var near := 10.0
@export var far := 30.0

@export_group("Laser")
@export var laser_draw := 0.45
@export var laser_thrust := 0.45
@export var laser_lock := 0.3
@export var laser_fire := 0.6
@export var laser_recover := 0.8
@export var laser_range := 80.0
## The beam's half-width (0.8 m across) and pilot's own radius for the hit.
@export var beam_radius := 0.4
@export var pilot_radius := 0.35
@export var laser_recoil := 2.0
@export var laser_rise := 0.5

@export_group("Missiles")
@export var missile_windup := 0.8
@export var missile_launch := 0.6
@export var missile_recover := 1.0
@export var missile_count := 6
@export var missile_rise := 3.0

@export_group("Smash")
## Over this (m, flat) he flies at pilot first, for `smash_approach` seconds.
@export var smash_fly_in := 25.0
@export var smash_approach := 1.0
@export var smash_rise := 0.7
@export var smash_mark := 0.6
## Of the mark, the seconds the ring follows pilot before it locks.
@export var smash_track := 0.35
@export var smash_dive := 0.45
@export var smash_stuck := 1.5
@export var smash_heave := 0.8
## Height over pilot's floor he rises to (sabaton tips, m).
@export var smash_height := 8.0
@export var smash_inner := 2.5
@export var smash_radius := 6.0
@export var smash_wave_time := 0.3
## A wave hit needs pilot on the ground within this band of the wave front (m).
@export var smash_wave_band := 0.7
## Camera shake on impact (h/v offset, m) and its seconds; felt even on a miss within 35 m.
@export var smash_shake := 0.22
@export var smash_shake_time := 0.6

var body: KnightBody
var pilot: Node3D
## The anchor (on the floor) and the floor's height.
var anchor := Vector3.ZERO
var floor_y := 0.0
var state := State.DORMANT
## Seconds in the current state.
var t := 0.0
## F10: hovering, never picking.
var frozen := false
## F7-F11 work (the arena turns them on).
var debug_keys := false
## The last moves, newest last (two kept).
var history: Array[StringName] = []
## Seconds until the next pick while floating.
var cooldown := 0.0
## How many times pilot was hit (a test/HUD hook).
var hits := 0
## Flat position (y unused) and height of his sabaton tips over the floor.
var pos := Vector3.ZERO
var alt := 1.0
var yaw := 0.0
var missiles: Array[KnightMissile] = []
var laser: KnightLaser
var smash: KnightSmash

var rng := RandomNumberGenerator.new()
var _vel := Vector3.ZERO
var _strafe := 1.0
var _strafe_t := 4.0
var _clock := 0.0
var _bob_w := 0.0
var _lean := Vector2.ZERO
## Added pitch (deg) a move asks for on top of the drift lean.
var _lean_extra := 0.0
var _poses := {}
var _yaw0 := 0.0
# Per-move state.
var _start_pos := Vector3.ZERO
var _start_alt := 0.0
var _aim_dir := Vector3.FORWARD
var _hit_done := false
var _launched := 0
var _approach := 0.0
var _mark := Vector3.ZERO
var _dive_from := Vector3.ZERO
var _dive_alt := 0.0
var _impacted := false
var _wave_r := 0.0
var _stuck_alt := 0.0


## Wire him up. `knight` is his body (this node's parent), `at` the anchor on the floor.
func setup(knight: KnightBody, target: Node3D, at: Vector3) -> void:
	body = knight
	pilot = target
	anchor = Vector3(at.x, 0.0, at.z)
	floor_y = at.y
	rng.randomize()
	for k: StringName in KnightPoses.ALL:
		_poses[k] = body.solve_pose(KnightPoses.ALL[k])
	var fwd := body.global_basis.z
	_yaw0 = atan2(fwd.x, fwd.z)
	laser = KnightLaser.new()
	add_child(laser)
	smash = KnightSmash.new()
	add_child(smash)
	_stuck_alt = _measure_stuck_alt()
	reset()


## Back to dormant on the anchor in the drawing's pose (F11).
func reset() -> void:
	_clear_attacks()
	state = State.DORMANT
	t = 0.0
	history.clear()
	pos = anchor
	alt = body.hover
	yaw = _yaw0
	_vel = Vector3.ZERO
	_bob_w = 0.0
	_lean = Vector2.ZERO
	_lean_extra = 0.0
	body.apply_pose()
	body.set_lean(0.0, 0.0)
	_apply_root()
	body.coat_sweep_target = 1.0
	body.reset_coat()


func _physics_process(delta: float) -> void:
	if body != null:
		tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F7: start_move(LASER)
		KEY_F8: start_move(MISSILES)
		KEY_F9: start_move(SMASH)
		KEY_F10: frozen = not frozen
		KEY_F11: reset()
		_: return
	get_viewport().set_input_as_handled()


## One frame of the Knight.
func tick(delta: float) -> void:
	_clock += delta
	t += delta
	_prune_missiles()
	match state:
		State.DORMANT:
			if pilot != null and _flat(pilot.global_position).distance_to(pos) <= wake_range:
				_enter(State.WAKE)
		State.WAKE: _tick_wake(delta)
		State.FLOAT: _tick_float(delta)
		State.LASER: _tick_laser(delta)
		State.MISSILES: _tick_missiles(delta)
		State.SMASH: _tick_smash(delta)
	if state != State.DORMANT:
		_tick_lean(delta)
	# The coat rests in the drawing's sweep while he sleeps and lets go as he wakes.
	body.coat_sweep_target = 1.0 if state == State.DORMANT else 0.0
	_apply_root()


func _enter(s: State) -> void:
	state = s
	t = 0.0
	_start_pos = pos
	_start_alt = alt
	_lean_extra = 0.0
	if s == State.FLOAT:
		cooldown = rng.randf_range(rest_time.x, rest_time.y)


## Starts a move now (the AI's pick, or F7-F9). Wakes him if dormant; cuts a running move short.
func start_move(move: StringName) -> void:
	_clear_attacks(false)
	if state == State.DORMANT or state == State.WAKE:
		alt = body.hover + wake_rise
		_bob_w = 1.0
	history.append(move)
	while history.size() > 2:
		history.pop_front()
	_hit_done = false
	_launched = 0
	_impacted = false
	_wave_r = 0.0
	match move:
		LASER: _enter(State.LASER)
		MISSILES: _enter(State.MISSILES)
		SMASH:
			_enter(State.SMASH)
			_approach = smash_approach if _pilot_dist() > smash_fly_in else 0.0


func is_awake() -> bool:
	return state != State.DORMANT


# --- waking and floating -----------------------------------------------------------------------

func _tick_wake(delta: float) -> void:
	var spread := wake_time * 0.67
	if t < spread:
		_show(&"drawing", &"wake", _smooth(t / spread))
	else:
		_show(&"wake", &"hover", _smooth((t - spread) / (wake_time - spread)), _sway())
	alt = lerpf(body.hover, body.hover + wake_rise, _smooth(t / wake_time))
	_bob_w = clampf(t / wake_time, 0.0, 1.0)
	_face_pilot(delta, 0.5)
	if t >= wake_time:
		_enter(State.FLOAT)


func _tick_float(delta: float) -> void:
	_drift(delta, 1.0)
	_cruise(delta)
	_face_pilot(delta)
	_show(&"hover", &"hover", 0.0, _sway())
	cooldown -= delta
	if cooldown <= 0.0 and not frozen and pilot != null:
		start_move(pick_move(_pilot_dist(), history, rng))


## Drift round pilot: hold `keep_distance`, circle sideways, stay on the leash. `amount` scales
## the wanted velocity (0 = come to rest).
func _drift(delta: float, amount: float) -> void:
	var want := Vector3.ZERO
	if pilot != null and amount > 0.0:
		var to := _flat(pilot.global_position) - pos
		var d := to.length()
		if d > 0.01:
			var dir := to / d
			var radial := clampf((d - keep_distance) * 0.8, -retreat_speed, follow_speed)
			var side := Vector3(-dir.z, 0.0, dir.x) * _strafe
			want = (dir * radial + side * strafe_speed) * amount
	var off := pos - anchor
	if off.length() > leash - 8.0:
		want += -off.normalized() * strafe_speed * clampf((off.length() - leash + 8.0) / 8.0, 0.0, 1.5)
	_vel = _vel.move_toward(want, drift_accel * delta)
	pos += _vel * delta
	pos = clamp_leash(pos, anchor, leash)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe = -_strafe
		_strafe_t = rng.randf_range(strafe_switch.x, strafe_switch.y)


## Cruise height: a slow swing between cruise_low and cruise_high.
func _cruise(delta: float) -> void:
	var mid := (cruise_low + cruise_high) * 0.5
	var target := mid + sin(_clock * 0.45) * (cruise_high - cruise_low) * 0.5
	alt = lerpf(alt, target, 1.0 - exp(-1.5 * delta))
	_bob_w = move_toward(_bob_w, 1.0, delta)


func _face_pilot(delta: float, rate := 1.0) -> void:
	if pilot == null:
		return
	var to := _flat(pilot.global_position) - pos
	if to.length() < 0.05:
		return
	yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-turn_speed * rate * delta))


func _tick_lean(delta: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var fwd := _vel.dot(b.z)
	var right := _vel.dot(-b.x)
	var want := Vector2(clampf(fwd * lean_per_speed, -lean_max, lean_max) + _lean_extra,
		clampf(right * lean_per_speed, -lean_max, lean_max))
	_lean = _lean.lerp(want, 1.0 - exp(-5.0 * delta))
	body.set_lean(_lean.x, _lean.y)


## The hover's loose legs and robe: a small sway on the bob's clock.
func _sway() -> Dictionary:
	var ph := TAU * _clock / bob_period
	return {
		&"LeftUpperLeg": [[Vector3.RIGHT, 4.0 * sin(ph)]],
		&"RightUpperLeg": [[Vector3.RIGHT, 4.0 * sin(ph + 1.3)]],
		&"LeftLowerLeg": [[Vector3.RIGHT, 3.0 * sin(ph - 0.6)]],
		&"RightLowerLeg": [[Vector3.RIGHT, 3.0 * sin(ph + 0.7)]],
		&"Head": [[Vector3.RIGHT, 1.5 * sin(ph + 0.4)]],
	}


# --- laser -------------------------------------------------------------------------------------

func laser_time() -> float:
	return laser_draw + laser_thrust + laser_lock + laser_fire + laser_recover


func _tick_laser(delta: float) -> void:
	_drift(delta, 0.0)
	var t_lock := laser_draw + laser_thrust
	var t_fire := t_lock + laser_lock
	var t_rec := t_fire + laser_fire
	alt = lerpf(_start_alt, _start_alt + laser_rise, _smooth(t / t_lock))
	var claw := claw_point()
	if t < t_lock:
		_face_pilot(delta, 1.5)
		if t < laser_draw:
			_show(&"hover", &"laser_draw", _smooth(t / laser_draw))
		else:
			_show(&"laser_draw", &"laser_thrust", _out((t - laser_draw) / laser_thrust))
		_aim_dir = (_pilot_chest() - claw).normalized()
		laser.show_aim(claw, claw + _aim_dir * beam_length(claw, _aim_dir), false)
	elif t < t_fire:
		_show(&"laser_thrust", &"laser_thrust", 0.0)
		var f := (t - t_lock) / laser_lock
		laser.show_aim(claw, claw + _aim_dir * beam_length(claw, _aim_dir), true, absf(sin(f * PI * 3.0)))
	elif t < t_rec:
		var f := (t - t_fire) / laser_fire
		var prev := _out((t - delta - t_fire) / laser_fire * 2.5)
		var now := _out(f * 2.5)
		pos += -Basis(Vector3.UP, yaw).z * laser_recoil * (now - maxf(prev, 0.0))
		pos = clamp_leash(pos, anchor, leash)
		_show(&"laser_thrust", &"laser_recoil", _out(f * 4.0))
		_lean_extra = -10.0 * (1.0 - f)
		var length := beam_length(claw, _aim_dir)
		laser.show_beam(claw, claw + _aim_dir * length, clampf((1.0 - f) / 0.25, 0.0, 1.0))
		if not _hit_done and pilot != null and beam_hits(claw, _aim_dir, length, beam_radius + pilot_radius,
				pilot_points()):
			_hit_done = true
			_hit_pilot(&"knight_laser", pilot.global_position + Vector3.UP * 1.0)
	elif t < laser_time():
		laser.hide_all()
		var f := (t - t_rec) / laser_recover
		if f < 0.5:
			_show(&"laser_recoil", &"laser_sag", _smooth(f * 2.0))
		else:
			_show(&"laser_sag", &"hover", _smooth(f * 2.0 - 1.0), _sway())
		_face_pilot(delta, 0.3)
	else:
		laser.hide_all()
		_enter(State.FLOAT)


## The right claw's tip, where the laser comes from.
func claw_point() -> Vector3:
	return body.bone_world("RightHand", Vector3(-0.13, 0.0, 0.02))


## How far the beam reaches from `from` along `dir`: the range, or the first wall / floor.
func beam_length(from: Vector3, dir: Vector3) -> float:
	if not is_inside_tree():
		return laser_range
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * laser_range, BEAM_MASK)
	if pilot is CollisionObject3D:
		q.exclude = [(pilot as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	return from.distance_to(hit.position) if not hit.is_empty() else laser_range


## Points up pilot's body the beam tests against.
func pilot_points() -> Array[Vector3]:
	var f := pilot.global_position
	return [f + Vector3.UP * 0.3, f + Vector3.UP * 0.9, f + Vector3.UP * 1.5]


# --- missiles ----------------------------------------------------------------------------------

func missile_time() -> float:
	return missile_windup + missile_launch + missile_recover


func _tick_missiles(delta: float) -> void:
	_drift(delta, 0.15)
	_face_pilot(delta)
	var t_launch := missile_windup
	var t_rec := t_launch + missile_launch
	if t < t_launch:
		alt = lerpf(_start_alt, _start_alt + missile_rise, _smooth(t / missile_windup))
		_show(&"hover", &"missile_raise", _smooth(t / missile_windup))
	elif t < t_rec:
		var gap := missile_launch / float(missile_count)
		while _launched < missile_count and t - t_launch >= _launched * gap:
			_launch(_launched)
			_launched += 1
		# The arms snap a little higher on each shot.
		var since := (t - t_launch) - (_launched - 1) * gap
		var kick := clampf(1.0 - since / gap, 0.0, 1.0) * 0.25
		_show(&"missile_raise", &"missile_snap", float(_launched) / missile_count * 0.75 + kick)
		_lean_extra = -6.0
	elif t < missile_time():
		while _launched < missile_count:
			_launch(_launched)
			_launched += 1
		var f := (t - t_rec) / missile_recover
		alt = lerpf(_start_alt + missile_rise, (cruise_low + cruise_high) * 0.5, _smooth(f))
		_show(&"missile_snap", &"hover", _smooth(f), _sway())
	else:
		_enter(State.FLOAT)


## The order the six fan out: outside in, alternating sides.
const FAN_ORDER := [0, 5, 1, 4, 2, 3]

func _launch(i: int) -> void:
	var b := Basis(Vector3.UP, yaw)
	var slot: int = FAN_ORDER[i % FAN_ORDER.size()] if missile_count == 6 else i
	var side := lerpf(-1.0, 1.0, float(slot) / maxf(missile_count - 1, 1))
	var from := body.bone_world("UpperChest") + Vector3.UP * 0.4 - b.z * 0.5 + b.x * side * 0.7
	var dir := (Vector3.UP + b.x * side * 0.75 - b.z * 0.35).normalized()
	var m := KnightMissile.new()
	m.shooter = body
	m.target = pilot
	m.velocity = dir * m.climb_speed
	var parent := body.get_parent() if body.get_parent() != null else self
	parent.add_child(m)
	m.global_position = from
	missiles.append(m)


func _prune_missiles() -> void:
	for k in range(missiles.size() - 1, -1, -1):
		if not is_instance_valid(missiles[k]):
			missiles.remove_at(k)


# --- smash -------------------------------------------------------------------------------------

func smash_time() -> float:
	return _approach + smash_rise + smash_mark + smash_dive + smash_stuck + smash_heave


func _tick_smash(delta: float) -> void:
	var t_rise := _approach
	var t_mark := t_rise + smash_rise
	var t_dive := t_mark + smash_mark
	var t_hit := t_dive + smash_dive
	var t_heave := t_hit + smash_stuck
	var p := _flat(pilot.global_position) if pilot != null else pos
	if t < t_rise:
		# Fly in at him first.
		var f := t / _approach
		var to := p - _start_pos
		var stop := _start_pos + to.normalized() * maxf(to.length() - 12.0, 0.0)
		var before := pos
		pos = _start_pos.lerp(stop, _smooth(f))
		_vel = (pos - before) / maxf(delta, 0.001)
		_face_pilot(delta, 2.0)
		_show(&"hover", &"smash_gather", _smooth(f) * 0.3)
		_lean_extra = 10.0
	elif t < t_mark:
		var f := (t - t_rise) / smash_rise
		if t - delta < t_rise or f <= 0.0:
			_start_pos = pos
			_start_alt = alt
		pos = _start_pos.lerp(p, _out(f))
		pos = clamp_leash(pos, anchor, leash)
		alt = lerpf(_start_alt, smash_height, _out(f))
		_vel = Vector3.ZERO
		_face_pilot(delta, 2.0)
		_show(&"hover", &"smash_gather", _smooth(f))
		_lean_extra = 0.0
	elif t < t_dive:
		var f := (t - t_mark) / smash_mark
		var tracking := t - t_mark < smash_track
		if tracking:
			_mark = Vector3(p.x, floor_y, p.z)
		pos = pos.lerp(_flat(_mark), 1.0 - exp(-10.0 * delta))
		pos = clamp_leash(pos, anchor, leash)
		alt = smash_height
		_show(&"smash_gather", &"smash_curl", _smooth(f))
		var flash := 0.0 if tracking else absf(sin((t - t_mark - smash_track) * PI * 8.0))
		smash.show_mark(_mark, not tracking, flash)
		_dive_from = pos
		_dive_alt = alt
		_lean_extra = 8.0
	elif t < t_hit:
		var f := (t - t_dive) / smash_dive
		var k := f * f * f
		pos = _dive_from.lerp(_flat(_mark), k)
		alt = lerpf(_dive_alt, _stuck_alt, k)
		_bob_w = 0.0
		_show(&"smash_curl", &"smash_dive", _out(f * 2.0))
		smash.show_mark(_mark, true, 1.0)
		_lean_extra = 0.0
	elif t < t_heave:
		if not _impacted:
			_impact()
		pos = _flat(_mark)
		alt = _stuck_alt
		var since := t - t_hit
		var tremble := {&"Spine": [[Vector3.RIGHT, 1.5 * sin(since * 40.0)]],
			&"Chest": [[Vector3.UP, 1.2 * sin(since * 33.0)]]}
		_show(&"smash_dive", &"smash_stuck", _out(since / 0.12), tremble)
		_lean_extra = 0.0
		_tick_wave(since)
	elif t < smash_time():
		smash.hide_wave()
		var f := (t - t_heave) / smash_heave
		alt = lerpf(_stuck_alt, (cruise_low + cruise_high) * 0.5, _smooth(f))
		_bob_w = f
		_show(&"smash_stuck", &"hover", _smooth(f), _sway())
		_face_pilot(delta, 0.5)
	else:
		smash.hide_wave()
		_enter(State.FLOAT)


func _impact() -> void:
	_impacted = true
	smash.hide_mark()
	smash.impact(_mark)
	if pilot != null and smash_inner_hits(_mark, pilot.global_position, smash_inner):
		_hit_done = true
		_hit_pilot(&"knight_smash", pilot.global_position + Vector3.UP * 0.5)
	if pilot != null:
		var d := _flat(pilot.global_position).distance_to(_flat(_mark))
		var fb: Node = pilot.get(&"hit_feedback") if &"hit_feedback" in pilot else null
		if fb != null and fb.has_method(&"shake") and d < 35.0:
			fb.shake(smash_shake * clampf(1.2 - d / 35.0, 0.3, 1.0), smash_shake_time)


func _tick_wave(since: float) -> void:
	if since > smash_wave_time + 0.15:
		smash.hide_wave()
		return
	var prev := _wave_r
	_wave_r = lerpf(smash_inner, smash_radius, clampf(since / smash_wave_time, 0.0, 1.0))
	smash.show_wave(_mark, _wave_r, 1.0 - clampf((since - smash_wave_time) / 0.15, 0.0, 1.0))
	if not _hit_done and pilot != null and since <= smash_wave_time + 0.02 \
			and wave_hits(_mark, pilot.global_position, prev, _wave_r, smash_wave_band, _grounded()):
		_hit_done = true
		_hit_pilot(&"knight_smash_wave", pilot.global_position + Vector3.UP * 0.3)


## His sabaton height with his claws on the floor in the stuck pose.
func _measure_stuck_alt() -> float:
	var keep := body.global_transform
	body.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, floor_y, 0.0))
	body.set_lean(0.0, 0.0)
	body.show_pose(_poses[&"smash_stuck"])
	var low := INF
	for tip in [body.bone_world("LeftHand", Vector3(0.13, 0.0, 0.02)),
			body.bone_world("RightHand", Vector3(-0.13, 0.0, 0.02))]:
		low = minf(low, tip.y - floor_y)
	body.global_transform = keep
	body.apply_pose()
	# Root y = floor + alt - hover; claws sink 0.15 m into the floor.
	return body.hover - low - 0.15


# --- shared ------------------------------------------------------------------------------------

func _show(a: StringName, b: StringName, f: float, extra := {}) -> void:
	body.show_blend(_poses[a], _poses[b], f, extra)


func _apply_root() -> void:
	var y := floor_y + alt - body.hover + bob_height * _bob_w * sin(TAU * _clock / bob_period)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y, pos.z))


func _clear_attacks(free_missiles := true) -> void:
	if laser != null:
		laser.hide_all()
	if smash != null:
		smash.hide_mark()
		smash.hide_wave()
	if free_missiles:
		for m in missiles:
			if is_instance_valid(m):
				m.queue_free()
		missiles.clear()


func _hit_pilot(kind: StringName, point: Vector3) -> void:
	hits += 1
	if pilot != null and pilot.has_method(&"take_hit"):
		pilot.take_hit(0.0, kind, point)


func _pilot_dist() -> float:
	return _flat(pilot.global_position).distance_to(pos) if pilot != null else INF


func _pilot_chest() -> Vector3:
	return pilot.global_position + Vector3.UP * 1.1


## Pilot on the ground (a jump clears the smash's wave).
func _grounded() -> bool:
	if pilot == null:
		return false
	if pilot.has_method(&"is_on_floor"):
		return pilot.is_on_floor()
	return pilot.global_position.y - floor_y < 0.15


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _smooth(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


static func _out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c) * (1.0 - c)


# --- pure rules (the suite tests these) --------------------------------------------------------

## How likely each move is at `dist` (m, flat), given the last moves (newest last).
static func move_weights(dist: float, last: Array, near_m := 10.0, far_m := 30.0) -> Dictionary:
	var w := {}
	if dist < near_m:
		w = {LASER: 0.2, MISSILES: 0.1, SMASH: 0.7}
	elif dist <= far_m:
		w = {LASER: 0.6, MISSILES: 0.25, SMASH: 0.15}
	else:
		w = {LASER: 0.25, MISSILES: 0.6, SMASH: 0.15}
	# Never three in a row.
	if last.size() >= 2 and last[-1] == last[-2]:
		w[last[-1]] = 0.0
	return w


static func pick_move(dist: float, last: Array, r: RandomNumberGenerator) -> StringName:
	var w := move_weights(dist, last)
	var total := 0.0
	for k in MOVES:
		total += float(w[k])
	var roll := r.randf() * total
	for k in MOVES:
		roll -= float(w[k])
		if roll <= 0.0 and float(w[k]) > 0.0:
			return k
	for k in MOVES:
		if float(w[k]) > 0.0:
			return k
	return LASER


## A beam from `origin` along `dir` for `length` m touches any of `points` within `radius`.
static func beam_hits(origin: Vector3, dir: Vector3, length: float, radius: float, points: Array) -> bool:
	var end := origin + dir.normalized() * length
	for p: Vector3 in points:
		if Geometry3D.get_closest_point_to_segment(p, origin, end).distance_to(p) <= radius:
			return true
	return false


## The impact itself: pilot's feet within `inner` (flat) of the centre and not far above it.
static func smash_inner_hits(centre: Vector3, feet: Vector3, inner: float) -> bool:
	return _flat(feet).distance_to(_flat(centre)) <= inner and feet.y - centre.y < 3.0


## The wave front moved from `r_prev` to `r_now` this frame: it hits a grounded pilot it passed
## (or who stands within `band` of it).
static func wave_hits(centre: Vector3, feet: Vector3, r_prev: float, r_now: float, band: float,
		grounded: bool) -> bool:
	if not grounded:
		return false
	var d := _flat(feet).distance_to(_flat(centre))
	return d >= r_prev - band and d <= r_now + band


## `p` (flat) kept inside `radius` of `centre`.
static func clamp_leash(p: Vector3, centre: Vector3, radius: float) -> Vector3:
	var off := p - centre
	off.y = 0.0
	if off.length() <= radius:
		return p
	var c := centre + off.normalized() * radius
	return Vector3(c.x, p.y, c.z)
