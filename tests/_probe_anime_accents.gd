extends SceneTree
## Measures where ANIME's impact accents should hold (docs/specs/anime-animation.md): how long after
## the event the impact pose actually arrives. ANIME is forced off so the live pose is measured.
##   godot --headless --fixed-fps 60 --path . --script tests/_probe_anime_accents.gd
##
## landing: drop from a height, the frame his hips are lowest (deepest knee bend) after touchdown.
## vault:   a real vault at a 0.9 m wall, the frame the lower hand is lowest (the plant).

const FACE_Z := -6.0
const DT := 1.0 / 60.0

var world: Node3D
var pilot: CharacterBody3D
var skel: Skeleton3D

func _initialize() -> void:
	_main.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _box(size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = pos
	world.add_child(b)

func _build(wall_h: float) -> void:
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(60, 1, 80), Vector3(0, -0.5, 0))
	if wall_h > 0.0:
		_box(Vector3(12, wall_h, 0.4), Vector3(0, wall_h * 0.5, FACE_Z - 0.2))
	pilot = load("res://scenes/pilot9.tscn").instantiate()
	world.add_child(pilot)
	skel = pilot.get_node("character/Armature/GeneralSkeleton")

func _teardown() -> void:
	for a in ["forward", "sprint", "walk", "jump"]:
		Input.action_release(a)
	world.queue_free()
	await _frames(2)

func _landing(height: float) -> void:
	_build(0.0)
	pilot.global_position = Vector3(0, height, 10)
	await _frames(1)
	pilot.anime_hold.enabled_override = 0
	var hips := skel.find_bone("Hips")
	var landed := -1
	var f := 0
	var low := 99.0
	var low_f := -1
	var standing := 0.0
	while f < 300:
		f += 1
		await process_frame
		if landed < 0:
			var pb0: AnimationNodeStateMachinePlayback = pilot.anim_tree.get("parameters/playback")
			if pb0.get_current_node() == &"jump_land":
				landed = f
			standing = skel.get_bone_global_pose(hips).origin.y
			continue
		var y := skel.get_bone_global_pose(hips).origin.y
		if OS.get_cmdline_user_args().has("verbose"):
			var pb: AnimationNodeStateMachinePlayback = pilot.anim_tree.get("parameters/playback")
			print("  +%2d  hips %.3f  %s" % [f - landed, y, pb.get_current_node()])
		if y < low:
			low = y
			low_f = f
		if f - landed > 30:
			break
	print("landing from %.1f m: hips lowest %d frames (%.3f s) after touchdown, %.3f below the fall pose" % [
		height, low_f - landed, (low_f - landed) * DT, standing - low])
	await _teardown()

func _vault() -> void:
	_build(0.9)
	pilot.global_position = Vector3(0, 0.02, FACE_Z + 14.0)
	await _frames(3)
	pilot.anime_hold.enabled_override = 0
	Input.action_press("sprint")
	await _frames(1)
	Input.action_release("sprint")
	Input.action_press("forward")
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	var start := -1
	var pressed := false
	var still := 99.0
	var still_f := -1
	var last := [Vector3.ZERO, Vector3.ZERO]
	var f := 0
	while f < 400:
		f += 1
		if not pressed and pilot.is_on_floor():
			var dist: float = pilot.global_position.z - FACE_Z - pilot._capsule_radius()
			if dist <= 1.5:
				Input.action_press("jump")
				pressed = true
		await process_frame
		if pressed:
			Input.action_release("jump")
		if pilot.is_vaulting:
			if start < 0:
				start = f
			# The plant: a hand on the wall top (within 0.15 m of 0.9, over the wall), at its stillest.
			var hands := [(skel.global_transform * skel.get_bone_global_pose(lh)).origin,
				(skel.global_transform * skel.get_bone_global_pose(rh)).origin]
			for i in 2:
				var p: Vector3 = hands[i]
				var speed: float = (p - last[i]).length() / DT
				var over := p.z < FACE_Z + 0.1 and p.z > FACE_Z - 0.5
				if f > start and absf(p.y - 0.9) < 0.15 and over and speed < still:
					still = speed
					still_f = f
				last[i] = p
		elif start >= 0:
			break
	if start < 0:
		print("vault: did not vault")
	else:
		print("vault: a hand is stillest on the wall top %d frames (%.3f s) after the vault starts (%.2f m/s)" % [
			still_f - start, (still_f - start) * DT, still])
	await _teardown()

func _main() -> void:
	await _frames(2)
	await _landing(1.5)
	await _landing(4.0)
	await _vault()
	quit(0)
