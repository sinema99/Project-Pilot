@tool
class_name Habitat
extends Node3D

# The habitat: the inside of a space-station cylinder, built from a Syd Mead painting. A control
# cab on a walkway above hydroponic fields, a long concourse, a lake crossed by a rock bridge that
# runs into a brown tower, terraced slopes, and a ribbed white vault overhead. See
# docs/specs/mead-habitat.md.
#
# GENERATED, like pipe_hall.gd and jump_grid.gd: every child is added WITHOUT an `owner`, so none
# of it is serialised into scenes/trial.tscn. The .tscn stores one instanced node and a transform.
# @tool so the editor viewport shows what the game will.
#
# LOCAL SPACE. Y is up, the long axis of the habitat is Z and the painting is seen looking down
# -Z. The ground is y = 0 and the cab walkway is DECK_Y above it, so the node is placed DECK_Y below
# the world floor it joins. The playable zone is x +-100, z -130..135 (colliders); beyond it is
# the backdrop, out to about z = -1100, which is never solid.
#
# The cab vantage (the `CabVantage` marker) is where the painting's composition lines up.
#
# Solid: decks, piers, the cab shell, field beds and soil, terraces, the lake banks and bed, the
# bridge slab, the tower and its flared base, the white tube. Not solid: the water surface (the
# bed is 6.5 m under it), every plant, the vault, every railing and all the backdrop.

const RAIL_SCRIPT := preload("res://scripts/rail.gd")
const ROUTES := preload("res://scripts/habitat_routes.gd")
const CEL_BASE := "res://resources/cel_ground.tres"
const WATER_SHADER := preload("res://shaders/habitat_water.gdshader")

# --- layout --------------------------------------------------------------------
const DECK_Y := 16.0
const WATER_Y := -1.5
const BED_Y := -8.0
const WALK_HALF := 2.2
const CAB_Z0 := 88.0
const CAB_Z1 := 97.0
const WALK_END := 128.0
## The painting's camera: behind the cab on its walkway, eye height above the deck.
const VANTAGE := Vector3(0.0, DECK_Y + 1.7, 114.0)
const TOWER_X0 := 30.0
const TOWER_X1 := 50.0
const TOWER_Z0 := -66.0
const TOWER_Z1 := -50.0
const TOWER_TOP := 156.0
const BRIDGE_TOP := 20.0
const BRIDGE_Z0 := -63.0
const BRIDGE_Z1 := -53.0
const FLARE_R := 26.0
## The vault: a half cylinder along Z, its axis VAULT_DROP under the ground.
const VAULT_R := 260.0
const VAULT_DROP := 100.0
const VAULT_Z0 := 220.0
const VAULT_Z1 := -900.0

# --- palette ---------------------------------------------------------------------
const C_CREAM := Color(0.86, 0.82, 0.73)
const C_CREAM_D := Color(0.66, 0.62, 0.55)
const C_WHITE := Color(0.91, 0.92, 0.90)
const C_SILVER := Color(0.78, 0.82, 0.85)
const C_DARK := Color(0.085, 0.10, 0.095)
const C_GLASS := Color(0.05, 0.07, 0.08)
const C_GREEN_ACC := Color(0.16, 0.72, 0.22)
const C_BROWN := Color(0.36, 0.25, 0.21)
const C_BROWN_L := Color(0.52, 0.40, 0.33)
const C_ROCK := Color(0.17, 0.16, 0.145)
const C_ROCK_L := Color(0.27, 0.25, 0.22)
const C_GRASS := Color(0.22, 0.38, 0.12)
const C_GRASS_D := Color(0.11, 0.24, 0.10)
const C_GRASS_L := Color(0.33, 0.48, 0.17)
const C_SOIL := Color(0.14, 0.12, 0.09)
const C_SAND := Color(0.72, 0.62, 0.45)
const C_CABBAGE_A := Color(0.50, 0.68, 0.42)
const C_CABBAGE_B := Color(0.36, 0.55, 0.32)
const C_BED := Color(0.72, 0.80, 0.70)
const C_CORN_A := Color(0.42, 0.56, 0.17)
const C_CORN_B := Color(0.30, 0.46, 0.14)
const C_TRUNK := Color(0.20, 0.15, 0.10)
const C_CYPRESS := Color(0.06, 0.17, 0.09)
const C_POND := Color(0.14, 0.27, 0.46)

@export_tool_button("Rebuild") var rebuild_action: Callable = _build
## Seeds every scatter: trees, crops, backdrop blocks.
@export var scatter_seed := 11
## Length of the walkway that runs back from the cab to the world floor it joins.
@export var causeway_length := 140.0

var _hull: StaticBody3D
var _vis: Node3D
## The section being built: where a node that is neither solid nor batched goes.
var _sec: Node3D
var _mats: Dictionary = {}
var _inst: Dictionary = {}
var _inst_def: Dictionary = {}
var _rng := RandomNumberGenerator.new()

const GENERATED := ["Hull", "Visual", "Water", "CabVantage", "Ambient"]

## The map's pieces, in build order (the order keeps the scatter seed's results). Each one is a
## real child node of the same name in habitat.tscn: drag it in the editor and its geometry and
## colliders go with it; untick its visibility (then Rebuild is automatic) to remove it. The
## node's origin is the habitat origin until moved.
const SECTIONS := [
	["Ground", &"_ground"],
	["Lake", &"_lake"],
	["WalkwayAndCab", &"_walkway_and_cab"],
	["Fields", &"_fields"],
	["LeftBuilding", &"_left_building"],
	["Concourse", &"_concourse"],
	["LeftTerraces", &"_left_terraces"],
	["Bridge", &"_bridge"],
	["Tower", &"_tower"],
	["Plants", &"_plants"],
	["Details", &"_details"],
	["Backdrop", &"_backdrop"],
	["Vault", &"_vault"],
	["Routes", &"_routes"],
]


func _ready() -> void:
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	_clear()
	_mats.clear()
	_inst.clear()
	_inst_def.clear()
	_rng.seed = scatter_seed

	_plant_defs()
	for sec: Array in SECTIONS:
		var node := _section_node(sec[0])
		_clear_section(node)
		if not node.visible:
			continue
		_hull = StaticBody3D.new()
		_hull.name = "Hull"
		node.add_child(_hull)
		_vis = Node3D.new()
		_vis.name = "Visual"
		node.add_child(_vis)
		_sec = node
		call(sec[1])
		_flush_instances()
	_sec = null
	_ambient()

	var m := Marker3D.new()
	m.name = "CabVantage"
	m.position = VANTAGE
	add_child(m)


## The section's node: the one stored in the scene, or a fresh one (unowned, so it is not saved)
## when the scene does not have it.
func _section_node(nm: String) -> Node3D:
	var n := get_node_or_null(NodePath(nm)) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = nm
		add_child(n)
	if Engine.is_editor_hint() and not n.visibility_changed.is_connected(_on_section_visibility):
		n.visibility_changed.connect(_on_section_visibility)
	return n


func _clear_section(node: Node3D) -> void:
	for nm in ["Hull", "Visual", "Water"]:
		var child := node.get_node_or_null(NodePath(nm))
		if child:
			node.remove_child(child)
			child.queue_free()


