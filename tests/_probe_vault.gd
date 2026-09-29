extends SceneTree
## Runs real vaults headlessly: pilot9 runs at a wall, presses jump, and the probe checks what
## happened. Not part of the suite (no test_ prefix) - the suite's runner is synchronous and a
## vault needs frames. Exits 1 if any check fails.
##   godot --headless --fixed-fps 60 --path . --script tests/_probe_vault.gd [-- verbose]

const FACE_Z := -6.0   # near face of the wall, facing +Z; he runs along -Z
const DEPTH := 0.4     # the vault lane's thin walls

var world: Node3D
var pilot: CharacterBody3D
var skel: Skeleton3D
var lh := -1
var rh := -1
var fails: Array[String] = []
var verbose := false

func _initialize() -> void:
	verbose = OS.get_cmdline_user_args().has("verbose")
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

func _build(h: float, depth: float, grid_lane := "") -> void:
	world = Node3D.new()
	root.add_child(world)
	if grid_lane != "":
		_place_grid(grid_lane)
	else:
		_box(Vector3(60, 1, 80), Vector3(0, -0.5, 0))
		_box(Vector3(12, h, depth), Vector3(0, h * 0.5, FACE_Z - depth * 0.5))
	pilot = load("res://scenes/pilot9.tscn").instantiate()
	world.add_child(pilot)
	skel = pilot.get_node("character/Armature/GeneralSkeleton")
	lh = skel.find_bone("LeftHand")
	rh = skel.find_bone("RightHand")

