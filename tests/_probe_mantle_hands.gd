extends SceneTree
## Throwaway probe: runs real mantles headlessly and logs where his hands sit relative to
## the lip on every frame. Not part of the suite (no test_ prefix).
##   godot --headless --fixed-fps 60 --path . --script tests/_probe_mantle_hands.gd

const WALL_Z := -3.0   # wall face, facing +Z; he approaches along -Z

var world: Node3D
var pilot: CharacterBody3D
var skel: Skeleton3D
var tree_node: AnimationTree
var lh := -1
var rh := -1
var tip_local := Vector3.ZERO   # grip point in hand-bone space
var verbose := false
var summary: Array = []

func _initialize() -> void:
	_main.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _build(ledge_h: float) -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(60, 1, 60)
	fs.shape = fb
	floor_body.add_child(fs)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	var ledge := StaticBody3D.new()
	var ls := CollisionShape3D.new()
	var lb := BoxShape3D.new(); lb.size = Vector3(8, ledge_h, 6)
	ls.shape = lb
	ledge.add_child(ls)
	ledge.position = Vector3(0, ledge_h * 0.5, WALL_Z - 3.0)
	world.add_child(ledge)
	pilot = load("res://scenes/pilot9.tscn").instantiate()
	world.add_child(pilot)
	skel = pilot.get_node("character/Armature/GeneralSkeleton")
	tree_node = pilot.get_node("AnimationTree")
	lh = skel.find_bone("LeftHand")
	rh = skel.find_bone("RightHand")

func _teardown() -> void:
	for a in ["forward", "jump", "sprint"]:
		Input.action_release(a)
	world.queue_free()
	await _frames(2)

## Grip point: the far end of the hand mesh along the hand bone, measured off the skin.
func _measure_hand_tip() -> void:
	var pts: Array[Vector3] = []
	for mi in skel.get_children():
		if not (mi is MeshInstance3D) or mi.skin == null:
			continue
		var skin: Skin = mi.skin
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per: int = bones.size() / verts.size()
			for v in verts.size():
				for k in per:
					if weights[v * per + k] < 0.5:
						continue
					var bind_idx: int = bones[v * per + k]
					var bone_name := skin.get_bind_name(bind_idx)
					var bone := skin.get_bind_bone(bind_idx) if bone_name == "" else skel.find_bone(bone_name)
					if bone != lh:
						continue
					pts.append(skin.get_bind_pose(bind_idx) * verts[v])
	if pts.is_empty():
		print("no hand verts found; grip = wrist")
		return
	var mn := pts[0]; var mx := pts[0]
	for p in pts:
		mn = mn.min(p); mx = mx.max(p)
	print("left hand mesh in bone space: min=%v max=%v (%d verts)" % [mn, mx, pts.size()])
	tip_local = Vector3((mn.x + mx.x) * 0.5, mx.y, (mn.z + mx.z) * 0.5)

func _hand_world(bone: int, local := Vector3.ZERO) -> Vector3:
	# What is drawn: the physics-interpolated transform, not the last tick's.
	return skel.get_global_transform_interpolated() * (skel.get_bone_global_pose(bone) * local)

func _playback() -> AnimationNodeStateMachinePlayback:
	return tree_node.get("parameters/playback")

func _run(name: String, ledge_h: float, dist: float, mode: String) -> void:
	_build(ledge_h)
	pilot.global_position = Vector3(0, 0.05, WALL_Z + dist + 3.0)
	if mode == "drop":
		pilot.global_position = Vector3(0, ledge_h - 1.0, WALL_Z + dist)
	await _frames(3)
	if tip_local == Vector3.ZERO:
		_measure_hand_tip()
	if mode == "sprint":
		Input.action_press("sprint"); await _frames(1); Input.action_release("sprint")
	Input.action_press("forward")
	var f := 0
	var climb_f := -1
	var log: Array = []
	var jumped := 0
	var jump_frame := -100
	var pre_state := ""
	while f < 300:
		f += 1
		if jumped == 1:
			Input.action_release("jump")
			jumped = 2
		elif jumped == 0 and mode != "drop" and pilot.is_on_floor() \
				and pilot.global_position.z - WALL_Z <= dist:
			Input.action_press("jump")
			jumped = 1
			jump_frame = f
		if mode == "double" and f == jump_frame + 18:
			Input.action_press("jump")
		if mode == "double" and f == jump_frame + 19:
			Input.action_release("jump")
		if climb_f < 0:
			pre_state = String(_playback().get_current_node())
		await process_frame
		if pilot.is_climbing and climb_f < 0:
			climb_f = f
			Input.action_release("forward")
		if climb_f < 0:
			continue
		var lip := Vector3(0, ledge_h, WALL_Z)
		var pb := _playback()
		var l := _hand_world(lh); var r := _hand_world(rh)
		var lt := _hand_world(lh, tip_local); var rt := _hand_world(rh, tip_local)
		var wrist := (l + r) * 0.5
		var tip := (lt + rt) * 0.5
		log.append({"f": f - climb_f, "st": String(pb.get_current_node()),
			"fade": String(pb.get_fading_from_node()),
			"wy": wrist.y - lip.y, "wz": wrist.z - lip.z,
			"ty": tip.y - lip.y, "tz": tip.z - lip.z,
			"u": pilot._climb_time / pilot.climb_duration if pilot.is_climbing else 1.0,
			"feet": pilot.get_global_transform_interpolated().origin.y - lip.y})
		if not pilot.is_climbing and f - climb_f > 3:
			break
	await _teardown()
	if climb_f < 0:
		print("%-24s NO MANTLE" % name)
		return
	var e0: Dictionary = log[0]
	# Worst wrist error over the first 20% of the clip, where the hands should be on the lip.
	var worst := 0.0
	for e in log:
		if e.u <= 0.2 and absf(e.wy) > absf(worst):
			worst = e.wy
	print("%-24s from=%-10s f0 state=%-8s fade=%-8s wrist dy=%+.3f dz=%+.3f  tip dy=%+.3f dz=%+.3f  worst(u<.2) dy=%+.3f"
		% [name, pre_state, e0.st, e0.fade, e0.wy, e0.wz, e0.ty, e0.tz, worst])
	if verbose:
		for e in log:
			print("   f%-3d u=%.2f %-10s fade=%-10s wrist dy=%+.3f dz=%+.3f  tip dy=%+.3f dz=%+.3f  feet=%+.3f"
				% [e.f, e.u, e.st, e.fade, e.wy, e.wz, e.ty, e.tz, e.feet])

func _main() -> void:
	await _frames(2)
	verbose = true
	await _run("jump d1.0 h2.4", 2.4, 1.0, "jump")
	verbose = false
	for h in [2.4, 3.2, 4.2]:
		for d in [0.6, 2.0, 3.0]:
			await _run("jump d%.1f h%.1f" % [d, h], h, d, "jump")
	await _run("drop d0.5 h2.0", 2.0, 0.5, "drop")
	await _run("double d1.5 h5.0", 5.0, 1.5, "double")
	quit()