func _on_section_visibility() -> void:
	if is_inside_tree():
		_build.call_deferred()


func _clear() -> void:
	for nm in GENERATED:
		var child := get_node_or_null(NodePath(nm))
		if child:
			remove_child(child)
			child.queue_free()


# --- materials -------------------------------------------------------------------

func _cel(col: Color) -> Material:
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	_mats[key] = m
	return m


func _glow(col: Color) -> Material:
	var key := "glow" + col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	_mats[key] = m
	return m


## A lit, outline-free material for one-sided surfaces: the cel shader's outline pass inks a
## single-sided ribbon solid black.
func _plain(col: Color) -> Material:
	var key := "plain" + col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _glass(col: Color, alpha: float) -> Material:
	var key := "glass" + col.to_html() + str(alpha)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


# --- primitives --------------------------------------------------------------------

## One box with a collider of the same transform and size.
func _box(pos: Vector3, size: Vector3, col: Color, collide := true,
		orient := Basis.IDENTITY, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _cel(col)
	mi.transform = Transform3D(orient, pos)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(orient, pos)
		_hull.add_child(cs)


## A box between two x/z corners with a flat top at `top` and its underside at `bottom`.
func _slab(x0: float, x1: float, z0: float, z1: float, top: float, bottom: float, col: Color,
		collide := true) -> void:
	_box(Vector3((x0 + x1) * 0.5, (top + bottom) * 0.5, (z0 + z1) * 0.5),
		Vector3(x1 - x0, top - bottom, z1 - z0), col, collide)


func _cyl(pos: Vector3, radius: float, height: float, col: Color, collide := false,
		orient := Basis.IDENTITY, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _cel(col)
	mi.transform = Transform3D(orient, pos)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		cs.transform = Transform3D(orient, pos)
		_hull.add_child(cs)


## A convex prism stood on the ground plane polygon `poly` (x, z), between y0 and y1.
func _prism(poly: PackedVector2Array, y0: float, y1: float, side_col: Color, top_col: Color,
		collide := true) -> void:
	var c2 := Vector2.ZERO
	for p in poly:
		c2 += p
	c2 /= float(poly.size())
	var top := PackedVector3Array()
	var top_n := PackedVector3Array()
	var sides := PackedVector3Array()
	var side_n := PackedVector3Array()
	var pts := PackedVector3Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for v: Vector3 in [Vector3(c2.x, y1, c2.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y)]:
			top.append(v)
			top_n.append(Vector3.UP)
		var e := b - a
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((a + b) * 0.5 - c2) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0.0, n2.y)
		for v: Vector3 in [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y),
				Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]:
			sides.append(v)
			side_n.append(n)
		pts.append(Vector3(a.x, y0, a.y))
		pts.append(Vector3(a.x, y1, a.y))
	var mesh := ArrayMesh.new()
	var sa := []
	sa.resize(Mesh.ARRAY_MAX)
	sa[Mesh.ARRAY_VERTEX] = sides
	sa[Mesh.ARRAY_NORMAL] = side_n
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sa)
	mesh.surface_set_material(0, _cel(side_col))
	var ta := []
	ta.resize(Mesh.ARRAY_MAX)
	ta[Mesh.ARRAY_VERTEX] = top
	ta[Mesh.ARRAY_NORMAL] = top_n
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
	mesh.surface_set_material(1, _cel(top_col))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_vis.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		sh.points = pts
		cs.shape = sh
		_hull.add_child(cs)


## A polyline `profile` swept along `extrude`, a ribbon. `hint` says which way the surface faces.
func _sweep(profile: PackedVector3Array, extrude: Vector3, col: Color, hint: Vector3,
		collide := true) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var n := (b - a).cross(extrude).normalized()
		if n.dot(hint) < 0.0:
			n = -n
		for v: Vector3 in [a, b, b + extrude, a, b + extrude, a + extrude]:
			verts.append(v)
			norms.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _plain(col))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		_hull.add_child(cs)


## A basis whose +Y runs along `dir`.
static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


# --- batched dressing -----------------------------------------------------------------
# Everything repeated (plants, crops, backdrop blocks) goes through one MultiMesh per mesh and
# colour, and none of it has a collider.

func _def(key: String, mesh: Mesh, col: Color) -> void:
	if not _inst_def.has(key):
		_inst_def[key] = [mesh, col]
		_inst[key] = [] as Array[Transform3D]


func _add(key: String, xf: Transform3D) -> void:
	(_inst[key] as Array[Transform3D]).append(xf)


## A scaled unit box in the instance batch for `col`: dressing that needs no collider.
func _dbox(pos: Vector3, size: Vector3, col: Color, orient := Basis.IDENTITY) -> void:
	var key := "b" + col.to_html()
	if not _inst_def.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		_def(key, bm, col)
	_add(key, Transform3D(orient * Basis.from_scale(size), pos))


func _unit_sphere() -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	return sm


func _unit_cyl() -> Mesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 7
	cm.rings = 1
	return cm


func _unit_cone() -> Mesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 7
	cm.rings = 1
	return cm


