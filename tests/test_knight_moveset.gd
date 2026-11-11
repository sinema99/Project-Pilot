extends "res://tests/test_case.gd"

# The Knight's moveset - see docs/specs/knight-moveset.md. Headless steps the brain by hand with a
# stand-in pilot (a Node3D that records take_hit; on the ground when his feet are on the floor):
# waking, floating, the pick rules, each move's timing and hits, the missiles' flight and reflect,
# the debug keys and the arena wiring. How the moves look is judged from tests/_probe_knight_moves.gd.

const ARENA := "res://scenes/boss_arena.tscn"
const DT := 1.0 / 60.0

var _nodes: Array[Node] = []

func end() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	super()

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

## A stand-in pilot: records hits.
func _pilot(at: Vector3) -> Node3D:
	var src := GDScript.new()
	src.source_code = "extends Node3D\nvar hits: Array = []\nfunc take_hit(_a, kind, _p):\n\thits.append(kind)\n"
	src.reload()
	var p := Node3D.new()
	p.set_script(src)
	_root().add_child(p)
	_nodes.append(p)
	p.global_position = at
	return p

## A knight on the anchor at the origin facing +Z, his brain wired to `pilot`.
func _knight(pilot: Node3D) -> KnightBrain:
	var holder := Node3D.new()
	_root().add_child(holder)
	_nodes.append(holder)
	var k := KnightBody.new()
	holder.add_child(k)
	var brain := KnightBrain.new()
	k.add_child(brain)
	brain.setup(k, pilot, Vector3.ZERO)
	brain.rng.seed = 7
	return brain

func _run(brain: KnightBrain, seconds: float, each := Callable()) -> void:
	var n := int(round(seconds / DT))
	for i in n:
		brain.tick(DT)
		for m in brain.missiles:
			if is_instance_valid(m):
				m.step(DT)
		if each.is_valid():
			each.call()

func _awake(pilot_at: Vector3) -> Array:
	var p := _pilot(pilot_at)
	var b := _knight(p)
	b.frozen = true
	b.start_move(KnightBrain.LASER)
	b._clear_attacks()
	b._enter(KnightBrain.State.FLOAT)
	return [b, p]


# --- waking ----------------------------------------------------------------------------------

func test_he_sleeps_until_pilot_is_within_40m() -> void:
	var p := _pilot(Vector3(0, 0, 50))
	var b := _knight(p)
	_run(b, 1.0)
	eq(b.state, KnightBrain.State.DORMANT, "dormant at 50 m")
	approx(b.alt, b.body.hover, 0.001, "hovering at the drawing's height")
	p.global_position = Vector3(0, 0, 39)
	_run(b, DT)
	eq(b.state, KnightBrain.State.WAKE, "wakes at 39 m")
	_run(b, b.wake_time + 0.05)
	eq(b.state, KnightBrain.State.FLOAT, "floats after the wake")
	check(b.alt > b.body.hover + 0.5, "the wake lifts him")
	p.global_position = Vector3(0, 0, 200)
	_run(b, 2.0)
	check(b.is_awake(), "never goes back to sleep")


# --- floating --------------------------------------------------------------------------------

func test_he_holds_his_distance_and_faces_pilot() -> void:
	var a := _awake(Vector3(0, 0, 6))
	var b: KnightBrain = a[0]
	var p: Node3D = a[1]
	_run(b, 12.0)
	var d := KnightBrain._flat(p.global_position).distance_to(b.pos)
	check(d > 13.0 and d < 23.0, "about 18 m from pilot (%.1f)" % d)
	var to := (KnightBrain._flat(p.global_position) - b.pos).normalized()
	check(b.body.global_basis.z.dot(to) > 0.9, "faces pilot")
	check(b.alt >= b.cruise_low - 0.3 and b.alt <= b.cruise_high + 0.3, "cruising 2-4 m (%.2f)" % b.alt)

func test_he_drifts_and_bobs() -> void:
	var a := _awake(Vector3(0, 0, 18))
	var b: KnightBrain = a[0]
	var start := b.pos
	var ys := []
	_run(b, 3.0, func(): ys.append(b.body.global_position.y))
	check(b.pos.distance_to(start) > 3.0, "he drifts sideways (%.1f m)" % b.pos.distance_to(start))
	check(ys.max() - ys.min() > 0.1, "he bobs")

func test_he_stays_on_the_leash() -> void:
	var a := _awake(Vector3(0, 0, 150))
	var b: KnightBrain = a[0]
	_run(b, 30.0)
	check(b.pos.distance_to(b.anchor) <= b.leash + 0.01, "inside 60 m (%.1f)" % b.pos.distance_to(b.anchor))

