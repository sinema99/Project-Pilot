extends "res://tests/test_case.gd"

# The boss arena on the RightWide cap - see docs/specs/boss-arena.md. Headless fences the wiring,
# the cap's floor and its stop-only wall (as shape data: the suite steps no physics), the spawn, the
# kill height, pilot9's probe masks and the land round the arena. How it looks is checked by
# tests/_probe_boss_arena.gd and by playing it.

const SCENE := "res://scenes/boss_arena.tscn"
const WRAPPER := "res://Boss_Arena.tscn"
const PILOT9 := preload("res://scripts/pilot9.gd")

var _scene: BossArena

func end() -> void:
	if is_instance_valid(_scene):
		_scene.free()
	_scene = null
	super()

func _load() -> BossArena:
	_scene = (load(SCENE) as PackedScene).instantiate() as BossArena
	(Engine.get_main_loop() as SceneTree).root.add_child(_scene)
	return _scene

func _tower() -> Dictionary:
	for t: Dictionary in ArrivalShot.TOWERS:
		if t.name == BossArena.TOWER:
			return t
	return {}

func _distance_to_ring(p: Vector2, ring: PackedVector2Array) -> float:
	var best := INF
	for k in ring.size():
		var q := Geometry2D.get_closest_point_to_segment(p, ring[k], ring[(k + 1) % ring.size()])
		best = minf(best, p.distance_to(q))
	return best

func test_the_scene_is_wired() -> void:
	var scene := _load()
	check(scene.pilot != null and scene.pilot.scene_file_path == "res://scenes/pilot9.tscn", "pilot should be pilot9")
	check(scene.world != null and not scene.world.cutscene, "the world is the shot's, cutscene off")
	check(scene.get_node_or_null("EXIA") == null, "pilot9 only, no mech")
	check(scene.world.get_node_or_null("Spire") == null, "the spire is in the backdrop, not 3D")
	check(scene.world.get_node_or_null("Camera3D") == null, "no cutscene camera")
	check(scene.world.base.get_node_or_null("OutpostDeck") == null, "the outpost is in the backdrop, not 3D")
	check(scene.world.base.get_node_or_null(BossArena.TOWER) != null, "the arena tower is built")
	check(scene.get_node_or_null("RetroLook") != null and scene.get_node_or_null("PixelLook") != null,
		"the gameplay look rigs come along")
	check(load(WRAPPER) is PackedScene, "Boss_Arena.tscn wrapper is missing")

func test_the_backdrop_is_the_baked_sky() -> void:
	var scene := _load()
	var env_node := scene.get_node("WorldEnvironment") as WorldEnvironment
	var env := env_node.environment
	var sky := env.sky.sky_material as ShaderMaterial
	check(sky != null and sky.shader.resource_path == "res://shaders/boss_arena_backdrop.gdshader", "sky should be the backdrop")
	for face in ["px", "nx", "py", "ny", "pz", "nz"]:
		var tex := sky.get_shader_parameter("face_" + face) as Texture2D
		check(tex != null and tex.resource_path == "res://assets/boss_arena/backdrop_%s.png" % face,
			"face %s should be the baked image" % face)
	check(env_node.compositor == null, "no cinema post in the arena")

func test_the_cap_is_the_shots_righwide_cap() -> void:
	var scene := _load()
	var t := _tower()
	var top := scene.world.at_distance(t.u, t.v, t.distance)
	approx(Vector2(scene.centre.x, scene.centre.z).distance_to(Vector2(top.x, top.z)), 0.0, 0.01, "centre on the cap")
	approx(scene.centre.y, top.y, 0.01, "a pad cap's top is the tower top")
	# True scale (decision 2): the rim reaches the full 160 m radius where it is not bitten.
	var reach := 0.0
	for p in scene.rim:
		reach = maxf(reach, p.distance_to(Vector2(top.x, top.z)))
	approx(reach, float(t.cap), 1.0, "the cap keeps the shot's 160 m radius")

func test_the_floor_is_one_flat_polygon_on_the_bitten_rim() -> void:
	var scene := _load()
	var shape := scene.map.get_node("Floor").get_child(0) as CollisionPolygon3D
	eq(shape.polygon, scene.rim, "the floor follows the bitten rim")
	# Local z (depth) runs down from the top face: top = origin.y + depth / 2.
	approx(shape.global_position.y + shape.depth * 0.5, scene.centre.y, 0.01, "the floor's top is the cap's top")
	approx(shape.global_basis.z.dot(Vector3.DOWN), 1.0, 0.001, "the depth runs straight down")

func test_nothing_grows_through_the_floor() -> void:
	var scene := _load()
	var mm := (scene.world.get_node("Growth/Scrub") as MultiMeshInstance3D).multimesh
	var on_floor := 0
	for i in mm.instance_count:
		var at := mm.get_instance_transform(i).origin
		if absf(at.y - scene.centre.y) < 5.0 and Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), scene.rim):
			on_floor += 1
	eq(on_floor, 0, "no scrub on the arena's floor")
	check(mm.instance_count > 1000, "the rest of the base keeps its scrub (%d)" % mm.instance_count)

