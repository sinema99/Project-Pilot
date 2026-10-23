extends "res://tests/test_case.gd"

# ANIME animation v2 (docs/specs/anime-animation.md): drawn cycles + impact accents. Whether it
# reads as drawn is the user's call; this fences the stride tracker (8 drawings a cycle, drawing 1
# on the left contact, no jitter drawings, stall recovery), the hold's mode priority and accent
# timing, the modifier's three modes and pilot9's wiring.

const PoseHold := preload("res://scripts/anime/anime_pose_hold.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const DT := 1.0 / 60.0

var _nodes: Array[Node] = []

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func end() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	super()

# --- the setting -----------------------------------------------------------------

func test_animation_row_defaults_to_smooth() -> void:
	eq(SettingsScript.values_of(&"anime_animation"), ["smooth", "anime"], "SMOOTH / ANIME")
	eq(SettingsScript.defaults()[&"anime_animation"], "smooth", "SMOOTH by default")
	eq(SettingsScript.section_of(&"anime_animation"), "graphics", "under LOOK in graphics")
	eq(SettingsScript.sanitise({"version": SettingsScript.CONFIG_VERSION})[&"anime_animation"],
		"smooth", "an old save without the row gets SMOOTH")

# --- the stride tracker -----------------------------------------------------------

## A synthetic stride: s = A cos(2 pi t / cycle), so t = 0 is the left contact.
func _run_stride(cycle: float, seconds: float, amplitude: float = 0.4) -> Dictionary:
	var st := AnimeStride.new()
	var times: Array[float] = []
	var events: Array[StringName] = []
	var t := 0.0
	while t < seconds:
		var before := st.last_event
		if st.update(t, amplitude * cos(TAU * t / cycle), DT):
			times.append(t)
			events.append(st.last_event if st.last_event != before or events.is_empty() else &"between")
		t += DT
	return {"times": times, "events": events}

func _drawings_in(times: Array[float], from: float, to: float) -> int:
	var n := 0
	for t in times:
		if t >= from and t < to:
			n += 1
	return n

func test_a_sprint_cycle_shows_eight_drawings() -> void:
	var r := _run_stride(0.6, 3.0)
	# Skip the first cycle while the quarter length is learnt.
	eq(_drawings_in(r.times, 0.6, 1.2), 8, "8 drawings in a 0.6 s cycle")
	eq(_drawings_in(r.times, 1.2, 2.4), 16, "and 8 in each after")

func test_a_walk_cycle_shows_eight_drawings_too() -> void:
	var r := _run_stride(1.1, 5.0, 0.3)
	eq(_drawings_in(r.times, 1.1, 3.3), 16, "8 a cycle at walk speed - the rate follows the stride")

func test_drawing_one_is_the_left_contact() -> void:
	var st := AnimeStride.new()
	var t := 0.0
	var calls: Array[float] = []
	while t < 2.0:
		st.update(t, 0.4 * cos(TAU * t / 0.6), DT)
		if st.last_event == &"contact_l" and (calls.is_empty() or t - calls[-1] > 0.3):
			calls.append(t)
		t += DT
		if st.last_event == &"contact_l":
			st.last_event = &""
	check(calls.size() >= 2, "left contacts are called (%d)" % calls.size())
	for c in calls:
		# The true contact is at a whole cycle; the call comes a frame or two after the peak.
		var into := fmod(c, 0.6)
		check(into < 0.06, "the left contact drawing is within a few frames of the peak (%.3f s in)" % into)

func test_quarters_go_contact_passing_contact_passing() -> void:
	var st := AnimeStride.new()
	var seq: Array[StringName] = []
	var t := 0.0
	while t < 1.3:
		st.update(t, 0.4 * cos(TAU * t / 0.6), DT)
		if st.last_event != &"":
			seq.append(st.last_event)
			st.last_event = &""
		t += DT
	var s := ",".join(PackedStringArray(seq))
	check(s.contains("passing,contact_r,passing,contact_l"), "the four boundaries in order (%s)" % s)

func test_jitter_in_the_dead_band_fires_nothing() -> void:
	var st := AnimeStride.new()
	var drawn := 0
	var t := 0.0
	for i in 20:
		if st.update(t, 0.015 if i % 2 == 0 else -0.015, DT):
			drawn += 1
		t += DT
	eq(drawn, 0, "no drawings from feet shuffling around zero")

func test_a_stall_still_takes_a_drawing() -> void:
	var st := AnimeStride.new()
	var drawn := 0
	var t := 0.0
	for i in 40:  # 0.67 s of a frozen pose
		if st.update(t, 0.1, DT):
			drawn += 1
		t += DT
	eq(drawn, 1, "one drawing after STALL with no boundary")

# --- the hold --------------------------------------------------------------------

func _hold(cycle: bool = false) -> AnimeHold:
	var hold := AnimeHold.new()
	hold.set_process(false)
	hold.set_process_unhandled_input(false)
	_tree().root.add_child(hold)
	_nodes.append(hold)
	hold.enabled_override = 1
	hold.cycle_state = func() -> bool: return cycle
	hold.velocity = func() -> Vector3: return Vector3(0, 0, 5)
	return hold

func _skeleton() -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.add_bone("Hips")
	skel.add_bone("LeftFoot")
	skel.set_bone_parent(1, 0)
	skel.add_bone("RightFoot")
	skel.set_bone_parent(2, 0)
	_tree().root.add_child(skel)
	_nodes.append(skel)
	return skel

func test_live_without_a_cycle_or_an_accent() -> void:
	var hold := _hold()
	hold.tick(10.0, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "smooth")

func test_accent_waits_its_delay_then_holds_its_length() -> void:
	var hold := _hold()
	hold.accents = {&"test": Vector3(0.05, 0.1, 0.1)}
	hold.accent(&"test", 1.0, 10.0)
	hold.tick(10.0, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "smooth during the delay")
	hold.tick(10.06, DT)
	eq(hold.mode, AnimeHold.Mode.HOLD, "held from the delay")
	hold.tick(10.14, DT)
	eq(hold.mode, AnimeHold.Mode.HOLD, "for its length")
	hold.tick(10.16, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "then smooth")
	check(not hold.is_accenting(), "and done")

func test_an_accent_from_a_move_he_left_is_dropped() -> void:
	var hold := _hold()
	hold.accents = {&"test": Vector3(0.2, 0.1, 0.1)}
	var still := [true]
	hold.accent(&"test", 1.0, 10.0, func() -> bool: return still[0])
	still[0] = false  # he ran out of the landing before the impact pose came round
	hold.tick(10.21, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "no held crouch mid-stride")
	check(not hold.is_accenting(), "the accent is dropped")

func test_a_hard_landing_holds_longer() -> void:
	var hold := _hold()
	var a: Vector3 = hold.accents[&"land"]
	hold.accent(&"land", 0.0, 10.0)
	hold.tick(10.0 + a.x + a.y + 0.01, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "a soft landing is over after the soft hold")
	hold.accent(&"land", 1.0, 20.0)
	hold.tick(20.0 + a.x + a.y + 0.01, DT)
	eq(hold.mode, AnimeHold.Mode.HOLD, "a hard one is still held")

func test_an_accent_beats_the_cycle() -> void:
	var hold := _hold(true)
	hold.setup(_skeleton())
	hold.tick(10.0, DT)
	eq(hold.mode, AnimeHold.Mode.CYCLE, "running: a drawn cycle")
	hold.accents = {&"test": Vector3(0.0, 0.1, 0.1)}
	hold.accent(&"test", 1.0, 10.0)
	hold.tick(10.02, DT)
	eq(hold.mode, AnimeHold.Mode.HOLD, "the accent wins")
	hold.tick(10.2, DT)
	eq(hold.mode, AnimeHold.Mode.CYCLE, "and hands back to the cycle")

func test_slow_or_no_skeleton_is_no_cycle() -> void:
	var hold := _hold(true)
	hold.tick(10.0, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "no skeleton, no cycle (the dummy)")
	var slow := _hold(true)
	slow.setup(_skeleton())
	slow.velocity = func() -> Vector3: return Vector3(0.5, 0, 0)
	slow.tick(10.0, DT)
	eq(slow.mode, AnimeHold.Mode.LIVE, "below 1 m/s he is smooth")

func test_smooth_setting_is_live_and_drops_accents() -> void:
	var hold := _hold()
	hold.accents = {&"test": Vector3(0.0, 0.5, 0.5)}
	hold.accent(&"test", 1.0, 10.0)
	hold.enabled_override = 0
	hold.tick(10.1, DT)
	eq(hold.mode, AnimeHold.Mode.LIVE, "SMOOTH")
	check(not hold.is_accenting(), "the accent is dropped")

func test_dummy_wobble_is_held_through_a_hit() -> void:
	var hold := _hold()
	var wobble := Node3D.new()
	hold.add_child(wobble)
	hold.inner = [wobble]
	wobble.rotation.x = 0.2
	hold.accent(&"hit", 0.0, 10.0)
	hold.tick(10.0, DT)
	wobble.rotation.x = 0.05
	hold.tick(10.05, DT)
	approx(wobble.rotation.x, 0.2, 1e-6, "the hit frame's wobble is held")

# --- the modifier ----------------------------------------------------------------

func test_modifier_modes() -> void:
	var skel := _skeleton()
	var mod := PoseHold.new()
	skel.add_child(mod)
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 0.5))
	mod.mode = PoseHold.Mode.HOLD
	mod._process_modification_with_delta(DT)
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 1.5))
	mod._process_modification_with_delta(DT)
	check(skel.get_bone_pose_rotation(1).is_equal_approx(Quaternion(Vector3.UP, 0.5)), "HOLD writes the copy back")
	mod.mode = PoseHold.Mode.LIVE
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 1.5))
	mod._process_modification_with_delta(DT)
	check(skel.get_bone_pose_rotation(1).is_equal_approx(Quaternion(Vector3.UP, 1.5)), "LIVE leaves the pose alone")
	mod.mode = PoseHold.Mode.CYCLE
	mod._process_modification_with_delta(DT)
	eq(mod.drawings, 1, "entering a cycle takes the pose now as the first drawing")
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 0.1))
	mod._process_modification_with_delta(DT)
	check(skel.get_bone_pose_rotation(1).is_equal_approx(Quaternion(Vector3.UP, 1.5)), "then holds it")

