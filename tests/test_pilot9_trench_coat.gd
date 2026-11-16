extends "res://tests/test_case.gd"

# docs/specs/pilot9-trench-coat.md. The key, on at boot, the bones and the mesh, the arm pieces,
# the springs' sizes and limits, the ghosts, and who never wears it. How it looks is judged from
# tests/_probe_coat_shot.gd and in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const COCKPIT_TSCN := "res://scenes/cockpit.tscn"
const COAT_MESH := preload("res://scripts/items/trench_coat_mesh.gd")
const BODY := preload("res://scripts/items/trench_coat_body.gd")
const CEL_SHADER := preload("res://shaders/cel/cel-shader-base.gdshader")
const DT := 1.0 / 60.0

# One shared in-tree instance, for the reason tests/test_pilot9_dash.gd gives.
var _pilot: Node = null
var _extra: Node = null

func end() -> void:
	if is_instance_valid(_extra):
		_extra.free()
	_extra = null
	super()

# The pilot unfrozen with the coat on and settled, whatever the last test left.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.frozen = false
	_pilot.is_crouching = false
	var coat: Node = _pilot.coat
	if coat != null:
		coat.velocity_override = null
		coat.extra_planes = []
		coat.set_on(true)
	return _pilot

func _run(coat: Node, ticks: int) -> void:
	for i in ticks:
		coat.tick(DT)

func test_t_is_no_longer_bound() -> void:
	check(not InputMap.has_action(&"coat"), "the coat is worn through the BODY slot now, not a T key")

func test_spawns_wearing_it() -> void:
	var ps := load(PILOT_TSCN) as PackedScene
	_extra = ps.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_extra)
	var coat: Node = _extra.coat
	check(coat != null and coat.mesh_instance != null, "the coat should be built at spawn")
	if coat == null or coat.mesh_instance == null:
		return
	check(_extra.is_coat_on() and coat.mesh_instance.visible, "he should spawn wearing it")
	eq(coat.mesh_instance.get_parent(), coat.skeleton, "the coat mesh sits under his skeleton")
	eq(coat.mesh_instance.get_node_or_null(coat.mesh_instance.skeleton), coat.skeleton, "and is skinned to it")

func test_body_slot_drives_the_coat() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var worn := Inventory.unequip(Inventory.SLOT_BODY)
	check(not pilot.is_coat_on() and not pilot.coat.mesh_instance.visible, "emptying BODY takes it off")
	Inventory.equip(Inventory.SLOT_BODY, worn)
	check(pilot.is_coat_on() and pilot.coat.mesh_instance.visible, "wearing it again puts it back on")

func test_chain_bones() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	var skel: Skeleton3D = coat.skeleton
	var hips := skel.find_bone("Hips")
	eq(coat.upper_bones.size(), 8, "eight chains")
	for c in 8:
		var up := skel.find_bone("CoatU%d" % c)
		var lo := skel.find_bone("CoatL%d" % c)
		check(up >= 0 and lo >= 0, "chain %d has both bones" % c)
		eq(skel.get_bone_parent(up), hips, "CoatU%d hangs from the hips" % c)
		eq(skel.get_bone_parent(lo), up, "CoatL%d hangs from CoatU%d" % [c, c])
		check(skel.get_bone_global_rest(up).basis.is_equal_approx(Basis.IDENTITY), "CoatU%d rests unrotated" % c)
		# Left chains 0..3 on his left (+X), right chains 4..7 mirrored.
		var x := skel.get_bone_global_rest(up).origin.x
		check(x > 0.0 if c < 4 else x < 0.0, "CoatU%d is on the right side of him" % c)
	eq(coat.mesh_instance.skin.get_bind_count(), skel.get_bone_count(), "the skin binds every bone")