func _flush_instances() -> void:
	for key: String in _inst_def:
		var list := _inst[key] as Array[Transform3D]
		if list.is_empty():
			continue
		var def: Array = _inst_def[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = def[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _cel(def[1])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(mmi)
		list.clear()


# --- plants -------------------------------------------------------------------------------

func _plant_defs() -> void:
	_def("trunk", _unit_cyl(), C_TRUNK)
	_def("blob_d", _unit_sphere(), Color(0.09, 0.22, 0.09))
	_def("blob_m", _unit_sphere(), Color(0.16, 0.33, 0.11))
	_def("blob_l", _unit_sphere(), Color(0.26, 0.43, 0.14))
	_def("cypress", _unit_cone(), C_CYPRESS)
	_def("frond", _unit_cone(), Color(0.14, 0.32, 0.12))


## A blockout tree: a trunk and four overlapping flattened blobs, three greens.
func _tree(p: Vector3, s: float) -> void:
	var h := 3.4 * s
	_add("trunk", Transform3D(Basis.from_scale(Vector3(0.28 * s, h, 0.28 * s)), p + Vector3(0, h * 0.5, 0)))
	var keys := ["blob_d", "blob_m", "blob_l"]
	for i in 4:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.0, 1.5) * s
		var blob_pos := p + Vector3(cos(a) * r, h + _rng.randf_range(-0.3, 1.3) * s, sin(a) * r)
		var sc := Vector3(2.3, 1.45, 2.3) * s * _rng.randf_range(0.8, 1.15)
		_add(keys[_rng.randi() % 3], Transform3D(Basis.from_scale(sc), blob_pos))


func _cypress(p: Vector3, s: float) -> void:
	var h := 9.0 * s
	_add("cypress", Transform3D(Basis.from_scale(Vector3(1.3 * s, h, 1.3 * s)), p + Vector3(0, h * 0.5, 0)))


func _palm(p: Vector3, s: float) -> void:
	var h := 7.0 * s
	_add("trunk", Transform3D(Basis.from_scale(Vector3(0.3 * s, h, 0.3 * s)), p + Vector3(0, h * 0.5, 0)))
	for i in 7:
		var a := TAU * float(i) / 7.0
		var dir := Vector3(cos(a), 0, sin(a))
		var shape := _align_y(dir * 0.8 + Vector3(0, -0.45, 0)) * Basis.from_scale(Vector3(0.45 * s, 4.2 * s, 0.12 * s))
		_add("frond", Transform3D(shape, p + Vector3(0, h, 0) + dir * 1.6 * s))


func _shrub(p: Vector3, s: float) -> void:
	var keys := ["blob_d", "blob_m", "blob_l"]
	_add(keys[_rng.randi() % 3], Transform3D(Basis.from_scale(Vector3(1.6, 0.9, 1.6) * s), p + Vector3(0, 0.4 * s, 0)))


# --- ground and lake -------------------------------------------------------------------------

func _ground() -> void:
	# The field floor, the hedge bank in front of the concourse, and the lake's banks.
	_slab(-100, 100, 52, 140, 0.0, -4.0, C_SOIL)
	_slab(-100, 100, 20, 52, 0.0, -4.0, C_GRASS_D)
	_slab(-62, 100, -130, -94, 0.0, -4.0, C_GRASS)
	_slab(-100, -62, -130, 20, 0.0, -4.0, C_GRASS)
	_slab(TOWER_X0, 88, -94, -24, 0.0, -4.0, C_CREAM)
	_slab(88, 100, -94, 20, 0.0, -4.0, C_GRASS)
	# The lake bed, under everything.
	_slab(-100, 100, -130, 20, BED_Y, BED_Y - 4.0, C_ROCK)
	# Bank corners cut diagonally, a peninsula with a sandy point, and the island.
	_prism(PackedVector2Array([Vector2(-62, 20), Vector2(-40, 20), Vector2(-62, 2)]), BED_Y, 0.0, C_GRASS_D, C_GRASS)
	_prism(PackedVector2Array([Vector2(-62, -94), Vector2(-36, -94), Vector2(-62, -72)]), BED_Y, 0.0, C_GRASS_D, C_GRASS)
	_prism(PackedVector2Array([Vector2(10, 20), Vector2(40, 20), Vector2(26, 4)]), BED_Y, 0.0, C_GRASS_D, C_GRASS)
	_prism(PackedVector2Array([Vector2(18, 20), Vector2(32, 20), Vector2(25, 9)]), BED_Y, 0.05, C_SAND, C_SAND)
	var isl := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0
		isl.append(Vector2(-28.0 + cos(a) * (14.0 + 2.5 * sin(a * 2.0)), -8.0 + sin(a) * (8.0 + 1.5 * cos(a * 3.0))))
	_prism(isl, BED_Y, 0.4, C_GRASS_D, C_GRASS)
	# The white ramp from the bank out to the foot of the tower.
	_slab(TOWER_X0, TOWER_X1, -24, 20, 0.0, -1.0, C_WHITE)


func _lake() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(162.0, 114.0)
	water.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var g := _sec.to_global(Vector3(60.0, 0.0, -40.0))
	m.set_shader_parameter("glare_centre", Vector2(g.x, g.z))
	water.material_override = m
	water.position = Vector3(19.0, WATER_Y, -37.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sec.add_child(water)


# --- the cab -----------------------------------------------------------------------------------

func _walkway_and_cab() -> void:
	var len_total := WALK_END + causeway_length - CAB_Z0
	var zc := CAB_Z0 + len_total * 0.5
	# The deck, dark with green edge lines, on a white pier that becomes a bare causeway.
	_box(Vector3(0, DECK_Y - 0.5, zc), Vector3(WALK_HALF * 2.0, 1.0, len_total), C_DARK)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * (WALK_HALF - 0.25), DECK_Y + 0.015, zc), Vector3(0.3, 0.03, len_total),
			C_GREEN_ACC, false, Basis.IDENTITY, false)
	_box(Vector3(0, DECK_Y + 0.015, CAB_Z0 + 0.3), Vector3(WALK_HALF * 2.0, 0.03, 0.4),
		C_GREEN_ACC, false, Basis.IDENTITY, false)
	_slab(-WALK_HALF - 0.6, WALK_HALF + 0.6, CAB_Z0, WALK_END, DECK_Y - 1.0, 0.0, C_WHITE)
	# The pier's white side walls, flaring outward toward the crop rows.
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * (WALK_HALF + 0.25), DECK_Y + 0.2, (CAB_Z1 + WALK_END) * 0.5),
			Vector3(0.5, 0.4, WALK_END - CAB_Z1), C_WHITE)
	# Bare causeway: slim supports every 20 m, no walls.
	var z := WALK_END + 10.0
	while z < WALK_END + causeway_length:
		_box(Vector3(0, (DECK_Y - 1.0) * 0.5, z), Vector3(1.6, DECK_Y - 1.0, 1.6), C_WHITE, false)
		z += 20.0

	# The cab: roof, four pillars, side glass and the consoles.
	var roof_y := DECK_Y + 3.6
	_box(Vector3(0, roof_y + 0.3, (CAB_Z0 + CAB_Z1) * 0.5), Vector3(7.6, 0.8, CAB_Z1 - CAB_Z0 + 1.6), C_WHITE)
	_box(Vector3(0, roof_y + 0.3, CAB_Z0 - 0.9), Vector3(6.8, 0.8, 0.8), C_WHITE, false)
	for sx: float in [-1.0, 1.0]:
		for zz: float in [CAB_Z0 + 0.5, CAB_Z1 - 0.5]:
			_box(Vector3(sx * 3.0, DECK_Y + 1.8, zz), Vector3(0.9, 3.6, 1.0), C_WHITE)
		var glass := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.1, 2.3, CAB_Z1 - CAB_Z0 - 2.0)
		glass.mesh = gm
		glass.material_override = _glass(C_GLASS, 0.45)
		glass.position = Vector3(sx * 3.3, DECK_Y + 2.2, (CAB_Z0 + CAB_Z1) * 0.5)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(glass)
		# A slanted console along the inside of each wall.
		_box(Vector3(sx * 2.5, DECK_Y + 0.9, (CAB_Z0 + CAB_Z1) * 0.5), Vector3(0.9, 0.3, CAB_Z1 - CAB_Z0 - 2.4),
			C_DARK, true, Basis(Vector3.BACK, sx * 0.4))
		_box(Vector3(sx * 2.85, DECK_Y + 0.4, (CAB_Z0 + CAB_Z1) * 0.5), Vector3(0.5, 0.8, CAB_Z1 - CAB_Z0 - 2.4),
			C_SILVER, false)
	# The green leaf emblem on the right front pillar: a green panel with a white leaf in it.
	_box(Vector3(3.0, DECK_Y + 2.3, CAB_Z0 - 0.02), Vector3(0.8, 0.8, 0.06), C_GREEN_ACC, false, Basis.IDENTITY, false)
	_box(Vector3(3.0, DECK_Y + 2.3, CAB_Z0 - 0.06), Vector3(0.3, 0.45, 0.04), C_WHITE, false, Basis.IDENTITY, false)


# --- fields -------------------------------------------------------------------------------------

