extends "res://tests/test_case.gd"

# Painted shading - see docs/specs/painted-shading.md. What can be fenced headlessly: the shader
# compiles with its uniforms, the materials pick the anchor the grill chose, the globals exist,
# the setting defaults on, and apply_stylized.gd stamps a stable per-mesh seed and takes it off
# again. What the patches look like is checked by eye (tests/_probe_paint_shot.gd).

const BASE := "res://shaders/cel/cel-shader-base.gdshader"
const APPLIER := "res://scripts/rendering/apply_stylized.gd"
const SettingsScript := preload("res://scripts/settings.gd")

func test_the_cel_shader_compiles_with_the_paint_anchor() -> void:
	var names := shader_uniform_names(BASE)
	check(names.size() > 0, "cel-shader-base failed to compile")
	check(names.has("paint_anchor"), "cel-shader-base has no paint_anchor uniform")

func test_characters_anchor_to_uv_and_the_ground_to_world() -> void:
	eq(declared_default(BASE, "paint_anchor"), "0", "the shader default is UV")
	var ground := load("res://resources/cel_ground.tres") as ShaderMaterial
	eq(ground.get_shader_parameter(&"paint_anchor"), 1, "cel_ground is world-anchored")
	for path in ["res://resources/cel_character.tres", "res://resources/pilot_cel_character.tres"]:
		var mat := load(path) as ShaderMaterial
		var anchor: Variant = mat.get_shader_parameter(&"paint_anchor")
		check(anchor == null or anchor == 0, "%s must stay UV-anchored" % path)

func test_project_declares_every_paint_global() -> void:
	for key in ["paint_strength", "paint_value", "paint_warmth", "paint_steps",
			"paint_softness", "paint_world_size", "paint_world_detail_size",
			"paint_world_detail_weight", "paint_uv_size", "paint_angularity"]:
		var entry: Dictionary = ProjectSettings.get_setting("shader_globals/" + key, {})
		eq(entry.get("type"), "float", "shader global %s missing or not a float" % key)
	eq(ProjectSettings.get_setting("shader_globals/paint_strength", {}).get("value"), 0.5,
		"painted shading is on at half strength unless the setting turns it off")
	eq(ProjectSettings.get_setting("shader_globals/paint_steps", {}).get("value"), 3.0,
		"three levels: dark / base / light")
	eq(ProjectSettings.get_setting("shader_globals/paint_world_size", {}).get("value"), 5.0,
		"big world patches are about 5 m, so a 20 m platform gets about four")
	eq(ProjectSettings.get_setting("shader_globals/paint_world_detail_size", {}).get("value"), 1.25,
		"the small world layer keeps crates and pillars from sitting inside one flat patch")
	eq(ProjectSettings.get_setting("shader_globals/paint_world_detail_weight", {}).get("value"), 0.35,
		"the small layer is the fainter one")
	eq(ProjectSettings.get_setting("shader_globals/paint_angularity", {}).get("value"), 0.6,
		"mostly straight-cut polygons with some cloud left in")

func test_the_setting_is_a_graphics_toggle_that_defaults_on() -> void:
	var row: Array = SettingsScript._row(&"painted_shading")
	check(not row.is_empty(), "no painted_shading row")
	if row.is_empty():
		return
	eq(row[2], "graphics", "PAINTED SHADING lives under graphics")
	eq(row[3], ["off", "on"], "PAINTED SHADING is OFF / ON")
	eq(SettingsScript.defaults()[&"painted_shading"], "on", "default ON")

func test_the_seed_is_stable_in_range_and_differs_between_meshes() -> void:
	var applier := load(APPLIER) as GDScript
	var a: float = applier.paint_seed_for("../Pilot9/Skeleton3D/Cube_039")
	eq(a, applier.paint_seed_for("../Pilot9/Skeleton3D/Cube_039"), "same path, same seed")
	check(a >= 0.0 and a < 100.0, "seed outside 0..100: %f" % a)
	check(a != applier.paint_seed_for("../Pilot9/Skeleton3D/Cube_040"),
		"two meshes got the same seed")

func test_apply_stamps_the_seed_and_clear_takes_it_off() -> void:
	var root := Node3D.new()
	var target := Node3D.new()
	target.name = "Target"
	var left := MeshInstance3D.new()
	left.name = "Left"
	var right := MeshInstance3D.new()
	right.name = "Right"
	target.add_child(left)
	target.add_child(right)
	root.add_child(target)
	var applier: Node = (load(APPLIER) as GDScript).new()
	root.add_child(applier)
	applier.material = ShaderMaterial.new()
	var targets: Array[NodePath] = [NodePath("../Target")]
	applier.targets = targets

	applier.apply_now()
	var seed_left: Variant = left.get_instance_shader_parameter(&"paint_seed")
	var seed_right: Variant = right.get_instance_shader_parameter(&"paint_seed")
	check(seed_left != null and seed_right != null, "apply must stamp paint_seed on every mesh")
	check(seed_left != seed_right, "sibling meshes must not share a seed")

	applier.clear_now()
	eq(left.get_instance_shader_parameter(&"paint_seed"), null,
		"clear must remove the seed, or it serialises into the scene on save")
	root.free()
