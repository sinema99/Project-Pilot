@tool
class_name HabitatPart
extends Habitat

# One building block of the habitat, stood alone at its own origin. Reuses every primitive and
# every colour of habitat.gd (this class extends it) so a part looks exactly like the same piece
# in the map. See docs/specs/habitat-parts.md.
#
# GENERATED like the habitat: the geometry is built in _ready() with no owner, so a scene that
# holds a part stores one node and a transform. Drop a part scene from scenes/habitat_parts/ into
# a level, or change `kind` on a placed one to swap it for another piece.
#
# Every part stands on the floor (y = 0) at the same height it has in the habitat, so pieces that
# met in the map meet here: the walkway deck is 16 m up, the bridge 12..20, the concourse 5. The
# origin is the middle of the footprint (the tower and tube bend are the exceptions, see `off`).

## The piece. The list is PARTS below.
@export var kind := "tree":
	set(v):
		kind = v
		if is_inside_tree():
			_build()
## Tower only: how tall the column is. The habitat's own is 164 m.
@export_range(40.0, 170.0, 1.0) var tower_height := 70.0:
	set(v):
		tower_height = v
		if is_inside_tree() and kind == "tower":
			_build()

const CAT_WALK := "Walkway and cab"
const CAT_BUILD := "Buildings"
const CAT_BIG := "Bridge, tower and tube"
const CAT_FARM := "Fields"
const CAT_LAND := "Ground and water"
const CAT_PLANT := "Plants"
const CAT_DETAIL := "Details"
const CAT_FAR := "Backdrop (far scenery)"

const CATEGORIES := [CAT_WALK, CAT_BUILD, CAT_BIG, CAT_FARM, CAT_LAND, CAT_PLANT, CAT_DETAIL, CAT_FAR]

