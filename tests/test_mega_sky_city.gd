extends "res://tests/test_case.gd"

# docs/specs/mega-sky-city.md. The planet city's outline sits over the USA inside the baked crop,
# clear of Florida; the generated platforms, blocks, towers and rails stay inside it, and the
# planet shader carries the City tunables. The descent card lands in the user's band, beyond both
# ridges, unshaded and static. The look is judged by eye
# (tests/_probe_intro_space_shot.gd, tests/_probe_descent_shot.gd).

const CITY_INC := "res://shaders/space/planet_city.gdshaderinc"
const PLANET_SHADER := "res://shaders/space/planet_snow.gdshader"
const DESCENT := "res://scenes/cutscene_descent.tscn"


## CITY_OUTLINE from the include, as Vector2(lon, lat) for Geometry2D.
func _outline() -> PackedVector2Array:
	var text := FileAccess.get_file_as_string(CITY_INC)
	var body := text.substr(text.find("CITY_OUTLINE["), text.find(");", text.find("CITY_OUTLINE[")) - text.find("CITY_OUTLINE["))
	var re := RegEx.create_from_string("vec2\\((-?[0-9.]+), (-?[0-9.]+)\\)")
	var out := PackedVector2Array()
	for m in re.search_all(body):
		out.append(Vector2(float(m.get_string(2)), float(m.get_string(1))))
	return out


func test_outline_is_the_traced_eighteen_points_over_the_usa() -> void:
	var o := _outline()
	eq(o.size(), 18, "outline points")
	for p in o:
		check(p.x > -110.0 and p.x < -78.0 and p.y > 29.0 and p.y < 43.0, "%s is over the USA" % p)
	# Inside the baked crop (8 S-86 N / 180 W-32 W), so the camera sees all of it.
	for p in o:
		check(p.x > -180.0 and p.x < -32.0 and p.y > -8.0 and p.y < 86.0, "%s inside the crop" % p)
	check(Geometry2D.is_point_in_polygon(Vector2(-97.0, 37.0), o), "Kansas is city")
	check(not Geometry2D.is_point_in_polygon(Vector2(-81.7, 27.8), o), "Florida (the storm) is not")


func test_planet_shader_has_the_city() -> void:
	var sh: Shader = load(PLANET_SHADER)
	var names := sh.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u.name)
	for n in ["city_on", "city_color", "city_tile_shade", "city_top_lift", "city_lip_color",
			"city_lip_width", "city_shadow_offset", "city_top_shadow_offset", "city_shadow_tone",
			"city_rail_color", "city_rail_deg", "city_blocks_on", "city_block_deg", "city_street",
			"city_street_lift", "city_boulevard_every", "city_block_shade", "city_empty_edge", "city_core_dark",
			"city_district_shade", "city_tower_color", "city_tower_shadow", "city_tower_shadow_width",
			"city_merge", "city_diagonal_share", "city_roundabout_share", "city_roundabout_blocks",
			"city_plaza_share", "city_open_share", "city_plaza_lift", "outposts_on", "outpost_frame_deg",
			"outpost_girder", "outpost_girder_dark", "outpost_ragged", "outpost_drift_color",
			"outpost_drift_deg", "outpost_drift_cover"]:
		check(names.has(n), "uniform %s" % n)
	check(sh.code.contains("planet_city.gdshaderinc"), "includes the city")


## A generated vec4 array from the include.
func _rects(name: String) -> Array[Vector4]:
	var text := FileAccess.get_file_as_string(CITY_INC)
	var at := text.find("const vec4 %s[" % name)
	var body := text.substr(at, text.find(");", at) - at)
	var re := RegEx.create_from_string("vec4\\((-?[0-9.]+), (-?[0-9.]+), (-?[0-9.]+), (-?[0-9.]+)\\)")
	var out: Array[Vector4] = []
	for m in re.search_all(body):
		out.append(Vector4(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)),
				float(m.get_string(4))))
	return out