func test_mesh_is_low_poly_faceted_and_weighted() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	var mesh := coat.mesh_instance.mesh as ArrayMesh
	eq(mesh.get_surface_count(), 2, "leather and lining")
	var triangles := 0
	var bone_count: int = coat.skeleton.get_bone_count()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		check(arrays[Mesh.ARRAY_INDEX] == null, "surface %d shares no vertices between triangles" % s)
		eq(verts.size() % 3, 0, "surface %d is whole triangles" % s)
		triangles += verts.size() / 3
		var flat := 0
		var facing := 0
		for t in verts.size() / 3:
			var n := normals[t * 3]
			if n.is_equal_approx(normals[t * 3 + 1]) and n.is_equal_approx(normals[t * 3 + 2]) and n.is_normalized():
				flat += 1
			# Godot's front face is clockwise: the stored normal should be that face's.
			var face := (verts[t * 3 + 2] - verts[t * 3]).cross(verts[t * 3 + 1] - verts[t * 3]).normalized()
			if face.dot(n) > 0.99:
				facing += 1
		eq(flat, verts.size() / 3, "surface %d: every triangle carries one face normal" % s)
		eq(facing, verts.size() / 3, "surface %d: every normal is its triangle's front" % s)
		var bad := 0
		for i in verts.size():
			var total := 0.0
			for j in 4:
				total += weights[i * 4 + j]
				if bones[i * 4 + j] < 0 or bones[i * 4 + j] >= bone_count:
					bad += 1
			if absf(total - 1.0) > 0.001:
				bad += 1
		eq(bad, 0, "surface %d: weights sum to 1 on real bones" % s)
	# 450 since the rounded sleeve heads (2026-11-12, +60). 600 since the long sleeves (cuff 0.36, 2026-11-12).
	check(triangles >= 250 and triangles <= 600, "about 300-600 triangles, got %d" % triangles)

func test_mesh_is_mirrored() -> void:
	var pilot := _scene()
	var mesh := pilot.coat.mesh_instance.mesh as ArrayMesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(COAT_MESH.LEATHER)[Mesh.ARRAY_VERTEX]
	var left := 0.0
	var right := 0.0
	for v in verts:
		left = maxf(left, v.x)
		right = minf(right, v.x)
	approx(left, -right, 0.0001, "the coat reaches as far right as left")

func test_hem_is_mid_calf_and_collar_under_his_ears() -> void:
	var pilot := _scene()
	var mesh := pilot.coat.mesh_instance.mesh as ArrayMesh
	var aabb := mesh.get_aabb()
	var skel: Skeleton3D = pilot.coat.skeleton
	var knee := skel.get_bone_global_rest(skel.find_bone("LeftLowerLeg")).origin.y
	var ankle := skel.get_bone_global_rest(skel.find_bone("LeftFoot")).origin.y
	check(aabb.position.y < knee and aabb.position.y > ankle + 0.15, "the hem is between knee and ankle (%.2f)" % aabb.position.y)
	# His ear fins start at 1.85 m; the hat's brim sits above that.
	check(aabb.end.y < 1.8, "the collar stays under his ears (%.2f)" % aabb.end.y)

func test_materials() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	var mi: MeshInstance3D = coat.mesh_instance
	check(mi.material_override == null, "no whole-mesh override: the looks swap it per surface, like his body")
	var colours := [coat.leather_color, coat.lining_color]
	for s in 2:
		var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
		check(base != null and base.albedo_color.is_equal_approx(colours[s]), "surface %d's own material carries its brown" % s)
		var cel := mi.get_surface_override_material(s) as ShaderMaterial
		check(cel != null and cel.shader == CEL_SHADER, "surface %d wears pilot9's cel material" % s)
		if cel != null:
			check((cel.get_shader_parameter(&"color") as Color).is_equal_approx(colours[s]), "surface %d's cel is tinted the same" % s)
	check((mi.get_surface_override_material(COAT_MESH.LEATHER) as ShaderMaterial).next_pass != null, "the leather is inked")
	check((mi.get_surface_override_material(COAT_MESH.LINING) as ShaderMaterial).next_pass == null, "the lining is not")
	check(coat.leather_color.r > coat.leather_color.g and coat.leather_color.g > coat.leather_color.b, "it is brown")
	check(coat.lining_color.get_luminance() < coat.leather_color.get_luminance(), "the lining is the darker brown")

func test_arm_pieces_hide_under_it() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	check(coat.arm_meshes.size() >= 2, "his arm pieces should be found (%d)" % coat.arm_meshes.size())
	for mi: MeshInstance3D in coat.arm_meshes:
		check(not mi.visible, "%s is hidden under the coat" % mi.name)
		check(coat.arm_share(mi.mesh, mi.skin) >= coat.ARM_SHARE, "%s is an arm piece" % mi.name)
	var kept := 0
	for child in coat.skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.name != &"CarriedCrate" and mi != coat.mesh_instance and not coat.arm_meshes.has(mi) \
				and not coat.covered_meshes.has(mi) and not coat.cut_meshes.has(mi):
			kept += 1
			check(mi.visible, "%s (not an arm or trunk piece) stays" % mi.name)
	check(kept >= 4, "his head, hands and legs stay (%d meshes)" % kept)
	coat.set_on(false)
	for mi: MeshInstance3D in coat.arm_meshes:
		check(mi.visible, "%s comes back with the coat off" % mi.name)