# name, category, footprint width (x), footprint depth (z), offset of the footprint's centre from
# the origin (x, z), solid (has colliders), builder method.
const PARTS := [
	["walkway_pier", CAT_WALK, 6.0, 20.0, 0.0, 0.0, true, &"_p_walkway_pier"],
	["walkway_causeway", CAT_WALK, 5.0, 20.0, 0.0, 0.0, true, &"_p_walkway_causeway"],
	["control_cab", CAT_WALK, 8.0, 12.0, 0.0, 0.0, true, &"_p_control_cab"],

	["wing_building", CAT_BUILD, 36.0, 24.0, 0.0, 0.0, true, &"_p_wing_building"],
	["concourse_deck", CAT_BUILD, 40.0, 12.0, 0.0, 0.0, true, &"_p_concourse_deck"],
	["service_deck", CAT_BUILD, 32.0, 6.0, 0.0, 0.0, true, &"_p_service_deck"],
	["white_dome", CAT_BUILD, 18.0, 18.0, 0.0, 0.0, true, &"_p_white_dome"],
	["cliff_block", CAT_BUILD, 24.0, 24.0, 0.0, 0.0, true, &"_p_cliff_block"],
	["retaining_wall", CAT_BUILD, 2.0, 20.0, 0.0, 0.0, true, &"_p_retaining_wall"],

	["rock_bridge", CAT_BIG, 40.0, 11.0, 0.0, 0.0, true, &"_p_rock_bridge"],
	["tower", CAT_BIG, 46.0, 42.0, 13.0, 13.0, true, &"_p_tower"],
	["waterfall", CAT_BIG, 8.0, 8.0, 0.0, 0.0, true, &"_p_waterfall"],
	["tube_straight", CAT_BIG, 40.0, 13.0, 0.0, 0.0, true, &"_p_tube_straight"],
	["tube_bend", CAT_BIG, 47.0, 53.0, 23.0, 20.0, true, &"_p_tube_bend"],

	["hydro_bed", CAT_FARM, 17.0, 20.0, 0.0, 0.0, true, &"_p_hydro_bed"],
	["corn_field", CAT_FARM, 20.0, 20.0, 0.0, 0.0, true, &"_p_corn_field"],

	["terrace", CAT_LAND, 40.0, 17.0, 0.0, 0.0, true, &"_p_terrace"],
	["ground_soil", CAT_LAND, 20.0, 20.0, 0.0, 0.0, true, &"_p_ground_soil"],
	["ground_grass", CAT_LAND, 20.0, 20.0, 0.0, 0.0, true, &"_p_ground_grass"],
	["ground_grass_dark", CAT_LAND, 20.0, 20.0, 0.0, 0.0, true, &"_p_ground_grass_dark"],
	["ground_plaza", CAT_LAND, 20.0, 20.0, 0.0, 0.0, true, &"_p_ground_plaza"],
	["ground_white", CAT_LAND, 20.0, 20.0, 0.0, 0.0, true, &"_p_ground_white"],
	["bank_corner", CAT_LAND, 20.0, 20.0, 0.0, 0.0, true, &"_p_bank_corner"],
	["island", CAT_LAND, 34.0, 20.0, 0.0, 0.0, true, &"_p_island"],
	["peninsula", CAT_LAND, 30.0, 16.0, 0.0, 0.0, true, &"_p_peninsula"],
	["water_tile", CAT_LAND, 24.0, 24.0, 0.0, 0.0, true, &"_p_water_tile"],

	["tree", CAT_PLANT, 8.0, 8.0, 0.0, 0.0, false, &"_p_tree"],
	["cypress", CAT_PLANT, 4.0, 4.0, 0.0, 0.0, false, &"_p_cypress"],
	["palm", CAT_PLANT, 10.0, 10.0, 0.0, 0.0, false, &"_p_palm"],
	["shrub", CAT_PLANT, 4.0, 4.0, 0.0, 0.0, false, &"_p_shrub"],
	["hedge_row", CAT_PLANT, 22.0, 8.0, 0.0, 0.0, false, &"_p_hedge_row"],
	["cypress_row", CAT_PLANT, 22.0, 4.0, 0.0, 0.0, false, &"_p_cypress_row"],
	["tree_grove", CAT_PLANT, 26.0, 26.0, 0.0, 0.0, false, &"_p_tree_grove"],

	["banners", CAT_DETAIL, 12.0, 2.0, 0.0, 0.0, false, &"_p_banners"],
	["stripe_fan", CAT_DETAIL, 16.0, 10.0, 0.0, 0.0, false, &"_p_stripe_fan"],

	["bowl", CAT_FAR, 105.0, 105.0, 0.0, 0.0, false, &"_p_bowl"],
	["far_dome", CAT_FAR, 24.0, 24.0, 0.0, 0.0, false, &"_p_far_dome"],
	["dome_cluster", CAT_FAR, 40.0, 30.0, 0.0, 0.0, false, &"_p_dome_cluster"],
	["hillside_terrace", CAT_FAR, 38.0, 58.0, 0.0, 0.0, false, &"_p_hillside_terrace"],
	["block_cluster", CAT_FAR, 50.0, 50.0, 0.0, 0.0, false, &"_p_block_cluster"],
]


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Array in PARTS:
		out.append(p[0])
	return out


static func entry_for(part_name: String) -> Array:
	for p: Array in PARTS:
		if p[0] == part_name:
			return p
	return []


