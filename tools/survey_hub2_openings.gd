extends SceneTree

# Finds the openings in each hub2 room's walls (docs/specs/hub2-final-pass.md): walks each wall of a
# room rectangle 1.5 m above its floor, casting outward; gaps in the wall are printed with their
# width, their height (to the lintel) and the floor height beyond.
#   godot --headless --path . --script tools/survey_hub2_openings.gd

const WORLD_SCALE := 0.6
## name, floor y, x0, x1, z0, z1 (a rectangle a little inside the room's walls)
const ROOMS := [
	["Eroom", 43.56, 77.6, 111.6, -65.6, -16.4],
	["C", 30.95, 70.0, 111.8, -135.6, -88.0],
]

var _phys: Node3D
var _ss: PhysicsDirectSpaceState3D
var _frames := 0


func _initialize() -> void:
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * WORLD_SCALE
	_phys.add_child(glb)
	root.add_child(_phys)


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.hit_back_faces = true
	return _ss.intersect_ray(q)


func _physics_process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_ss = _phys.get_world_3d().direct_space_state
	for r: Array in ROOMS:
		var fy: float = r[1]
		var x0: float = r[2]
		var x1: float = r[3]
		var z0: float = r[4]
		var z1: float = r[5]
		print("== %s floor %.2f  x %.1f..%.1f z %.1f..%.1f" % [r[0], fy, x0, x1, z0, z1])
		# side: name, fixed axis value, along range, outward dir
		var sides := [["N(-z)", Vector3(0, 0, -1), z0, x0, x1, true], ["S(+z)", Vector3(0, 0, 1), z1, x0, x1, true],
			["W(-x)", Vector3(-1, 0, 0), x0, z0, z1, false], ["E(+x)", Vector3(1, 0, 0), x1, z0, z1, false]]
		for s: Array in sides:
			var dir: Vector3 = s[1]
			var fixed: float = s[2]
			var a0: float = s[3]
			var a1: float = s[4]
			var along_x: bool = s[5]
			# wall distance: first find how far the wall is at most samples
			var gap_start := NAN
			var t := a0
			var gaps: Array = []
			while t <= a1 + 0.001:
				var p := Vector3(t, fy + 1.5, fixed) if along_x else Vector3(fixed, fy + 1.5, t)
				var hit := _ray(p, p + dir * 6.0)
				var open := hit.is_empty()
				if open and is_nan(gap_start):
					gap_start = t
				elif not open and not is_nan(gap_start):
					gaps.append([gap_start, t - 0.5])
					gap_start = NAN
				t += 0.5
			if not is_nan(gap_start):
				gaps.append([gap_start, a1])
			for g: Array in gaps:
				var mid := (float(g[0]) + float(g[1])) * 0.5
				var p := Vector3(mid, fy + 0.3, fixed) if along_x else Vector3(fixed, fy + 0.3, mid)
				var wall_hit := _ray(p + Vector3.UP * 1.2 + dir * 0.0, p + Vector3.UP * 1.2 + dir * 30.0)
				var up := _ray(p + dir * 2.0, p + dir * 2.0 + Vector3.UP * 200.0)
				var lintel := (up["position"] as Vector3).y - fy if not up.is_empty() else INF
				var beyond := _ray(p + dir * 4.0 + Vector3.UP * 3.0, p + dir * 4.0 + Vector3.DOWN * 60.0)
				var by := (beyond["position"] as Vector3).y if not beyond.is_empty() else NAN
				print("  %s gap %.1f..%.1f (w %.1f)  lintel +%.1f  floor beyond %.2f" % [s[0], g[0], g[1], float(g[1]) - float(g[0]) + 0.5, lintel, by])
	return true
