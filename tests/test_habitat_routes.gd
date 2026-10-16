extends "res://tests/test_case.gd"

# Covers the habitat's traversal layer. See docs/specs/habitat-routes.md.
#
# Two halves. The DATA half audits scripts/habitat_routes.gd's records against the player's
# measured limits (jump, double jump, sprint, wall-run grid, vault band, rail catch) - the spec's
# "geometry audit". The BUILD half checks scripts/habitat.gd turned those records into the
# colliders, rails and dressing it should, and that none of it clips the map that was already there.
# The scripted real runs are tests/_probe_routes.gd (they need frames).

const ROUTES := preload("res://scripts/habitat_routes.gd")
const HABITAT_SCENE := preload("res://scenes/habitat.tscn")
const CONTROLLER := preload("res://scripts/pilot9.gd")

var _lim: Dictionary = {}


func _limits() -> Dictionary:
	if _lim.is_empty():
		var body: CharacterBody3D = CONTROLLER.new()
		_lim = ROUTES.limits(body)
		body.free()
	return _lim


func _routes() -> RefCounted:
	var rt := ROUTES.new()
	rt.build(_limits())
	return rt


func _spawn() -> Node3D:
	var h := HABITAT_SCENE.instantiate() as Node3D
	(Engine.get_main_loop() as SceneTree).root.add_child(h)
	return h


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


# --- the data half ------------------------------------------------------------------------------------

func test_the_audit_is_clean() -> void:
	begin("routes: every link keeps inside its share of the player's limits")
	var bad: PackedStringArray = _routes().audit()
	for line in bad:
		fail(line)
	check(true, "audit ran")
	end()


func test_the_limits_are_the_pilots_own() -> void:
	begin("routes: the limits are what pilot9 itself reports")
	var body: CharacterBody3D = CONTROLLER.new()
	var lim := _limits()
	approx(lim.wall_run, body.wall_run_distance(), 0.0001, "the wall-run grid")
	approx(lim.dash, body.dash_distance(), 0.0001, "the dash")
	approx(ROUTES.jump_reach(0.0, lim), body.jump_distance(body.sprint_speed), 0.0001, "a flat sprint jump")
	approx(ROUTES.jump_reach(lim.jump_h, lim), lim.speed * lim.apex, 0.0001, "a jump to the apex arrives at the apex")
	check(ROUTES.jump_reach(lim.jump_h + 0.1, lim) == 0.0, "nothing above the apex is reachable")
	body.free()
	end()


func test_the_tower_constants_match_the_habitat() -> void:
	begin("routes: the mirrored tower numbers are the habitat's")
	var h := _spawn()
	eq(ROUTES.TX0, h.TOWER_X0, "TX0")
	eq(ROUTES.TX1, h.TOWER_X1, "TX1")
	eq(ROUTES.TZ0, h.TOWER_Z0, "TZ0")
	eq(ROUTES.TZ1, h.TOWER_Z1, "TZ1")
	eq(ROUTES.ROOF_Y, h.TOWER_TOP, "the roof")
	eq(ROUTES.BRIDGE_TOP, h.BRIDGE_TOP, "the bridge")
	_drop(h)
	end()


func test_the_stages_tighten_and_the_branches_are_the_hardest() -> void:
	begin("routes: each stage asks for more, and the branches ask for the most")
	var plan: Array = ROUTES.STAGE_PLAN
	for k in range(1, plan.size()):
		check(plan[k].gap > plan[k - 1].gap, "stage %d gap" % (k + 1))
		check(plan[k].rise > plan[k - 1].rise, "stage %d rise" % (k + 1))
		check(plan[k].run > plan[k - 1].run, "stage %d run" % (k + 1))
	check(plan[0].gap <= 0.7 and plan[0].rise <= 0.7, "the first stage is comfortable (70% or under)")
	check(ROUTES.BRANCH_CAP > plan[plan.size() - 1].gap, "the branches are tighter than the last stage")
	end()


func test_there_are_four_stages_with_a_run_in_each() -> void:
	begin("routes: four stages, each with its own wall-run and its rest ledge")
	var rt := _routes()
	eq(rt.rest_ids.size(), 4, "rest ledges")
	var runs := {}
	for l: Dictionary in rt.links:
		if l.mech == "run" and l.branch == "spine":
			var id := String(l.from)
			runs[id.get_slice("_", 0)] = true
	for k in 4:
		check(runs.has("s%d" % k), "stage %d has a wall-run on its spine" % (k + 1))
	end()