# Long sleeves: the cuff's rim reaches his hand, so no wrist shows.
func test_cuff_reaches_his_hand() -> void:
	var skel: Skeleton3D = _scene().coat.skeleton
	var elbow := skel.get_bone_global_rest(skel.find_bone("LeftLowerArm")).origin
	var wrist := skel.get_bone_global_rest(skel.find_bone("LeftHand")).origin
	var rim: Array = COAT_MESH.SLEEVE_LOWER[COAT_MESH.SLEEVE_LOWER.size() - 1]
	check(elbow.distance_to(wrist) - float(rim[0]) < 0.01, "the cuff ends at his hand (%.3f short)" % (elbow.distance_to(wrist) - float(rim[0])))

# -- the fitted cut: his trunk under the coat ---------------------------------------------------

# Rest-pose position and heaviest bone of every vertex of `mi`, per surface: [positions, bone names].
func _rest_vertices(mi: MeshInstance3D, skel: Skeleton3D, surface: int) -> Array:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(verts.size(), 1)
	var at := PackedVector3Array()
	var names := PackedStringArray()
	for i in verts.size():
		var p := Vector3.ZERO
		var best := ""
		var best_w := 0.0
		for j in per:
			var w := weights[i * per + j]
			if w <= 0.0:
				continue
			var bind := bones[i * per + j]
			var bone := skel.find_bone(mi.skin.get_bind_name(bind))
			if bone < 0:
				bone = mi.skin.get_bind_bone(bind)
			p += (skel.get_bone_global_rest(bone) * (mi.skin.get_bind_pose(bind) * verts[i])) * w
			if w > best_w:
				best_w = w
				best = skel.get_bone_name(bone)
		at.append(p)
		names.append(best)
	var index = arrays[Mesh.ARRAY_INDEX]
	if index == null:
		index = PackedInt32Array(range(verts.size()))
	return [at, names, index]

func test_trunk_pieces_are_swapped_for_cut_copies() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	check(coat.covered_meshes.size() >= 2, "his torso and hip pieces are covered (%d)" % coat.covered_meshes.size())
	check(coat.cut_meshes.size() >= 2, "and have cut copies (%d)" % coat.cut_meshes.size())
	for mi: MeshInstance3D in coat.covered_meshes:
		check(not mi.visible, "%s is hidden under the coat" % mi.name)
		check(not coat.arm_meshes.has(mi), "%s is not also an arm piece" % mi.name)
	for mi: MeshInstance3D in coat.cut_meshes:
		check(mi.visible, "%s is worn under the coat" % mi.name)
		eq(mi.get_parent(), coat.skeleton, "%s sits under his skeleton" % mi.name)
		eq(mi.get_node_or_null(mi.skeleton), coat.skeleton, "%s is skinned to it" % mi.name)
		var own := coat.skeleton.get_node_or_null(String(mi.name).trim_suffix(coat.CUT_SUFFIX)) as MeshInstance3D
		check(own != null and coat.covered_meshes.has(own), "%s stands in for one of his own pieces" % mi.name)
		if own != null:
			eq(mi.skin, own.skin, "%s shares its piece's skin" % mi.name)
			eq(mi.mesh.get_surface_count(), own.mesh.get_surface_count(), "%s keeps its piece's surfaces" % mi.name)
	coat.set_on(false)
	for mi: MeshInstance3D in coat.covered_meshes:
		check(mi.visible, "%s comes back whole with the coat off" % mi.name)
	for mi: MeshInstance3D in coat.cut_meshes:
		check(not mi.visible, "%s goes with the coat" % mi.name)

