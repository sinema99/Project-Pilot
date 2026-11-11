extends "res://tests/test_case.gd"

# docs/specs/jetpack-look.md. The scene wires up, the look swaps every surface it owns and gives
# them back, and the QA keys flip what they say. How it LOOKS is judged in play and by
# tests/_probe_jetpack_shot.gd.

const SURFACE := "res://shaders/ps1/ps1_surface.gdshader"
const SCREEN := "res://shaders/ps1/ps1_screen.gdshader"


func _scene() -> Node:
	var s: Node = (load("res://Jetpack.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _key(look: Node, keycode: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	e.pressed = true
	look._unhandled_input(e)


func _ps1(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.get_surface_override_material(0) as ShaderMaterial


func test_shaders_declare_the_toggles() -> void:
	var names := shader_uniform_names(SURFACE)
	for u in ["albedo_color", "mapping", "object_scale", "texels_per_metre", "shade_count",
			"shade_dark", "shade_light", "clump_texels", "jitter_chance", "snap_enabled",
			"snap_lines", "affine_enabled", "sun_dir"]:
		check(u in names, "surface shader has %s" % u)
	check(not ("albedo_tex" in names), "no textures: colour pixels only")
	eq(declared_default(SURFACE, "affine_enabled"), "false", "affine starts off")
	eq(declared_default(SURFACE, "snap_enabled"), "true", "snap starts on")
	var screen := shader_uniform_names(SCREEN)
	for u in ["stripe_strength", "fringe_px", "saturation", "contrast"]:
		check(u in screen, "screen shader has %s" % u)


func test_scene_applies_the_look() -> void:
	var s := _scene()
	var look: Node = s.get_node(^"JetpackLook")
	eq(look._world_surfaces.size(), 15, "ground + 14 boxes are look surfaces")
	var ground := s.get_node(^"World/Ground/Mesh") as MeshInstance3D
	check(_ps1(ground) != null, "ground wears the PS1 material")
	approx(float(_ps1(ground).get_shader_parameter(&"texels_per_metre")), 16.0, 0.001,
		"16 texels per metre is the rule")
	check(look.is_pilot_swapped(), "pilot wears the PS1 material")
	check(look.filter_visible(), "screen filter is up")
	var pilot := s.get_node(^"Pilot9")
	eq(pilot.movement_effects_allowed, false, "pilot's movement effects are vetoed")
	eq(pilot.starting_item, null, "pilot carries no staff")
	eq(pilot.rim_light_enabled, false, "no rim light")
	s.free()


func test_surfaces_take_their_own_colour() -> void:
	var s := _scene()
	var red := s.get_node(^"World/Boxes/RedBlock/Mesh") as MeshInstance3D
	var blue := s.get_node(^"World/Boxes/BigBlock/Mesh") as MeshInstance3D
	var c_red: Color = _ps1(red).get_shader_parameter(&"albedo_color")
	var c_blue: Color = _ps1(blue).get_shader_parameter(&"albedo_color")
	check(c_red.r > c_red.b, "red box stays red")
	check(c_blue.b > c_blue.r, "blue box stays blue")
	eq(_ps1(red).get_shader_parameter(&"mapping"), 0, "the level is world projected")
	s.free()


func test_pilot_body_is_rest_pose_projected() -> void:
	var s := _scene()
	var look: Node = s.get_node(^"JetpackLook")
	var first: Array = look._pilot_surfaces[0]
	var mi := first[0] as MeshInstance3D
	var ps1 := first[3] as ShaderMaterial
	eq(ps1.get_shader_parameter(&"mapping"), 2, "skinned body uses the rest pose")
	var fmt: int = mi.mesh.surface_get_format(0)
	check(fmt & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "rest positions baked into CUSTOM0")
	check(fmt & Mesh.ARRAY_FORMAT_CUSTOM1 != 0, "rest normals baked into CUSTOM1")
	check(fmt & Mesh.ARRAY_FORMAT_BONES != 0, "still skinned after the bake")
	# The scale turns mesh units into metres (an imported body may store him at another size), so his
	# tallest side comes out human sized.
	# The body comes in pieces (pilot 2 wears 11 meshes), so measure all of them together.
	var tall := 0.0
	for entry: Array in look._pilot_surfaces:
		var piece := entry[0] as MeshInstance3D
		var size := piece.mesh.get_aabb().size
		var piece_scale: float = (entry[3] as ShaderMaterial).get_shader_parameter(&"object_scale")
		tall = maxf(tall, maxf(size.x, maxf(size.y, size.z)) * piece_scale)
	check(tall > 1.0 and tall < 3.0, "rest scale gives a human-sized body (%.2f m)" % tall)
	s.free()


func test_look_key_gives_everything_back() -> void:
	var s := _scene()
	var look: Node = s.get_node(^"JetpackLook")
	var ground := s.get_node(^"World/Ground/Mesh") as MeshInstance3D
	var first: Array = look._pilot_surfaces[0]
	_key(look, KEY_5)
	check(ground.get_surface_override_material(0) is StandardMaterial3D, "look off: own colour material")
	eq((first[0] as MeshInstance3D).get_surface_override_material(first[1]), first[2],
		"look off: pilot's own material back")
	check(not look.filter_visible(), "look off: no filter")
	_key(look, KEY_5)
	check(look.is_world_swapped(), "look on again")
	check(look.is_pilot_swapped(), "pilot swapped again")
	s.free()


func test_qa_keys_flip_the_shader() -> void:
	var s := _scene()
	var look: Node = s.get_node(^"JetpackLook")
	var mat := _ps1(s.get_node(^"World/Ground/Mesh") as MeshInstance3D)
	_key(look, KEY_6)
	eq(mat.get_shader_parameter(&"snap_enabled"), false, "6 turns snapping off")
	_key(look, KEY_7)
	eq(mat.get_shader_parameter(&"affine_enabled"), true, "7 turns affine on")
	_key(look, KEY_8)
	approx(mat.get_shader_parameter(&"texels_per_metre"), 8.0, 0.001, "8 drops to 8 /m")
	_key(look, KEY_8)
	approx(mat.get_shader_parameter(&"texels_per_metre"), 16.0, 0.001, "8 again is back to 16 /m")
	_key(look, KEY_9)
	check(not look.filter_visible(), "9 hides the filter")
	s.free()
