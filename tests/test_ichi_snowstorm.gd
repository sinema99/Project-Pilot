extends "res://tests/test_case.gd"

# Ichi snowstorm - see docs/specs/ichi-snowstorm.md. What can be fenced headlessly: the shaders
# compile, the snow mesh keeps the contract the vertex shader reads, and the scene is overcast
# with Godot's own fog off. What it looks like is checked by eye (tests/_probe_storm_shot.gd).

const FOG := "res://shaders/storm/storm_fog.gdshader"
const SNOW := "res://shaders/storm/storm_snow.gdshader"
const SCENE := "res://scenes/operation_ichi.tscn"

func test_the_storm_shaders_compile() -> void:
	# The fog quad's only own uniform is a depth hint, which the list leaves out; the storm_fog
	# include it runs on is compiled by the crease test below.
	var fog := load(FOG) as Shader
	check(fog != null and fog.code.contains("storm_fog_at"), "storm_fog runs on the shared fog")
	check(shader_uniform_names(SNOW).has("wind_speed"), "storm_snow failed to compile")

func test_the_snow_mesh_keeps_the_vertex_shader_contract() -> void:
	var mesh := Storm.snow_mesh(10, 1)
	var arrays := mesh.surface_get_arrays(0)
	eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 40, "four vertices per flake")
	eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 60, "two triangles per flake")
	eq((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size(), 40, "a seed colour per vertex")
	check(mesh.custom_aabb.size.x > 1000.0, "the quads must never be culled on their own bounds")

func test_the_scene_is_overcast_with_a_storm() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var env: Environment = scene.get_node("WorldEnvironment").environment
	check(not env.fog_enabled, "Godot's single-colour fog is off; the storm quad does the fog")
	check(env.sky.sky_material is ProceduralSkyMaterial, "flat gradient sky, not the cel sky")
	var sun: DirectionalLight3D = scene.get_node("Sun")
	check(sun.light_energy < 0.4, "overcast: the sun is dim")
	check(scene.get_node_or_null("Storm") is Storm, "the scene has its Storm node")
	scene.free()

# Snow shelter: the roof map's decode and the "under a roof" test, on a hand-made 2x1 map whose
# left pixel is a roof at 10 m and whose right pixel is open sky. The real bake needs a renderer,
# so it is checked windowed by tests/_probe_storm_shelter.gd.
func test_the_snow_shader_takes_a_roof_map() -> void:
	var names := shader_uniform_names(SNOW)
	check(names.has("roof_map") and names.has("shelter_on"), "storm_snow lost its shelter uniforms")
	check(shader_uniform_names("res://shaders/storm/storm_roof_bake.gdshader").has("y_span"),
		"storm_roof_bake failed to compile")

func test_a_point_under_a_roof_is_sheltered_and_the_open_is_not() -> void:
	var storm := Storm.new()
	var img := Image.create(2, 1, false, Image.FORMAT_RGBAH)
	# Height 10 m over [0, 20]: h = 0.5, h * 255 = 127.5 -> R = 127 / 255, G = 0.5.
	img.set_pixel(0, 0, Color(127.0 / 255.0, 0.5, 0.0, 1.0))
	img.set_pixel(1, 0, Color(0.0, 0.0, 0.0, 0.0))
	storm.use_roof_map(img, Rect2(0.0, 0.0, 2.0, 1.0), 0.0, 20.0)
	check(absf(storm.roof_height(Vector2(0.5, 0.5)) - 10.0) < 0.01, "decodes the roof at 10 m")
	check(storm.is_sheltered(Vector3(0.5, 2.0, 0.5)), "2 m up, under a 10 m roof: no snow")
	check(not storm.is_sheltered(Vector3(0.5, 9.9, 0.5)), "within the margin of the roof: snow")
	check(not storm.is_sheltered(Vector3(0.5, 12.0, 0.5)), "above the roof: snow")
	check(not storm.is_sheltered(Vector3(1.5, 2.0, 0.5)), "open sky: snow")
	check(not storm.is_sheltered(Vector3(-5.0, 2.0, 0.5)), "off the map: snow")
	storm.free()

func test_the_bake_draws_only_the_static_level() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var meshes := Storm.level_meshes(scene)
	check(not meshes.is_empty(), "OP_1's meshes carry their trimesh collision")
	var pilot: Node = scene.get_node("Pilot9")
	for mi in meshes:
		check(not pilot.is_ancestor_of(mi), "the pilot is not a roof: %s" % mi.name)
		check(scene.get_node("OP_1").is_ancestor_of(mi), "only the map: %s" % mi.name)
	scene.free()

# Blizzard (2026-10-14): the gust whiteout and the ground drift. Both shaders share the gust curve
# through storm_gust.gdshaderinc; what they look like is checked by tests/_probe_storm_shot.gd.
func test_the_fog_closes_in_on_the_gusts() -> void:
	check(shader_uniform_names(SNOW).has("gust_visibility"),
		"the snow fades with the same moving wall as the fog")

func test_the_snow_shader_has_a_drift_mode() -> void:
	var names := shader_uniform_names(SNOW)
	check(names.has("drift") and names.has("drift_height") and names.has("drift_calm"),
		"storm_snow lost its drift uniforms")

func test_the_storm_builds_a_drift_layer() -> void:
	var storm := Storm.new()
	# Builds the layers off-tree; headless skips the roof bake.
	storm._ready()
	var drift := storm.get_node_or_null("Drift") as MeshInstance3D
	check(drift != null, "the storm builds its Drift layer")
	if drift != null:
		var mat := drift.material_override as ShaderMaterial
		check(mat.get_shader_parameter(&"drift") == true, "the drift layer runs in drift mode")
		check(storm.fine_material.get_shader_parameter(&"drift") != true,
			"the falling snow does not")
		eq(mat.get_shader_parameter(&"streak_time"), storm.drift_streak_time,
			"drift keeps its own longer streaks after apply()")
	storm.free()

func test_the_defaults_are_a_blizzard() -> void:
	var storm := Storm.new()
	check(storm.visibility <= 40.0, "40 m between gusts")
	check(storm.gust_visibility < storm.visibility, "the gusts close the wall in")
	check(storm.wind_speed >= 28.0, "28 m/s wind")
	eq(storm.fine_count, 20000, "20k fine flakes")
	eq(storm.near_count, 2400, "2.4k near flakes")
	storm.free()

# The ink passes fog themselves (the hull over sky pixels is out of the fog quad's reach, the
# crease draws after it), off the storm_* globals; outside the storm storm_fog is 0. Storm sets
# and clears them, but the dummy renderer cannot read a global back, so that is checked windowed.
func test_the_ink_passes_still_compile_with_the_storm_fog() -> void:
	check(shader_uniform_names("res://shaders/cel/crease.gdshader").has("fade_end_m"),
		"crease failed to compile with the storm fog include")
	var outline := load("res://shaders/cel/outline.gdshader") as Shader
	check(outline != null and outline.code.contains("storm_fog_ink"), "the hull fogs its ink")
	eq(ProjectSettings.get_setting("shader_globals/storm_fog")["value"], 0.0,
		"storm fog is off by default, so other scenes keep their ink")
