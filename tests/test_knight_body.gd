extends "res://tests/test_case.gd"

# The knight boss's body - see docs/specs/knight-boss.md. Headless fences the build (his own meshes
# only, all skinned to pilot9's skeleton), the robe's blended weights, the frozen pose, the pose
# layer and his place in the arena. How he looks is checked by tests/_probe_knight_shot.gd.

const ARENA := "res://scenes/boss_arena.tscn"
const PARTS := [&"Armor", &"Robe", &"RobeInner", &"Cloth", &"Mask", &"Sash", &"Decals"]

var _node: Node

func end() -> void:
	if is_instance_valid(_node):
		_node.free()
	_node = null
	super()

func _knight() -> KnightBody:
	var k := KnightBody.new()
	_node = k
	(Engine.get_main_loop() as SceneTree).root.add_child(k)
	return k

func test_only_his_own_meshes_are_on_the_skeleton() -> void:
	var k := _knight()
	var meshes := k.find_children("*", "MeshInstance3D", true, false)
	eq(meshes.size(), PARTS.size(), "one mesh per material, none of pilot9's")
	for key: StringName in PARTS:
		var mi: MeshInstance3D = k.parts.get(key)
		check(mi != null and mi.get_parent() == k.skeleton, "%s is on the skeleton" % key)