func test_planet_city_is_a_cluster_of_platforms_inside_the_outline() -> void:
	var k := cos(deg_to_rad(35.5))
	var grid := PackedVector2Array()
	for p in _outline():
		grid.append(Vector2(p.x * k, p.y))
	var plats := _rects("CITY_PLATFORMS")
	var anchors := plats.filter(func(r: Vector4) -> bool: return maxf(r.z, r.w) * 2.0 >= 2.7)
	check(plats.size() >= 30 and plats.size() <= 46, "30-46 platforms (%d)" % plats.size())
	check(anchors.size() >= 4 and anchors.size() <= 6, "4-6 anchors 300 km+ (%d)" % anchors.size())
	for r in plats:
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = Vector2(r.x, r.y) + c * Vector2(r.z, r.w)
			check(Geometry2D.is_point_in_polygon(p, grid), "%s corner inside the outline" % r)
	var tops := _rects("CITY_TOPS")
	check(tops.size() >= 1, "has raised blocks")
	for t in tops:
		check(plats.any(func(r: Vector4) -> bool:
			return absf(t.x - r.x) + t.z <= r.z + 0.001 and absf(t.y - r.y) + t.w <= r.w + 0.001),
			"block %s sits on a platform" % t)
	var towers := _rects("CITY_TOWERS")
	check(towers.size() >= 6, "has towers (%d)" % towers.size())
	for w in towers:
		check(plats.any(func(r: Vector4) -> bool:
			return absf(w.x - r.x) <= r.z and absf(w.y - r.y) <= r.w), "tower %s stands on a platform" % w)
		check(w.z <= 0.06, "tower %s is tiny" % w)
	var rails := _rects("CITY_RAILS")
	check(rails.size() >= 8 and rails.size() <= 14, "8-14 rails (%d)" % rails.size())
	for s in rails:
		check(is_equal_approx(s.x, s.z) or is_equal_approx(s.y, s.w), "rail %s on the axis" % s)



func test_outposts_scatter_clear_of_the_mega_city_and_the_storm() -> void:
	var k := cos(deg_to_rad(35.5))
	var grid := PackedVector2Array()
	for p in _outline():
		grid.append(Vector2(p.x * k, p.y))
	var plats := _rects("OUTPOST_PLATFORMS")
	var fades := _rects("OUTPOST_FADE")
	check(plats.size() >= 70 and plats.size() <= 100, "70-100 outpost platforms, USA + Mexico + Canada (%d)" % plats.size())
	check(fades.size() == plats.size(), "a fade per outpost platform")
	check(fades.filter(func(f: Vector4) -> bool: return f.x == 0.0 and f.y == 0.0).size() == 11,
			"11 almost-towns (4 USA, 2 Mexico, 5 Canada) fade radially from the core")
	var north := range(plats.size()).filter(func(i: int) -> bool: return plats[i].y > 60.0)
	check(north.size() >= 6, "Canada reaches the far north (%d platforms above 60 N)" % north.size())
	check(fades.any(func(f: Vector4) -> bool: return f.z < 0.0), "some are frame-only")
	var storm := Vector2(-81.7 * k, 27.8)
	for r in plats:
		var overlaps := func(q: Vector4) -> bool:
			return q != r and absf(q.x - r.x) < q.z + r.z and absf(q.y - r.y) < q.w + r.w
		check(not plats.any(overlaps), "%s overlaps nothing" % r)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			var p: Vector2 = Vector2(r.x, r.y) + c * Vector2(r.z, r.w)
			check(not Geometry2D.is_point_in_polygon(p, grid), "%s clear of the mega city" % r)
			check(p.distance_to(storm) >= 9.0, "%s clear of the storm" % r)
	var towers := _rects("OUTPOST_TOWERS")
	check(towers.size() == 11, "one tower per almost-town (%d)" % towers.size())
	for s in _rects("OUTPOST_RAILS"):
		check(is_equal_approx(s.x, s.z) or is_equal_approx(s.y, s.w), "outpost rail %s on the axis" % s)


func _descent() -> DescentShot:
	var s: DescentShot = (load(DESCENT) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func test_descent_card_sits_in_the_users_band_beyond_the_ridges() -> void:
	var s := _descent()
	var city: DescentSkyCity = s.get_node("SkyCity")
	check(city.mesh != null and city.mesh.get_surface_count() == 1, "card is built")
	var verts: PackedVector3Array = city.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(verts.size() > 100, "has platforms and drapes (%d verts)" % verts.size())
	var top := INF
	var right := -INF
	for v in verts:
		var px := DescentShot.to_sketch(v)
		top = minf(top, px.y)
		right = maxf(right, px.x)
		var d := Vector2(v.x, v.z).length()
		check(d > DescentShot.FAR_RANGE_DISTANCE + 3000.0 and d < 23000.0, "beyond the far range (%.0f m)" % d)
	check(top >= DescentShot.HORIZON_PX - 210.0, "nothing above the band (top %.0f px)" % top)
	check(top <= DescentSkyCity.BAND_TOP + city.city_drop + 15.0, "reaches the band's top, dropped (%.0f px)" % top)
	check(right <= DescentSkyCity.END_X + 80.0, "ends about 62%% across (%.0f px)" % right)
	s.free()


func test_descent_card_ignores_lightning_and_never_moves() -> void:
	var sh: Shader = load("res://shaders/cutscene/sky_city.gdshader")
	check(sh.code.contains("unshaded") and sh.code.contains("fog_disabled"), "unshaded, fog-free")
	var s := _descent()
	var city: DescentSkyCity = s.get_node("SkyCity")
	var before := city.global_transform
	var mesh := city.mesh
	s.apply(0.55)
	s.apply(12.69)
	check(city.global_transform.is_equal_approx(before) and city.mesh == mesh, "static")
	s.free()
