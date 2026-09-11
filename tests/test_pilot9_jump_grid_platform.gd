extends "res://tests/test_case.gd"

# Covers the 2026-09-11 jump grid platform - the generated dev ruler in scenes/jump_grid.tscn.
# See docs/specs/pilot9-jump-grid-platform.md.
#
# This file does NOT assert that the sprint lane equals jump_distance(sprint_speed).
# scripts/jump_grid.gd reads that export to build the lane, so the assertion would be a
# tautology that passed forever while the platform rotted - the same dead test
# tests/test_pilot9_jump_grid.gd warns about in its own header. Grid correctness is that
# file's job.
#
# This file's job is that the INSTRUMENT does not lie. Four claims, and three of them are
# silent ones - break any and the platform still looks entirely correct while measuring
# something else:
#
#   - a label matches its geometry, by AABB and never by re-running the formula
#   - pillar chaining is impossible
#   - every pillar has the headroom the mantle needs above its lip
#   - every lane has its runway, level with its landing, attached to the spine
#
# Geometry is read off the COLLISION shapes, not the meshes. The ruler the player measures
# against is the one they stand on, and the grab strips and pillar caps are paint - they
# carry no collider on purpose, and including them would have made every pillar a centimetre
# too tall.
#
# Everything here assumes the platform's boxes are axis-aligned, which _box() in
# scripts/jump_grid.gd guarantees: it never rotates and never scales a node.

const GRID_TSCN := "res://scenes/jump_grid.tscn"
const PILOT_TSCN := "res://scenes/pilot9.tscn"

# Half a centimetre. Every distance below is metres of level geometry, so this is loose
# enough to absorb float error and far tighter than any mistake worth catching.
const TOL := 0.005

var _grid: Node3D = null
var _pilots: Array[Node] = []

# ONE platform, built once and shared. Generating it puts a few hundred meshes and collision
# shapes into the tree, and a --script run never cleans those RIDs up - standing a fresh one
# up per test piles enough of them to segfault the engine on exit. Nothing any test does
# mutates it, so sharing costs nothing. Same reasoning as tests/test_pilot9_climb.gd.
#
# It has to enter the tree: the generator builds in _ready(), and nothing calls that for a
# node with no tree above it.
func _platform() -> Node3D:
	if _grid == null or not is_instance_valid(_grid):
		var ps := load(GRID_TSCN) as PackedScene
		if ps == null:
			return null
		_grid = ps.instantiate() as Node3D
		var loop := Engine.get_main_loop() as SceneTree
		if loop and _grid:
			loop.root.add_child(_grid)
	return _grid

# A pilot of our own, read independently of the generator's. The chaining and headroom tests
# need pilot9's numbers to have something to compare against, and taking them from the thing
# under test is how a tautology gets in.
func _pilot() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var p := ps.instantiate()
	_pilots.append(p)
	return p

func end() -> void:
	for p in _pilots:
		if is_instance_valid(p):
			p.free()
	_pilots.clear()
	super()

# --- reading the built platform -------------------------------------------

# The box a body presents to the player, in the platform's own space.
func _body_box(grid: Node3D, body: StaticBody3D) -> AABB:
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var centre := (grid.global_transform.affine_inverse() * cs.global_transform).origin
		return AABB(centre - box.size * 0.5, box.size)
	return AABB()

func _collect_bodies(node: Node, out: Array[StaticBody3D]) -> void:
	if node is StaticBody3D:
		out.append(node as StaticBody3D)
	for child in node.get_children():
		_collect_bodies(child, out)

func _label_of(node: Node) -> Label3D:
	for child in node.get_children():
		if child is Label3D:
			return child as Label3D
	return null

# The metres a marker CLAIMS, taken from the text a player reads. "4.9 m · MANTLE" -> 4.9.
# NAN when there is no label at all, which every caller reports as its own failure.
func _claimed_metres(node: Node) -> float:
	var label := _label_of(node)
	if label == null:
		return NAN
	var head := label.text.split(" ")[0]
	return head.to_float() if head.is_valid_float() else NAN

# Shortest distance between two axis-aligned boxes on the ground plane. Zero when they
# overlap in both axes.
func _ground_gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return sqrt(dx * dx + dz * dz)