func test_the_cutscene_keeps_its_scrub_and_its_clear_day() -> void:
	var shot := (load("res://scenes/cutscene_arrival.tscn") as PackedScene).instantiate()
	eq((shot.get_node("Growth") as ArrivalGrowth).bare_caps.size(), 0, "every cap grows in the shot")
	approx((shot.get_node("Land") as ArrivalLand).range_lift, 1.0, 0.0001, "the shot's ranges are not lifted")
	approx((shot.get_node("Spire") as ArrivalSpire).taper_height, 0.0, 0.0001, "the shot's spire keeps its taper")
	approx((shot.get_node("Sun") as DirectionalLight3D).light_energy, 0.85, 0.0001, "the shot's sun is unchanged")
	eq((shot.get_node("Land") as ArrivalLand).snow_color, Color(0.82, 0.85, 0.9), "the shot's snow is unchanged")
	shot.free()

func test_the_surface_is_visual_and_covers_the_rim() -> void:
	var scene := _load()
	var surface := scene.map.get_node("Surface") as MeshInstance3D
	check(surface != null, "the floor has its painted surface")
	var mat := surface.material_override as ShaderMaterial
	check(PixelLook.is_cel(mat), "on the cel shader, so every look takes it")
	check(mat.get_shader_parameter("base_texture") != null, "it carries the painted floor")
	eq(surface.get_child_count(), 0, "visual only: no body under it")
	var box := surface.get_aabb()
	approx(box.position.y, scene.centre.y + BossArena.FLOOR_LIFT, 0.001, "just over the cap's snow")
	approx(box.size.y, 0.0, 0.001, "flat")
	var arrays := surface.mesh.surface_get_arrays(0)
	for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
		check(uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0, "the rim stays inside the image")

func test_the_arena_is_overcast() -> void:
	var scene := _load()
	approx(scene.sun.light_energy, BossArena.OVERCAST.sun_energy, 0.0001, "the dim sun")
	eq(scene.environment.environment.ambient_light_color, BossArena.OVERCAST.ambient, "the cold ambient")
	eq(scene.world.land.snow_color, BossArena.OVERCAST.snow, "the land's snow in the same light")
	eq(scene.world.clouds.lit_color, BossArena.OVERCAST.cloud_lit, "the clouds in the same light")

func test_the_range_lift_only_raises_what_stands_over_it() -> void:
	var scene := _load()
	var land := scene.world.land
	var peak := Vector2.ZERO
	var best := -INF
	for k in 720:
		var p := Vector2.from_angle(TAU * k / 720.0) * 30000.0
		if land.ranges_at(p.x, p.y) > best:
			best = land.ranges_at(p.x, p.y)
			peak = p
	check(best > land.range_lift_from, "a far crest stands over the lift line (%.0f m)" % best)
	land.range_lift = 2.0
	approx(land.ranges_at(peak.x, peak.y) - land.range_lift_from, (best - land.range_lift_from) * 2.0, 0.01,
		"twice as tall over the line")
	var low := Vector2(0.0, -6000.0)
	land.range_lift = 1.0
	var valley: float = minf(land.ranges_at(low.x, low.y), land.range_lift_from)
	land.range_lift = 2.0
	check(land.ranges_at(low.x, low.y) >= valley, "nothing drops")
	land.range_lift = 1.0

func test_the_wall_stands_inside_the_bitten_rim() -> void:
	var scene := _load()
	check(scene.wall_line.size() >= 8, "a wall line")
	for p in scene.wall_line:
		check(Geometry2D.is_point_in_polygon(p, scene.rim), "wall point outside the rim")
		check(_distance_to_ring(p, scene.rim) >= scene.wall_inset - 0.1, "wall point closer than wall_inset to the edge")

func test_the_wall_is_stop_only_and_tall() -> void:
	var scene := _load()
	var body := scene.map.get_node("Wall") as StaticBody3D
	eq(body.collision_layer, BossArena.STOP_ONLY_LAYER, "the wall is only on the stop-only layer")
	eq(body.collision_mask, 0, "the wall looks for nothing")
	eq(BossArena.STOP_ONLY_LAYER, PILOT9.STOP_ONLY_LAYER, "arena and pilot agree on the layer")
	var boxes := body.get_children()
	check(boxes.size() >= scene.wall_line.size() - 1, "a box per wall edge")
	for c: CollisionShape3D in boxes:
		var box := c.shape as BoxShape3D
		check(box.size.y >= 60.0, "the wall is at least 60 m tall")
		check(c.global_position.y - box.size.y * 0.5 <= scene.centre.y, "the wall starts at or under the floor")
		# The box's inner face sits on the wall line: its centre is half a thickness outside it.
		var mid := Vector2(c.global_position.x, c.global_position.z)
		approx(_distance_to_ring(mid, scene.wall_line), box.size.z * 0.5, 0.05, "the box's inner face is on the line")
		check(not Geometry2D.is_point_in_polygon(mid, scene.wall_line), "the box stands outside the line")