func _fields() -> void:
	_def("cab_a", _unit_sphere(), C_CABBAGE_A)
	_def("cab_b", _unit_sphere(), C_CABBAGE_B)
	_def("corn_a", BoxMesh.new(), C_CORN_A)
	_def("corn_b", BoxMesh.new(), C_CORN_B)

	# Hydroponic beds: pairs of white slopes tilted toward a dark grated channel, cabbages on top.
	var tilt := deg_to_rad(18.0)
	for i in 6:
		var xc := -92.0 + float(i) * 16.0
		var z_far := 52.0 if xc > -34.0 else 68.0
		var z_near := 136.0
		var zc := (z_far + z_near) * 0.5
		var length := z_near - z_far
		_box(Vector3(xc, 0.6, zc), Vector3(2.0, 0.6, length), C_DARK, false)
		for k in 12:
			_dbox(Vector3(xc, 0.92, z_far + 3.0 + float(k) * (length - 6.0) / 11.0),
				Vector3(1.6, 0.06, 0.25), Color(0.3, 0.32, 0.3))
		for side: float in [-1.0, 1.0]:
			var rot := Basis(Vector3.BACK, side * tilt)
			var centre := Vector3(xc + side * 4.6, 1.75, zc)
			_box(centre, Vector3(7.6, 0.5, length), C_BED, true, rot)
			_box(Vector3(xc + side * 4.6, 0.6, zc), Vector3(7.0, 1.2, length - 0.4), C_CREAM_D, false)
			var row := 0
			var u := 0.7
			while u < 7.0:
				var z_at := z_far + 0.6
				while z_at < z_near - 0.6:
					var jitter := Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12))
					var pos := centre + rot * Vector3(u - 3.8, 0.45, 0.0)
					pos.z = z_at
					pos += jitter
					var key := "cab_a" if (row % 2 == 0) else "cab_b"
					_add(key, Transform3D(rot * Basis.from_scale(Vector3(0.52, 0.3, 0.52)), pos))
					z_at += 1.05
				u += 1.05
				row += 1

	# The corn field on the right of the walkway: a raised soil block and dense stalks.
	_slab(5.0, 100.0, 52.0, 136.0, 0.6, -0.5, C_SOIL)
	var ix := 0
	var x := 6.0
	while x < 99.5:
		var z := 53.0
		while z < 135.5:
			var h := _rng.randf_range(2.3, 3.0)
			var key := "corn_a" if (ix % 2 == 0) else "corn_b"
			var p := Vector3(x + _rng.randf_range(-0.25, 0.25), 0.6 + h * 0.5, z + _rng.randf_range(-0.25, 0.25))
			_add(key, Transform3D(Basis.from_scale(Vector3(0.55, h, 0.55)), p))
			z += 1.0
		x += 1.0
		ix += 1
	# A white retaining wall between the corn and the walkway pier.
	_slab(3.2, 5.0, 88.0, 136.0, 1.6, -0.5, C_WHITE)


# --- the building ---------------------------------------------------------------------------------

func _left_building() -> void:
	# The long white wing on the left: a dark window band, white belts, a rounded end.
	_slab(-100.0, -42.0, 42.0, 66.0, 13.0, 3.0, C_WHITE)
	_cyl(Vector3(-42.0, 8.0, 54.0), 12.0, 10.0, C_WHITE, true)
	_box(Vector3(-71.0, 8.0, 66.06), Vector3(58.0, 4.0, 0.12), C_GLASS, false, Basis.IDENTITY, false)
	_box(Vector3(-71.0, 5.4, 66.08), Vector3(58.0, 0.7, 0.14), C_SILVER, false, Basis.IDENTITY, false)
	_box(Vector3(-71.0, 10.6, 66.08), Vector3(58.0, 0.7, 0.14), C_SILVER, false, Basis.IDENTITY, false)
	# The curve of the end: a dark band wrapped round it.
	_cyl(Vector3(-42.0, 8.0, 54.0), 12.15, 4.0, C_GLASS, false, Basis.IDENTITY, false)
	for x: float in [-94.0, -78.0, -62.0, -48.0]:
		_box(Vector3(x, 1.5, 60.0), Vector3(2.4, 3.0, 3.0), C_WHITE)
	# Under the wing: the shadow of the floor above.
	_box(Vector3(-71.0, 1.5, 54.0), Vector3(58.0, 3.0, 22.0), C_DARK, false)


# --- the concourse ---------------------------------------------------------------------------------

func _concourse() -> void:
	# The long deck that runs across the middle distance, with machinery hung under it.
	_slab(-42.0, 100.0, 38.0, 50.0, 5.0, 4.0, C_CREAM)
	_box(Vector3(29.0, 5.6, 49.75), Vector3(142.0, 1.2, 0.5), C_WHITE, false)
	_box(Vector3(29.0, 5.6, 38.25), Vector3(142.0, 1.2, 0.5), C_WHITE, false)
	for zz: float in [49.8, 38.2]:
		_dbox(Vector3(29.0, 7.3, zz), Vector3(142.0, 0.1, 0.1), C_SILVER)
		var x := -42.0
		while x <= 100.0:
			_dbox(Vector3(x, 6.6, zz), Vector3(0.1, 1.4, 0.1), C_SILVER)
			x += 4.0
	_box(Vector3(29.0, 2.0, 44.0), Vector3(142.0, 4.0, 10.0), C_DARK, false)
	var xs := -42.0
	while xs < 100.0:
		_box(Vector3(xs + 1.0, 2.0, 44.0), Vector3(2.0, 4.0, 2.0), C_WHITE)
		xs += 18.0
	for zp: float in [41.5, 46.5]:
		_cyl(Vector3(29.0, 2.6, zp), 0.8, 142.0, Color(0.30, 0.31, 0.30), false,
			Basis(Vector3.BACK, PI * 0.5), false)
	# A lower service deck on the right, in front of it.
	_slab(0.0, 100.0, 28.0, 34.0, 3.0, 2.0, C_CREAM_D)
	_box(Vector3(50.0, 1.0, 31.0), Vector3(100.0, 2.0, 5.0), C_DARK, false)
	var xl := 4.0
	while xl < 100.0:
		_box(Vector3(xl, 1.0, 31.0), Vector3(1.4, 2.0, 1.4), C_WHITE, false)
		xl += 16.0


# --- terraces ------------------------------------------------------------------------------------------

func _left_terraces() -> void:
	# Stepped cream rakes climbing away to the left, a green strip and cypresses on each.
	var tilt := deg_to_rad(12.0)
	for i in 6:
		var zc := 10.0 - float(i) * 18.0
		var yc := 4.6 + float(i % 3) * 2.2
		var rot := Basis(Vector3.BACK, -tilt)
		var centre := Vector3(-81.0, yc, zc)
		_box(centre, Vector3(40.0, 2.5, 17.2), C_CREAM, true, rot)
		_box(Vector3(-81.0, (yc + BED_Y) * 0.5 - 0.6, zc), Vector3(38.0, yc - BED_Y - 1.2, 16.8), C_CREAM_D, true)
		_box(centre + rot * Vector3(-7.0, 1.4, 0.0), Vector3(22.0, 0.5, 13.0), C_GRASS, false, rot)
		for k in 5:
			var cx := _rng.randf_range(-99.0, -70.0)
			var cz := zc + _rng.randf_range(-6.0, 6.0)
			var cy := yc + (-81.0 - cx) * tan(tilt) + 1.7
			_cypress(Vector3(cx, cy, cz), _rng.randf_range(1.0, 1.5))


