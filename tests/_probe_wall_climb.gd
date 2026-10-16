extends SceneTree
## Runs real wall climbs headlessly: pilot9 runs at a wall and the probe checks what happened.
## Not part of the suite (no test_ prefix) - the suite's runner is synchronous and a climb needs
## frames and move_and_slide(). Exits 1 if any check fails. See docs/specs/pilot9-wall-climb.md.
##   godot --headless --fixed-fps 60 --path . --script tests/_probe_wall_climb.gd [-- verbose]

const FACE_Z := -8.0   # near face of wall A, facing +Z; he runs along -Z

var world: Node3D
var pilot: CharacterBody3D
var skel: Skeleton3D
var fails: Array[String] = []
var verbose := false

func _initialize() -> void:
	verbose = OS.get_cmdline_user_args().has("verbose")
	_main.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _box(size: Vector3, pos: Vector3, rot_deg := 0.0) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = pos
	b.rotation.y = deg_to_rad(rot_deg)
	world.add_child(b)

func _build() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(60, 1, 80), Vector3(0, -0.5, 0))

func _spawn(at: Vector3, yaw := 0.0) -> void:
	pilot = load("res://scenes/pilot9.tscn").instantiate()
	world.add_child(pilot)
	pilot.global_position = at
	pilot.camera_pivot.rotation.y = yaw
	skel = pilot.get_node("character/Armature/GeneralSkeleton")

func _teardown() -> void:
	for a in ["forward", "jump", "sprint"]:
		Input.action_release(a)
	world.queue_free()
	await _frames(2)

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("    FAIL ", msg)

func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)

## How far in front of the face plane his hands are drawn, the nearer of the two.
func _hand_gap(face_z: float, normal_z: float) -> float:
	var best := INF
	for bone in [&"LeftHand", &"RightHand"]:
		var p := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin
		best = minf(best, (p.z - face_z) * normal_z)
	return best

func _state() -> String:
	var pb: AnimationNodeStateMachinePlayback = pilot.anim_tree.get("parameters/playback")
	return String(pb.get_current_node()) if pb != null else ""

## Runs at wall A (height `h`, `depth` deep) from 12 m back. Returns what happened.
func _run_at(h: float, depth: float, opts := {}) -> Dictionary:
	_build()
	_box(Vector3(14, h, depth), Vector3(0, h * 0.5, FACE_Z - depth * 0.5))
	var ang := deg_to_rad(opts.get("angle", 0.0))
	_spawn(Vector3(sin(ang) * 12.0, 0.02, FACE_Z + cos(ang) * 12.0), ang)
	await _frames(3)
	if opts.get("sprint", false):
		await _press("sprint")
	Input.action_press("forward")
	var res := {"climbed": false, "entry_on_floor": false, "entry_speed": 0.0, "start_y": 0.0,
		"peak": 0.0, "mantled": false, "end_y": 0.0, "peeled": false, "state_seen": false,
		"hand_gap": INF, "wall_ran": false}
	var was := false
	for f in 360:
		var before_floor := pilot.is_on_floor()
		var before_speed := Vector2(pilot.velocity.x, pilot.velocity.z).length()
		await _frames(1)
		if pilot.is_wall_running:
			res.wall_ran = true
		if pilot.is_wall_climbing and not was:
			res.climbed = true
			res.entry_on_floor = before_floor
			res.entry_speed = before_speed
			res.start_y = pilot.global_position.y - pilot.velocity.y / 60.0
		if pilot.is_wall_climbing:
			res.peak = maxf(res.peak, pilot.global_position.y)
			if _state() == "wall_climb":
				res.state_seen = true
				# Past the 0.1 s blend in from the run - the climb pose is what is judged.
				if pilot._wall_climb_time >= 0.12:
					res.hand_gap = minf(res.hand_gap, _hand_gap(FACE_Z, 1.0))
					if verbose:
						print("    t %.2f  hand gap %.3f  pitch %.1f  mesh z %.3f" % [
							pilot._wall_climb_time, _hand_gap(FACE_Z, 1.0),
							rad_to_deg(pilot.character.rotation.x), pilot.character.position.z])
		if was and not pilot.is_wall_climbing and pilot.is_climbing:
			res.mantled = true
		if was and not pilot.is_wall_climbing and not pilot.is_climbing:
			res.peeled = pilot.velocity.z > 0.5
		was = pilot.is_wall_climbing
		if res.climbed and not pilot.is_wall_climbing and not pilot.is_climbing \
				and pilot.is_on_floor() and f > 30:
			break
	res.end_y = pilot.global_position.y
	await _teardown()
	return res

