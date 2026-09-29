extends SceneTree
## Throwaway probe: runs real mantles headlessly and logs the exit - his origin, his drawn soles
## and the camera against the top of the ledge - from the last frames of the climb until he has
## settled in Locomotion. Not part of the suite (no test_ prefix).
##   godot --headless --fixed-fps 60 --path . --script tests/_probe_mantle_exit.gd

const WALL_Z := -3.0   # wall face, facing +Z; he approaches along -Z

var world: Node3D
var pilot: CharacterBody3D
var skel: Skeleton3D
var tree_node: AnimationTree
var cam: Camera3D
var toes: Array[int] = []
var toes_rest_y := 0.0

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
	cam = pilot.get_node("CameraPivot/SpringArm3D/Camera3D")
	toes = [skel.find_bone("LeftToes"), skel.find_bone("RightToes")]
	toes_rest_y = 0.0
	for b in toes:
		toes_rest_y += skel.get_bone_global_rest(b).origin.y * 0.5

func _teardown() -> void:
	for a in ["forward", "jump"]:
		Input.action_release(a)
	world.queue_free()
	await _frames(2)

## Where the ground under his drawn toes is: toe bones minus their standing height.
func _soles_y() -> float:
	var xf := skel.get_global_transform_interpolated()
	var y := 0.0
	for b in toes:
		y += (xf * skel.get_bone_global_pose(b).origin).y * 0.5
	return y - toes_rest_y * skel.get_global_transform_interpolated().basis.get_scale().y

func _run(name: String, ledge_h: float, dist: float, verbose: bool) -> void:
	_build(ledge_h)
	pilot.global_position = Vector3(0, 0.05, WALL_Z + dist + 3.0)
	await _frames(3)
	Input.action_press("forward")
	var f := 0
	var jumped := 0
	var climb_f := -1
	var end_f := -1
	var rows: Array = []
	while f < 400:
		f += 1
		if jumped == 1:
			Input.action_release("jump")
			jumped = 2
		elif jumped == 0 and pilot.is_on_floor() and pilot.global_position.z - WALL_Z <= dist:
			Input.action_press("jump")
			jumped = 1
		await process_frame
		if pilot.is_climbing and climb_f < 0:
			climb_f = f
			Input.action_release("forward")
		if climb_f < 0:
			continue
		if not pilot.is_climbing and end_f < 0:
			end_f = f
		var pb: AnimationNodeStateMachinePlayback = tree_node.get("parameters/playback")
		rows.append({"f": f - climb_f, "end": end_f >= 0,
			"st": String(pb.get_current_node()), "fade": String(pb.get_fading_from_node()),
			"org": pilot.get_global_transform_interpolated().origin.y - ledge_h,
			"soles": _soles_y() - ledge_h,
			"cam": cam.get_global_transform_interpolated().origin.y - ledge_h,
			"floor": pilot.is_on_floor()})
		if end_f >= 0 and f - end_f > 30:
			break
	await _teardown()
	if climb_f < 0:
		print("%-18s NO MANTLE" % name)
		return
	# From 6 frames before the end: the worst the soles go under the top, and the biggest
	# one-frame jumps in origin and camera height.
	var i0 := 0
	for i in rows.size():
		if rows[i].end:
			i0 = maxi(i - 6, 1)
			break
	var sink := 0.0
	var org_jump := 0.0
	var cam_jump := 0.0
	for i in range(i0, rows.size()):
		sink = minf(sink, rows[i].soles)
		if absf(rows[i].org - rows[i - 1].org) > absf(org_jump):
			org_jump = rows[i].org - rows[i - 1].org
		if absf(rows[i].cam - rows[i - 1].cam) > absf(cam_jump):
			cam_jump = rows[i].cam - rows[i - 1].cam
	print("%-18s soles worst %+.3f  origin step %+.3f  camera step %+.3f  final origin %+.3f"
		% [name, sink, org_jump, cam_jump, rows[-1].org])
	if verbose:
		for i in range(i0 - 6, rows.size()):
			var e: Dictionary = rows[i]
			print("   f%-3d %-4s %-10s fade=%-10s origin=%+.3f soles=%+.3f cam=%+.3f floor=%s"
				% [e.f, "END" if e.end else "", e.st, e.fade, e.org, e.soles, e.cam, e.floor])

func _main() -> void:
	await _frames(2)
	await _run("h2.4 d1.0", 2.4, 1.0, true)
	for h in [2.0, 3.2, 4.2]:
		for d in [0.6, 2.0]:
			await _run("h%.1f d%.1f" % [h, d], h, d, false)
	quit()