## Where the library puts every part. Rows by category, wrapped at `row_width`. Returns
## {pos: {name: Vector3 origin}, heads: [[text, Vector3]], rect: Rect2 of everything placed}.
static func layout(row_width := 300.0, gap := 14.0, row_gap := 34.0) -> Dictionary:
	var pos := {}
	var heads := []
	var z := 0.0
	var max_x := 0.0
	for cat: String in CATEGORIES:
		heads.append([cat, Vector3(0.0, 30.0, z)])
		z += 26.0
		var x := 0.0
		var row_depth := 0.0
		for p: Array in PARTS:
			if p[1] != cat:
				continue
			var w: float = p[2]
			var d: float = p[3]
			if x > 0.0 and x + w > row_width:
				z += row_depth + row_gap
				x = 0.0
				row_depth = 0.0
			pos[p[0]] = Vector3(x + w * 0.5 - float(p[4]), 0.0, z + d * 0.5 - float(p[5]))
			x += w + gap
			max_x = maxf(max_x, x - gap)
			row_depth = maxf(row_depth, d)
		z += row_depth + row_gap + 10.0
	return {"pos": pos, "heads": heads, "rect": Rect2(0.0, 0.0, max_x, z)}


func _validate_property(property: Dictionary) -> void:
	if property.name == "kind":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names())
	elif property.name == "causeway_length":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _build() -> void:
	if not is_inside_tree():
		return
	_clear()
	_mats.clear()
	_inst.clear()
	_inst_def.clear()
	_rng.seed = scatter_seed

	_hull = StaticBody3D.new()
	_hull.name = "Hull"
	add_child(_hull)
	_vis = Node3D.new()
	_vis.name = "Visual"
	add_child(_vis)

	_plant_defs()
	var entry := entry_for(kind)
	if not entry.is_empty():
		call(entry[7])
	_flush_instances()


# --- helpers ------------------------------------------------------------------------------------

func _sphere(pos: Vector3, radius: float, col: Color, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = _cel(col)
	mi.position = pos
	_vis.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = radius
		cs.shape = sh
		cs.position = pos
		_hull.add_child(cs)


## The walkway deck: dark slab, green edge lines, and (with `pier`) the white pier under it.
func _deck(zc: float, length: float, pier: bool) -> void:
	_box(Vector3(0, DECK_Y - 0.5, zc), Vector3(WALK_HALF * 2.0, 1.0, length), C_DARK)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * (WALK_HALF - 0.25), DECK_Y + 0.015, zc), Vector3(0.3, 0.03, length),
			C_GREEN_ACC, false, Basis.IDENTITY, false)
	if pier:
		_slab(-WALK_HALF - 0.6, WALK_HALF + 0.6, zc - length * 0.5, zc + length * 0.5, DECK_Y - 1.0, 0.0, C_WHITE)
		for sx: float in [-1.0, 1.0]:
			_box(Vector3(sx * (WALK_HALF + 0.25), DECK_Y + 0.2, zc), Vector3(0.5, 0.4, length), C_WHITE)


## A tube of radius 6.5 along `pts`, solid.
func _tube(pts: PackedVector3Array) -> void:
	var mesh := RAIL_SCRIPT.tube_mesh(pts, 6.5, 20, false) as ArrayMesh
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cel(C_SILVER)
	_vis.add_child(mi)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 6.5
		cyl.height = a.distance_to(b)
		cs.shape = cyl
		cs.transform = Transform3D(_align_y(b - a), (a + b) * 0.5)
		_hull.add_child(cs)


func _tile(col: Color, depth := 4.0) -> void:
	_slab(-10.0, 10.0, -10.0, 10.0, 0.0, -depth, col)


# --- walkway and cab ------------------------------------------------------------------------------

func _p_walkway_pier() -> void:
	_deck(0.0, 20.0, true)


func _p_walkway_causeway() -> void:
	_deck(0.0, 20.0, false)
	_box(Vector3(0, (DECK_Y - 1.0) * 0.5, 0.0), Vector3(1.6, DECK_Y - 1.0, 1.6), C_WHITE)