func _main() -> void:
	print("wall climb probe")

	# 1. Ground run at a tall wall: climbs from the floor, exactly 4 m, peels off, and plays the clip.
	var r := await _run_at(14.0, 1.0)
	if verbose: print("  tall  ", r)
	_check(r.climbed, "a run dead-on into a 14 m wall did not climb")
	_check(r.entry_on_floor, "the climb did not start from the floor")
	_check(absf(r.peak - r.start_y - 4.0) < 0.15, "climbed %.2f m, not 4.0" % (r.peak - r.start_y))
	_check(r.peeled, "the climb did not peel off the face")
	_check(r.state_seen, "the wall_climb state never played")
	_check(r.hand_gap < 0.2 and r.hand_gap > -0.05,
		"the hands are drawn %.2f m off the face at their nearest" % r.hand_gap)
	print("  tall wall: %.2f m climbed, hands %.3f m off the face at their nearest"
		% [r.peak - r.start_y, r.hand_gap])

	# 2. Sprinting in changes nothing about the height.
	r = await _run_at(14.0, 1.0, {"sprint": true})
	_check(absf(r.peak - r.start_y - 4.0) < 0.15,
		"sprinting in climbed %.2f m, not 4.0" % (r.peak - r.start_y))
	print("  sprint in: %.2f m climbed at %.1f m/s entry" % [r.peak - r.start_y, r.entry_speed])

	# 3. A 5.5 m block: the ground climb reaches its lip and the mantle stands him on top.
	r = await _run_at(5.5, 3.0)
	if verbose: print("  5.5   ", r)
	_check(r.climbed and r.mantled, "a 5.5 m block was not climbed then mantled")
	_check(absf(r.end_y - 5.5) < 0.15, "after the 5.5 m mantle he stands at %.2f" % r.end_y)
	print("  5.5 m block: mantled=%s, standing at %.2f" % [r.mantled, r.end_y])

	# 4. A 6.5 m block is out of a ground climb's reach (4 + 1.9 = 5.9): climb, peel, no mantle.
	r = await _run_at(6.5, 3.0)
	_check(r.climbed and not r.mantled and r.peeled, "a 6.5 m block was not climb-and-peel")
	print("  6.5 m block: mantled=%s peeled=%s" % [r.mantled, r.peeled])

	# 5. A 1.5 m wall: the climb starts and the mantle takes the lip at once.
	r = await _run_at(1.5, 3.0)
	_check(r.mantled and absf(r.end_y - 1.5) < 0.15, "a 1.5 m wall run into was not mantled")
	print("  1.5 m wall: mantled=%s, standing at %.2f" % [r.mantled, r.end_y])

	# 6. 30 degrees off dead-on on the ground: no climb.
	r = await _run_at(14.0, 1.0, {"angle": 30.0})
	_check(not r.climbed, "a 30 degree approach climbed")
	print("  30 degrees: climbed=%s" % r.climbed)

	# 7. The chimney: climb A, jump, catch B, jump, catch A - each climb higher than the last.
	_build()
	_box(Vector3(14, 30, 1), Vector3(0, 15, FACE_Z - 0.5))          # A: face at FACE_Z, +Z
	_box(Vector3(14, 30, 1), Vector3(0, 15, FACE_Z + 6.0 + 0.5))    # B: 6 m across, face -Z
	_spawn(Vector3(0, 0.02, FACE_Z + 5.0))
	await _frames(3)
	Input.action_press("forward")
	var catches: Array[float] = []
	var normals: Array[float] = []
	var was := false
	for f in 600:
		await _frames(1)
		if pilot.is_wall_climbing and not was:
			catches.append(pilot.global_position.y)
			normals.append(pilot._wall_climb_normal.z)
			Input.action_release("forward")
		if pilot.is_wall_climbing and pilot._wall_climb_time >= 0.4:
			await _press("jump")
		was = pilot.is_wall_climbing
		if catches.size() >= 4:
			break
	await _teardown()
	print("  chimney: caught at %s, normals %s" % [str(catches), str(normals)])
	_check(catches.size() >= 4, "the chimney stalled after %d catches" % catches.size())
	for i in range(1, catches.size()):
		_check(normals[i] * normals[i - 1] < 0.0, "catch %d was the same wall again" % i)
		_check(catches[i] > catches[i - 1], "catch %d was no higher than the last" % i)

	print("")
	if fails.is_empty():
		print("PASS  wall climb probe")
		quit(0)
	else:
		print("FAIL  %d checks" % fails.size())
		quit(1)