func test_nothing_of_his_trunk_is_left_under_the_coat() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	var skel: Skeleton3D = coat.skeleton
	var trunk := ["Hips", "Spine", "Chest", "UpperChest"]
	var kept := 0
	var behind := 0
	var outside := 0
	var front := 0
	for mi: MeshInstance3D in coat.cut_meshes:
		for s in mi.mesh.get_surface_count():
			var data := _rest_vertices(mi, skel, s)
			var at: PackedVector3Array = data[0]
			var names: PackedStringArray = data[1]
			var index: PackedInt32Array = data[2]
			for t in index.size() / 3:
				var a := index[t * 3]
				var b := index[t * 3 + 1]
				var c := index[t * 3 + 2]
				if a == b and b == c:
					continue
				kept += 1
				if not (trunk.has(names[a]) and trunk.has(names[b]) and trunk.has(names[c])):
					continue
				var centre := (at[a] + at[b] + at[c]) / 3.0
				# What stands inside the collar is not under the coat.
				if centre.y >= BODY.COLLAR_Y:
					continue
				if centre.z < 0.0:
					behind += 1
				elif absf(centre.x) > COAT_MESH.front_edge_x(centre.y) + BODY.STRIP_MARGIN + 0.001:
					outside += 1
				else:
					front += 1
	check(kept > 0, "the cut copies still have triangles")
	eq(behind, 0, "no trunk triangle is left behind his side seam")
	eq(outside, 0, "no trunk triangle is left outside the front strip")
	check(front > 50, "the front of his chest and belt is still there (%d triangles)" % front)

func test_cut_leaves_his_legs_head_and_hands_whole() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	for child in coat.skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi == coat.mesh_instance or mi.skin == null or coat.cut_meshes.has(mi):
			continue
		var legs: float = BODY.bone_share(mi.mesh, mi.skin, ["UpperLeg", "LowerLeg", "Foot", "Toes", "Head", "Hand"])
		if legs > 0.9:
			check(not coat.covered_meshes.has(mi), "%s (legs, head or hands) is never cut" % mi.name)

func test_coat_is_fitted() -> void:
	var pilot := _scene()
	var mesh := pilot.coat.mesh_instance.mesh as ArrayMesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(COAT_MESH.LEATHER)[Mesh.ARRAY_VERTEX]
	# Half-widths by height band: shoulders, chest, waist, hem.
	var widest := {"shoulder": 0.0, "waist": 0.0, "hem": 0.0}
	var back := {"chest": 0.0, "waist": 0.0}
	for v in verts:
		# The sleeves are not the trunk.
		if v.y > 1.45 and v.y < 1.63 and absf(v.x) < 0.3 and absf(v.z) < 0.01:
			widest["shoulder"] = maxf(widest["shoulder"], absf(v.x))
		if absf(v.y - COAT_MESH.ROW_WAIST_Y) < 0.001:
			widest["waist"] = maxf(widest["waist"], absf(v.x))
			back["waist"] = maxf(back["waist"], -v.z)
		if absf(v.y - COAT_MESH.ROW_CHEST_Y) < 0.001:
			back["chest"] = maxf(back["chest"], -v.z)
		if absf(v.y - COAT_MESH.ROW_HEM_Y) < 0.001:
			widest["hem"] = maxf(widest["hem"], absf(v.x))
	# The slim cut: tight everywhere. Below the waist the floor is his legs (+-0.215, never cut).
	check(widest["shoulder"] <= 0.23, "the shoulders sit on his own shoulder line (%.3f)" % widest["shoulder"])
	check(widest["waist"] <= 0.205, "the waist is taken in (%.3f)" % widest["waist"])
	check(back["chest"] <= 0.14 and back["waist"] <= 0.14, "the back sits on him (%.3f, %.3f)" % [back["chest"], back["waist"]])
	check(widest["hem"] >= 0.235 and widest["hem"] <= 0.27, "the skirt is a column just outside his legs (%.3f)" % widest["hem"])
	check(widest["hem"] > widest["waist"] + 0.03, "the skirt still clears his stride")

func test_ghosts_wear_the_cut_body() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	pilot._afterimage._build_if_stale()
	for mi: MeshInstance3D in coat.cut_meshes:
		check(pilot._afterimage._sources.has(mi), "the afterimage pool knows %s" % mi.name)
	# A ghost copies only what is visible when it is dropped: the cut pieces, not the whole ones.
	for mi: MeshInstance3D in coat.covered_meshes:
		check(not mi.is_visible_in_tree(), "%s would not be copied onto a ghost" % mi.name)