func _p_control_cab() -> void:
	_deck(0.0, 12.0, true)
	var z0 := -4.5
	var z1 := 4.5
	_box(Vector3(0, DECK_Y + 0.015, z0 + 0.3), Vector3(WALK_HALF * 2.0, 0.03, 0.4),
		C_GREEN_ACC, false, Basis.IDENTITY, false)
	var roof_y := DECK_Y + 3.6
	_box(Vector3(0, roof_y + 0.3, 0.0), Vector3(7.6, 0.8, z1 - z0 + 1.6), C_WHITE)
	_box(Vector3(0, roof_y + 0.3, z0 - 0.9), Vector3(6.8, 0.8, 0.8), C_WHITE, false)
	for sx: float in [-1.0, 1.0]:
		for zz: float in [z0 + 0.5, z1 - 0.5]:
			_box(Vector3(sx * 3.0, DECK_Y + 1.8, zz), Vector3(0.9, 3.6, 1.0), C_WHITE)
		var glass := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.1, 2.3, z1 - z0 - 2.0)
		glass.mesh = gm
		glass.material_override = _glass(C_GLASS, 0.45)
		glass.position = Vector3(sx * 3.3, DECK_Y + 2.2, 0.0)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(glass)
		_box(Vector3(sx * 2.5, DECK_Y + 0.9, 0.0), Vector3(0.9, 0.3, z1 - z0 - 2.4),
			C_DARK, true, Basis(Vector3.BACK, sx * 0.4))
		_box(Vector3(sx * 2.85, DECK_Y + 0.4, 0.0), Vector3(0.5, 0.8, z1 - z0 - 2.4), C_SILVER, false)
	_box(Vector3(3.0, DECK_Y + 2.3, z0 - 0.02), Vector3(0.8, 0.8, 0.06), C_GREEN_ACC, false, Basis.IDENTITY, false)
	_box(Vector3(3.0, DECK_Y + 2.3, z0 - 0.06), Vector3(0.3, 0.45, 0.04), C_WHITE, false, Basis.IDENTITY, false)


# --- buildings ------------------------------------------------------------------------------------

func _p_wing_building() -> void:
	# The long white wing with its rounded end on the +x side; the window band faces +z.
	_slab(-18.0, 6.0, -12.0, 12.0, 13.0, 3.0, C_WHITE)
	_cyl(Vector3(6.0, 8.0, 0.0), 12.0, 10.0, C_WHITE, true)
	_box(Vector3(-6.0, 8.0, 12.06), Vector3(24.0, 4.0, 0.12), C_GLASS, false, Basis.IDENTITY, false)
	_box(Vector3(-6.0, 5.4, 12.08), Vector3(24.0, 0.7, 0.14), C_SILVER, false, Basis.IDENTITY, false)
	_box(Vector3(-6.0, 10.6, 12.08), Vector3(24.0, 0.7, 0.14), C_SILVER, false, Basis.IDENTITY, false)
	_cyl(Vector3(6.0, 8.0, 0.0), 12.15, 4.0, C_GLASS, false, Basis.IDENTITY, false)
	for x: float in [-16.0, -6.0, 4.0]:
		_box(Vector3(x, 1.5, 6.0), Vector3(2.4, 3.0, 3.0), C_WHITE)
	_box(Vector3(-6.0, 1.5, 0.0), Vector3(24.0, 3.0, 22.0), C_DARK, false)


func _p_concourse_deck() -> void:
	_slab(-20.0, 20.0, -6.0, 6.0, 5.0, 4.0, C_CREAM)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(0.0, 5.6, sz * 5.75), Vector3(40.0, 1.2, 0.5), C_WHITE, false)
		_dbox(Vector3(0.0, 7.3, sz * 5.8), Vector3(40.0, 0.1, 0.1), C_SILVER)
		var x := -20.0
		while x <= 20.0:
			_dbox(Vector3(x, 6.6, sz * 5.8), Vector3(0.1, 1.4, 0.1), C_SILVER)
			x += 4.0
	_box(Vector3(0.0, 2.0, 0.0), Vector3(40.0, 4.0, 10.0), C_DARK, false)
	var xs := -20.0
	while xs < 20.0:
		_box(Vector3(xs + 1.0, 2.0, 0.0), Vector3(2.0, 4.0, 2.0), C_WHITE)
		xs += 18.0
	for zp: float in [-2.5, 2.5]:
		_cyl(Vector3(0.0, 2.6, zp), 0.8, 40.0, Color(0.30, 0.31, 0.30), false,
			Basis(Vector3.BACK, PI * 0.5), false)