## The real jump grid, moved so `lane`'s wall face sits where the probe's own wall would: x = 0,
## z = FACE_Z, the row's floor at y = 0.
func _place_grid(lane: String) -> void:
	var grid := (load("res://scenes/jump_grid.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(grid)
	var wall := grid.get_node("Vaults/%s/Wall" % lane) as Node3D
	var floor_body := grid.get_node("Vaults/Floor") as Node3D
	var wall_size: Vector3 = (wall.get_node("Shape") as CollisionShape3D).shape.size
	var floor_size: Vector3 = (floor_body.get_node("Shape") as CollisionShape3D).shape.size
	var face := wall.global_position + Vector3(0, 0, wall_size.z * 0.5)
	var floor_top := floor_body.global_position.y + floor_size.y * 0.5
	grid.global_position -= Vector3(face.x, floor_top, face.z - FACE_Z)

func _teardown() -> void:
	for a in ["forward", "jump", "sprint", "walk", "crouch"]:
		Input.action_release(a)
	world.queue_free()
	await _frames(2)

## Where the wrist is DRAWN: the physics-interpolated skeleton transform, as the camera sees it.
func _hand(bone: int) -> Vector3:
	return skel.get_global_transform_interpolated() * skel.get_bone_global_pose(bone).origin

func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("    FAIL ", msg)

## gait: walk / run / sprint. press_at: metres from the capsule's front to the face at the press.
## opts: "jump_at" (clip fraction to press jump at mid-vault), "crouch" (press crouch as the vault
## starts), "angle" (approach off square, degrees), "depth" (wall depth).
func _run(h: float, gait: String, press_at: float, opts := {}) -> Dictionary:
	_build(h, opts.get("depth", DEPTH), opts.get("grid", ""))
	var ang := deg_to_rad(opts.get("angle", 0.0))
	var back := 14.0
	pilot.global_position = Vector3(sin(ang) * back, 0.02, FACE_Z + cos(ang) * back)
	# Camera yaw steers "forward" (-Z at 0); turning it by `ang` aims the run at the face at `ang`.
	pilot.camera_pivot.rotation.y = ang
	await _frames(3)
	if gait == "sprint":
		Input.action_press("sprint")
		await _frames(1)
		Input.action_release("sprint")
	if gait == "walk":
		Input.action_press("walk")
	Input.action_press("forward")
	var res := {"vaulted": false, "entry": 0.0, "exit": 0.0, "hand_err": 0.0, "hand_dy": 0.0,
		"end_z": 0.0, "end_y": 0.0, "state": "", "jumped": false, "slid": false, "dip": false,
		"exit_on_floor": false, "exit_u": -1.0, "settle_y": 99.0}
	var pressed_f := -1
	var f := 0
	var planted := {}
	var jump_mid := -1
	var crouch_f := -1
	while f < 400:
		f += 1
		if pressed_f < 0 and pilot.is_on_floor():
			var dist: float = (pilot.global_position.z - FACE_Z) / cos(ang) - pilot._capsule_radius()
			if dist <= press_at:
				res.entry = Vector2(pilot.velocity.x, pilot.velocity.z).length()
				Input.action_press("jump")
				pressed_f = f
		elif pressed_f > 0 and f == pressed_f + 1:
			Input.action_release("jump")
		if pilot.is_vaulting and opts.has("jump_at") and jump_mid < 0 \
				and pilot._vault_u >= opts["jump_at"]:
			jump_mid = f
			Input.action_press("jump")
		elif jump_mid > 0 and f == jump_mid + 1:
			Input.action_release("jump")
		if pilot.is_vaulting and opts.has("crouch") and crouch_f < 0:
			crouch_f = f
			Input.action_press("crouch")
		elif crouch_f > 0 and f == crouch_f + 1:
			Input.action_release("crouch")
		var dip_before: float = pilot._dip_velocity
		var was_vaulting: bool = pilot.is_vaulting
		var u_before: float = pilot._vault_u
		await process_frame
		# process_frame fires BEFORE the idle pass that seeks and poses the skeleton, so the pose
		# here is last frame's. Run that pass's two steps now - the seek pilot9.gd's _process()
		# makes, then the tree - so the wrist is read off the pose this frame actually draws.
		# (frame_post_draw never fires headless.)
		pilot._seek_vault_clip()
		pilot.anim_tree.advance(0.0)
		if pilot._dip_velocity < dip_before - 0.01:
			res.dip = true
		if pilot.is_vaulting and not res.vaulted:
			res.vaulted = true
		if pilot.is_vaulting:
			var u: float = pilot._vault_u
			# Each wrist, inside its own planted window (the bake's, measured 2026-09-27): once
			# down it must not move, and it must sit a palm over the top.
			for b in [lh, rh]:
				var win := Vector2(0.46, 0.54) if b == lh else Vector2(0.52, 0.60)
				if u < win.x + 0.01 or u > win.y - 0.01:
					continue
				var p := _hand(b)
				if not planted.has(b):
					planted[b] = p
				res.hand_err = maxf(res.hand_err, (p - planted[b]).length())
				res.hand_dy = maxf(res.hand_dy, absf(p.y - (h + pilot.vault_palm)))
				if verbose:
					print("   %s u=%.3f hand %v  in from face %.3f  over top %+.3f"
						% ["L" if b == lh else "R", u, p, FACE_Z - p.z, p.y - h])
			if verbose:
				print("   f%d u=%.3f pos %v released=%s state=%s" % [f, u, pilot.global_position,
					pilot._vault_released, pilot.anim_tree.get("parameters/playback").get_current_node()])
		if was_vaulting and not pilot.is_vaulting:
			res.exit = Vector2(pilot.velocity.x, pilot.velocity.z).length()
			res.exit_u = u_before
			res.end_z = pilot.global_position.z
			res.end_y = pilot.global_position.y
			res.exit_on_floor = pilot.is_on_floor()
			res.land_speed = pilot._landing_speed_in
			res.jumped = pilot.velocity.y > 0.5
			res.slid = pilot.is_sliding
			# The dip is kicked the frame AFTER the touchdown (_resolve_landing_dip()).
			var dip_at_exit: float = pilot._dip_velocity
			await _frames(2)
			if pilot._dip_velocity < dip_at_exit - 0.01:
				res.dip = true
			res.state = String(pilot.anim_tree.get("parameters/playback").get_current_node())
			await _frames(20)
			res.settle_y = pilot.global_position.y
			break
		if not res.vaulted and pressed_f > 0 and f > pressed_f + 3:
			break
	await _teardown()
	return res

func _lane(h: float, gait: String) -> void:
	var name := "h%.1f %s" % [h, gait]
	var r := await _run(h, gait, 1.5)
	var want := maxf(r.entry, 5.0)
	print("%-12s vaulted=%s entry=%.2f exit=%.2f end z=%.2f y=%.3f floor=%s -> %-10s hands drift %.3f dy %.3f touchdown %.1f m/s dip=%s"
		% [name, r.vaulted, r.entry, r.exit, r.end_z, r.end_y, r.exit_on_floor, r.state,
		r.hand_err, r.hand_dy, r.get("land_speed", 0.0), r.dip])
	_check(r.vaulted, name + ": did not vault")
	if not r.vaulted:
		return
	_check(r.end_z < FACE_Z - DEPTH - 0.3, name + ": ended at z=%.2f, not past the wall" % r.end_z)
	_check(r.exit_on_floor and absf(r.settle_y) < 0.05,
		name + ": not on the floor after (settled y=%.3f)" % r.settle_y)
	_check(absf(r.exit - want) <= 0.1, name + ": exit %.2f, want %.2f" % [r.exit, want])
	_check(r.hand_err <= 0.03, name + ": planted wrist drifted %.3f m" % r.hand_err)
	_check(r.hand_dy <= 0.03, name + ": wrist %.3f m off a palm over the top" % r.hand_dy)

func _main() -> void:
	await _frames(2)
	var settings := root.get_node_or_null("/root/Settings")
	print("camera motion setting: %s" % (settings.camera_motion if settings else "no Settings"))
	if verbose:
		await _lane(1.1, "sprint")
		quit(0)
		return
	for h in [0.5, 0.7, 0.9, 1.1, 1.3]:
		for gait in ["walk", "run", "sprint"]:
			await _lane(h, gait)
	# The same vault on the real jump grid's lanes - the geometry the user plays.
	for lane in [["Vault_0p5m", 0.5], ["Vault_0p9m", 0.9], ["Vault_1p3m", 1.3]]:
		var g := await _run(lane[1], "sprint", 1.5, {"grid": lane[0]})
		print("grid %-10s vaulted=%s exit=%.2f end z=%.2f floor=%s -> %s" % [lane[0], g.vaulted,
			g.exit, g.end_z, g.exit_on_floor, g.state])
		_check(g.vaulted and g.exit_on_floor and g.end_z < FACE_Z - DEPTH - 0.3,
			"the jump grid's %s did not vault cleanly" % lane[0])
	for lane in ["Vault_1p5m_JUMP", "Vault_1p1m_TOODEEP"]:
		var g := await _run(1.1, "sprint", 1.5, {"grid": lane})
		print("grid %-18s vaulted=%s" % [lane, g.vaulted])
		_check(not g.vaulted, "the jump grid's %s control vaulted" % lane)
	# Informational, not a check: how deep a top actually vaults. The predicate allows
	# vault_max_depth, but the release pose has to be clear of the top too, and the clip's hands
	# let go ~0.9 m past where they planted.
	var line := "depth sweep (1.1 m, sprint):"
	for dd in [0.4, 0.5, 0.6, 0.7, 0.8, 1.0, 1.5]:
		var g := await _run(1.1, "sprint", 1.5, {"depth": dd})
		line += "  %.1f=%s" % [dd, "vault" if g.vaulted else "jump"]
	print(line)
	var r := await _run(1.5, "sprint", 1.5)
	print("1.5 m wall     vaulted=%s" % r.vaulted)
	_check(not r.vaulted, "1.5 m wall vaulted")
	r = await _run(1.1, "sprint", 1.5, {"depth": 3.0})
	print("deep block     vaulted=%s" % r.vaulted)
	_check(not r.vaulted, "3 m deep block vaulted")
	r = await _run(1.1, "sprint", 3.5)
	print("3.5 m out      vaulted=%s" % r.vaulted)
	_check(not r.vaulted, "press 3.5 m out vaulted")
	r = await _run(1.1, "run", 1.5, {"angle": 50.0})
	print("50 deg         vaulted=%s" % r.vaulted)
	_check(not r.vaulted, "50 degree approach vaulted")
	r = await _run(1.1, "run", 1.5, {"angle": 40.0})
	print("40 deg         vaulted=%s end z=%.2f" % [r.vaulted, r.end_z])
	_check(r.vaulted, "40 degree approach did not vault")
	r = await _run(1.1, "sprint", 1.5, {"jump_at": 0.3})
	print("jump buffered  jumped=%s at u=%.3f -> %s" % [r.jumped, r.exit_u, r.state])
	_check(r.jumped and absf(r.exit_u - 0.61) < 0.03, "a jump pressed before the release did not fire on it")
	r = await _run(1.1, "sprint", 1.5, {"jump_at": 0.64})
	print("jump cancel    jumped=%s at u=%.3f -> %s" % [r.jumped, r.exit_u, r.state])
	_check(r.jumped and r.exit_u < 0.7, "a jump after the release did not cancel the vault")
	r = await _run(1.1, "sprint", 1.5, {"crouch": true})
	print("crouch->slide  slid=%s -> %s" % [r.slid, r.state])
	_check(r.slid, "crouch during a sprint vault did not exit into a slide")
	print("")
	print("PASS" if fails.is_empty() else "FAIL %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