func test_six_branches_each_ending_on_a_payoff() -> void:
	begin("routes: six branches, and each ends on a pod or a landing")
	var rt := _routes()
	var seen := {}
	for l: Dictionary in rt.links:
		if String(l.branch).begins_with("B"):
			seen[l.branch] = l.to
	eq(seen.size(), 6, "branches")
	for br: String in seen:
		var to: String = seen[br]
		var ok: bool = (rt.pads.has(to) and rt.pads[to].kind == "pod") or ROUTES.anchors().has(to)
		check(ok, "%s ends on %s, which is neither a pod nor existing ground" % [br, to])
	end()


func test_three_open_areas_with_things_to_play_on() -> void:
	begin("routes: the concourse, the lake and the bridge plaza each carry low blocks")
	var rt := _routes()
	var names := {}
	for a: Dictionary in rt.areas:
		names[a.id] = true
	for id in ["concourse", "plaza", "lake"]:
		check(names.has(id), "open area %s" % id)
	for a: Dictionary in rt.areas:
		if a.id == "summit":
			continue
		var box: AABB = rt.box_of(a.box).grow(3.0)
		var also: Array = a.get("also", [])
		var boxes: Array[AABB] = [box]
		for extra: String in also:
			boxes.append(rt.box_of(extra).grow(3.0))
		var props := 0
		for w: Dictionary in rt.walls:
			if w.kind != "vault" and w.kind != "block":
				continue
			for bx in boxes:
				if bx.has_point(w.center):
					props += 1
					break
		check(props >= 3, "%s has %d low blocks, wanted 3" % [a.id, props])
	end()


func test_the_ledges_stay_on_their_faces() -> void:
	begin("routes: every ring ledge hangs off its own face, stood off by the plan's amount")
	var rt := _routes()
	var n := 0
	var reach: float = ROUTES.STANDOFF + ROUTES.LEDGE_D + ROUTES.BALCONY_LEN
	var near := AABB(Vector3(ROUTES.TX0, -1000.0, ROUTES.TZ0),
		Vector3(ROUTES.TX1 - ROUTES.TX0, 2000.0, ROUTES.TZ1 - ROUTES.TZ0)).grow(reach)
	for id: String in rt.pad_ids:
		var p: Dictionary = rt.pads[id]
		if not p.has("face"):
			continue
		n += 1
		var b := ROUTES.pad_aabb(p)
		check(near.encloses(AABB(Vector3(b.position.x, 0.0, b.position.z), Vector3(b.size.x, 1.0, b.size.z))),
			"%s is within %.1f m of the tower" % [id, reach])
		if not p.has("standoff"):
			continue
		var face: Dictionary = ROUTES.FACES[int(p.face)]
		var out_n: Vector3 = face.n
		var o: Vector3 = face.o
		# How far the pad's inner edge is off the face plane, along the face's normal.
		var inner: float
		if absf(out_n.x) > 0.5:
			inner = (b.position.x - o.x) if out_n.x > 0.0 else (o.x - b.end.x)
		else:
			inner = (b.position.z - o.z) if out_n.z > 0.0 else (o.z - b.end.z)
		var want: float = p.standoff if p.standoff > 0.0 else -0.05
		if p.get("balcony", false):
			want = -0.05
		approx(inner, want, 0.011, "%s's inner edge is %.2f m off its face" % [id, want])
	check(n > 40, "the climb has ledges (%d)" % n)
	end()


# --- the build half -----------------------------------------------------------------------------------

func _routes_hull(h: Node3D) -> Array[Node]:
	var out: Array[Node] = []
	var n := h.get_node_or_null("Routes/Hull")
	if n:
		out.append_array(n.get_children())
	return out


func test_every_pad_and_wall_is_a_collider() -> void:
	begin("routes: the Routes section has a solid box for every pad and every wall")
	var rt := _routes()
	var h := _spawn()
	var boxes: Array[AABB] = []
	for cs in _routes_hull(h):
		var c := cs as CollisionShape3D
		if c and c.shape is BoxShape3D:
			var half := (c.shape as BoxShape3D).size * 0.5
			boxes.append(c.transform * AABB(-half, half * 2.0))
	eq(boxes.size(), rt.pad_ids.size() + rt.walls.size(), "colliders in Routes/Hull")
	for id: String in rt.pad_ids:
		var want := ROUTES.pad_aabb(rt.pads[id])
		var hit := false
		for b in boxes:
			if b.position.distance_to(want.position) < 0.01 and b.size.distance_to(want.size) < 0.01:
				hit = true
				break
		check(hit, "pad %s has its collider" % id)
	_drop(h)
	end()


func test_the_accents_and_dressing_are_never_solid() -> void:
	begin("routes: nothing but pads and walls is solid - no strip, bracket, pylon or post")
	var rt := _routes()
	var h := _spawn()
	var solid := _routes_hull(h).size()
	eq(solid, rt.pad_ids.size() + rt.walls.size(), "solid children")
	var vis := h.get_node_or_null("Routes/Visual")
	check(vis != null and vis.get_child_count() > 100, "the dressing exists")
	_drop(h)
	end()