func _p_service_deck() -> void:
	_slab(-16.0, 16.0, -3.0, 3.0, 3.0, 2.0, C_CREAM_D)
	_box(Vector3(0.0, 1.0, 0.0), Vector3(32.0, 2.0, 5.0), C_DARK, false)
	for x: float in [-14.0, 0.0, 14.0]:
		_box(Vector3(x, 1.0, 0.0), Vector3(1.4, 2.0, 1.4), C_WHITE, false)


func _p_white_dome() -> void:
	_sphere(Vector3.ZERO, 9.0, C_WHITE, true)


func _p_cliff_block() -> void:
	_slab(-12.0, 12.0, -12.0, 12.0, 22.0, 0.0, C_CREAM)
	_slab(-12.0, 12.0, -12.0, 12.0, 22.4, 22.0, C_GRASS)


func _p_retaining_wall() -> void:
	_slab(-0.9, 0.9, -10.0, 10.0, 1.6, -0.5, C_WHITE)


# --- bridge, tower and tube ---------------------------------------------------------------------------

func _p_rock_bridge() -> void:
	# A 40 m span at the habitat's own height (slab y 12..20), the ragged underside and green drape.
	var x0 := -20.0
	var x1 := 20.0
	_slab(x0, x1, -5.0, 5.0, BRIDGE_TOP - 0.4, BRIDGE_TOP - 8.0, C_ROCK)
	_slab(x0, x1, -5.2, 5.2, BRIDGE_TOP, BRIDGE_TOP - 0.4, C_GRASS)
	var x := x0 + 4.0
	while x < x1 - 4.0:
		var lx := _rng.randf_range(6.0, 16.0)
		var ly := _rng.randf_range(1.0, 3.2)
		_dbox(Vector3(x, BRIDGE_TOP - 8.0 - ly * 0.5, _rng.randf_range(-2.0, 2.0)),
			Vector3(lx, ly, 10.0 * _rng.randf_range(0.6, 0.95)), C_ROCK)
		x += lx * 0.9
	for k in 6:
		_dbox(Vector3(_rng.randf_range(x0 + 4.0, x1 - 4.0), BRIDGE_TOP - _rng.randf_range(2.0, 7.0), 5.06),
			Vector3(_rng.randf_range(4.0, 14.0), 0.18, 0.05), C_ROCK_L)
	var vx := x0 + 2.0
	while vx < x1 - 2.0:
		var drop := _rng.randf_range(0.8, 3.2)
		_dbox(Vector3(vx, BRIDGE_TOP - 0.4 - drop * 0.5, 5.2),
			Vector3(_rng.randf_range(1.0, 2.6), drop, 0.4), C_GRASS_D)
		_dbox(Vector3(vx + 1.0, BRIDGE_TOP - 0.4 - drop * 0.4, -5.2),
			Vector3(_rng.randf_range(1.0, 2.6), drop * 0.8, 0.4), C_GRASS_D)
		vx += _rng.randf_range(1.6, 3.4)
	x = x0 + 4.0
	while x < x1 - 2.0:
		_tree(Vector3(x, BRIDGE_TOP, _rng.randf_range(-3.0, 3.0)), _rng.randf_range(1.0, 1.7))
		_shrub(Vector3(x + 3.0, BRIDGE_TOP, _rng.randf_range(-3.0, 3.0)), _rng.randf_range(1.0, 1.8))
		x += _rng.randf_range(8.0, 12.0)