# --- the bridge --------------------------------------------------------------------------------------------

func _bridge() -> void:
	# A dark rock slab from the cliff on the left into the face of the tower, ragged on its
	# underside and draped with green.
	var x0 := -100.0
	var x1 := TOWER_X0 + 1.0
	var zc := (BRIDGE_Z0 + BRIDGE_Z1) * 0.5
	var w := BRIDGE_Z1 - BRIDGE_Z0
	_slab(x0 - 12.0, -88.0, -70.0, -46.0, 22.0, BED_Y, C_CREAM)
	_slab(x0 - 12.0, -88.0, -70.0, -46.0, 22.4, 22.0, C_GRASS)
	_slab(x0, x1, BRIDGE_Z0, BRIDGE_Z1, BRIDGE_TOP - 0.4, BRIDGE_TOP - 8.0, C_ROCK)
	_slab(x0, x1, BRIDGE_Z0 - 0.2, BRIDGE_Z1 + 0.2, BRIDGE_TOP, BRIDGE_TOP - 0.4, C_GRASS)
	# Broken underside and cracks.
	var x := x0 + 4.0
	while x < x1 - 4.0:
		var lx := _rng.randf_range(6.0, 16.0)
		var ly := _rng.randf_range(1.0, 3.2)
		_dbox(Vector3(x, BRIDGE_TOP - 8.0 - ly * 0.5, zc + _rng.randf_range(-2.0, 2.0)),
			Vector3(lx, ly, w * _rng.randf_range(0.6, 0.95)), C_ROCK)
		x += lx * 0.9
	for k in 14:
		var ck := _rng.randf_range(x0 + 4.0, x1 - 4.0)
		_dbox(Vector3(ck, BRIDGE_TOP - _rng.randf_range(2.0, 7.0), BRIDGE_Z1 + 0.06),
			Vector3(_rng.randf_range(4.0, 14.0), 0.18, 0.05), C_ROCK_L)
	# Hanging green along the lip of the slab.
	var vx := x0 + 2.0
	while vx < x1 - 2.0:
		var drop := _rng.randf_range(0.8, 3.2)
		_dbox(Vector3(vx, BRIDGE_TOP - 0.4 - drop * 0.5, BRIDGE_Z1 + 0.2),
			Vector3(_rng.randf_range(1.0, 2.6), drop, 0.4), C_GRASS_D)
		_dbox(Vector3(vx + 1.0, BRIDGE_TOP - 0.4 - drop * 0.4, BRIDGE_Z0 - 0.2),
			Vector3(_rng.randf_range(1.0, 2.6), drop * 0.8, 0.4), C_GRASS_D)
		vx += _rng.randf_range(1.6, 3.4)


# --- the tower -----------------------------------------------------------------------------------------------

func _tower() -> void:
	var cx := (TOWER_X0 + TOWER_X1) * 0.5
	var cz := (TOWER_Z0 + TOWER_Z1) * 0.5
	_box(Vector3(cx, (TOWER_TOP - BED_Y) * 0.5 + BED_Y, cz),
		Vector3(TOWER_X1 - TOWER_X0, TOWER_TOP - BED_Y, TOWER_Z1 - TOWER_Z0), C_BROWN)
	# A paler inset panel down the front, and a pale collar where the flare begins.
	_box(Vector3(cx - 2.0, FLARE_R + (TOWER_TOP - FLARE_R) * 0.5, TOWER_Z1 + 0.15),
		Vector3(9.0, TOWER_TOP - FLARE_R, 0.35), C_BROWN_L, false, Basis.IDENTITY, false)

	# The flared base: a quarter-round sweeping out to the front and to the right, the white
	# shell the painting's tower pours into.
	var front := PackedVector3Array()
	var right := PackedVector3Array()
	for i in 13:
		var phi := deg_to_rad(90.0) * float(i) / 12.0
		var z_at := TOWER_Z1 + FLARE_R - FLARE_R * cos(phi)
		var x_at := TOWER_X1 + FLARE_R - FLARE_R * cos(phi)
		var y_at := FLARE_R - FLARE_R * sin(phi)
		front.append(Vector3(TOWER_X0, y_at, z_at))
		right.append(Vector3(x_at, y_at, TOWER_Z0))
	_sweep(front, Vector3(TOWER_X1 - TOWER_X0, 0, 0), C_SILVER, Vector3(0, 1, 1))
	_sweep(right, Vector3(0, 0, TOWER_Z1 - TOWER_Z0), C_SILVER, Vector3(1, 1, 0))

	# A slim, pale waterfall down the tower's left face under the bridge, and a splash.
	var fall := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.3, BRIDGE_TOP - 8.0 - WATER_Y, 5.0)
	fall.mesh = fm
	fall.material_override = _glow(Color(0.86, 0.93, 1.0))
	fall.position = Vector3(TOWER_X0 - 0.15, (BRIDGE_TOP - 8.0 + WATER_Y) * 0.5, cz + 1.0)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(fall)
	_dbox(Vector3(TOWER_X0 - 1.0, WATER_Y + 0.3, cz + 1.0), Vector3(5.0, 0.8, 7.0), Color(0.93, 0.97, 1.0))

	# The pale tube that runs away from the base, toward the right and out of the playable zone.
	var pts := PackedVector3Array([Vector3(44, 22, -58), Vector3(74, 14, -57), Vector3(130, 14, -54),
		Vector3(180, 22, -36), Vector3(240, 36, -1), Vector3(300, 52, 59)])
	var curve := Curve3D.new()
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var tangent := (next - prev) / 6.0
		curve.add_point(pts[i], -tangent, tangent)
	var baked := PackedVector3Array()
	for i in 41:
		baked.append(curve.sample_baked(curve.get_baked_length() * float(i) / 40.0))
	var mesh := RAIL_SCRIPT.tube_mesh(baked, 6.5, 20, false) as ArrayMesh
	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _cel(C_SILVER)
		_vis.add_child(mi)
		for i in baked.size() - 1:
			var a := baked[i]
			var b := baked[i + 1]
			if a.x > 105.0:
				break
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 6.5
			cyl.height = a.distance_to(b)
			cs.shape = cyl
			cs.transform = Transform3D(_align_y(b - a), (a + b) * 0.5)
			_hull.add_child(cs)


# --- plants placed ---------------------------------------------------------------------------------------------------