func _group(grid: Node3D, name_: String) -> Node:
	var node := grid.get_node_or_null(name_)
	check(node != null, "the platform generated no `%s` group - it did not build" % name_)
	if node != null:
		check(node.get_child_count() > 0, "`%s` is empty" % name_)
	return node

# --- a label matches its geometry -----------------------------------------

# The failure this catches is a ruler that reads wrong: a lane captioned 7 m that is not 7 m
# across. Measured between the facing lips of the two pads, which is the distance the player
# is actually asked to cover.
func test_every_lane_measures_the_gap_its_label_claims() -> void:
	var grid := _platform()
	check(grid != null, "scenes/jump_grid.tscn did not instantiate")
	if grid == null:
		return
	var lanes := _group(grid, "Lanes")
	if lanes == null:
		return
	for lane in lanes.get_children():
		var claimed := _claimed_metres(lane)
		check(not is_nan(claimed), "lane `%s` carries no readable label" % lane.name)
		if is_nan(claimed):
			continue
		var takeoff := lane.get_node_or_null("Takeoff") as StaticBody3D
		var landing := lane.get_node_or_null("Landing") as StaticBody3D
		check(takeoff != null and landing != null,
			"lane `%s` is missing a pad - there is nothing to measure between" % lane.name)
		if takeoff == null or landing == null:
			continue
		var a := _body_box(grid, takeoff)
		var b := _body_box(grid, landing)
		# The two sides of the spine run in opposite directions, so take the near faces
		# rather than assuming which pad is further along z.
		var gap := maxf(a.position.z, b.position.z) - minf(a.end.z, b.end.z)
		approx(gap, claimed, TOL,
			"lane `%s` says %s m and measures %.3f m - the ruler reads wrong"
				% [lane.name, _label_of(lane).text, gap])

# Same claim, vertically. A pillar's number is the height of its lip above the floor he jumps
# from, which is the slab - not above the pads, and not above his own origin. Getting this
# backwards would put the whole vertical half of the ruler out by a body height.
func test_every_pillar_stands_as_tall_as_its_label_claims() -> void:
	var grid := _platform()
	if grid == null:
		return
	var slab := grid.get_node_or_null("Slab") as StaticBody3D
	check(slab != null, "the platform has no Slab - there is no floor to measure from")
	if slab == null:
		return
	var floor_y := _body_box(grid, slab).end.y
	var pillars := _group(grid, "Pillars")
	if pillars == null:
		return
	for pillar in pillars.get_children():
		var claimed := _claimed_metres(pillar)
		check(not is_nan(claimed), "pillar `%s` carries no readable label" % pillar.name)
		if is_nan(claimed):
			continue
		var body := pillar.get_node_or_null("Body") as StaticBody3D
		check(body != null, "pillar `%s` has no body" % pillar.name)
		if body == null:
			continue
		var box := _body_box(grid, body)
		approx(box.end.y - floor_y, claimed, TOL,
			"pillar `%s` says %s m and its lip stands %.3f m over the slab"
				% [pillar.name, _label_of(pillar).text, box.end.y - floor_y])
		# And it starts on the floor. A pillar hovering over the slab measures the gap under
		# it, not the height printed on it.
		approx(box.position.y, floor_y, TOL,
			"pillar `%s` does not stand on the slab" % pillar.name)

# --- the silent three -----------------------------------------------------

# Chaining a pillar into its neighbour would turn the mantle ceilings into something reached
# from halfway up rather than from the floor, and every number in the field would quietly
# become a lower bound. The bar is a sprint jump plus the forward grab the mantle adds on
# top of it - measured against a pilot read here, not against the generator's own copy.
func test_no_pillar_can_be_chained_into_its_neighbour() -> void:
	var grid := _platform()
	var p := _pilot()
	check(grid != null and p != null, "platform or pilot9 did not instantiate")
	if grid == null or p == null:
		return
	var reach: float = p.jump_distance(p.sprint_speed) + p.climb_probe_reach
	var pillars := _group(grid, "Pillars")
	if pillars == null:
		return

	var bodies: Array[StaticBody3D] = []
	for pillar in pillars.get_children():
		var body := pillar.get_node_or_null("Body") as StaticBody3D
		if body != null:
			bodies.append(body)
	check(bodies.size() > 1, "there is no pillar field to check for chaining")

	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			var sep := _ground_gap(_body_box(grid, bodies[i]), _body_box(grid, bodies[j]))
			check(sep > reach,
				"`%s` and `%s` are %.2f m apart and a sprint jump plus the mantle assist reaches %.2f m - the field can be chained"
					% [bodies[i].get_parent().name, bodies[j].get_parent().name, sep, reach])