func test_stride_signal_is_left_foot_ahead_along_travel() -> void:
	var skel := _skeleton()
	var mod := PoseHold.new()
	skel.add_child(mod)
	skel.set_bone_pose_position(1, Vector3(0.1, 0, 0.3))
	skel.set_bone_pose_position(2, Vector3(-0.1, 0, -0.2))
	mod.travel = Vector3(0, 0, 1)
	approx(mod.stride_signal(skel), 0.5, 1e-5, "left 0.3 ahead, right 0.2 behind")

# --- pilot9 ----------------------------------------------------------------------

func test_pilot9_wires_its_hold() -> void:
	var ps := load(PILOT_TSCN) as PackedScene
	var pilot := ps.instantiate()
	_tree().root.add_child(pilot)
	_nodes.append(pilot)
	var hold: AnimeHold = pilot.anime_hold
	check(hold != null, "pilot9 builds a hold")
	if hold == null:
		return
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	check(skel.find_bone("LeftFoot") >= 0 and skel.find_bone("RightFoot") >= 0, "the feet the stride reads exist")
	var last_mod: Node = null
	for c in skel.get_children():
		if c is SkeletonModifier3D:
			last_mod = c
	eq(last_mod, hold.pose_hold, "the pose hold is the last modifier")
	for a in [&"land", &"wall_kick", &"mantle_grab", &"vault_plant", &"rail_land", &"perfect_reflect"]:
		check(hold.accents.has(a), "accent %s is in the table" % a)
	eq((pilot.get_node("character/Armature") as Node3D).physics_interpolation_mode,
		Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "v2 never takes the Armature off interpolation")
