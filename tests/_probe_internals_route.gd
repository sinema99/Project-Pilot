extends SceneTree

# Probe for the Internals greybox (docs/specs/internals-map.md): walks the plan's route table
# against the built collision. For every route node: ground under it, headroom over it; for every
# pair of nodes at about the same height: nothing solid between them at waist height (a door that
# didn't cut). Also checks the pilot settles on the spawn. Exits 1 on any failure.
#
#   godot --headless --path . --script tests/_probe_internals_route.gd

const SCENE := "res://scenes/internals.tscn"
const PLAN := "res://docs/specs/internals-plan.html"

var _scene: Node
var _frames := 0
var _route: Array = []

func _initialize() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	var html := FileAccess.get_file_as_string(PLAN)
	var start := html.find("const R = [")
	var open := html.find("[", start)
	var body := html.substr(open, html.find("\n];", open) - open + 2)
	body = RegEx.create_from_string(",\\s*\\]").sub(body, "]", true)
	_route = JSON.parse_string(body)

func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 90:
		return false
	var space := (_scene as Node3D).get_world_3d().direct_space_state
	var pilot := _scene.get("pilot") as CharacterBody3D
	var fails := 0
	var exclude := [pilot.get_rid()]
	print("pilot at %s on_floor=%s" % [pilot.global_position, pilot.is_on_floor()])
	if absf(pilot.global_position.y - 45.0) > 0.5:
		print("FAIL pilot did not settle on the spawn")
		fails += 1
	for i in _route.size():
		var r: Array = _route[i]
		var p := Vector3(float(r[0]), float(r[2]), float(r[1]))
		var down := _ray(space, p + Vector3.UP * 1.0, p + Vector3.DOWN * 0.6, exclude)
		if down.is_empty():
			print("FAIL node %d %s: no ground" % [i, p])
			fails += 1
		elif absf(down.position.y - p.y) > 0.3:
			print("WARN node %d %s: ground at %.2f" % [i, p, down.position.y])
		var up := _ray(space, p + Vector3.UP * 0.2, p + Vector3.UP * 2.1, exclude)
		if not up.is_empty():
			print("FAIL node %d %s: ceiling at %.2f" % [i, p, up.position.y])
			fails += 1
		if i > 0:
			var q: Array = _route[i - 1]
			var a := Vector3(float(q[0]), float(q[2]), float(q[1]))
			if absf(a.y - p.y) < 0.6:
				var y := maxf(a.y, p.y) + 1.0
				var hit := _ray(space, Vector3(a.x, y, a.z), Vector3(p.x, y, p.z), exclude)
				if not hit.is_empty() and str(hit.collider.name).begins_with("Gate_"):
					print("ok   %d->%d through one-way %s (opens from its far side)" % [i - 1, i, hit.collider.name])
				elif not hit.is_empty():
					print("FAIL %d->%d blocked at %s by %s" % [i - 1, i, hit.position, hit.collider.name])
					fails += 1
	print("route nodes %d, fails %d" % [_route.size(), fails])
	quit(1 if fails > 0 else 0)
	return true

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)