func _plants() -> void:
	# The hedge line in front of the concourse.
	for i in 48:
		_tree(Vector3(-97.0 + float(i) * 4.05 + _rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(24.0, 36.0)),
			_rng.randf_range(0.9, 1.5))
	# The lone tree on the island, and a small one on the peninsula.
	_tree(Vector3(-28.0, 0.4, -8.0), 2.8)
	_tree(Vector3(24.0, 0.0, 14.0), 1.5)
	# Trees and shrubs along the top of the bridge.
	var x := -92.0
	while x < 36.0:
		_tree(Vector3(x, BRIDGE_TOP, _rng.randf_range(-61.0, -55.0)), _rng.randf_range(1.0, 1.7))
		_shrub(Vector3(x + 3.0, BRIDGE_TOP, _rng.randf_range(-61.0, -55.0)), _rng.randf_range(1.0, 1.8))
		x += _rng.randf_range(6.0, 11.0)
	# The big trees on the right, against the white curve.
	for i in 24:
		_tree(Vector3(_rng.randf_range(70.0, 98.0), 0.0, _rng.randf_range(-92.0, -62.0)), _rng.randf_range(1.8, 3.0))
	for i in 9:
		_tree(Vector3(_rng.randf_range(90.0, 99.0), 0.0, _rng.randf_range(-6.0, 18.0)), _rng.randf_range(2.0, 3.2))
	# The back bank across the lake: a dark green band of trees.
	for i in 30:
		_tree(Vector3(_rng.randf_range(-60.0, 44.0), 0.0, _rng.randf_range(-128.0, -98.0)), _rng.randf_range(1.6, 2.6))
	# Cypress and palm by the building, on the left terraces.
	for i in 14:
		_cypress(Vector3(_rng.randf_range(-98.0, -48.0), 0.0, _rng.randf_range(28.0, 37.0)), _rng.randf_range(1.1, 1.6))
	for p: Vector3 in [Vector3(-66.0, 4.6, 14.0), Vector3(-72.0, 5.8, 6.0), Vector3(-92.0, 7.6, -30.0)]:
		_palm(p, 1.2)
	# Shrubs and saplings among the terraces.
	for i in 40:
		_shrub(Vector3(_rng.randf_range(-99.0, -64.0), 0.0, _rng.randf_range(-88.0, 18.0)), _rng.randf_range(0.8, 1.6))


func _details() -> void:
	# Tall banners by the tower, and the fan of coloured stripes on the plaza.
	var cols := [Color(0.72, 0.12, 0.10), Color(0.92, 0.72, 0.15), Color(0.10, 0.09, 0.09),
		Color(0.85, 0.35, 0.12), Color(0.72, 0.12, 0.10)]
	for i in cols.size():
		_box(Vector3(72.0 + float(i) * 2.4, 9.0, -86.0), Vector3(1.6, 14.0, 0.25), cols[i], false, Basis.IDENTITY, false)
	var fan := [Color(0.85, 0.2, 0.1), Color(0.95, 0.6, 0.12), Color(0.95, 0.88, 0.25),
		Color(0.92, 0.92, 0.88), Color(0.3, 0.6, 0.2), Color(0.85, 0.2, 0.1), Color(0.95, 0.6, 0.12)]
	for i in fan.size():
		var b := Basis(Vector3.UP, deg_to_rad(-30.0 + float(i) * 10.0))
		_box(Vector3(80.0 + float(i) * 0.6, 0.06, -40.0 - float(i) * 0.4), Vector3(14.0, 0.06, 1.3), fan[i], false, b, false)
	# A white dome at the foot of the bridge, half sunk into the bank.
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 9.0
	sm.height = 18.0
	dome.mesh = sm
	dome.material_override = _cel(C_WHITE)
	dome.position = Vector3(30.0, 0.0, -84.0)
	_vis.add_child(dome)


# --- the backdrop ------------------------------------------------------------------------------------------------------