func test_the_rails_are_in_the_rails_group() -> void:
	begin("routes: three grind rails, found through the `rails` group, curves matching the records")
	var rt := _routes()
	var h := _spawn()
	var found := {}
	for n in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("rails"):
		if h.is_ancestor_of(n):
			found[String(n.name)] = n
	eq(found.size(), rt.rails.size(), "rails in the group")
	for r: Dictionary in rt.rails:
		var node: Path3D = found.get("Rail" + String(r.id))
		check(node != null, "rail %s exists" % r.id)
		if node:
			var pts: Array = r.pts
			eq(node.curve.point_count, pts.size(), "rail %s points" % r.id)
			check(node.curve.get_point_position(0).is_equal_approx(pts[0]), "rail %s starts where the record says" % r.id)
	_drop(h)
	end()


func test_the_section_can_be_hidden() -> void:
	begin("routes: hiding the Routes section removes everything it generated and nothing else")
	var h := _spawn()
	var total_before := 0
	for sec: Array in h.SECTIONS:
		var hull := h.get_node_or_null(NodePath(sec[0] + "/Hull"))
		if hull and sec[0] != "Routes":
			total_before += hull.get_child_count()
	(h.get_node("Routes") as Node3D).visible = false
	h._build()
	check(h.get_node_or_null("Routes/Hull") == null, "no hull under a hidden Routes")
	check(h.get_node_or_null("Routes/Visual") == null, "no visuals under a hidden Routes")
	var total_after := 0
	for sec: Array in h.SECTIONS:
		var hull := h.get_node_or_null(NodePath(sec[0] + "/Hull"))
		if hull and sec[0] != "Routes":
			total_after += hull.get_child_count()
	eq(total_after, total_before, "the other sections' colliders")
	_drop(h)
	end()


func test_a_rebuild_does_not_stack_routes() -> void:
	begin("routes: a rebuild replaces the layer instead of adding a second one")
	var h := _spawn()
	var before := _routes_hull(h).size()
	var rails_before := 0
	for n in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("rails"):
		if h.is_ancestor_of(n):
			rails_before += 1
	h._build()
	eq(_routes_hull(h).size(), before, "colliders after a rebuild")
	await_frame_free()
	_drop(h)
	check(rails_before == 3, "three rails before")
	end()


func await_frame_free() -> void:
	pass


## Box colliders of every section but Routes, as habitat-local AABBs.
func _existing_solids(h: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for sec: Array in h.SECTIONS:
		if sec[0] == "Routes":
			continue
		var n := h.get_node_or_null(NodePath(sec[0] + "/Hull"))
		if n == null:
			continue
		for c in n.get_children():
			var cs := c as CollisionShape3D
			if cs and cs.shape is BoxShape3D:
				var half := (cs.shape as BoxShape3D).size * 0.5
				var xf: Transform3D = h.global_transform.affine_inverse() * cs.global_transform
				out.append(xf * AABB(-half, half * 2.0))
	return out


func test_no_pad_is_roofed_in_by_the_existing_map() -> void:
	begin("routes: nothing that already stood in the habitat sits on a pad's head")
	var rt := _routes()
	var h := _spawn()
	var solids := _existing_solids(h)
	for id: String in rt.pad_ids:
		var p: Dictionary = rt.pads[id]
		var b := ROUTES.pad_aabb(p)
		# The volume a standing body needs: the pad's footprint, inset, from just over its top to 1.8 m.
		var head := AABB(Vector3(b.position.x + 0.2, b.end.y + 0.05, b.position.z + 0.2),
			Vector3(maxf(b.size.x - 0.4, 0.05), 1.75, maxf(b.size.z - 0.4, 0.05)))
		for s in solids:
			if s.intersects(head):
				fail("pad %s: the existing map has a solid on its head: %s" % [id, str(s)])
				break
	check(true, "checked %d pads against %d solids" % [rt.pad_ids.size(), solids.size()])
	_drop(h)
	end()


func test_walls_are_not_buried_in_the_existing_map() -> void:
	begin("routes: a vault block or bulkhead is not swallowed by something already there")
	var rt := _routes()
	var h := _spawn()
	var solids := _existing_solids(h)
	for w: Dictionary in rt.walls:
		var sz: Vector3 = w.size
		var c: Vector3 = w.center
		# A point just over the top of the wall must be clear, or the wall is buried and cannot be vaulted.
		var over := c + Vector3(0, sz.y * 0.5 + 0.1, 0)
		for s in solids:
			if s.has_point(over):
				fail("wall %s: its top is buried inside %s" % [w.id, str(s)])
				break
	check(true, "checked %d walls" % rt.walls.size())
	_drop(h)
	end()
