extends "res://tests/test_case.gd"

# docs/specs/pilot9-gunplay.md. The GunDef numbers, the input map (right mouse aims, left fires, dash
# on Q), the default loadout (rifle 1, revolver 2), the pure helpers, and the controller's rules:
# single fire on a 0.35 s limit, per-gun magazines, dry fire, reload, swap, and the blocked states.
# Whether a ray lands on the dummy is tests/_probe_gunplay_hit.gd; how it feels is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const RIFLE := "res://resources/items/rifle.tres"
const REVOLVER := "res://resources/items/revolver.tres"
const STAFF := "res://resources/items/staff.tres"
const GUNPLAY := preload("res://scripts/items/gunplay.gd")
const DT := 1.0 / 60.0

var _pilot: Node = null

# One shared in-tree pilot9 with the revolver drawn and a fresh magazine, every flag clear.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	for flag in [&"is_climbing", &"is_vaulting", &"is_wall_running", &"is_wall_climbing", &"frozen",
			&"is_sliding", &"is_dashing", &"is_rail_grinding", &"is_rail_switching", &"is_carrying"]:
		_pilot.set(flag, false)
	_pilot.riding = null
	_pilot.tredge.mode = preload("res://scripts/pilot9_tredge.gd").Mode.FORCED_OFF
	_pilot.end_tredge()
	_pilot.equip_anim.finish_now()
	var slots: Array[HeldItem] = [load(RIFLE), load(REVOLVER)]
	_pilot.weapon_slots = slots
	_pilot.set_item(load(REVOLVER))
	if not _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	for item in slots:
		_pilot.gunplay.refill(item.gun)
	_pilot.gunplay._cooldown = 0.0
	_pilot.gunplay._reload_left = 0.0
	return _pilot

func _event_matches(action: StringName, pred: Callable) -> bool:
	for ev in InputMap.action_get_events(action):
		if pred.call(ev):
			return true
	return false

# --- the data ---------------------------------------------------------------------------------------

func test_gun_numbers() -> void:
	var revolver: GunDef = (load(REVOLVER) as HeldItem).gun
	var rifle: GunDef = (load(RIFLE) as HeldItem).gun
	check(revolver != null and rifle != null, "both guns carry a GunDef")
	if revolver == null or rifle == null:
		return
	eq(revolver.damage, 25.0, "revolver does 25")
	eq(rifle.damage, 50.0, "rifle does 50")
	eq(revolver.magazine, 6, "revolver holds 6")
	eq(rifle.magazine, 10, "rifle holds 10")
	eq(revolver.fire_interval, 0.35, "revolver: 0.35 s between shots")
	eq(rifle.fire_interval, 0.35, "rifle: the same fire rate")
	eq(revolver.reload_time, 2.0, "revolver reloads in 2.0 s")
	eq(rifle.reload_time, 2.5, "rifle reloads in 2.5 s")
	check((load(STAFF) as HeldItem).gun == null, "the staff is not a gun")

func test_default_loadout_is_rifle_then_revolver() -> void:
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("/root/Inventory")
	if inv == null:
		return
	eq(inv.DEFAULT_LOADOUT[&"weapon_1"], "res://resources/items/rifle_weapon.tres", "1 is the rifle")
	eq(inv.DEFAULT_LOADOUT[&"weapon_2"], "res://resources/items/revolver_weapon.tres", "2 is the revolver")
	check(not inv.DEFAULT_LOADOUT.values().has("res://resources/items/staff_weapon.tres"),
		"the staff is not slotted")

func test_input_map() -> void:
	check(InputMap.has_action(&"aim") and InputMap.has_action(&"fire"), "aim and fire exist")
	check(_event_matches(&"aim", func(e): return e is InputEventMouseButton \
		and e.button_index == MOUSE_BUTTON_RIGHT), "right mouse aims")
	check(_event_matches(&"fire", func(e): return e is InputEventMouseButton \
		and e.button_index == MOUSE_BUTTON_LEFT), "left mouse fires")
	check(_event_matches(&"dash", func(e): return e is InputEventKey and e.physical_keycode == KEY_Q),
		"dash is on Q")
	check(not _event_matches(&"dash", func(e): return e is InputEventMouseButton),
		"dash is off the mouse")

