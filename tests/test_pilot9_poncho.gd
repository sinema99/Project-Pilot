extends "res://tests/test_case.gd"

# Covers pilot9's poncho - the cut, the lattice's motion, and its wiring. See
# docs/specs/pilot9-poncho.md.
#
# The look (drape, ink, how much it moves on screen) is tests/_probe_poncho_shot.gd's and the play
# session's. What these fence is what fails silently: an asymmetric cut, a rest shape inside the
# body, a lag that never settles, a wind that is not capped, a teleport that whips, a colour that
# is not the scarf's, and a ghost that keeps moving.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const DT := 1.0 / 60.0
const C := Pilot9Poncho.COLS
const HEM := (Pilot9Poncho.ROWS - 1) * Pilot9Poncho.COLS

var _pilot: Node = null

func end() -> void:
	Settings.set_value(&"poncho", "on")
	super()

# One shared in-tree pilot9 wearing it, for tests/test_pilot9_dash.gd's reason (RID leaks).
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		_pilot.poncho_enabled = true
		(Engine.get_main_loop() as SceneTree).root.add_child(_pilot)
		_pilot.global_position = Vector3(400.0, 60.0, -400.0)
	Settings.set_value(&"poncho", "on")
	return _pilot

## A bare lattice driven by pure translation `velocity(t)` for `frames`; returns per-frame offsets
## of point `index`.
func _drive(p: Pilot9Poncho, velocity: Callable, frames: int, index: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var pos := Vector3.ZERO
	for f in frames:
		pos += velocity.call(f * DT) * DT
		var targets := PackedVector3Array()
		targets.resize(Pilot9Poncho.N)
		for i in Pilot9Poncho.N:
			targets[i] = p.rest[i] + pos
		p.step(DT, targets, pos)
		out.append(p.offsets()[index])
	return out

static func _peak(offsets: PackedVector3Array) -> float:
	var m := 0.0
	for d in offsets:
		m = maxf(m, d.length())
	return m

# --- the cut -------------------------------------------------------------------

func test_front_and_back_are_the_same_cut() -> void:
	var shell := Pilot9Poncho.rest_shell()
	for r in Pilot9Poncho.ROWS:
		for c in range(1, C / 2):
			var front := shell[r * C + c]
			var back := shell[r * C + C / 2 - c]
			approx(front.y, back.y, 0.0001, "row %d col %d: front and back heights differ" % [r, c])
			var mirror := shell[r * C + (C - c) % C]
			approx(front.x, -mirror.x, 0.0001, "row %d col %d: left and right are not mirrored" % [r, c])
			approx(front.y, mirror.y, 0.0001, "row %d col %d: left and right heights differ" % [r, c])

func test_the_hem_is_low_front_and_back_and_open_at_the_sides() -> void:
	var shell := Pilot9Poncho.rest_shell()
	approx(shell[HEM].y, Pilot9Poncho.HEM_Y, 0.001, "front hem height")
	approx(shell[HEM + C / 2].y, Pilot9Poncho.HEM_Y, 0.001, "back hem height")
	check(shell[HEM + C / 4].y > 1.4, "the hem should rise over the shoulder at his left: %f" % shell[HEM + C / 4].y)
	check(shell[HEM + 3 * C / 4].y > 1.4, "the hem should rise over the shoulder at his right")
	check(shell[HEM].z > 0.0 and shell[HEM + C / 2].z < 0.0, "column 0 is the front, C/2 the back")

func test_the_collar_clears_the_scarf() -> void:
	# The scarf: x +-0.135, z -0.12 .. 0.16 (bind space, tests/_probe_poncho_fit.gd).
	var shell := Pilot9Poncho.rest_shell()
	for c in C:
		var p := shell[c]
		# The scarf is a round wrap, so an ellipse through its extents.
		var x := absf(p.x) / 0.135
		var z := p.z / 0.16 if p.z > 0.0 else -p.z / 0.12
		check(x * x + z * z > 1.0, "collar point %d is inside the scarf: %s" % [c, p])

func test_the_rest_shape_sits_clear_of_every_collider() -> void:
	var p := Pilot9Poncho.new()
	var gap := p.thickness * 0.5 + Pilot9Poncho.CLEARANCE
	for i in range(C, Pilot9Poncho.N):
		for spec: Array in Pilot9Poncho.COLLIDERS:
			if not spec[4]:
				continue
			var push := Pilot9Poncho.push_out(p.rest[i], spec[1], spec[2], spec[3], gap - 0.0005)
			check(push == Vector3.ZERO, "rest point %d is inside %s" % [i, spec[0]])
	p.free()

func test_it_hugs_him() -> void:
	# Torso box (UpperChest collider) is x +-0.23, z +-0.20 rounded; the old shell stood 3.5-7 cm
	# off it. The first drape row (above the pack) now sits within 2.5 cm of it, and the ridge
	# rolls round the shoulder.
	var p := Pilot9Poncho.new()
	var mid := (Pilot9Poncho.RIDGE_ROW + 1) * C
	check(p.rest[mid].z < 0.225, "the front drape should hug the chest: z %f" % p.rest[mid].z)
	check(p.rest[mid + C / 2].z > -0.225, "and the back: z %f" % p.rest[mid + C / 2].z)
	var ridge_side := p.rest[Pilot9Poncho.RIDGE_ROW * C + C / 4]
	check(ridge_side.x < 0.31 and ridge_side.y < 1.56,
		"the ridge rolls round the shoulder cap, not a shelf out past it: %s" % ridge_side)
	check(p.thickness <= 0.01, "thin wool: %f" % p.thickness)
	p.free()

func test_a_raised_arm_lifts_the_shoulder_edge() -> void:
	# All colliders at bind = his arms out in the T-pose: the arm capsules run through where the
	# ridge rests (it is fitted to his arms DOWN), so they must lift it over the arm.
	var p := Pilot9Poncho.new()
	var targets := p.rest.duplicate()
	p.step(DT, targets, Vector3.ZERO)
	for k in Pilot9Poncho.COLLIDERS.size():
		p.collider_xforms.append(Transform3D.IDENTITY)
	p.step(DT, targets, Vector3.ZERO)
	for side in [C / 4, 3 * C / 4]:
		var i: int = Pilot9Poncho.RIDGE_ROW * C + side
		check(p.world[i].y > 1.58 + p.thickness * 0.5,
			"col %d: the ridge should ride up over the arm: %s (rest %s)" % [side, p.world[i], p.rest[i]])
	var front: int = Pilot9Poncho.RIDGE_ROW * C
	check(p.world[front].distance_to(p.rest[front]) < 0.001, "the front of the ridge is left alone")
	p.free()

func test_push_out_puts_a_point_on_the_gap() -> void:
	var push := Pilot9Poncho.push_out(Vector3(0.0, 0.0, 0.1), Vector3.ZERO, Vector3(0.2, 0.2, 0.2),
		0.0, 0.01)
	approx(push.z, 0.11, 0.0001, "pushed out through the nearest face to the gap")
	eq(Pilot9Poncho.push_out(Vector3(0.0, 0.0, 0.5), Vector3.ZERO, Vector3(0.2, 0.2, 0.2), 0.0, 0.01),
		Vector3.ZERO, "a point outside the gap is left alone")

# --- the motion ----------------------------------------------------------------

func test_standing_still_it_holds_its_shape() -> void:
	var p := Pilot9Poncho.new()
	var d := _drive(p, func(_t: float) -> Vector3: return Vector3.ZERO, 120, HEM)
	check(_peak(d) < 0.0001, "nothing moving, nothing should move: %f" % _peak(d))
	p.free()

func test_a_run_start_lags_then_settles() -> void:
	var p := Pilot9Poncho.new()
	p.wind_max_lift = 0.0
	var d := _drive(p, func(t: float) -> Vector3: return Vector3(0, 0, 7.5) if t > 0.2 else Vector3.ZERO,
		240, HEM + C / 2)
	var most_back := 0.0
	for v in d:
		most_back = minf(most_back, v.z)
	check(most_back < -0.01, "the back hem should trail behind on the start: %f" % most_back)
	check(_peak(d) < 0.08, "a lag, not a whip: %f m" % _peak(d))
	check(d[d.size() - 1].length() < 0.003, "it should settle back: %s" % d[d.size() - 1])
	p.free()

func test_a_hard_landing_is_one_capped_bounce() -> void:
	var p := Pilot9Poncho.new()
	p.wind_max_lift = 0.0
	var d := _drive(p, func(t: float) -> Vector3: return Vector3(0, -10, 0) if t < 0.2 else Vector3.ZERO,
		240, HEM)
	var lowest := 0.0
	for v in d:
		lowest = minf(lowest, v.y)
	check(lowest < -0.01, "the hem should carry on down on the landing: %f" % lowest)
	check(_peak(d) < 0.08, "a 10 m/s landing stays a bounce: %f m" % _peak(d))
	check(d[d.size() - 1].length() < 0.003, "and settles: %s" % d[d.size() - 1])
	p.free()

func test_the_wind_is_capped_at_full_speed() -> void:
	var at := {}
	for speed in [0.0, 10.0, 20.0, 40.0]:
		var p := Pilot9Poncho.new()
		var d := _drive(p, func(_t: float) -> Vector3: return Vector3(0, 0, speed), 240, HEM + C / 2)
		at[speed] = d[d.size() - 1]
		p.free()
	check((at[0.0] as Vector3).length() < 0.001, "no speed, no wind")
	check((at[20.0] as Vector3).z < -0.05, "full wind should lift the back hem back: %s" % at[20.0])
	check((at[10.0] as Vector3).length() < (at[20.0] as Vector3).length(), "more speed, more lift up to the cap")
	approx((at[40.0] as Vector3).length(), (at[20.0] as Vector3).length(), 0.002,
		"twice full speed lifts no further")

func test_the_wind_angle_is_the_tunable() -> void:
	var w := Pilot9Poncho.wind_offset_dir(Vector3(0, 0, 30), 20.0, 18.0)
	approx(w.length(), deg_to_rad(18.0), 0.0001, "past full speed the lift is max_lift")
	check(w.z < 0.0, "the airflow runs against his travel")
	var fall := Pilot9Poncho.wind_offset_dir(Vector3(0, -30, 0), 20.0, 18.0)
	approx(fall.y, deg_to_rad(18.0) * Pilot9Poncho.VERTICAL_WIND, 0.0001, "a fall lifts at half strength")

func test_a_teleport_starts_again_from_rest() -> void:
	var p := Pilot9Poncho.new()
	var d := _drive(p, func(t: float) -> Vector3: return Vector3(0, 0, 600) if absf(t - 0.5) < 0.001 \
		else Vector3.ZERO, 40, HEM)
	check(_peak(d) < 0.0001, "a 10 m jump in one frame is a respawn, not a whip: %f" % _peak(d))
	p.free()

# --- the wiring ----------------------------------------------------------------

func test_the_switch_is_a_settings_row() -> void:
	var found := false
	for row: Array in Settings.DEFS:
		if row[0] == &"poncho":
			found = true
			eq(row[1], "PONCHO", "the row's label")
			eq(row[3][row[4]], "on", "it should default ON")
	check(found, "settings.gd has no poncho row")

func test_off_by_default_on_trial_pilot() -> void:
	var ps := load(PILOT_TSCN) as PackedScene
	var bare := ps.instantiate()
	eq(bare.poncho_enabled, false, "pilot9.tscn ships without it")
	bare.free()
	var trial := FileAccess.get_file_as_string("res://scenes/trial.tscn")
	var at := trial.find('[node name="Pilot9" ')
	var next := trial.find("[node", at + 1)
	check(trial.substr(at, next - at).contains("poncho_enabled = true"), "trial's Pilot9 should wear it")
	var second := trial.find('[node name="Pilot9Decimate" ')
	check(not trial.substr(second, trial.find("[node", second + 1) - second).contains("poncho_enabled"),
		"the second pilot should not")

func test_it_hangs_under_his_skeleton_in_the_scarf_colour() -> void:
	var p := _scene()
	if p == null:
		check(false, "pilot9.tscn did not load")
		return
	var poncho: Pilot9Poncho = p.poncho
	check(poncho != null, "poncho_enabled should build it")
	if poncho == null:
		return
	eq(poncho.get_parent(), p.get_node(^"character/Armature/GeneralSkeleton"), "under his skeleton")
	check(poncho.mesh != null and poncho.mesh.get_surface_count() == 1, "one drawn surface")
	var mat := poncho.mesh.surface_get_material(0)
	eq(mat.resource_name.strip_edges(), "scarf", "the scarf slot, for ApplyCelPilot9")
	check(mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_color.is_equal_approx(
		Pilot9Poncho.FALLBACK_COLOR), "the scarf's red")

func test_the_settings_row_hides_it() -> void:
	var p := _scene()
	if p == null or p.poncho == null:
		check(false, "no poncho")
		return
	Settings.set_value(&"poncho", "off")
	p.poncho._update_from_skeleton(DT)
	check(not p.poncho.visible, "PONCHO off should hide it")
	Settings.set_value(&"poncho", "on")
	p.poncho._update_from_skeleton(DT)
	check(p.poncho.visible, "and on shows it again")

func test_a_ghost_keeps_the_frame_it_was_handed() -> void:
	var p := _scene()
	if p == null or p.poncho == null:
		check(false, "no poncho")
		return
	var frozen: Mesh = p.poncho.frozen_mesh()
	check(frozen != null, "a mesh to hand over")
	var before := frozen.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	p.poncho._update_from_skeleton(DT)
	p.poncho._update_from_skeleton(DT)
	p.poncho._update_from_skeleton(DT)
	check(p.poncho.mesh != frozen, "the live poncho moved on to another buffer")
	var after := frozen.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	check(before == after, "the handed-over mesh is never rewritten")

func test_a_dash_ghost_wears_a_frozen_poncho() -> void:
	var p := _scene()
	if p == null or p.poncho == null:
		check(false, "no poncho")
		return
	var ai: Node = p._afterimage
	ai._build_if_stale()
	ai.begin(p.character, true)
	ai._drop(p.character, Vector3.ZERO)
	var copy: MeshInstance3D = null
	for c in ai._pool[0].get_children():
		if c.name == &"Poncho":
			copy = c
	check(copy != null and copy.visible, "the ghost should carry a poncho copy")
	if copy == null:
		ai.clear()
		return
	var held := copy.mesh
	p.poncho._update_from_skeleton(DT)
	p.poncho._update_from_skeleton(DT)
	check(copy.mesh == held and held != p.poncho.mesh, "the ghost's poncho stays the frame it dropped on")
	ai.end()
	ai.clear()