func _backdrop() -> void:
	# Far ground, cream with green patches, well past the playable zone and never solid.
	_box(Vector3(0, -2.0, -678.0), Vector3(500.0, 4.0, 1100.0), C_CREAM_D, false, Basis.IDENTITY, false)
	_box(Vector3(175.0, -2.0, 25.0), Vector3(150.0, 4.0, 230.0), C_GRASS_D, false, Basis.IDENTITY, false)
	_box(Vector3(-175.0, -2.0, 25.0), Vector3(150.0, 4.0, 230.0), C_GRASS_D, false, Basis.IDENTITY, false)
	for i in 70:
		var px := _rng.randf_range(-230.0, 230.0)
		var pz := _rng.randf_range(-100.0, -1000.0)
		_dbox(Vector3(px, 0.08, pz), Vector3(_rng.randf_range(20.0, 70.0), 0.1, _rng.randf_range(20.0, 90.0)),
			C_GRASS if i % 3 != 0 else C_GRASS_L)
	# The green park down the middle, with its pond and a white bridge across it.
	_dbox(Vector3(0, 0.15, -290.0), Vector3(70.0, 0.2, 140.0), C_GRASS_L)
	var pond := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 46.0
	pc.bottom_radius = 46.0
	pc.height = 0.3
	pc.radial_segments = 28
	pond.mesh = pc
	pond.material_override = _glow(C_POND)
	pond.scale = Vector3(1.0, 1.0, 0.55)
	pond.position = Vector3(0, 0.3, -160.0)
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(pond)
	_dbox(Vector3(0, 1.2, -160.0), Vector3(6.0, 0.6, 50.0), C_WHITE)
	for i in 60:
		_tree(Vector3(_rng.randf_range(-32.0, 32.0), 0.1, _rng.randf_range(-225.0, -355.0)), _rng.randf_range(1.6, 2.8))

	# White blocks scattered down the middle distance.
	for i in 90:
		var sx := _rng.randf_range(-70.0, 70.0)
		if absf(sx) < 38.0 and _rng.randf() < 0.75:
			continue
		var h := _rng.randf_range(4.0, 22.0)
		_dbox(Vector3(sx, h * 0.5, _rng.randf_range(-110.0, -800.0)),
			Vector3(_rng.randf_range(10.0, 34.0), h, _rng.randf_range(10.0, 30.0)),
			C_WHITE if i % 2 == 0 else C_CREAM)

	# Terraced hillsides climbing the two sides toward the vault: cream rakes with green strips.
	var slope := 0.22
	var tilt := atan(slope)
	for side: float in [-1.0, 1.0]:
		for col in 4:
			var x_c := side * (75.0 + float(col) * 40.0)
			var z_c := 130.0
			while z_c > -720.0:
				var skip := false
				if col == 0 and z_c > -130.0:
					skip = true
				# Room for the bowl on the right and the dome cluster on the left.
				if side > 0.0 and col >= 1 and col <= 2 and z_c < -75.0 and z_c > -230.0:
					skip = true
				if side < 0.0 and col >= 1 and col <= 2 and z_c < -60.0 and z_c > -160.0:
					skip = true
				if not skip:
					var zj := z_c + _rng.randf_range(-4.0, 4.0)
					var h := maxf(slope * (absf(x_c) - 60.0), 1.0) + _rng.randf_range(-1.5, 2.5)
					var rot := Basis(Vector3.BACK, side * tilt)
					_dbox(Vector3(x_c, h, zj), Vector3(38.0, 2.4, 58.0), C_CREAM, rot)
					_dbox(Vector3(x_c, h * 0.5 - 1.0, zj), Vector3(37.0, h + 1.0, 57.0), C_CREAM_D)
					if _rng.randf() < 0.7:
						_dbox(Vector3(x_c, h + 1.4, zj) + rot * Vector3(side * 6.0, 0.0, 0.0),
							Vector3(20.0, 0.5, 40.0), C_GRASS if _rng.randf() < 0.6 else C_GRASS_L, rot)
				z_c -= 62.0
	# A stadium-like white bowl on the right and a cluster of small domes on the left.
	_bowl(Vector3(155.0, 0.0, -160.0))
	for p: Vector3 in [Vector3(-160.0, 0.0, -118.0), Vector3(-146.0, 0.0, -124.0), Vector3(-172.0, 0.0, -110.0)]:
		_far_dome(p, _rng.randf_range(6.0, 11.0))
	_far_dome(Vector3(-105.0, 0.0, -330.0), 18.0)
	_far_dome(Vector3(120.0, 0.0, -420.0), 24.0)

	# The hub ring at the far end of the cylinder.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 78.0
	tm.outer_radius = 92.0
	tm.rings = 48
	tm.ring_segments = 12
	ring.mesh = tm
	ring.material_override = _cel(C_WHITE)
	ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	ring.position = Vector3(0.0, 100.0, -860.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(ring)
	# Far trees along the sides.
	for i in 160:
		var sx := _rng.randf_range(-200.0, 200.0)
		_tree(Vector3(sx, maxf(0.22 * (absf(sx) - 60.0), 0.0) + 2.0, _rng.randf_range(-100.0, -800.0)),
			_rng.randf_range(2.0, 4.0))


func _bowl(p: Vector3) -> void:
	var rot := Basis(Vector3.BACK, deg_to_rad(10.0))
	_cyl(p + Vector3(0, 9.0, 0), 52.0, 12.0, C_WHITE, false, rot, false)
	_cyl(p + Vector3(0, 15.2, 0), 44.0, 0.6, C_CREAM_D, false, rot, false)
	for i in 4:
		_cyl(p + Vector3(0, 15.6 + float(i) * 0.4, 0), 40.0 - float(i) * 8.0, 0.3, C_WHITE if i % 2 == 0 else C_CREAM,
			false, rot, false)


func _far_dome(p: Vector3, r: float) -> void:
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	dome.mesh = sm
	dome.material_override = _cel(C_WHITE)
	dome.position = p
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(dome)


# --- the vault --------------------------------------------------------------------------------------------------------------

## The inside of a huge half cylinder, white and ribbed. Vertex colours carry the panel pattern;
## it is unshaded (the sun never reaches an underside) and casts no shadow.
func _vault() -> void:
	var cy := -VAULT_DROP
	var t_max := acos((-2.0 - cy) / VAULT_R)
	var bands := 9
	var band_w := 2.0 * t_max / float(bands)
	var seam_a := deg_to_rad(0.45)
	var panel_len := 9.6
	var seam_len := 0.4
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var slate := Color(0.50, 0.53, 0.60)
	var band_cols: Array[Color] = [slate, Color(0.88, 0.86, 0.82), Color(0.94, 0.95, 0.96),
		Color(0.86, 0.88, 0.92), Color(0.96, 0.96, 0.95), Color(0.86, 0.88, 0.92),
		Color(0.94, 0.95, 0.96), Color(0.88, 0.86, 0.82), slate]
	var seam_col := Color(0.50, 0.52, 0.55)
	var z := VAULT_Z0
	while z > VAULT_Z1:
		for seam_z in [false, true]:
			var seg := seam_len if seam_z else panel_len
			var z_b := z - seg
			for b in bands:
				for seam_t in [false, true]:
					var t0 := -t_max + float(b) * band_w
					var t1 := t0 + band_w
					if seam_t:
						t0 = t1 - seam_a
					else:
						t1 = t1 - seam_a
					var haze := clampf((VAULT_Z0 - z) / (VAULT_Z0 - VAULT_Z1), 0.0, 1.0)
					var col := seam_col if (seam_z or seam_t) else band_cols[b]
					var t_mid := (t0 + t1) * 0.5
					col = col * lerpf(0.78, 1.0, cos(t_mid * 0.9))
					col = col.lerp(Color(0.86, 0.92, 1.0), haze * 0.45)
					col.a = 1.0
					var a := Vector3(VAULT_R * sin(t0), cy + VAULT_R * cos(t0), z)
					var bb := Vector3(VAULT_R * sin(t1), cy + VAULT_R * cos(t1), z)
					var c := Vector3(VAULT_R * sin(t1), cy + VAULT_R * cos(t1), z_b)
					var d := Vector3(VAULT_R * sin(t0), cy + VAULT_R * cos(t0), z_b)
					for v: Vector3 in [a, bb, c, a, c, d]:
						verts.append(v)
						colors.append(col)
			z = z_b
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mi)


# --- the routes -------------------------------------------------------------------------------------------------------------
# The traversal layer (docs/specs/habitat-routes.md). scripts/habitat_routes.gd computes the
# records; this builds them. Solid: ledges, pods, decks, vault blocks, bulkheads and the gallery.
# Not solid: every green accent strip, brace, pylon and post, so a jump is never snagged on dressing.
# Rails are Rail nodes, found by the player through the `rails` group like any other.

func _routes() -> void:
	var probe: Object = (load("res://scripts/pilot9.gd") as GDScript).new()
	var lim: Dictionary = ROUTES.limits(probe)
	if probe is Node:
		(probe as Node).free()
	var rt := ROUTES.new()
	rt.build(lim)
	for id: String in rt.pad_ids:
		_route_pad(rt.pads[id])
	for w: Dictionary in rt.walls:
		_route_wall(w)
	for r: Dictionary in rt.rails:
		_route_rail(r)
	for d: Dictionary in rt.dressing:
		if d.kind == "strip":
			_route_strip(d)
	# The beacon on the roof: the climb's end, a pale needle with a green cap.
	_box(Vector3(40.0, ROUTES.ROOF_Y + 3.0, -58.0), Vector3(0.9, 6.0, 0.9), C_WHITE, false)
	_box(Vector3(40.0, ROUTES.ROOF_Y + 6.1, -58.0), Vector3(1.1, 0.4, 1.1), C_GREEN_ACC, false,
		Basis.IDENTITY, false)