func test_he_leans_into_his_drift() -> void:
	var a := _awake(Vector3(0, 0, 60))
	var b: KnightBrain = a[0]
	_run(b, 1.5)
	# Pilot is far: he advances, so he pitches forward.
	check(b._lean.x > 2.0, "leans forward advancing (%.1f)" % b._lean.x)


# --- choosing ------------------------------------------------------------------------------

func test_distance_weights_the_pick() -> void:
	var near := KnightBrain.move_weights(6.0, [])
	var mid := KnightBrain.move_weights(18.0, [])
	var far := KnightBrain.move_weights(40.0, [])
	check(near[KnightBrain.SMASH] > near[KnightBrain.LASER] and near[KnightBrain.SMASH] > near[KnightBrain.MISSILES], "smash up close")
	check(mid[KnightBrain.LASER] > mid[KnightBrain.SMASH] and mid[KnightBrain.LASER] > mid[KnightBrain.MISSILES], "laser at mid range")
	check(far[KnightBrain.MISSILES] > far[KnightBrain.LASER] and far[KnightBrain.MISSILES] > far[KnightBrain.SMASH], "missiles far out")

func test_never_three_in_a_row() -> void:
	var w := KnightBrain.move_weights(18.0, [KnightBrain.LASER, KnightBrain.LASER])
	eq(w[KnightBrain.LASER], 0.0, "a third laser is off the table")
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 300:
		check(KnightBrain.pick_move(18.0, [KnightBrain.LASER, KnightBrain.LASER], r) != KnightBrain.LASER, "no third")

func test_he_picks_after_resting() -> void:
	var a := _awake(Vector3(0, 0, 18))
	var b: KnightBrain = a[0]
	b.frozen = false
	b.cooldown = 3.0
	_run(b, 2.9)
	eq(b.state, KnightBrain.State.FLOAT, "resting")
	_run(b, 0.2)
	check(b.state != KnightBrain.State.FLOAT, "then he attacks")

func test_frozen_never_picks() -> void:
	var a := _awake(Vector3(0, 0, 18))
	var b: KnightBrain = a[0]
	_run(b, 10.0)
	eq(b.state, KnightBrain.State.FLOAT, "F10 keeps him floating")


# --- laser ---------------------------------------------------------------------------------

func test_laser_tracks_locks_fires_once() -> void:
	var p := _pilot(Vector3(0, 0, 18))
	var b := _knight(p)
	b.start_move(KnightBrain.LASER)
	_run(b, 0.6)
	check(b.laser.is_aiming(), "the aim line is up in the windup")
	_run(b, 0.4)
	check(b.laser.is_aiming(), "still aiming in the lock")
	var locked := b._aim_dir
	p.global_position += Vector3(0.0, 0.0, 0.0)
	_run(b, 0.1)
	check(b._aim_dir.is_equal_approx(locked), "the lock stops tracking")
	var start := b.pos
	_run(b, 0.6)
	eq(p.hits.size(), 1, "one hit for the whole beam")
	eq(p.hits[0], &"knight_laser", "the laser's kind")
	check(start.distance_to(b.pos) > 1.5, "the recoil shoves him back (%.2f m)" % start.distance_to(b.pos))
	_run(b, b.laser_time())
	eq(b.state, KnightBrain.State.FLOAT, "floats again after the recovery")
	check(not b.laser.is_aiming() and not b.laser.is_firing(), "the beam is gone")

func test_laser_timing() -> void:
	var p := _pilot(Vector3(0, 0, 18))
	var b := _knight(p)
	approx(b.laser_draw + b.laser_thrust, 0.9, 0.001, "windup 0.9 s")
	approx(b.laser_lock, 0.3, 0.001, "lock 0.3 s")
	approx(b.laser_fire, 0.6, 0.001, "fire 0.6 s")
	approx(b.laser_recover, 0.8, 0.001, "recovery 0.8 s")

func test_laser_dodged_by_a_sidestep_after_lock() -> void:
	var p := _pilot(Vector3(0, 0, 18))
	var b := _knight(p)
	b.start_move(KnightBrain.LASER)
	_run(b, 1.0)
	p.global_position += Vector3(3.0, 0.0, 0.0)
	_run(b, 1.0)
	eq(p.hits.size(), 0, "a sidestep in the lock dodges it")

func test_beam_hit_rule() -> void:
	var pts := [Vector3(0, 1, 10)]
	check(KnightBrain.beam_hits(Vector3(0, 1, 0), Vector3.BACK, 80.0, 0.75, pts), "dead on")
	check(KnightBrain.beam_hits(Vector3(0, 1, 0), Vector3.BACK, 80.0, 0.75, [Vector3(0.7, 1, 10)]), "grazed")
	check(not KnightBrain.beam_hits(Vector3(0, 1, 0), Vector3.BACK, 80.0, 0.75, [Vector3(1.0, 1, 10)]), "missed")
	check(not KnightBrain.beam_hits(Vector3(0, 1, 0), Vector3.BACK, 5.0, 0.75, pts), "stopped short by a wall")