# --- the pure helpers -------------------------------------------------------------------------------

func test_can_fire_gates() -> void:
	check(GUNPLAY.can_fire(true, false, 0.0, false, 3), "armed, free, ready: fires")
	check(not GUNPLAY.can_fire(false, false, 0.0, false, 3), "not armed: no")
	check(not GUNPLAY.can_fire(true, true, 0.0, false, 3), "blocked: no")
	check(not GUNPLAY.can_fire(true, false, 0.1, false, 3), "cooling down: no")
	check(not GUNPLAY.can_fire(true, false, 0.0, true, 3), "reloading: no")
	check(not GUNPLAY.can_fire(true, false, 0.0, false, 0), "empty: no")

func test_fov_scale_and_crosshair() -> void:
	approx(GUNPLAY.fov_scale(0.1, 0.0), 1.0, 1e-6, "hip: lens untouched")
	approx(GUNPLAY.fov_scale(0.1, 1.0), 0.9, 1e-6, "full aim: 10% off")
	approx(GUNPLAY.fov_scale(0.18, 1.0), 0.82, 1e-6, "rifle: 18% off")
	check(GUNPLAY.ring_radius(0.0, 70.0, 1080.0) == GUNPLAY.CROSS_AIM_RADIUS, "no spread: the base ring")
	check(GUNPLAY.ring_radius(2.0, 70.0, 1080.0) > GUNPLAY.CROSS_AIM_RADIUS, "bloom widens the ring")
	eq(GUNPLAY.ammo_text(6, false), "6 / ∞", "the count reads 6 / ∞")
	eq(GUNPLAY.ammo_text(0, true), "RELOADING", "reloading says so")

# --- the controller ---------------------------------------------------------------------------------

func test_single_fire_and_interval() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	check(g.armed(), "a drawn revolver arms it")
	eq(g.rounds_left(), 6, "a full magazine")
	check(g.try_fire(), "the first click fires")
	eq(g.rounds_left(), 5, "one round gone")
	check(not g.try_fire(), "a second click inside 0.35 s does nothing")
	eq(g.rounds_left(), 5, "no round spent on it")
	g.tick(0.36)
	check(g.try_fire(), "after 0.35 s it fires again")

func test_dry_fire_and_reload() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	for i in 6:
		g.tick(0.4)
		check(g.try_fire(), "round %d fires" % (i + 1))
	eq(g.rounds_left(), 0, "empty after six")
	g.tick(0.4)
	check(not g.try_fire(), "dry fire spends nothing and returns false")
	check(g.is_reloading(), "the dry press starts the reload by itself")
	check(g.is_reloading(), "reloading")
	g.tick(0.4)
	check(not g.try_fire(), "no shooting mid reload")
	g.tick(1.7)
	check(not g.is_reloading(), "done after 2.0 s")
	eq(g.rounds_left(), 6, "a full magazine again")
	check(not g.press_reload(), "a full magazine does not reload")

func test_swap_keeps_rounds_and_cancels_reload() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	g.try_fire()
	eq(g.rounds_left(), 5, "revolver at 5")
	g.press_reload()
	p.set_item(load(RIFLE))
	if not p.is_item_drawn():
		p.toggle_drawn()
	g.tick(DT)
	check(not g.is_reloading(), "a swap cancels the reload")
	eq(g.rounds_left(), 10, "the rifle has its own magazine")
	p.set_item(load(REVOLVER))
	if not p.is_item_drawn():
		p.toggle_drawn()
	g.tick(DT)
	eq(g.rounds_left(), 5, "the revolver remembered its count")

func test_staff_and_holster_are_not_armed() -> void:
	var p := _scene()
	if p == null:
		return
	p.set_item(load(STAFF))
	if not p.is_item_drawn():
		p.toggle_drawn()
	check(not p.gunplay.armed(), "the staff is not a gun")
	check(not p.gunplay.try_fire(), "left mouse with the staff fires nothing")
	p.set_item(load(REVOLVER))
	if p.is_item_drawn():
		p.toggle_drawn()
	check(not p.gunplay.armed(), "a holstered gun is not armed")