func test_tilt_helpers_round_trip() -> void:
	var coat: Node = _scene().coat
	for d: Vector2 in [Vector2(0.3, 0.0), Vector2(-0.2, 0.9), Vector2(0.0, -1.4)]:
		var u: Vector3 = coat.tilt_quat(d) * Vector3.DOWN
		check(coat.tilt_of(u).is_equal_approx(d), "tilt %s survives the round trip" % d)
	# y is his front (+Z), x his left (+X).
	check((coat.tilt_quat(Vector2(0.0, 0.5)) * Vector3.DOWN).z > 0.4, "a front tilt swings the tip forward")
	check((coat.tilt_quat(Vector2(0.5, 0.0)) * Vector3.DOWN).x > 0.4, "a left tilt swings the tip to his left")

func test_idle_sways_a_little_and_never_much() -> void:
	var coat: Node = _scene().coat
	_run(coat, 120)
	var low := Vector3(INF, INF, INF)
	var high := -low
	for i in 240:
		coat.tick(DT)
		var tip: Vector3 = coat.chain_world(3)[2]
		low = low.min(tip)
		high = high.max(tip)
	var travel := (high - low).length()
	check(travel > 0.003, "the hem is never dead still (%.4f m)" % travel)
	check(travel < 0.05, "and only sways a couple of centimetres (%.4f m)" % travel)

func test_run_and_sprint_trail_the_tails() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	var facing: Vector3 = pilot._facing()
	var angles := []
	for speed: float in [5.0, 7.5]:
		coat.reset()
		coat.velocity_override = facing * speed
		_run(coat, 150)
		# The vent chains' lower segments (3 and 7): the tails he is seen by from behind.
		var lean: float = (coat.tilt_deg(8 + 3).length() + coat.tilt_deg(8 + 7).length()) * 0.5
		angles.append(lean)
		var hang: Array = coat.chain_world(3)
		check((hang[2] - hang[0]).dot(facing) < -0.1, "at %.1f m/s the tail streams behind him" % speed)
	check(angles[0] > 10.0 and angles[0] < 25.0, "about 15 deg in a run, got %.1f" % angles[0])
	check(angles[1] > 30.0 and angles[1] < 46.0, "35-45 deg in a sprint, got %.1f" % angles[1])

func test_front_panels_stay_on_him_in_a_sprint() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	coat.velocity_override = pilot._facing() * 7.5
	_run(coat, 150)
	for c: int in [0, 4]:
		var inward: float = -coat.tilt_deg(c).dot(coat._out[c])
		check(inward <= coat.inward_deg + 0.5, "front panel %d is pressed to him, not through him (%.1f deg in)" % [c, inward])

func test_dash_is_capped_below_level() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	coat.velocity_override = pilot._facing() * 40.0
	_run(coat, 150)
	for c in 8:
		var pts: Array = coat.chain_world(c)
		check(pts[2].y < pts[0].y - 0.1, "chain %d still hangs below its waist pivot in a dash" % c)
		check(coat.tilt_deg(8 + c).length() <= coat.cap_deg + 0.01, "chain %d is inside the hard cap" % c)
	check(coat.tilt_deg(8 + 3).length() > 50.0, "and the tails are near the drag cap (%.1f)" % coat.tilt_deg(8 + 3).length())

func test_falling_flares_it() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	_run(coat, 60)
	var still: float = coat.tilt_deg(8 + 1).dot(coat._out[1])
	coat.velocity_override = Vector3.DOWN * 12.0
	_run(coat, 150)
	var falling: float = coat.tilt_deg(8 + 1).dot(coat._out[1])
	check(falling > still + 12.0, "a fall lifts the side panel outward (%.1f -> %.1f deg)" % [still, falling])

func test_floor_keeps_the_tails_up() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	# A floor at knee height, as when he is low in a slide: every joint and tip stays above it.
	var floor_y: float = pilot.global_position.y + 0.55
	coat.extra_planes = [[Vector3(0.0, floor_y, 0.0), Vector3.UP]]
	coat.velocity_override = pilot._facing() * 9.0
	_run(coat, 150)
	for c in 8:
		var pts: Array = coat.chain_world(c)
		check(pts[1].y >= floor_y + coat.plane_margin - 0.005, "chain %d's knee row is above the floor" % c)
		check(pts[2].y >= floor_y + coat.plane_margin - 0.005, "chain %d's hem is above the floor (%.3f)" % [c, pts[2].y - floor_y])

