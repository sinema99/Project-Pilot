extends "res://tests/test_case.gd"

# EXIA's weathered paint. See docs/specs/mech-weathering.md. The look is tests/_probe_mech_paint_shot.gd.

const MechScene := preload("res://scenes/mech.tscn")
const SHADER_PATH := "res://shaders/mech_weathered.gdshader"
const Bake := preload("res://scripts/mech_wear_bake.gd")

var _instances: Array[Node] = []

func _mech_in_tree() -> Node3D:
	var mech: Node3D = MechScene.instantiate()
	_instances.append(mech)
	(Engine.get_main_loop() as SceneTree).root.add_child(mech)
	mech.set_physics_process(false)
	mech.set_process(false)
	return mech

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super.end()

func _meshes(mech: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in mech.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		# The two back boxes (BoxMesh, built in code) are not the GLB's body.
		if not (n as MeshInstance3D).mesh is BoxMesh:
			out.append(n as MeshInstance3D)
	return out

func _mat(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.material_override as ShaderMaterial

func _mesh(mech: Node3D, mesh_name: String) -> MeshInstance3D:
	for mi in _meshes(mech):
		if mi.name == mesh_name:
			return mi
	return null

func test_the_shader_compiles_with_the_uniforms_the_script_drives() -> void:
	var names := shader_uniform_names(SHADER_PATH)
	check(not names.is_empty(), "the weathering shader compiles")
	for want in ["paint_color", "paint_left", "is_frame", "hazard", "use_rest", "seed", "has_wear_map",
			"box_half", "ground_grime"]:
		check(want in names, "uniform %s exists" % want)
	check(not "glow" in names, "nothing on the mech glows any more")
	# The one EMISSION allowed is AIRFRAME's flat magenta CharView marker (airframe-character-pixels).
	var code := (load(SHADER_PATH) as Shader).code.replace("EMISSION = vec3(1.0, 0.0, 1.0);", "")
	check(not "EMISSION" in code, "the weathering shader writes no emission beyond the CharView marker")

func test_every_mech_mesh_wears_the_weathered_paint() -> void:
	var mech := _mech_in_tree()
	var meshes := _meshes(mech)
	eq(meshes.size(), 19, "EXIA has 19 meshes")
	for mi in meshes:
		var m := _mat(mi)
		check(m != null and m.shader == load(SHADER_PATH), "%s wears the weathered shader" % mi.name)

func test_shell_takes_the_paint_and_the_frame_is_dark_metal() -> void:
	var mech := _mech_in_tree()
	for shell in ["Cube_013", "Cube_004", "Cube_003", "Cube_009", "Cube_001", "Cylinder", "Cube_011"]:
		eq(_mat(_mesh(mech, shell)).get_shader_parameter(&"is_frame"), false, "%s is shell" % shell)
	for frame in ["Sphere_002", "Sphere_003", "Sphere_004", "Sphere_005"]:
		eq(_mat(_mesh(mech, frame)).get_shader_parameter(&"is_frame"), true, "%s is frame" % frame)

func test_wear_runs_from_the_chest_down_to_the_legs() -> void:
	var mech := _mech_in_tree()
	var chest: float = _mat(_mesh(mech, "Cube_013")).get_shader_parameter(&"paint_left")
	var thigh: float = _mat(_mesh(mech, "Cube_003")).get_shader_parameter(&"paint_left")
	approx(chest, 0.85, 0.001, "the chest keeps about 85% of its paint")
	approx(thigh, 0.7, 0.001, "the thighs keep about 70%")

func test_the_head_sphere_is_yellow_shell_and_only_the_feet_are_striped() -> void:
	var mech := _mech_in_tree()
	eq(_mat(_mesh(mech, "Sphere_006")).get_shader_parameter(&"is_frame"), false, "the head sphere is yellow shell like the body")
	for mi in _meshes(mech):
		var hazard: bool = _mat(mi).get_shader_parameter(&"hazard")
		eq(hazard, mi.name == "Cube_011" or mi.name == "Cube_012", "%s hazard stripes" % mi.name)

func test_every_part_wears_a_fresh_wear_bake() -> void:
	var mech := _mech_in_tree()
	for mi in _meshes(mech):
		eq(_mat(mi).get_shader_parameter(&"has_wear_map"), true, "%s has its wear bake" % mi.name)
		check((mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM2) != 0, "%s carries the wear distances" % mi.name)
	# The live GLB parts still match what was baked (a Mech_V1 re-export means re-running the tool).
	var fresh: Node3D = MechScene.instantiate()
	_instances.append(fresh)
	for mi: MeshInstance3D in fresh.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var baked := load("%s/%s.res" % [MechPaint.WEAR_DIR, mi.name]) as ArrayMesh
		check(baked != null, "%s has a bake on disk" % mi.name)
		if baked != null:
			eq(int(baked.get_meta(&"source_vertex_count", -1)), mi.mesh.surface_get_array_len(0),
				"%s bake matches the GLB (else run tools/bake_mech_wear.gd)" % mi.name)

func test_the_bake_puts_wear_on_edges_and_bottoms_first() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var baked: ArrayMesh = (Bake.bake_parts({"box": box}) as Dictionary)["box"]
	var arr := baked.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var field: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM2]
	check(pos.size() > 100, "a 1 m box is subdivided (%d verts)" % pos.size())
	# On the +X side face: the vertex nearest the top edge, the bottom edge and the middle.
	var want := {"top": Vector3(0.5, 0.42, 0.0), "bottom": Vector3(0.5, -0.42, 0.0), "middle": Vector3(0.5, 0.0, 0.0)}
	var at := {}
	for key: String in want:
		var best := -1
		for v in pos.size():
			if nrm[v].x > 0.9 and (best < 0 or pos[v].distance_to(want[key]) < pos[best].distance_to(want[key])):
				best = v
		at[key] = best
	var chip := func(v: int) -> float: return field[v * 4]
	var drop := func(v: int) -> float: return field[v * 4 + 2]
	check(chip.call(at["bottom"]) < chip.call(at["top"]), "a bottom edge wears more than a top edge")
	check(chip.call(at["middle"]) > chip.call(at["top"]), "the middle of a face is farther from wear than its edges")
	check(drop.call(at["top"]) < drop.call(at["middle"]), "streaks start right under the top edge")
	approx(field[at["middle"] * 4 + 1], Bake.FAR, 0.001, "a lone box has no seams")

func test_the_scheme_dropdown_repaints_every_part() -> void:
	var mech := _mech_in_tree()
	var paint: MechPaint = mech.get_node("MechPaint")
	eq(paint.scheme, MechPaint.Scheme.YELLOW, "yellow is the default")
	for scheme: int in MechPaint.PAINTS:
		paint.scheme = scheme
		for mi in _meshes(mech):
			eq(_mat(mi).get_shader_parameter(&"paint_color"), MechPaint.PAINTS[scheme],
				"%s wears scheme %d" % [mi.name, scheme])

func test_the_wear_slider_scales_the_rust() -> void:
	var mech := _mech_in_tree()
	var paint: MechPaint = mech.get_node("MechPaint")
	var chest := _mat(_mesh(mech, "Cube_013"))
	paint.wear = 0.0
	check(float(chest.get_shader_parameter(&"paint_left")) >= 1.0, "wear 0 turns all wear off")
	paint.wear = 2.0
	approx(chest.get_shader_parameter(&"paint_left"), 0.7, 0.001, "wear 2 doubles the rust share")

func test_the_back_boxes_are_shell_with_heavier_wear() -> void:
	var mech := _mech_in_tree()
	var boxes := 0
	for attach in mech.find_children("BackPanels*", "BoneAttachment3D", true, false):
		var mi := attach.get_child(0) as MeshInstance3D
		var m := _mat(mi)
		check(m != null, "%s wears the paint" % mi.name)
		if m == null:
			continue
		eq(m.get_shader_parameter(&"is_frame"), false, "%s is shell" % mi.name)
		approx(m.get_shader_parameter(&"paint_left"), MechPaint.BACK_BOX_LEFT, 0.001, "%s heavier wear" % mi.name)
		check(float(m.get_shader_parameter(&"paint_left")) < float(_mat(_mesh(mech, "Cube_013")).get_shader_parameter(&"paint_left")),
			"%s is more worn than the chest" % mi.name)
		eq(m.get_shader_parameter(&"box_half"), (mi.mesh as BoxMesh).size * 0.5, "%s edges come from its box" % mi.name)
		eq(m.get_shader_parameter(&"ground_grime"), false, "%s has no ground grime" % mi.name)
		boxes += 1
	eq(boxes, 2, "two back boxes")

func test_skinned_bodies_wear_their_rest_pose_in_the_running_game() -> void:
	var mech := _mech_in_tree()
	for mi in _meshes(mech):
		eq(_mat(mi).get_shader_parameter(&"use_rest"), true, "%s projects from its rest pose" % mi.name)
		check((mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, "%s carries the rest positions" % mi.name)

func test_undress_leaves_nothing_for_the_scene_file() -> void:
	var mech := _mech_in_tree()
	var paint: MechPaint = mech.get_node("MechPaint")
	paint.undress()
	for mi in _meshes(mech):
		check(mi.material_override == null, "%s has no override left" % mi.name)
		check((mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM2) == 0, "%s has its GLB mesh back" % mi.name)