func test_every_part_is_skinned_to_the_skeleton() -> void:
	var k := _knight()
	for key: StringName in k.parts:
		var mi: MeshInstance3D = k.parts[key]
		check(mi.skin != null and mi.skin.get_bind_count() == k.skeleton.get_bone_count(), "%s has a bind per bone" % key)
		check(mi.get_node_or_null(mi.skeleton) == k.skeleton, "%s points at the skeleton" % key)
		check(mi.material_override is ShaderMaterial, "%s keeps its own material_override" % key)
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		eq((arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size(), verts.size() * 4, "%s has 4 weights a vertex" % key)

func test_the_decals_carry_no_ink_pass() -> void:
	var k := _knight()
	check((k.parts[&"Decals"] as MeshInstance3D).material_override.next_pass == null, "slots and cracks are ink already")
	check((k.parts[&"Armor"] as MeshInstance3D).material_override.next_pass != null, "the armour is outlined")

# --- the coat (docs/specs/knight-coat.md) ------------------------------------------------------

const COAT_DT := 1.0 / 60.0

func test_the_robe_hangs_on_the_coat_chains() -> void:
	var k := _knight()
	var sk := k.skeleton
	for i in KnightBody.COAT_CHAINS:
		check(sk.find_bone("CoatU%d" % i) >= 0 and sk.find_bone("CoatL%d" % i) >= 0, "chain %d has two bones" % i)
		eq(sk.get_bone_parent(sk.find_bone("CoatL%d" % i)), sk.find_bone("CoatU%d" % i), "chain %d is a chain" % i)
	check(sk.find_bone("SashTail0") >= 0 and sk.find_bone("SashTail1") >= 0, "a bone per sash tail")
	eq(k.coat_first, sk.find_bone("CoatU0"), "the coat bones come last")
	var arrays := (k.parts[&"Robe"] as MeshInstance3D).mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var hips := sk.find_bone("Hips")
	var blended := 0
	var on_coat := 0
	var below := 0
	for v in verts.size():
		var up := false
		var lo := false
		var coat := 0.0
		for j in 4:
			var b := bones[v * 4 + j]
			var w := weights[v * 4 + j]
			if w > 0.05 and b >= k.coat_first:
				up = up or sk.get_bone_name(b).begins_with("CoatU")
				lo = lo or sk.get_bone_name(b).begins_with("CoatL")
			if b >= k.coat_first:
				coat += w
			elif w > 0.0:
				check(b == hips, "the robe's only other bone is the hips")
		if up and lo:
			blended += 1
		if verts[v].y < 0.8:
			below += 1
			if coat > 0.999:
				on_coat += 1
	check(blended > 50, "robe vertices blend the upper and lower segment (%d)" % blended)
	eq(on_coat, below, "below the waist band the robe is all coat")

func test_the_pose_layer_leaves_the_coat_alone() -> void:
	var k := _knight()
	var b := k.skeleton.find_bone("CoatL3")
	var q := Quaternion(Vector3.RIGHT, 0.3)
	k.skeleton.set_bone_pose_rotation(b, q)
	k.show_pose(k.solve_pose(KnightPoses.HOVER))
	k.show_blend(k.solve_pose(KnightPoses.HOVER), k.solve_pose(KnightPoses.SMASH_DIVE), 0.5)
	check(k.skeleton.get_bone_pose_rotation(b).is_equal_approx(q), "show_pose / show_blend skip the coat bones")

## Chain i's hem point (skeleton space, unscaled).
func _hem(k: KnightBody, i: int) -> Vector3:
	var lo := k.skeleton.find_bone("CoatL%d" % i)
	var deg := float(i) * KnightBody.COAT_STEP
	var hem := KnightBody.ROBE.size() - 1
	var off := k._robe_point(deg, hem, 1.0 + k._coat_depth(hem)) - k.skeleton.get_bone_global_rest(lo).origin
	var pose := k.skeleton.get_bone_global_pose(lo)
	return pose.origin + pose.basis * off

func _hem_centre(k: KnightBody) -> Vector3:
	var c := Vector3.ZERO
	for i in KnightBody.COAT_CHAINS:
		c += _hem(k, i)
	return c / float(KnightBody.COAT_CHAINS)

func _awake_coat(k: KnightBody) -> void:
	k.set_physics_process(false)
	k.coat_sweep_target = 0.0
	k.reset_coat()

func test_dormant_coat_rests_in_the_drawings_sweep() -> void:
	var k := _knight()
	k.set_physics_process(false)
	approx(k.coat_sweep, 1.0, 0.0001, "dormant: the full sweep")
	var swept := _hem_centre(k)
	_awake_coat(k)
	var straight := _hem_centre(k)
	check(swept.x - straight.x > 0.2, "the hem sweeps to his left (%.3f m)" % (swept.x - straight.x))
	check(swept.z < straight.z, "and back (%.3f m)" % (swept.z - straight.z))

func test_the_idle_billow_never_stops() -> void:
	var k := _knight()
	_awake_coat(k)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var still := 0
	var longest := 0
	var prev := _hem(k, 2)
	for n in 360:
		k.tick_coat(COAT_DT)
		var p := _hem(k, 2)
		if n > 60:
			lo = lo.min(p)
			hi = hi.max(p)
		still = still + 1 if p.distance_to(prev) < 1e-5 else 0
		longest = maxi(longest, still)
		prev = p
	var travel := (hi - lo).length() * k.body_scale
	check(travel > 0.05 and travel < 0.1, "the hem travels 5-8 cm when he's still (%.3f m)" % travel)
	check(longest < 10, "it never holds still (%d frames)" % longest)
	var tail := k.skeleton.find_bone("SashTail0")
	check(not k.skeleton.get_bone_pose_rotation(tail).is_equal_approx(k.skeleton.get_bone_rest(tail).basis.get_rotation_quaternion()),
		"the sash tails move too")

func test_drift_trails_the_coat_then_it_settles() -> void:
	var k := _knight()
	_awake_coat(k)
	k.coat_idle_deg = 0.0
	var waist := k.skeleton.get_bone_global_pose(k.skeleton.find_bone("Hips")).origin
	# Let it hang first (the drawing's hips are tilted, so gravity moves it a little).
	for n in 240:
		k.tick_coat(COAT_DT)
	var rest := _hem_centre(k)
	for n in 180:
		k.global_position += Vector3.RIGHT * 4.0 * COAT_DT
		k.tick_coat(COAT_DT)
	var trail := _hem_centre(k)
	var angle := rad_to_deg(atan2(rest.x - trail.x, waist.y - trail.y))
	check(angle > 17.0 and angle < 23.0, "a 4 m/s drift trails the hem ~20 deg (%.1f)" % angle)
	var crossed := false
	for n in 240:
		k.tick_coat(COAT_DT)
		crossed = crossed or _hem_centre(k).x > rest.x + 0.005
	check(crossed, "it swings past when he stops")
	check(_hem_centre(k).distance_to(rest) < 0.01, "and settles (%.3f m)" % _hem_centre(k).distance_to(rest))

func test_big_moves_flare_but_stay_capped() -> void:
	var k := _knight()
	_awake_coat(k)
	var cap := deg_to_rad(k.coat_cap_deg) + 0.001
	var inward := deg_to_rad(k.coat_inward_deg) + 0.001
	var flare := 0.0
	var ok := true
	var segs := k._seg_d.size()
	for n in 90:
		var speed := 47.0 if n < 27 else 0.0
		k.global_position += Vector3.DOWN * speed * COAT_DT
		k.tick_coat(COAT_DT)
		var sum := 0.0
		for s in segs:
			var d: Vector2 = k._seg_d[s]
			ok = ok and d.length() <= cap and d.dot(k._seg_out[s]) >= -inward
			if s >= KnightBody.COAT_CHAINS and s < 2 * KnightBody.COAT_CHAINS:
				sum += d.dot(k._seg_out[s])
		flare = maxf(flare, rad_to_deg(sum / float(KnightBody.COAT_CHAINS)))
	check(ok, "no segment passes the cap or swings in more than the inward cap")
	check(flare > 25.0, "the dive flares the hem out (%.1f deg)" % flare)

func test_a_teleport_does_not_whip_the_coat() -> void:
	var k := _knight()
	_awake_coat(k)
	k.coat_idle_deg = 0.0
	k.tick_coat(COAT_DT)
	k.global_position += Vector3(50.0, 0.0, 0.0)
	k.tick_coat(COAT_DT)
	k.tick_coat(COAT_DT)
	var most := 0.0
	for d: Vector2 in k._seg_d:
		most = maxf(most, d.length())
	check(most < 0.01, "a jump over 5 m is a reset, not a kick (%.3f rad)" % most)

func test_waking_lets_the_sweep_go() -> void:
	var holder := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var k := KnightBody.new()
	holder.add_child(k)
	_node = holder
	k.set_physics_process(false)
	var pilot := Node3D.new()
	holder.add_child(pilot)
	pilot.global_position = Vector3(0.0, 0.0, 20.0)
	var brain := KnightBrain.new()
	k.add_child(brain)
	brain.setup(k, pilot, Vector3.ZERO)
	brain.set_physics_process(false)
	brain.tick(COAT_DT)
	k.tick_coat(COAT_DT)
	check(brain.is_awake(), "pilot in range wakes him")
	eq(k.coat_sweep_target, 0.0, "awake: the coat heads for a neutral hang")
	for n in 45:
		brain.tick(COAT_DT)
		k.tick_coat(COAT_DT)
	check(k.coat_sweep > 0.3 and k.coat_sweep < 0.7, "it lets go over the wake (%.2f at 0.77 s)" % k.coat_sweep)
	for n in 60:
		brain.tick(COAT_DT)
		k.tick_coat(COAT_DT)
	approx(k.coat_sweep, 0.0, 0.0001, "gone by 1.5 s")
	brain.reset()
	approx(k.coat_sweep, 1.0, 0.0001, "a reset puts him back in the drawing")

func test_the_pose_is_the_drawing_and_he_hovers() -> void:
	var k := _knight()
	var arm := k.skeleton.find_bone("RightUpperArm")
	check(not k.skeleton.get_bone_pose_rotation(arm).is_equal_approx(k.skeleton.get_bone_rest(arm).basis.get_rotation_quaternion()),
			"the reaching arm is posed")
	# His right hand reaches out (-X) past his left, which hangs by the hip.
	var r := k.skeleton.get_bone_global_pose(k.skeleton.find_bone("RightHand")).origin
	var l := k.skeleton.get_bone_global_pose(k.skeleton.find_bone("LeftHand")).origin
	check(r.x < -0.6 and absf(l.x) < 0.45, "right hand out, left hand in (%s, %s)" % [r, l])
	approx(k.model.position.y + k.lowest_point() * k.body_scale, k.hover, 0.001, "the sabaton tips hover")
	approx(k.model.scale.x, 1.5, 0.0001, "1.5x pilot9")

func test_f6_idle_swap_is_retired() -> void:
	var k := _knight()
	check(not k.has_method(&"set_idle"), "the idle-clip swap is gone (docs/specs/knight-moveset.md)")
	check(not (&"toggle_key" in k), "no F6 key on the body")

func test_pose_layer_blends_two_solved_poses() -> void:
	var k := _knight()
	var arm := k.skeleton.find_bone("RightUpperArm")
	var a := k.solve_pose(KnightPoses.HOVER)
	var b := k.solve_pose(KnightPoses.LASER_THRUST)
	k.show_blend(a, b, 0.0)
	check(k.skeleton.get_bone_pose_rotation(arm).is_equal_approx(a[arm]), "t=0 is the first pose")
	k.show_blend(a, b, 1.0)
	check(k.skeleton.get_bone_pose_rotation(arm).is_equal_approx(b[arm]), "t=1 is the second pose")
	k.show_blend(a, b, 0.5)
	var mid := k.skeleton.get_bone_pose_rotation(arm)
	check(not mid.is_equal_approx(a[arm]) and not mid.is_equal_approx(b[arm]), "t=0.5 is in between")
	var drawing := k.solve_pose(KnightBody.POSE)
	k.apply_pose()
	check(k.skeleton.get_bone_pose_rotation(arm).is_equal_approx(drawing[arm]), "the drawing solves to the old pose")

func test_take_hit_flashes_him() -> void:
	var k := _knight()
	var got := []
	k.hit_taken.connect(func(a, kind, _p): got.append([a, kind]))
	k.take_hit(50.0, &"reflect_perfect", k.global_position)
	check(k.is_flashing(), "a white flash")
	check((k.parts[&"Armor"] as MeshInstance3D).material_overlay != null, "the overlay is on")
	eq(got.size(), 1, "hit_taken fired")
	k._process(1.0)
	check(not k.is_flashing() and (k.parts[&"Armor"] as MeshInstance3D).material_overlay == null, "the flash fades off")

func test_the_arena_puts_him_on_the_anchor_facing_the_spawn() -> void:
	var arena := (load(ARENA) as PackedScene).instantiate() as BossArena
	_node = arena
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	var k := arena.knight as KnightBody
	check(k != null, "the arena has the knight")
	var anchor := arena.map.get_node(^"BossAnchor") as Node3D
	check(k.global_position.is_equal_approx(anchor.global_position), "on the anchor")
	var spawn := arena.map.get_node(^"spawn") as Node3D
	var to := spawn.global_position - k.global_position
	to.y = 0.0
	check(k.global_basis.z.normalized().dot(to.normalized()) > 0.99, "he faces the spawn")

func test_knight_has_his_own_key_light() -> void:
	var k := _knight()
	check(k.key_light != null and k.key_light.get_parent() == k, "the key light rides on him")
	eq(k.key_light.light_cull_mask, KnightBody.LIGHT_MASK, "it lights his layer only")
	for key: StringName in k.parts:
		eq((k.parts[key] as MeshInstance3D).layers, KnightBody.LIGHT_MASK, "%s is on his light layer" % key)
	# It comes from his front, above, on his right (the drawing's image left).
	# A directional light shines along its -Z, so +Z points back at where it comes from.
	var from := k.key_light.basis.z
	check(from.z > 0.3 and from.y > 0.3 and from.x < 0.0, "lit from upper front right (%s)" % from)

func test_knight_outline_is_heavier() -> void:
	var k := _knight()
	var outline := (k.parts[&"Armor"] as MeshInstance3D).material_override.next_pass as ShaderMaterial
	approx(float(outline.get_meta(&"ink_scale", 1.0)), k.ink_scale, 0.0001, "RETRO reads his ink scale")
	check(k.ink_scale > 1.0, "his line is heavier than everyone's")
	var retro := RetroLook.new()
	var ink := retro.ink_chain(outline, (k.parts[&"Armor"] as MeshInstance3D).material_override) as ShaderMaterial
	approx(float(ink.get_shader_parameter(&"ink_width")), retro.ink_width * k.ink_scale, 0.0001, "RETRO's twin keeps the scale")
	# Far away the line thins with him, in both looks.
	check(k.ink_far_ref > 0.0, "his line thins with distance")
	approx(float(outline.get_shader_parameter(&"ink_far_ref")), k.ink_far_ref, 0.0001, "CEL thins")
	approx(float(ink.get_shader_parameter(&"ink_far_ref")), k.ink_far_ref, 0.0001, "RETRO thins")
	approx(float(ink.get_shader_parameter(&"ink_far_min")), k.ink_far_min, 0.0001, "RETRO keeps the floor")
	retro.free()

func test_knight_arena_sun_leaves_him_to_his_key_light() -> void:
	var arena := (load(ARENA) as PackedScene).instantiate() as BossArena
	_node = arena
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	check(arena.sun != null and arena.sun.light_cull_mask & KnightBody.LIGHT_MASK == 0, "the sun skips his layer")
	check(arena.sun.light_cull_mask & 1 != 0, "the sun still lights the map")