func test_blocked_states_stop_fire_and_aim() -> void:
	var p := _scene()
	if p == null:
		return
	for flag in [&"frozen", &"is_sliding", &"is_dashing", &"is_wall_running", &"is_climbing",
			&"is_vaulting", &"is_rail_grinding", &"is_carrying"]:
		p.set(flag, true)
		check(p.gunplay.blocked(), "%s blocks the gun" % flag)
		check(not p.gunplay.try_fire(), "no shot while %s" % flag)
		check(not p.gunplay.aim_active(), "no aim while %s" % flag)
		p.set(flag, false)
	check(not p.gunplay.blocked(), "all clear again")

func test_aim_camera_numbers() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	g.aim_blend = 0.0
	approx(g.shoulder_offset(0.25), 0.25, 1e-6, "hip shoulder offset untouched")
	approx(g.arm_length(1.7), 1.7, 1e-6, "hip arm untouched")
	approx(g.look_scale(), 1.0, 1e-6, "hip look untouched")
	g.aim_blend = 1.0
	approx(g.shoulder_offset(0.25), 1.0, 1e-6, "aim: 1.0 m shoulder")
	approx(g.arm_length(1.7), 1.25, 1e-6, "aim: the arm is 1.25 m")
	approx(g.look_scale(), 0.7, 1e-6, "aim: look at 70%")
	approx(g.sway_scale(), 0.5, 1e-6, "aim: sway halved")
	approx(g.fov_multiplier(), 0.8, 1e-6, "aim: the revolver cuts 20% off the lens")
	g.aim_blend = 0.0


# --- pass 2: recoil, bloom, reload timing, the pose timeline (docs/specs/pilot9-gunplay-pass2.md) ---

const RELOAD := preload("res://scripts/items/gun_reload.gd")

func test_reload_seconds_tactical_is_shorter() -> void:
	var g := load("res://resources/items/rifle_gun.tres") as GunDef
	approx(GUNPLAY.reload_seconds(g, 0), 2.5, 1e-6, "empty rifle: the full 2.5 s")
	approx(GUNPLAY.reload_seconds(g, 4), 2.0, 1e-6, "rounds left: 80% of it")

func test_hip_kicks_harder_than_aim() -> void:
	var g := load("res://resources/items/revolver_gun.tres") as GunDef
	check(GUNPLAY.kick_pitch(g, 0.0) > GUNPLAY.kick_pitch(g, 1.0), "hip kick > aimed kick")
	approx(GUNPLAY.kick_pitch(g, 1.0), deg_to_rad(g.recoil_pitch_deg), 1e-6, "aimed is the base kick")

func test_spread_stays_inside_the_cone_and_bloom_widens_it() -> void:
	var g := load("res://resources/items/revolver_gun.tres") as GunDef
	approx(GUNPLAY.spread_deg(g, 1.0, 0.0), g.spread_aim_deg, 1e-6, "aimed rest spread")
	approx(GUNPLAY.spread_deg(g, 0.0, 0.0), g.spread_hip_deg, 1e-6, "hip rest spread")
	check(GUNPLAY.spread_deg(g, 1.0, 1.0) > g.spread_aim_deg, "bloom adds")
	approx(GUNPLAY.spread_deg(g, 0.0, 99.0), g.bloom_max_deg, 1e-6, "capped at the ceiling")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var worst := 0.0
	for i in 400:
		var d: Vector3 = GUNPLAY.spread_dir(Vector3.FORWARD, 2.0, rng)
		worst = maxf(worst, rad_to_deg(d.angle_to(Vector3.FORWARD)))
	check(worst <= 2.0 + 1e-3, "no shot leaves a 2 degree cone, worst %f" % worst)
	check(GUNPLAY.spread_dir(Vector3.FORWARD, 0.0, rng) == Vector3.FORWARD, "no cone: dead straight")

