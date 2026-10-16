extends "res://tests/test_case.gd"

# docs/specs/descent-trees.md. Three bands of tundra spruce in the descent shot: close lone trees
# (placement, slender, inked, swaying 0-0.4 deg downwind on the shot clock), mid creek ribbons (count,
# distances, no ink, clear of the wrecks' upper two thirds) and far 2-tone clumps. How they look
# is judged by eye (tests/_probe_descent_shot.gd).

const SCENE := "res://scenes/cutscene_descent.tscn"


func _shot() -> DescentShot:
	var s: DescentShot = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _dist(p: Vector3) -> float:
	return Vector2(p.x, p.z).length()


func test_trees_are_generated() -> void:
	var s := _shot()
	for n in ["LoneSpruce0", "MidTrees", "FarClumps"]:
		check(s.trees.has_node(n), "has %s" % n)
		eq(s.trees.get_node(n).owner, null, "%s generated, not saved" % n)
	s.free()


func test_close_trees_sit_left_and_right_with_the_middle_clear() -> void:
	var s := _shot()
	eq(s.trees.lone.size(), 4, "four close trees")
	var left := 0
	var right := 0
	for t in s.trees.lone:
		var d := _dist(t.position)
		check(d >= 60.0 and d <= 200.0, "close: 60-200 m (%.0f)" % d)
		var x := DescentShot.to_sketch(t.position).x
		check(x < 700.0 or x > 1300.0, "middle stays clear (x %.0f)" % x)
		if x >= 100.0 and x <= 400.0:
			left += 1
		elif x >= 1440.0 and x <= 1660.0:
			right += 1
	eq(left, 3, "three on the left")
	eq(right, 1, "one on the right")
	s.free()


func test_close_trees_are_slender_spruce_with_ink_and_snow() -> void:
	var s := _shot()
	for t in s.trees.lone:
		var box := t.mesh.get_aabb()
		check(box.size.y >= 9.0 and box.size.y <= 22.0, "9-21 m tall (%.1f)" % box.size.y)
		var wide := maxf(box.size.x, box.size.z)
		check(wide >= 0.9 and wide <= 8.5, "pencil to bushy (%.1f m across)" % wide)
		eq(t.mesh.get_surface_count(), 2, "green + tier snow")
		var green := t.mesh.surface_get_material(0) as ShaderMaterial
		check(green.next_pass != null, "inked")
		check((green.get_shader_parameter("color") as Color).v < 0.25, "near-black green")
	s.free()


func test_trees_vary_in_size_and_thickness() -> void:
	var s := _shot()
	var heights: Array[float] = []
	for t: Dictionary in s.trees.mid_trees:
		heights.append(t.height)
	heights.sort()
	var n := heights.size()
	check(heights[n - 1] > heights[0] * 3.0, "tallest over 3x the shortest (%.1f / %.1f)" % [heights[n - 1], heights[0]])
	check(heights[int(n * 0.9)] > heights[int(n * 0.1)] * 1.6, "spread through the middle too")
	var ratios: Array[float] = []
	for t in s.trees.lone:
		var box := t.mesh.get_aabb()
		ratios.append(maxf(box.size.x, box.size.z) / box.size.y)
	ratios.sort()
	check(ratios[ratios.size() - 1] > ratios[0] * 1.3, "close trees differ in thickness (%s)" % [ratios])
	s.free()


func test_close_trees_sway_downwind_on_the_shot_clock() -> void:
	var s := _shot()
	var most := 0.0
	for i in 60:
		s.apply(i * 0.2)
		for k in s.trees.lone.size():
			var lean := s.trees.lean_degrees(k)
			check(lean <= 0.4001, "at most 0.4 deg (%.3f)" % lean)
			most = maxf(most, lean)
			var tip := s.trees.lone[k].transform.basis.y
			if lean > 0.05:
				check(Vector3(tip.x, 0.0, tip.z).normalized().dot(s.trees.downwind()) > 0.99, "leans downwind")
	check(most > 0.35, "reaches near 0.4 deg (%.3f)" % most)
	s.apply(7.3)
	var a := s.trees.lone[0].transform
	s.apply(2.0)
	s.apply(7.3)
	check(s.trees.lone[0].transform.is_equal_approx(a), "same time, same pose")
	check(absf(s.trees.lean_degrees(0) - s.trees.lean_degrees(1)) > 1e-4 or absf(s.trees.lean_degrees(1) - s.trees.lean_degrees(2)) > 1e-4,
			"each on its own phase")
	s.free()


func test_mid_ribbons() -> void:
	var s := _shot()
	var n := s.trees.mid_trees.size()
	check(n >= 150 and n <= 250, "150-250 mid trees (%d)" % n)
	var per := {}
	for t: Dictionary in s.trees.mid_trees:
		var d := _dist(t.at)
		check(d >= 280.0 and d <= 1550.0, "mid: 300 m - 1.5 km (%.0f)" % d)
		per[t.ribbon] = int(per.get(t.ribbon, 0)) + 1
	for r in DescentShot.TREE_RIBBONS.size():
		check(int(per.get(r, 0)) >= 8, "ribbon %d has trees (%d)" % [r, per.get(r, 0)])
		var row: Array = DescentShot.TREE_RIBBONS[r]
		var a := DescentShot.sketch_point(Vector2(row[0], DescentShot.HORIZON_PX), row[1])
		var b := DescentShot.sketch_point(Vector2(row[2], DescentShot.HORIZON_PX), row[3])
		var length := Vector2(a.x - b.x, a.z - b.z).length()
		check(length >= 80.0 and length <= 400.0, "ribbon %d 80-400 m long (%.0f)" % [r, length])
	check(int(per.get(-1, 0)) > 0, "a few strays")
	var mid := s.trees.get_node("MidTrees") as MeshInstance3D
	eq((mid.mesh.surface_get_material(0) as ShaderMaterial).next_pass, null, "no ink")
	s.free()


func test_mid_trees_never_hide_a_wreck_above_its_lower_third() -> void:
	var s := _shot()
	for t: Dictionary in s.trees.mid_trees:
		check(not s.trees._hides_a_wreck(t.at, t.height), "tree at %.0f m clear of the wrecks" % _dist(t.at))
	check(s.trees._wreck_boxes.size() == s.land.wrecks.size(), "knows every wreck")
	s.free()


func test_far_clumps_are_two_tone_mounds() -> void:
	var s := _shot()
	check(s.trees.clumps.size() >= 15, "clumps (%d)" % s.trees.clumps.size())
	for c: Dictionary in s.trees.clumps:
		var d := _dist(c.at)
		check(d >= 1400.0 and d <= 5200.0, "far: 1.5-5 km (%.0f)" % d)
	var far := s.trees.get_node("FarClumps") as MeshInstance3D
	var m := far.mesh.surface_get_material(0) as ShaderMaterial
	eq(m.shader.resource_path, "res://shaders/cutscene/tree_clump.gdshader", "2-tone clump shader")
	eq(m.next_pass, null, "no ink")
	s.free()