func _p_tower() -> void:
	# The brown column (20 x 16) with the pale front panel and the flared silver base sweeping out
	# to +z (front) and +x (right). Stands centred on the origin.
	var h := tower_height
	_box(Vector3(0.0, h * 0.5, 0.0), Vector3(20.0, h, 16.0), C_BROWN)
	_box(Vector3(-2.0, FLARE_R + (h - FLARE_R) * 0.5, 8.15), Vector3(9.0, h - FLARE_R, 0.35),
		C_BROWN_L, false, Basis.IDENTITY, false)
	var front := PackedVector3Array()
	var right := PackedVector3Array()
	for i in 13:
		var phi := deg_to_rad(90.0) * float(i) / 12.0
		var out := FLARE_R - FLARE_R * cos(phi)
		var y_at := FLARE_R - FLARE_R * sin(phi)
		front.append(Vector3(-10.0, y_at, 8.0 + out))
		right.append(Vector3(10.0 + out, y_at, -8.0))
	_sweep(front, Vector3(20.0, 0.0, 0.0), C_SILVER, Vector3(0, 1, 1))
	_sweep(right, Vector3(0.0, 0.0, 16.0), C_SILVER, Vector3(1, 1, 0))


func _p_waterfall() -> void:
	# A pale sheet down a brown wall (the wall is on +x), and the splash at its foot.
	_slab(0.0, 2.0, -4.0, 4.0, 16.0, 0.0, C_BROWN)
	var fall := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.3, 15.0, 5.0)
	fall.mesh = fm
	fall.material_override = _glow(Color(0.86, 0.93, 1.0))
	fall.position = Vector3(-0.15, 7.5, 0.0)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(fall)
	_dbox(Vector3(-1.0, 0.4, 0.0), Vector3(5.0, 0.8, 7.0), Color(0.93, 0.97, 1.0))


func _p_tube_straight() -> void:
	var pts := PackedVector3Array()
	for i in 5:
		pts.append(Vector3(-20.0 + 10.0 * float(i), 6.5, 0.0))
	_tube(pts)


func _p_tube_bend() -> void:
	# A quarter turn of radius 40: enters heading +x at the origin, leaves heading +z.
	var pts := PackedVector3Array()
	for i in 13:
		var t := (PI * 0.5) * float(i) / 12.0
		pts.append(Vector3(40.0 * sin(t), 6.5, 40.0 * (1.0 - cos(t))))
	_tube(pts)


# --- fields ---------------------------------------------------------------------------------------------

func _p_hydro_bed() -> void:
	# A V of two white slopes tilted toward a dark grated channel, cabbages on top. 20 m long.
	_def("cab_a", _unit_sphere(), C_CABBAGE_A)
	_def("cab_b", _unit_sphere(), C_CABBAGE_B)
	var tilt := deg_to_rad(18.0)
	var z_far := -10.0
	var z_near := 10.0
	var length := z_near - z_far
	_box(Vector3(0.0, 0.6, 0.0), Vector3(2.0, 0.6, length), C_DARK, false)
	for k in 4:
		_dbox(Vector3(0.0, 0.92, z_far + 3.0 + float(k) * (length - 6.0) / 3.0),
			Vector3(1.6, 0.06, 0.25), Color(0.3, 0.32, 0.3))
	for side: float in [-1.0, 1.0]:
		var rot := Basis(Vector3.BACK, side * tilt)
		var centre := Vector3(side * 4.6, 1.75, 0.0)
		_box(centre, Vector3(7.6, 0.5, length), C_BED, true, rot)
		_box(Vector3(side * 4.6, 0.6, 0.0), Vector3(7.0, 1.2, length - 0.4), C_CREAM_D, false)
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