func test_a_shot_kicks_the_view_up_and_bloom_builds() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	g.tick(1.0 / 60.0)
	g.aim_blend = 1.0
	var before: float = p.camera_pivot.rotation.x
	check(g.try_fire(), "fires")
	check(g.bloom_deg > 0.0, "the shot blooms the cone")
	for i in 30:
		g.tick(1.0 / 60.0)
	check(p.camera_pivot.rotation.x > before, "the view is higher after the kick")
	for i in 120:
		g.tick(1.0 / 60.0)
	var left: float = p.camera_pivot.rotation.x - before
	check(left > 0.0, "part of the kick stays until the player pulls down")
	check(left < GUNPLAY.kick_pitch(g.gun(), 1.0), "the recoverable part came back")
	check(g.bloom_deg < 0.01, "bloom settled")

func test_empty_press_auto_reloads_and_can_be_turned_off() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	g.auto_reload = false
	for i in 6:
		g.tick(0.4)
		g.try_fire()
	g.tick(0.4)
	check(not g.try_fire(), "dry")
	check(not g.is_reloading(), "auto reload off: stays empty")
	g.auto_reload = true
	g.tick(0.4)
	g.try_fire()
	check(g.is_reloading(), "auto reload on: the dry press reloads")

func test_reload_timelines_exist_for_both_guns_and_end_on_the_hold() -> void:
	for gun_name in ["REVOLVER", "RIFLE"]:
		for empty in [true, false]:
			var keys: Array = RELOAD.timeline_for(gun_name, empty)
			check(not keys.is_empty(), "%s empty=%s has a timeline" % [gun_name, empty])
			eq(keys[0][1], "BASE", "starts on the hold")
			eq(keys[keys.size() - 1][1], "BASE", "ends on the hold")
			approx(float(keys[keys.size() - 1][0]), 1.0, 1e-6, "ends at 1.0")
	check(RELOAD.timeline_for("RIFLE", true).size() > RELOAD.timeline_for("RIFLE", false).size(),
		"the empty rifle reload adds the rack")

func test_timeline_segments_and_ease() -> void:
	var keys := [[0.0, "BASE"], [0.5, "R1"], [1.0, "BASE"]]
	eq(RELOAD.segment(keys, 0.2), 0, "first segment")
	eq(RELOAD.segment(keys, 0.7), 1, "second segment")
	approx(RELOAD.segment_k(keys, 0, 0.0), 0.0, 1e-6, "eases from 0")
	approx(RELOAD.segment_k(keys, 0, 0.5), 1.0, 1e-6, "to 1")
	approx(RELOAD.segment_k(keys, 0, 0.25), 0.5, 1e-6, "halfway is half")

func test_shot_feedback_nodes_clean_themselves_up() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	g.aim_blend = 1.0
	g.try_fire()
	for i in 90:
		g.fx._process(1.0 / 60.0)
	check(g.fx._tracers.is_empty(), "the tracer finished")
	check(g.fx._flash_nodes.is_empty(), "the muzzle flash finished")

func test_aim_pose_follows_aim_and_drops_in_a_reload() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	for i in 30:
		g.aim_blend = 1.0
		g.tick(1.0 / 60.0)
	check(g.aim_pose > 0.5, "aim pose up while aiming")
	g.try_fire()
	g.press_reload()
	for i in 30:
		g.tick(1.0 / 60.0)
	check(g.aim_pose < 0.1, "the aim pose lets go for the reload")


# 2026-11-16: aimed, the body is locked to the standing-aim pose; the crosshair is a T.
func test_aim_locks_the_body_and_the_crosshair_is_a_t() -> void:
	var p := _scene()
	if p == null:
		return
	var g = p.gunplay
	check(g.body_locked() == g.aim_active(), "the body lock is the aim")
	check(GUNPLAY.CROSS_GAP > 0.0 and GUNPLAY.CROSS_ARM_BLOCKS > 0, "a T with an empty centre")
	check(GUNPLAY.CROSS_MAX_DRIFT > 0.0, "the crosshair drift is clamped")
	# Hip: the crosshair sits at screen centre.
	g.aim_pose = 0.0
	g.tick(1.0 / 60.0)
	check(g._barrel_offset == Vector2.ZERO, "no barrel offset at the hip")
	# Aimed: it may drift off centre, but never past the clamp.
	for i in 30:
		g.aim_blend = 1.0
		g.tick(1.0 / 60.0)
	check(g._barrel_offset.length() <= GUNPLAY.CROSS_MAX_DRIFT + 0.01, "drift stays inside the clamp")