# --- missiles ------------------------------------------------------------------------------

func test_missiles_six_launched_reflectable() -> void:
	var p := _pilot(Vector3(0, 0, 40))
	var b := _knight(p)
	b.start_move(KnightBrain.MISSILES)
	var alt0 := b.alt
	_run(b, b.missile_windup - 0.05)
	check(b.alt > alt0 + 2.0, "he rises for the volley")
	eq(b.missiles.size(), 0, "nothing before the launch")
	_run(b, b.missile_launch + 0.1)
	eq(b.missiles.size(), 6, "six missiles")
	for m in b.missiles:
		check(m.is_in_group(&"reflectable"), "reflectable")
		check(m.shooter == b.body, "the Knight is the shooter")
		check(m.velocity.y > 0.0, "launched up")
	_run(b, b.missile_recover)
	eq(b.state, KnightBrain.State.FLOAT, "floats after the recovery")

func test_missile_climbs_then_homes_with_a_turn_cap() -> void:
	var p := _pilot(Vector3(0, 0, 30))
	var m := KnightMissile.new()
	m.target = p
	m.velocity = Vector3.UP * m.climb_speed
	_root().add_child(m)
	_nodes.append(m)
	m.global_position = Vector3(0, 4, 0)
	for i in int(m.climb_time / DT) - 1:
		m.step(DT)
	check(m.velocity.normalized().is_equal_approx(Vector3.UP), "climbs straight first")
	var before := m.velocity
	m.step(DT)
	m.step(DT)
	var turned := rad_to_deg(before.angle_to(m.velocity))
	check(turned > 0.5 and turned <= m.turn_rate_deg * DT * 2.0 + 0.01, "turns at most 100 deg/s (%.2f)" % turned)
	var hit := false
	for i in 400:
		m.step(DT)
		if m.global_position.distance_to(p.global_position + Vector3.UP * 1.1) < 0.6:
			hit = true
			break
	check(hit, "homes onto a pilot standing still")

func test_turn_cap_rule() -> void:
	var v := KnightMissile.turn_toward(Vector3.FORWARD * 10.0, Vector3.RIGHT, deg_to_rad(10.0))
	approx(rad_to_deg(Vector3.FORWARD.angle_to(v)), 10.0, 0.01, "capped")
	approx(v.length(), 10.0, 0.001, "speed kept")

func test_missile_lifetime() -> void:
	var m := KnightMissile.new()
	m.velocity = Vector3.UP * 10.0
	_root().add_child(m)
	_nodes.append(m)
	for i in int(7.1 / DT):
		m.step(DT)
	check(m.spent, "gone after 7 s")
	check(not m.is_in_group(&"reflectable"), "a spent missile is not reflectable")

func test_missile_hits_pilot_once() -> void:
	var p := _pilot(Vector3.ZERO)
	var m := KnightMissile.new()
	_root().add_child(m)
	_nodes.append(m)
	m.hit_pilot(p)
	m.hit_pilot(p)
	eq(p.hits, [&"knight_missile"], "one hit, then spent")

func test_perfect_reflect_returns_to_the_knight() -> void:
	var p := _pilot(Vector3(0, 0, 30))
	var b := _knight(p)
	var m := KnightMissile.new()
	m.shooter = b.body
	m.target = p
	_root().add_child(m)
	_nodes.append(m)
	m.global_position = Vector3(0, 3, 12)
	m.velocity = Vector3(0, 0, 16)
	m.reflect(Vector3(1, 0, 0), true)
	var got := []
	b.body.hit_taken.connect(func(_a, kind, _p): got.append(kind))
	for i in 200:
		m.step(DT)
		if m.spent:
			break
	eq(got, [&"reflect_perfect"], "it lands on him")
	check(b.body.is_flashing(), "he flashes")
	eq(p.hits.size(), 0, "a reflected missile leaves pilot alone")
	m.hit_pilot(p)
	eq(p.hits.size(), 0, "even if it touches him")


# --- smash ---------------------------------------------------------------------------------

func _smash(pilot_at: Vector3) -> Array:
	var p := _pilot(pilot_at)
	var b := _knight(p)
	b.start_move(KnightBrain.SMASH)
	return [b, p]