func _p_corn_field() -> void:
	_def("corn_a", BoxMesh.new(), C_CORN_A)
	_def("corn_b", BoxMesh.new(), C_CORN_B)
	_slab(-10.0, 10.0, -10.0, 10.0, 0.6, -0.5, C_SOIL)
	var ix := 0
	var x := -9.5
	while x < 9.6:
		var z := -9.5
		while z < 9.6:
			var h := _rng.randf_range(2.3, 3.0)
			var key := "corn_a" if (ix % 2 == 0) else "corn_b"
			var p := Vector3(x + _rng.randf_range(-0.25, 0.25), 0.6 + h * 0.5, z + _rng.randf_range(-0.25, 0.25))
			_add(key, Transform3D(Basis.from_scale(Vector3(0.55, h, 0.55)), p))
			z += 1.0
		x += 1.0
		ix += 1


# --- ground and water -------------------------------------------------------------------------------------------

func _p_terrace() -> void:
	# One cream rake tilted 12 degrees down toward +x, a green strip and cypresses, on a solid fill.
	var tilt := deg_to_rad(12.0)
	var yc := 6.0
	var rot := Basis(Vector3.BACK, -tilt)
	var centre := Vector3(0.0, yc, 0.0)
	_box(centre, Vector3(40.0, 2.5, 17.2), C_CREAM, true, rot)
	_box(Vector3(0.0, (yc - 1.2) * 0.5, 0.0), Vector3(38.0, yc - 1.2, 16.8), C_CREAM_D)
	_box(centre + rot * Vector3(-7.0, 1.4, 0.0), Vector3(22.0, 0.5, 13.0), C_GRASS, false, rot)
	for k in 5:
		var cx := _rng.randf_range(-18.0, 11.0)
		var cz := _rng.randf_range(-6.0, 6.0)
		_cypress(Vector3(cx, yc + (-cx) * tan(tilt) + 1.7, cz), _rng.randf_range(1.0, 1.5))


func _p_ground_soil() -> void:
	_tile(C_SOIL)


func _p_ground_grass() -> void:
	_tile(C_GRASS)


func _p_ground_grass_dark() -> void:
	_tile(C_GRASS_D)


func _p_ground_plaza() -> void:
	_tile(C_CREAM)


func _p_ground_white() -> void:
	_tile(C_WHITE, 1.0)


func _p_bank_corner() -> void:
	_prism(PackedVector2Array([Vector2(-10, 10), Vector2(10, 10), Vector2(-10, -10)]), -4.0, 0.0, C_GRASS_D, C_GRASS)


func _p_island() -> void:
	var isl := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0
		isl.append(Vector2(cos(a) * (14.0 + 2.5 * sin(a * 2.0)), sin(a) * (8.0 + 1.5 * cos(a * 3.0))))
	_prism(isl, -4.0, 0.4, C_GRASS_D, C_GRASS)
	_tree(Vector3(0.0, 0.4, 0.0), 2.8)


func _p_peninsula() -> void:
	_prism(PackedVector2Array([Vector2(-15, 8), Vector2(15, 8), Vector2(1, -8)]), -4.0, 0.0, C_GRASS_D, C_GRASS)
	_prism(PackedVector2Array([Vector2(-7, 8), Vector2(7, 8), Vector2(0, -3)]), -4.0, 0.05, C_SAND, C_SAND)
	_tree(Vector3(-1.0, 0.0, 2.0), 1.5)


func _p_water_tile() -> void:
	# The lake's water plane over its solid rock bed (bed top 6.5 m under the surface). It sinks
	# below y = 0, so it needs a hole in whatever floor it is set into.
	_slab(-12.0, 12.0, -12.0, 12.0, BED_Y, BED_Y - 4.0, C_ROCK)
	var water := MeshInstance3D.new()
	water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(24.0, 24.0)
	water.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var g := to_global(Vector3(60.0, 0.0, -40.0))
	m.set_shader_parameter("glare_centre", Vector2(g.x, g.z))
	water.material_override = m
	water.position = Vector3(0.0, WATER_Y, 0.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


# --- plants ----------------------------------------------------------------------------------------------------------

func _p_tree() -> void:
	_tree(Vector3.ZERO, 2.0)


func _p_cypress() -> void:
	_cypress(Vector3.ZERO, 1.3)


func _p_palm() -> void:
	_palm(Vector3.ZERO, 1.2)


func _p_shrub() -> void:
	_shrub(Vector3.ZERO, 1.5)


func _p_hedge_row() -> void:
	for i in 5:
		_tree(Vector3(-8.0 + float(i) * 4.05 + _rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-2.0, 2.0)),
			_rng.randf_range(0.9, 1.5))