func test_wall_keeps_the_near_side_off_it() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	var facing: Vector3 = pilot._facing()
	# A wall 0.3 m to one side of him, closer than the hem hangs.
	var side: Vector3 = facing.cross(Vector3.UP).normalized()
	var point: Vector3 = pilot.global_position + side * 0.3
	coat.extra_planes = [[point, -side]]
	coat.velocity_override = facing * 7.5
	_run(coat, 150)
	for c in 8:
		var pts: Array = coat.chain_world(c)
		for k: int in [1, 2]:
			var gap: float = (pts[k] - point).dot(-side)
			check(gap >= coat.plane_margin - 0.005, "chain %d point %d is off the wall (%.3f m)" % [c, k, gap])

func test_crouch_pools_the_skirt() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	_run(coat, 120)
	var before: float = coat.tilt_deg(8 + 1).dot(coat._out[1])
	pilot.is_crouching = true
	_run(coat, 120)
	var after: float = coat.tilt_deg(8 + 1).dot(coat._out[1])
	pilot.is_crouching = false
	check(after > before + coat.crouch_pool_deg * 0.6, "the side panel pools outward in a crouch (%.1f -> %.1f)" % [before, after])

func test_reset_stills_it() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	coat.velocity_override = pilot._facing() * 20.0
	_run(coat, 60)
	coat.velocity_override = null
	coat.reset()
	for k in 16:
		check(coat.tilt_deg(k).length() < 0.001, "segment %d hangs still after a reset" % k)

func test_ghosts_wear_it() -> void:
	var pilot := _scene()
	var coat: Node = pilot.coat
	pilot._afterimage._build_if_stale()
	check(pilot._afterimage._sources.has(coat.mesh_instance), "the afterimage pool should copy the coat")
	var ghost: Skeleton3D = pilot._afterimage._pool[0]
	eq(ghost.get_bone_count(), coat.skeleton.get_bone_count(), "a ghost has the coat's chain bones")
	check(ghost.find_bone("CoatL7") >= 0, "by name")

func test_hat_and_coat_are_independent() -> void:
	var pilot := _scene()
	if pilot.is_hat_on():
		pilot.toggle_hat()
	check(pilot.is_coat_on() and not pilot.is_hat_on(), "coat on, hat off to start the check")
	pilot.toggle_hat()
	check(pilot.is_coat_on() and pilot.is_hat_on(), "H leaves the coat alone")
	pilot.toggle_coat()
	check(not pilot.is_coat_on() and pilot.is_hat_on(), "T leaves the hat alone")
	pilot.toggle_hat()
	pilot.toggle_coat()

func test_hidden_with_him_aboard() -> void:
	var ps := load(PILOT_TSCN) as PackedScene
	_extra = ps.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_extra)
	_extra.enter_vehicle(null)
	check(not _extra.coat.mesh_instance.is_visible_in_tree(), "the coat is hidden with him inside the mech")

func test_cockpit_pilot_and_knight_never_wear_it() -> void:
	var ps := load(COCKPIT_TSCN) as PackedScene
	check(ps != null, "cockpit.tscn loads")
	if ps != null:
		_extra = ps.instantiate()
		check(_extra.find_children("Coat", "MeshInstance3D", true, false).is_empty(), "no coat in the cockpit shot")
		check(_extra.find_children("TrenchCoat", "", true, false).is_empty(), "no coat holder in the cockpit shot")
		_extra.free()
	var knight := KnightBody.new()
	_extra = knight
	(Engine.get_main_loop() as SceneTree).root.add_child(knight)
	check(knight.skeleton.get_node_or_null(^"Coat") == null, "the Knight has no trench coat")

func test_tick_is_cheap() -> void:
	var coat: Node = _scene().coat
	coat.velocity_override = _pilot._facing() * 7.5
	_run(coat, 30)
	var t0 := Time.get_ticks_usec()
	_run(coat, 400)
	var each := float(Time.get_ticks_usec() - t0) / 400.0
	# The budget is 0.3 ms for both pilots; one pilot's tick measures ~0.06 ms.
	check(each < 150.0, "one pilot's tick is under 0.15 ms (%.0f usec)" % each)