func test_smash_ring_follows_then_locks() -> void:
	var a := _smash(Vector3(0, 0, 8))
	var b: KnightBrain = a[0]
	var p: Node3D = a[1]
	eq(b._approach, 0.0, "no fly-in up close")
	_run(b, b.smash_rise)
	approx(b.alt, b.smash_height, 0.3, "risen ~8 m")
	_run(b, 0.1)
	check(b.smash.is_marking(), "the ring is down")
	p.global_position = Vector3(2, 0, 9)
	_run(b, 0.1)
	check(KnightBrain._flat(b._mark).distance_to(KnightBrain._flat(p.global_position)) < 0.01, "it follows him")
	_run(b, b.smash_track)
	var locked := b._mark
	p.global_position = Vector3(-6, 0, 9)
	_run(b, 0.1)
	check(b._mark.is_equal_approx(locked), "then it locks")

func test_smash_inner_hit_and_stuck_window() -> void:
	var a := _smash(Vector3(0, 0, 8))
	var b: KnightBrain = a[0]
	var p: Node3D = a[1]
	_run(b, b.smash_rise + b.smash_mark + b.smash_dive + 0.05)
	eq(p.hits, [&"knight_smash"], "standing on the mark is a hit")
	check(absf(b.alt - b._stuck_alt) < 0.01, "stuck down at the floor")
	_run(b, b.smash_wave_time + 0.1)
	eq(p.hits.size(), 1, "one hit per smash")
	_run(b, b.smash_stuck - 0.5)
	eq(b.state, KnightBrain.State.SMASH, "still stuck: the opening")
	_run(b, b.smash_heave + 0.5)
	eq(b.state, KnightBrain.State.FLOAT, "heaves back up and floats")

func test_smash_wave_hits_grounded_only() -> void:
	for jump in [false, true]:
		var a := _smash(Vector3(0, 0, 8))
		var b: KnightBrain = a[0]
		var p: Node3D = a[1]
		_run(b, b.smash_rise + b.smash_track + 0.05)
		var at := b._mark
		_run(b, b.smash_mark - b.smash_track)
		p.global_position = at + Vector3(4.5, 1.5 if jump else 0.0, 0.0)
		_run(b, b.smash_dive + b.smash_wave_time + 0.1)
		if jump:
			eq(p.hits.size(), 0, "a jump clears the wave")
		else:
			eq(p.hits, [&"knight_smash_wave"], "the wave catches him on the ground")

func test_smash_flies_in_when_far() -> void:
	var a := _smash(Vector3(0, 0, 40))
	var b: KnightBrain = a[0]
	approx(b._approach, 1.0, 0.001, "a 1 s fly-in past 25 m")
	_run(b, 1.0)
	var d := KnightBrain._flat(a[1].global_position).distance_to(b.pos)
	check(d < 14.0, "he closed in (%.1f m)" % d)

func test_smash_out_of_range_is_safe() -> void:
	var a := _smash(Vector3(0, 0, 8))
	var b: KnightBrain = a[0]
	var p: Node3D = a[1]
	_run(b, b.smash_rise + b.smash_track + 0.05)
	p.global_position = b._mark + Vector3(12, 0, 0)
	_run(b, 3.0)
	eq(p.hits.size(), 0, "12 m out, nothing")


# --- debug keys and the arena ----------------------------------------------------------------

func _key(b: KnightBrain, code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	b._unhandled_input(e)

func test_debug_keys() -> void:
	var p := _pilot(Vector3(0, 0, 100))
	var b := _knight(p)
	b.debug_keys = true
	_key(b, KEY_F7)
	eq(b.state, KnightBrain.State.LASER, "F7 lasers, waking him")
	_key(b, KEY_F8)
	eq(b.state, KnightBrain.State.MISSILES, "F8 missiles")
	_key(b, KEY_F9)
	eq(b.state, KnightBrain.State.SMASH, "F9 smashes")
	check(b._approach > 0.0, "the debug smash still flies in from far")
	_key(b, KEY_F10)
	check(b.frozen, "F10 freezes")
	_key(b, KEY_F11)
	eq(b.state, KnightBrain.State.DORMANT, "F11 resets")
	check(b.pos.is_equal_approx(b.anchor), "on the anchor")
	_key(b, KEY_F6)
	eq(b.state, KnightBrain.State.DORMANT, "F6 does nothing now")

func test_the_arena_wires_the_brain() -> void:
	var arena := (load(ARENA) as PackedScene).instantiate() as BossArena
	_root().add_child(arena)
	_nodes.append(arena)
	check(arena.brain != null and arena.brain.get_parent() == arena.knight, "the brain rides on the knight")
	check(arena.brain.pilot == arena.pilot, "it watches pilot")
	check(arena.brain.debug_keys, "debug keys on in the arena")
	eq(arena.brain.state, KnightBrain.State.DORMANT, "dormant at the start")
	var spawn := arena.map.get_node(^"spawn") as Node3D
	check(KnightBrain._flat(spawn.global_position).distance_to(arena.brain.pos) > arena.brain.wake_range,
		"the spawn is outside the wake range")