## A pad or ledge: a white slab with a green edge line, and on a face a bracket under it.
func _route_pad(p: Dictionary) -> void:
	var c: Vector3 = p.center
	var sz: Vector2 = p.size
	var t: float = p.thick
	var kind: String = p.kind
	var body := C_CREAM if kind == "pod" or kind == "plaza" else C_WHITE
	_box(Vector3(c.x, c.y - t * 0.5, c.z), Vector3(sz.x, t, sz.y), body)
	var edge := 0.22
	var y := c.y + 0.015
	if p.has("toward"):
		# Hung on a wall: the line runs along the outer edge only.
		var toward: Vector3 = p.toward
		var depth: float = p.depth
		var out := -toward
		if absf(toward.x) > 0.5:
			_box(Vector3(c.x + out.x * (sz.x * 0.5 - edge * 0.5), y, c.z), Vector3(edge, 0.03, sz.y),
				C_GREEN_ACC, false, Basis.IDENTITY, false)
		else:
			_box(Vector3(c.x, y, c.z + out.z * (sz.y * 0.5 - edge * 0.5)), Vector3(sz.x, 0.03, edge),
				C_GREEN_ACC, false, Basis.IDENTITY, false)
		# The bracket: a silver block under the ledge, against the wall.
		var bsz := Vector3(sz.x * 0.5, 1.2, sz.y * 0.6) if absf(toward.x) > 0.5 else Vector3(sz.x * 0.6, 1.2, sz.y * 0.5)
		var bc := Vector3(c.x, c.y - t - 0.6, c.z) + toward * depth * 0.2
		_box(bc, bsz, C_SILVER, false, Basis.IDENTITY, false)
		# A ledge that stands off the face hangs from an arm back to it.
		var standoff: float = p.standoff if p.has("standoff") else 0.0
		if standoff > 0.0:
			var arm_len := standoff + depth * 0.5
			var arm_c := Vector3(c.x, c.y - t - 0.3, c.z) + toward * (depth * 0.5 - arm_len * 0.5 + arm_len * 0.5 + 0.0)
			arm_c = Vector3(c.x, c.y - t - 0.3, c.z) + toward * (arm_len * 0.5)
			var arm_sz := Vector3(arm_len, 0.5, minf(sz.y, 1.0) * 0.6) if absf(toward.x) > 0.5 else Vector3(minf(sz.x, 1.0) * 0.6, 0.5, arm_len)
			_box(arm_c, arm_sz, C_SILVER, false, Basis.IDENTITY, false)
	else:
		# Free-standing: the line runs round all four edges.
		_box(Vector3(c.x, y, c.z - sz.y * 0.5 + edge * 0.5), Vector3(sz.x, 0.03, edge), C_GREEN_ACC, false, Basis.IDENTITY, false)
		_box(Vector3(c.x, y, c.z + sz.y * 0.5 - edge * 0.5), Vector3(sz.x, 0.03, edge), C_GREEN_ACC, false, Basis.IDENTITY, false)
		_box(Vector3(c.x - sz.x * 0.5 + edge * 0.5, y, c.z), Vector3(edge, 0.03, sz.y), C_GREEN_ACC, false, Basis.IDENTITY, false)
		_box(Vector3(c.x + sz.x * 0.5 - edge * 0.5, y, c.z), Vector3(edge, 0.03, sz.y), C_GREEN_ACC, false, Basis.IDENTITY, false)
	# Pylons from a deck or pod down to the ground, four, inset from the corners.
	var base: float = p.support_to
	if base > -9000.0 and c.y - t - base > 0.5:
		var h := c.y - t - base
		for sx: float in [-1.0, 1.0]:
			for sz_sign: float in [-1.0, 1.0]:
				_box(Vector3(c.x + sx * (sz.x * 0.5 - 1.0), base + h * 0.5, c.z + sz_sign * (sz.y * 0.5 - 1.0)),
					Vector3(0.7, h, 0.7), C_WHITE, false)


## A vault block, a bulkhead or a piece of the gallery.
func _route_wall(w: Dictionary) -> void:
	var c: Vector3 = w.center
	var sz: Vector3 = w.size
	var kind: String = w.kind
	var col := C_CREAM if kind == "hall" else C_WHITE
	_box(c, sz, col)
	if kind == "vault" or kind == "block":
		# A green line along the top, the length of the wall.
		var along_x := sz.x >= sz.z
		var ssz := Vector3(sz.x, 0.04, 0.14) if along_x else Vector3(0.14, 0.04, sz.z)
		_box(Vector3(c.x, c.y + sz.y * 0.5 + 0.02, c.z), ssz, C_GREEN_ACC, false, Basis.IDENTITY, false)
	elif kind == "bulkhead":
		# The run line: a band down each face at hand height, the length of the wall.
		var by: float = w.band_y if w.has("band_y") else c.y
		var along_x2 := sz.x >= sz.z
		for side: float in [-1.0, 1.0]:
			if along_x2:
				_box(Vector3(c.x, by, c.z + side * (sz.z * 0.5 + 0.02)), Vector3(sz.x, 0.14, 0.05),
					C_GREEN_ACC, false, Basis.IDENTITY, false)
			else:
				_box(Vector3(c.x + side * (sz.x * 0.5 + 0.02), by, c.z), Vector3(0.05, 0.14, sz.z),
					C_GREEN_ACC, false, Basis.IDENTITY, false)
		# A post under it where it hangs over the hedge.
		if w.has("posts"):
			for pz: float in w.posts:
				var bottom := c.y - sz.y * 0.5
				_box(Vector3(c.x, bottom * 0.5, pz), Vector3(0.7, bottom, 0.7), C_WHITE, false)
	elif kind == "hall" and sz.y < 1.0:
		# The gallery roof: a green line along each long edge.
		for side: float in [-1.0, 1.0]:
			_box(Vector3(c.x, c.y + sz.y * 0.5 + 0.02, c.z + side * (sz.z * 0.5 - 0.15)), Vector3(sz.x, 0.04, 0.2),
				C_GREEN_ACC, false, Basis.IDENTITY, false)


## A grind rail on posts. The Rail node builds its own tube from the curve.
func _route_rail(r: Dictionary) -> void:
	var pts: Array = r.pts
	var curve := Curve3D.new()
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var tangent := (next - prev) / 6.0
		curve.add_point(pts[i], -tangent, tangent)
	var rail := RAIL_SCRIPT.new() as Path3D
	rail.name = "Rail" + String(r.id)
	rail.curve = curve
	_vis.add_child(rail)
	var base: float = r.base_y
	if base > -9000.0:
		var length := curve.get_baked_length()
		var off := 4.0
		while off < length - 3.0:
			var pos := curve.sample_baked(off)
			var h := pos.y - 0.12 - base
			if h > 0.5:
				_dbox(Vector3(pos.x, base + h * 0.5, pos.z), Vector3(0.22, h, 0.22), C_SILVER)
			off += 10.0


## A green line along a tower face, down the length of a wall-run.
func _route_strip(d: Dictionary) -> void:
	var a: Vector3 = d.a
	var b: Vector3 = d.b
	var n: Vector3 = d.n
	var mid := (a + b) * 0.5 + n * 0.03
	var len_along := a.distance_to(b)
	var sz := Vector3(0.05, 0.14, len_along) if absf(n.x) > 0.5 else Vector3(len_along, 0.14, 0.05)
	_box(mid, sz, C_GREEN_ACC, false, Basis.IDENTITY, false)


# --- ambient -------------------------------------------------------------------------------------------------------------------

# The scene's sky ambient is a cool blue that greys every white surface in here. A probe over the
# playable zone swaps it for a warm off-white, the way the pipe hall swaps it for a dark blue.
func _ambient() -> void:
	var probe := ReflectionProbe.new()
	probe.name = "Ambient"
	probe.position = Vector3(0, 70.0, 20.0)
	probe.size = Vector3(320.0, 200.0, 360.0)
	probe.interior = true
	probe.box_projection = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.86, 0.86, 0.82)
	probe.ambient_color_energy = 1.0
	probe.intensity = 0.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = 0
	add_child(probe)