# _evaluate_ledge() refuses a lip with anything inside `climb_headroom` above it. Put a box
# over a pillar and the mantle never fires, and the pillar silently measures nothing at all -
# it just becomes a thing he bounces off.
func test_every_pillar_has_the_headroom_the_mantle_needs() -> void:
	var grid := _platform()
	var p := _pilot()
	check(grid != null and p != null, "platform or pilot9 did not instantiate")
	if grid == null or p == null:
		return
	var headroom: float = p.climb_headroom
	var pillars := _group(grid, "Pillars")
	if pillars == null:
		return

	# Everything solid on the platform, so this catches a slab, a pad or a future addition
	# overhanging a lip just as well as a second pillar would.
	var solids: Array[StaticBody3D] = []
	_collect_bodies(grid, solids)
	check(not solids.is_empty(), "the platform generated no collision at all")

	for pillar in pillars.get_children():
		var body := pillar.get_node_or_null("Body") as StaticBody3D
		if body == null:
			continue
		var box := _body_box(grid, body)
		# The column a mantle needs clear: the lip's own footprint, from just above the lip
		# to a full headroom over it.
		var column := AABB(
			Vector3(box.position.x, box.end.y + TOL, box.position.z),
			Vector3(box.size.x, headroom, box.size.z))
		for other in solids:
			if other == body:
				continue
			check(not column.intersects(_body_box(grid, other)),
				"`%s` has %s inside its %.1f m of mantle headroom" % [pillar.name, other.get_path(), headroom])

# A lane whose takeoff pad is missing, detached from the spine, or at a different height from
# its landing is not measuring the jump on its label. None of the three is visible from
# across the platform, and all three leave a lane that looks exactly right.
func test_every_lane_has_its_runway() -> void:
	var grid := _platform()
	if grid == null:
		return
	var spine := grid.get_node_or_null("Spine") as StaticBody3D
	check(spine != null, "the platform has no Spine for the lanes to hang off")
	if spine == null:
		return
	var spine_box := _body_box(grid, spine)
	var lanes := _group(grid, "Lanes")
	if lanes == null:
		return

	for lane in lanes.get_children():
		var takeoff := lane.get_node_or_null("Takeoff") as StaticBody3D
		check(takeoff != null,
			"lane `%s` has no takeoff pad - it measures a standing jump" % lane.name)
		if takeoff == null:
			continue
		var a := _body_box(grid, takeoff)
		check(a.size.z > 0.0, "lane `%s`'s takeoff pad has no depth" % lane.name)
		# Touching the spine, so it can be walked onto. A pad a metre adrift is a pad you
		# have to jump to before you can jump from it.
		approx(_ground_gap(a, spine_box), 0.0, TOL,
			"lane `%s`'s takeoff pad does not reach the spine" % lane.name)

		var landing := lane.get_node_or_null("Landing") as StaticBody3D
		if landing == null:
			continue
		# Level with the landing. A step up or down turns the gap into a different jump than
		# the one the label names, and jump_air_time only holds between equal heights.
		approx(a.end.y, _body_box(grid, landing).end.y, TOL,
			"lane `%s` takes off and lands at different heights" % lane.name)

# --- the surface ----------------------------------------------------------

# The metre lines are half the instrument - "a 6 m pillar is six squares tall from across the
# map, no label required" - and a shader that fails to compile takes them away silently while
# every box stays exactly where it belongs. The spacings are the claim, so they are asserted
# against the spec's 1 m and 5 m rather than against whatever the file happens to say.
func test_the_surface_counts_in_metres() -> void:
	var path := "res://shaders/metre_grid.gdshader"
	var names := shader_uniform_names(path)
	check(names.has("base_color"), "metre_grid.gdshader did not compile, or lost base_color")
	approx(declared_default_float(path, "minor_spacing"), 1.0, 0.0001,
		"the minor grid is no longer 1 m - the surface cannot be counted")
	approx(declared_default_float(path, "major_spacing"), 5.0, 0.0001,
		"the heavy line is no longer every 5 m")