func test_pilot9_collides_with_the_wall_but_his_probes_do_not() -> void:
	var scene := _load()
	check(scene.pilot.collision_mask & PILOT9.STOP_ONLY_LAYER != 0, "his body stops at the wall")
	check(PILOT9.PROBE_MASK & PILOT9.STOP_ONLY_LAYER == 0, "wall-run / climb / mantle / vault rays skip it")
	check(PILOT9.PROBE_MASK & 1 != 0, "his probes still see the ordinary world")
	var arm := scene.pilot.find_child("SpringArm3D", true, false) as SpringArm3D
	check(arm != null and arm.collision_mask & PILOT9.STOP_ONLY_LAYER == 0, "the camera ignores the wall")

func test_pilot9_probes_all_use_the_mask() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/pilot9.gd")
	var rays := src.count("PhysicsRayQueryParameters3D.create(")
	var shapes := src.count("intersect_shape(")
	var masked := src.count(".collision_mask = PROBE_MASK")
	eq(masked, rays + shapes, "every movement ray and shape test in pilot9.gd sets PROBE_MASK")

func test_he_starts_at_the_spawn_facing_the_spire() -> void:
	var scene := _load()
	var spawn := scene.map.get_node("spawn") as Node3D
	var at := Vector2(spawn.global_position.x, spawn.global_position.z)
	approx(spawn.global_position.y, scene.centre.y, 0.01, "the spawn is on the floor")
	check(Geometry2D.is_point_in_polygon(at, scene.wall_line), "the spawn is inside the wall")
	approx(_distance_to_ring(at, scene.wall_line), scene.spawn_in, 1.5, "spawn_in from the nearest wall")
	# On the side facing the shot's camera (at the world origin).
	var c := Vector2(scene.centre.x, scene.centre.z)
	check((at - c).normalized().dot(-c.normalized()) > 0.99, "the spawn is on the camera side")
	var spire := scene.world.at_distance(ArrivalShot.SPIRE.u, ArrivalShot.SPIRE.v, ArrivalShot.SPIRE.distance)
	var look := (Vector2(spire.x, spire.z) - at).normalized()
	var f := -spawn.global_basis.z
	check(Vector2(f.x, f.z).normalized().dot(look) > 0.999, "he looks at the spire")
	approx(scene.pilot.global_position.distance_to(spawn.global_position + Vector3.UP * scene.spawn_lift), 0.0, 0.01,
		"he is put on the spawn at load")

func test_falling_off_respawns_on_the_cap() -> void:
	var scene := _load()
	approx(scene.kill_height, scene.centre.y - 30.0, 0.01, "kill height 30 m under the cap")
	scene.pilot.global_position = scene.centre + Vector3(0, -40, 0)
	scene._physics_process(0.016)
	var spawn := scene.map.get_node("spawn") as Node3D
	approx(scene.pilot.global_position.distance_to(spawn.global_position + Vector3.UP * scene.spawn_lift), 0.0, 0.01,
		"below the kill height he is back on the spawn")

func test_the_boss_anchor_marks_the_centre() -> void:
	var scene := _load()
	var anchor := scene.map.get_node_or_null("BossAnchor") as Node3D
	check(anchor != null, "BossAnchor exists")
	approx(anchor.global_position.distance_to(scene.centre), 0.0, 0.01, "BossAnchor at the cap centre")
	eq(anchor.get_child_count(), 0, "the anchor is an empty marker")

func test_the_land_is_a_full_circle_round_the_arena() -> void:
	var scene := _load()
	var land := scene.world.land
	var c := Vector2(scene.centre.x, scene.centre.z)
	approx(land.view_centre.distance_to(c), 0.0, 0.01, "the land is centred on the arena")
	var bearings := {}
	var farthest := 0.0
	for v in land.vertices:
		var d := Vector2(v.x, v.z) - c
		farthest = maxf(farthest, d.length())
		bearings[int(floor(fposmod(atan2(d.y, d.x), TAU) / (TAU / 8.0)))] = true
	eq(bearings.size(), 8, "land in every direction round the arena")
	check(farthest <= land.far * 1.02, "no land past its far ring (the backdrop takes over)")

func test_only_the_cloud_sea_stays_and_it_is_under_the_arena() -> void:
	var scene := _load()
	for card in scene.world.clouds.get_children():
		var mi := card as MeshInstance3D
		if mi == null:
			continue
		if mi.name == &"Sea":
			check(mi.visible, "the sea stays")
			approx(Vector2(mi.position.x, mi.position.z).distance_to(Vector2(scene.centre.x, scene.centre.z)), 0.0, 0.01,
				"the sea is centred under the arena")
		else:
			check(not mi.visible, "%s is a shot-camera card: hidden" % mi.name)

func test_snow_falls_round_him() -> void:
	var scene := _load()
	var snow := scene.get_node_or_null("Snow") as GPUParticles3D
	check(snow != null and not snow.local_coords, "world-space snowfall")
	scene._process(0.016)
	approx(Vector2(snow.global_position.x, snow.global_position.z).distance_to(
		Vector2(scene.pilot.global_position.x, scene.pilot.global_position.z)), 0.0, 0.01, "the snow box rides with him")