func _p_cypress_row() -> void:
	for i in 6:
		_cypress(Vector3(-10.0 + float(i) * 4.0, 0.0, 0.0), _rng.randf_range(1.1, 1.6))


func _p_tree_grove() -> void:
	for i in 10:
		_tree(Vector3(_rng.randf_range(-11.0, 11.0), 0.0, _rng.randf_range(-11.0, 11.0)), _rng.randf_range(1.6, 2.6))


# --- details -------------------------------------------------------------------------------------------------------------

func _p_banners() -> void:
	var cols := [Color(0.72, 0.12, 0.10), Color(0.92, 0.72, 0.15), Color(0.10, 0.09, 0.09),
		Color(0.85, 0.35, 0.12), Color(0.72, 0.12, 0.10)]
	for i in cols.size():
		_box(Vector3(-4.8 + float(i) * 2.4, 7.0, 0.0), Vector3(1.6, 14.0, 0.25), cols[i], false, Basis.IDENTITY, false)


func _p_stripe_fan() -> void:
	var fan := [Color(0.85, 0.2, 0.1), Color(0.95, 0.6, 0.12), Color(0.95, 0.88, 0.25),
		Color(0.92, 0.92, 0.88), Color(0.3, 0.6, 0.2), Color(0.85, 0.2, 0.1), Color(0.95, 0.6, 0.12)]
	for i in fan.size():
		var b := Basis(Vector3.UP, deg_to_rad(-30.0 + float(i) * 10.0))
		_box(Vector3(-1.8 + float(i) * 0.6, 0.06, 1.2 - float(i) * 0.4), Vector3(14.0, 0.06, 1.3), fan[i], false, b, false)


# --- backdrop ---------------------------------------------------------------------------------------------------------------

func _p_bowl() -> void:
	_bowl(Vector3.ZERO)


func _p_far_dome() -> void:
	_far_dome(Vector3.ZERO, 12.0)


func _p_dome_cluster() -> void:
	_far_dome(Vector3(-6.0, 0.0, -4.0), 10.0)
	_far_dome(Vector3(9.0, 0.0, -6.0), 7.0)
	_far_dome(Vector3(-12.0, 0.0, 8.0), 6.0)


func _p_hillside_terrace() -> void:
	var tilt := atan(0.22)
	var h := 9.0
	var rot := Basis(Vector3.BACK, tilt)
	_dbox(Vector3(0.0, h, 0.0), Vector3(38.0, 2.4, 58.0), C_CREAM, rot)
	_dbox(Vector3(0.0, h * 0.5 - 1.0, 0.0), Vector3(37.0, h + 1.0, 57.0), C_CREAM_D)
	_dbox(Vector3(0.0, h + 1.4, 0.0) + rot * Vector3(6.0, 0.0, 0.0), Vector3(20.0, 0.5, 40.0), C_GRASS, rot)


func _p_block_cluster() -> void:
	for i in 8:
		var h := _rng.randf_range(4.0, 22.0)
		_dbox(Vector3(_rng.randf_range(-16.0, 16.0), h * 0.5, _rng.randf_range(-16.0, 16.0)),
			Vector3(_rng.randf_range(8.0, 18.0), h, _rng.randf_range(8.0, 18.0)),
			C_WHITE if i % 2 == 0 else C_CREAM)
