class_name Hub2RoofDoor
extends Node3D

# hub2's roof hangar door (docs/specs/hub2-roof-door.md): a gap in the shaft-D roof with two sliding
# leaves stuck most of the way open, a steel frame and rails round it, cold daylight and soft snow
# coming in. Place the node at the middle of the opening ON the roof plane (x, roof height, z).
# Everything is built in code; nothing is saved into the scene.
#
#   cut_roof()      mesh + collision of the flat roof really have the hole (Hub2RoofClip)
#   door            frame, rails, leaves, gear housings, dead beacons, snow on the tops (PropKit)
#   sky dome        inward-facing pale overcast with a sun-glow patch, only seen through the gap
#   beams           faked additive light cards, steep and cold, down from the gap
#   flakes          one vertex-shader mesh of falling snow in a column under the gap
#   bake_cover()    top-down height map of what the open sky sees; the surface shader lays snow on it,
#                   daylight pools and low snow mounds come from it too
#
# Node space: origin = the middle of the opening on the roof plane, +Y up, +Z along the shaft.

const FLAKE_SHADER := preload("res://shaders/hub2_roof_snow.gdshader")
const BEAM_SHADER := preload("res://shaders/hub2_roof_beam.gdshader")
## How many metres the beams' edges blur over (across, along the shaft).
const BEAM_FEATHER := Vector2(3.5, 6.0)

## Sun elevation of the daylight, degrees; it comes from +X like the map's sun.
const SUN_ELEVATION := 65.0
## Height-map cell, metres.
const CELL := 0.5

## The imported map GLB instance (its roof gets the hole).
@export var map: Node3D
## Hub2Wear, which must already have run (its baked meshes are what get cut).
@export var wear: Hub2Wear
## Gets the daylight patches as extra light pools.
@export var lamp_pools: Hub2LampPools
## Half width of the hole cut in the roof (x). The shaft itself is 12 m half width.
@export var half_width := 16.0
## Half length of the opening (z).
@export var half_length := 40.0
## Half width of the shaft under it: the sky gap is this wide.
@export var shaft_half_width := 12.0
## Leaf length and how far each has slid from shut (the opening is "stuck ~90 % open").
@export var leaf_length := 44.0
@export var leaf_shift := 36.0
@export_range(0.0, 1.0, 0.05) var wear_amount := 0.55
@export var snow_count := 6000
## Metres the flakes fall below the roof plane before they wrap (the shaft bottom is 152 m down).
@export var column_depth := 152.0
@export var dome_radius := 1500.0

var door_body: StaticBody3D
var lid: StaticBody3D
var cover_image: Image
var cover_rect := Rect2()
var mound_count := 0
var pool_count := 0
var cut_report: Dictionary = {}


## Metres of sideways travel per metre of fall along a beam.
static func beam_shift() -> float:
	return 1.0 / tan(deg_to_rad(SUN_ELEVATION))


## Unit vector toward the sun.
static func sun_direction() -> Vector3:
	var e := deg_to_rad(SUN_ELEVATION)
	return Vector3(cos(e), sin(e), 0.0)


## Half length of the sky gap: the opening minus what each leaf still overhangs.
func gap_half_length() -> float:
	return half_length - leaf_length + leaf_shift


func _ready() -> void:
	_build_door()
	_build_sky()
	_build_beams()
	_build_flakes()
	cut_roof()
	_bake_when_physics_is_ready()


# -- the hole ---------------------------------------------------------------------------------

## Cuts the hole out of every flat roof triangle of `map` (visual and collision). Returns how many
## meshes and collision shapes changed.
func cut_roof() -> int:
	if map == null:
		push_warning("Hub2RoofDoor: no map assigned.")
		return 0
	var gp := global_position
	var hole := Rect2(gp.x - half_width, gp.z - half_length, half_width * 2.0, half_length * 2.0)
	var y_lo := gp.y - 0.25
	var y_hi := gp.y + 0.25
	var meshes := 0
	var shapes := 0
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var cut := Hub2RoofClip.cut_mesh(mi.mesh, mi.global_transform, hole, y_lo, y_hi)
		if cut != null:
			mi.mesh = cut
			meshes += 1
		for body in mi.get_children():
			if not body is StaticBody3D:
				continue
			for child in body.get_children():
				var cs := child as CollisionShape3D
				if cs == null or not cs.shape is ConcavePolygonShape3D:
					continue
				var old := cs.shape as ConcavePolygonShape3D
				var faces := old.get_faces()
				var cut_faces := Hub2RoofClip.cut_faces(faces, (body as Node3D).global_transform, hole, y_lo, y_hi)
				if cut_faces.size() != faces.size() or cut_faces != faces:
					var shape := ConcavePolygonShape3D.new()
					shape.backface_collision = old.backface_collision
					shape.set_faces(cut_faces)
					cs.shape = shape
					shapes += 1
	cut_report = {"meshes": meshes, "shapes": shapes}
	return meshes + shapes


# -- the door ---------------------------------------------------------------------------------

const STEEL := Color(0.34, 0.36, 0.38)
const STEEL_LEAF := Color(0.40, 0.42, 0.43)
const RAIL := Color(0.16, 0.16, 0.18)
const SNOW := Color(0.80, 0.86, 0.94)
const AMBER_DEAD := Color(0.30, 0.16, 0.04)


func _build_door() -> void:
	var kit := PropKit.new(wear_amount, 7711)
	kit.grime_height = 3.0
	var boxes: Array = []
	var hl := half_length
	var span := hl + leaf_shift + 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417

	for sx in [-1.0, 1.0]:
		# Long girder along the shaft, rack strip and teeth on it, the rail the leaves run on.
		_mbox(kit, boxes, sx, 12.0, 18.5, 0.0, 1.4, -span, span, STEEL)
		_mbox(kit, boxes, sx, 13.4, 15.4, 1.4, 1.75, -span, span, RAIL)
		_mbox(kit, null, sx, 12.3, 13.0, 1.4, 1.6, -span + 1.0, span - 1.0, STEEL_LEAF)
		var z := -span + 2.0
		while z < span - 2.0:
			_mbox(kit, null, sx, 12.35, 12.95, 1.6, 1.85, z, z + 0.5, RAIL)
			z += 1.8
		# Buffer stops at both ends of the rail.
		_mbox(kit, boxes, sx, 13.0, 15.8, 1.4, 2.6, -span, -span + 1.5, STEEL_LEAF)
		_mbox(kit, boxes, sx, 13.0, 15.8, 1.4, 2.6, span - 1.5, span, STEEL_LEAF)
		# Outer conduit and the four drive housings (a motor on each).
		kit.tube(Vector3(sx * 19.0, 0.55, -span), Vector3(sx * 19.0, 0.55, span), 0.16, RAIL, 6)
		for hz in [-68.0, -12.0, 12.0, 68.0]:
			_mbox(kit, boxes, sx, 18.5, 22.2, 0.0, 2.8, hz - 2.2, hz + 2.2, Hub2PropBuild.STEEL_DARK)
			kit.tube(Vector3(sx * 22.2, 1.5, hz), Vector3(sx * 24.4, 1.5, hz), 0.8, Color(0.30, 0.22, 0.16), 8)
			_mbox(kit, null, sx, 19.2, 21.6, 2.8, 3.2, hz - 1.2, hz + 1.2, RAIL)
		# Dead beacons on the girder tops at the corners of the frame.
		for bz in [-(hl + 2.0), hl + 2.0]:
			var post := Vector3(sx * 17.2, 1.4, bz)
			kit.tube(post, post + Vector3(0, 1.7, 0), 0.16, RAIL, 6)
			kit.box(post + Vector3(-0.3, 1.7, -0.3), post + Vector3(0.3, 2.4, 0.3), AMBER_DEAD)
			kit.box(post + Vector3(-0.36, 2.4, -0.36), post + Vector3(0.36, 2.52, 0.36), RAIL)
	# Header beams close the frame across both ends of the opening, over the cut roof edge.
	_mbox(kit, boxes, 1.0, -12.0, 12.0, 0.0, 1.2, hl, hl + 4.0, STEEL)
	_mbox(kit, boxes, 1.0, -12.0, 12.0, 0.0, 1.2, -hl - 4.0, -hl, STEEL)

	# The leaves: slab, lead beam with hazard stripes, ribs, trucks on the rail, snow on top.
	for s in [-1.0, 1.0]:
		var z_lead: float = s * (hl - leaf_length + leaf_shift)
		var z_trail: float = s * (hl + leaf_shift)
		var zlo := minf(z_lead, z_trail)
		var zhi := maxf(z_lead, z_trail)
		_mbox(kit, boxes, 1.0, -17.6, 17.6, 2.3, 3.5, zlo, zhi, STEEL_LEAF)
		var bz0 := minf(z_lead, z_lead + s * 1.4)
		var bz1 := maxf(z_lead, z_lead + s * 1.4)
		_mbox(kit, null, 1.0, -17.9, 17.9, 1.9, 3.9, bz0, bz1, STEEL)
		var x := -17.6
		var odd := false
		while x < 17.6 - 0.01:
			var x1 := minf(x + 2.2, 17.6)
			kit.box(Vector3(x, 3.9, bz0), Vector3(x1, 3.97, bz1), Hub2PropBuild.SAFETY_YELLOW if odd else Hub2PropBuild.BLACK, Transform3D.IDENTITY, false)
			odd = not odd
			x = x1
		var rz := zlo + 2.0
		while rz < zhi - 1.0:
			_mbox(kit, null, 1.0, -17.2, 17.2, 3.5, 3.75, rz - 0.15, rz + 0.15, STEEL)
			rz += 4.0
		for rx in [-8.0, 0.0, 8.0]:
			_mbox(kit, null, 1.0, rx - 0.2, rx + 0.2, 3.5, 3.72, zlo + 0.5, zhi - 0.5, STEEL)
		for k in 6:
			var tz: float = z_lead + s * (4.0 + 7.5 * k)
			for sx in [-1.0, 1.0]:
				_mbox(kit, null, sx, 13.0, 15.8, 1.75, 2.3, tz - 1.5, tz + 1.5, RAIL)
		for k in 26:
			var dz := rng.randf_range(2.0, 5.5)
			var dw := rng.randf_range(2.5, 7.0)
			var cz := rng.randf_range(zlo + dz, zhi - dz)
			var cx := rng.randf_range(-15.0, 15.0)
			var h := rng.randf_range(0.1, 0.22)
			kit.box(Vector3(cx - dw * 0.5, 3.5, cz - dz * 0.5), Vector3(cx + dw * 0.5, 3.5 + h, cz + dz * 0.5), SNOW, Transform3D.IDENTITY, false)
	# Snow along the girder tops and the rails.
	for sx in [-1.0, 1.0]:
		var sz := -span + 2.0
		while sz < span - 2.0:
			if rng.randf() < 0.7:
				var drift_len := rng.randf_range(1.5, 4.0)
				var h := rng.randf_range(0.1, 0.25)
				kit.blob(Vector3(sx * rng.randf_range(16.4, 17.8), 1.4 + h * 0.3, sz + drift_len * 0.5), Vector3(rng.randf_range(0.5, 1.1), h, drift_len * 0.5), SNOW, rng)
				kit.blob(Vector3(sx * 14.4, 1.75 + h * 0.2, sz + drift_len * 0.5), Vector3(0.9, h * 0.8, drift_len * 0.45), SNOW, rng)
			sz += 3.2

	var visual := MeshInstance3D.new()
	visual.name = "DoorVisual"
	visual.mesh = kit.commit()
	visual.set_meta(&"prop_part", true)
	add_child(visual)
	door_body = StaticBody3D.new()
	door_body.name = "DoorBody"
	door_body.set_meta(&"prop_part", true)
	add_child(door_body)
	var i := 0
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		cs.name = "Box%d" % i
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		door_body.add_child(cs)
		i += 1

	# Nothing climbs out through the gap onto the roof: an invisible stop-only lid over the whole door
	# (pilot9 collides with this layer; its probes, the camera and the cover bake do not).
	lid = StaticBody3D.new()
	lid.name = "RoofLid"
	lid.collision_layer = 1 << 9
	lid.collision_mask = 0
	lid.set_meta(&"prop_part", true)
	var lcs := CollisionShape3D.new()
	var lbs := BoxShape3D.new()
	lbs.size = Vector3(40.0, 1.0, span * 2.0 + 4.0)
	lcs.shape = lbs
	lcs.position = Vector3(0.0, 0.5, 0.0)
	lid.add_child(lcs)
	add_child(lid)


## A box mirrored by `sx` (x run a..b on that side), with collision when `boxes` is given.
func _mbox(kit: PropKit, boxes: Variant, sx: float, a: float, b: float, y0: float, y1: float,
		z0: float, z1: float, col: Color) -> void:
	var lo := Vector3(minf(sx * a, sx * b), y0, z0)
	var hi := Vector3(maxf(sx * a, sx * b), y1, z1)
	kit.box(lo, hi, col)
	if boxes != null:
		(boxes as Array).append([(lo + hi) * 0.5, hi - lo])


# -- sky and light ----------------------------------------------------------------------------

## The pale overcast seen through the gap: a hemisphere facing in, so it vanishes seen from outside
## (room A's own sky is left alone). Flat bands, with a soft white patch where the beams come from.
func _build_sky() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 28
	var sectors := 64
	var sun := sun_direction()
	for i in rings:
		for j in sectors:
			var p00 := _dome_point(i, j, rings, sectors)
			var p01 := _dome_point(i, j + 1, rings, sectors)
			var p10 := _dome_point(i + 1, j, rings, sectors)
			var p11 := _dome_point(i + 1, j + 1, rings, sectors)
			var c := _sky_colour(((p00 + p01 + p10 + p11) * 0.25).normalized(), sun)
			_dome_tri(st, p00, p01, p11, c)
			_dome_tri(st, p00, p11, p10, c)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.name = "SkyDome"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"prop_part", true)
	add_child(mi)


func _dome_point(i: int, j: int, rings: int, sectors: int) -> Vector3:
	var lat := (PI * 0.5) * float(i) / rings    # 0 at the horizon, up to the zenith
	var lon := TAU * float(j) / sectors
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * dome_radius


## One triangle, wound so its front shows from the middle of the dome.
func _dome_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(a + b + c) < 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _sky_colour(dir: Vector3, sun: Vector3) -> Color:
	var elev := clampf(dir.y, 0.0, 1.0)
	var band := floorf(elev * 5.0) / 4.0
	var base := Color(0.56, 0.61, 0.68).lerp(Color(0.80, 0.84, 0.90), clampf(band, 0.0, 1.0))
	var ang := acos(clampf(dir.dot(sun), -1.0, 1.0))
	if ang < 0.13:
		return Color(1.0, 0.99, 0.97)
	if ang < 0.30:
		return Color(0.94, 0.96, 0.99)
	if ang < 0.55:
		return base.lerp(Color(0.92, 0.94, 0.98), 0.55)
	if ang < 0.85:
		return base.lerp(Color(0.92, 0.94, 0.98), 0.25)
	return base


## Faked daylight shafts (rev 1, soft): slices through one light field that BEAM_SHADER evaluates per
## pixel, so the slices agree and their edges never show. Three families, so whichever way the camera
## looks some slices face it (the shader fades the edge-on ones): cross-sections across the shaft,
## sheets along the sun's slant, and level slices. Every slice is cut bigger than the light it carries.
func _build_beams() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gx := shaft_half_width
	var gz := gap_half_length()
	var shift := beam_shift()
	var reach := 2.0 * gx / shift
	var top := 2.0
	var bot := -reach - 1.0
	var zr := gz + BEAM_FEATHER.y
	var white := Color.WHITE
	# Cross-sections every 3 m along the shaft.
	var nz := int(ceilf(zr * 2.0 / 3.0))
	for k in nz + 1:
		var z := lerpf(-zr, zr, float(k) / nz)
		_card(st, Vector3(-gx - 1.0, top, z), Vector3(gx + BEAM_FEATHER.x, top, z), Vector3(gx + BEAM_FEATHER.x, bot, z), Vector3(-gx - 1.0, bot, z), white)
	# Sheets along the slant, every 3 m across, each down to (just behind) the west wall.
	var xt := -gx + 1.5
	while xt < gx + BEAM_FEATHER.x * 0.5:
		var d_end: float = (xt + gx) / shift + 2.0
		_card(st, Vector3(xt + shift * top, top, -zr), Vector3(xt + shift * top, top, zr), Vector3(xt - shift * d_end, -d_end, zr), Vector3(xt - shift * d_end, -d_end, -zr), white)
		xt += 3.0
	# Level slices every 5 m down.
	var d := 3.0
	while d < reach:
		_card(st, Vector3(-gx - 1.0, -d, -zr), Vector3(gx + BEAM_FEATHER.x, -d, -zr), Vector3(gx + BEAM_FEATHER.x, -d, zr), Vector3(-gx - 1.0, -d, zr), white)
		d += 5.0
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter(&"gap", Vector2(gx, gz))
	mat.set_shader_parameter(&"feather", BEAM_FEATHER)
	mat.set_shader_parameter(&"beam_shift", shift)
	mat.set_shader_parameter(&"reach", reach)
	var mi := MeshInstance3D.new()
	mi.name = "Beams"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"prop_part", true)
	add_child(mi)


func _card(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(p)


# -- falling snow -----------------------------------------------------------------------------

func _build_flakes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var top := 2.2
	var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var gz := gap_half_length() + 4.0
	for f in snow_count:
		var base := Vector3(rng.randf_range(-half_width, half_width), top - rng.randf() * column_depth, rng.randf_range(-gz, gz))
		var r := rng.randf()
		var size := 0.07 + r * r * 0.1
		if rng.randf() < 0.05:
			size = 0.22
		var c := Color(size, rng.randf(), rng.randf_range(0.8, 1.25), 0.0)
		var v0 := verts.size()
		for corner: Vector2 in corners:
			verts.append(base)
			uvs.append(corner)
			cols.append(c)
		for k in [0, 1, 2, 0, 2, 3]:
			idx.append(v0 + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-half_width - 2.0, -column_depth - 2.0, -gz - 2.0), Vector3(half_width * 2.0 + 4.0, column_depth + 6.0, gz * 2.0 + 4.0))
	var mat := ShaderMaterial.new()
	mat.shader = FLAKE_SHADER
	mat.set_shader_parameter(&"column_top", top)
	mat.set_shader_parameter(&"column_height", column_depth)
	mat.set_shader_parameter(&"gap", Vector4(-shaft_half_width, -gap_half_length(), shaft_half_width, gap_half_length()))
	mat.set_shader_parameter(&"beam_shift", beam_shift())
	mat.set_shader_parameter(&"dark_begin", -column_depth * 0.35)
	mat.set_shader_parameter(&"dark_end", -column_depth)
	var mi := MeshInstance3D.new()
	mi.name = "Flakes"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"prop_part", true)
	add_child(mi)


# -- what the open sky sees -------------------------------------------------------------------

func _bake_when_physics_is_ready() -> void:
	# The door's boxes and the cut roof are only in the physics space after a step or two.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	bake_cover()


## Casts a ray down every CELL of the gap (plus a margin) and keeps the height of the top surface:
## that image is the snow cover's map (shaders/hub2_ps1.gdshaderinc), and the daylight pools and the
## low snow mounds are read from it. Needs the roof cut and the door in the physics space.
func bake_cover() -> Image:
	var gp := global_position
	var rect := Rect2(gp.x - half_width, gp.z - gap_half_length() - 12.0, half_width * 2.0, (gap_half_length() + 12.0) * 2.0)
	var w := int(rect.size.x / CELL)
	var h := int(rect.size.y / CELL)
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	var space := get_world_3d().direct_space_state
	var top := gp.y + 40.0
	var bottom := gp.y - column_depth - 60.0
	for zi in h:
		for xi in w:
			var x := rect.position.x + (xi + 0.5) * CELL
			var z := rect.position.y + (zi + 0.5) * CELL
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z), 1)
			var hit := space.intersect_ray(q)
			img.set_pixel(xi, zi, Color(-1000.0 if hit.is_empty() else (hit["position"] as Vector3).y, 0, 0, 1))
	cover_image = img
	cover_rect = rect
	_apply_cover()
	_add_daylight_pools()
	_add_mounds()
	bake_edges()
	return img


## Edge-map cell, metres, and how far past the gap's ends (z) and the shaft walls (x) it reaches.
const EDGE_CELL := 0.3
const EDGE_REACH := Vector2(1.5, 16.0)
## A neighbour with no floor within this many metres below makes a cell a drop edge.
const EDGE_DROP := 1.0
## Distances stop at this; nothing past it gets dusting.
const EDGE_CAP := 1.5
## Floor levels kept per column (the shaft has walkways under overhangs, bridges, the bottom).
const EDGE_LAYERS := 4
const EMPTY := -1000.0

## r,g,b,a = up to four floor heights per cell (highest first, EMPTY when none) and the metres from
## each to the nearest drop edge on its own level.
var edge_heights: Image
var edge_dists: Image
var edge_rect := Rect2()
var edge_lips := 0


## The edge dusting's map (rev 1): every floor level down each column of the shaft (plus EDGE_REACH),
## and how far each is from a real drop: a neighbouring column with no floor near that level, and no
## wall in between. Flush seams between map pieces never count, and walkways under overhangs still do
## (they look out into the open shaft sideways). Spread over frames; the dusting appears when done.
func bake_edges() -> void:
	var gp := global_position
	var hx := shaft_half_width + EDGE_REACH.x
	var hz := gap_half_length() + EDGE_REACH.y
	var rect := Rect2(gp.x - hx, gp.z - hz, hx * 2.0, hz * 2.0)
	var w := int(rect.size.x / EDGE_CELL)
	var h := int(rect.size.y / EDGE_CELL)
	var L := EDGE_LAYERS
	var heights := PackedFloat32Array()
	heights.resize(w * h * L)
	heights.fill(EMPTY)
	var space := get_world_3d().direct_space_state
	var top := gp.y - 0.5
	var bottom := gp.y - column_depth - 60.0
	var q := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)
	q.hit_back_faces = false
	for zi in h:
		if zi % 24 == 23:
			await get_tree().process_frame
			if not is_inside_tree():
				return
		for xi in w:
			var x := rect.position.x + (xi + 0.5) * EDGE_CELL
			var z := rect.position.y + (zi + 0.5) * EDGE_CELL
			var y := top
			var n := 0
			var guard := 0
			while n < L and guard < 12:
				guard += 1
				q.from = Vector3(x, y, z)
				q.to = Vector3(x, bottom, z)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					break
				var hp: Vector3 = hit["position"]
				if (hit["normal"] as Vector3).y > 0.6:
					heights[(zi * w + xi) * L + n] = hp.y
					n += 1
				y = hp.y - 0.05
	# Drop edges, per level.
	var dist := PackedFloat32Array()
	dist.resize(w * h * L)
	dist.fill(EDGE_CAP)
	var lips: Array[Vector3i] = []
	var hq := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)
	for zi in h:
		for xi in w:
			for l in L:
				var hc := heights[(zi * w + xi) * L + l]
				if hc <= EMPTY + 1.0:
					break
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := xi + d.x
					var nz := zi + d.y
					if nx < 0 or nz < 0 or nx >= w or nz >= h:
						continue
					if _edge_level(heights, (nz * w + nx) * L, hc, EDGE_DROP, 0.5) >= 0:
						continue
					# Nothing to stand on next door at this level: a drop, unless it is a wall.
					var a := Vector3(rect.position.x + (xi + 0.5) * EDGE_CELL, hc + 0.3, rect.position.y + (zi + 0.5) * EDGE_CELL)
					hq.from = a
					hq.to = a + Vector3(d.x, 0, d.y) * EDGE_CELL * 1.5
					if not space.intersect_ray(hq).is_empty():
						continue
					dist[(zi * w + xi) * L + l] = 0.0
					lips.append(Vector3i(xi, zi, l))
					break
	edge_lips = lips.size()
	# Distance: stamp a disc round every lip onto cells of the same level.
	var r := int(ceilf(EDGE_CAP / EDGE_CELL))
	for lip in lips:
		var hl := heights[(lip.y * w + lip.x) * L + lip.z]
		for dz in range(-r, r + 1):
			var nz := lip.y + dz
			if nz < 0 or nz >= h:
				continue
			for dx in range(-r, r + 1):
				var nx := lip.x + dx
				if nx < 0 or nx >= w:
					continue
				var dd := sqrt(float(dx * dx + dz * dz)) * EDGE_CELL
				if dd >= EDGE_CAP:
					continue
				var m := _edge_level(heights, (nz * w + nx) * L, hl, 0.3, 0.3)
				if m >= 0 and dd < dist[(nz * w + nx) * L + m]:
					dist[(nz * w + nx) * L + m] = dd
	var himg := Image.create(w, h, false, Image.FORMAT_RGBAF)
	var dimg := Image.create(w, h, false, Image.FORMAT_RGBAF)
	for zi in h:
		for xi in w:
			var b := (zi * w + xi) * L
			himg.set_pixel(xi, zi, Color(heights[b], heights[b + 1], heights[b + 2], heights[b + 3]))
			dimg.set_pixel(xi, zi, Color(dist[b], dist[b + 1], dist[b + 2], dist[b + 3]))
	edge_heights = himg
	edge_dists = dimg
	edge_rect = rect
	var ht := ImageTexture.create_from_image(himg)
	var dt := ImageTexture.create_from_image(dimg)
	for m in _snow_materials():
		m.set_shader_parameter(&"snow_edge_heights", ht)
		m.set_shader_parameter(&"snow_edge_dists", dt)
		m.set_shader_parameter(&"snow_edge_rect", Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))


## Which of a column's levels (starting at index b) lies within [y - below, y + above], or -1.
func _edge_level(heights: PackedFloat32Array, b: int, y: float, below: float, above: float) -> int:
	for l in EDGE_LAYERS:
		var v := heights[b + l]
		if v <= EMPTY + 1.0:
			return -1
		if v >= y - below and v <= y + above:
			return l
	return -1


func _snow_materials() -> Array[ShaderMaterial]:
	var mats: Array[ShaderMaterial] = []
	if wear != null and wear.surface_material != null:
		mats.append(wear.surface_material)
	var decals := wear.map.get_node_or_null(Hub2Wear.DECAL_NODE) as MeshInstance3D if wear != null and wear.map != null else null
	if decals != null and decals.material_override is ShaderMaterial:
		mats.append(decals.material_override)
	return mats


func cover_height(x: int, z: int) -> float:
	return cover_image.get_pixel(x, z).r


func _apply_cover() -> void:
	var gp := global_position
	var tex := ImageTexture.create_from_image(cover_image)
	for m in _snow_materials():
		m.set_shader_parameter(&"snow_map", tex)
		m.set_shader_parameter(&"snow_map_rect", Vector4(cover_rect.position.x, cover_rect.position.y, cover_rect.end.x, cover_rect.end.y))
		m.set_shader_parameter(&"snow_core", Vector4(gp.x - shaft_half_width, gp.z - gap_half_length(), gp.x + shaft_half_width, gp.z + gap_half_length()))
		# Edge dusting (rev 1): the shaft's own lips along the gap, thinning 15 m past its ends.
		m.set_shader_parameter(&"snow_edge_zone", Vector4(gp.x - shaft_half_width - 1.0, gp.z - gap_half_length(), gp.x + shaft_half_width + 1.0, gp.z + gap_half_length()))
		m.set_shader_parameter(&"snow_edge_fade", Vector2(2.0, 15.0))
		m.set_shader_parameter(&"snow_edge_top", gp.y - 1.0)
		m.set_shader_parameter(&"snow_edge_deep", Vector2(150.0, 0.35))


## True when a world point on a surface at height h lies in a beam: following the sun up from it
## reaches the roof plane inside the sky gap.
func is_in_beam(x: float, h: float) -> bool:
	var gp := global_position
	var xt := x + beam_shift() * (gp.y - h)
	return xt > gp.x - shaft_half_width and xt < gp.x + shaft_half_width


## A cool daylight pool on every 6 m block of floor that a beam reaches (bridges, ledges), at most 28.
func _add_daylight_pools() -> void:
	if lamp_pools == null:
		return
	var gp := global_position
	var gz := gap_half_length()
	var pools: Array = []
	var block := int(6.0 / CELL)
	for bz in range(0, cover_image.get_height(), block):
		for bx in range(0, cover_image.get_width(), block):
			var lit := 0
			var sum := Vector3.ZERO
			for dz in block:
				for dx in block:
					var xi := bx + dx
					var zi := bz + dz
					if xi >= cover_image.get_width() or zi >= cover_image.get_height():
						continue
					var hgt := cover_height(xi, zi)
					if hgt < gp.y - 120.0 or hgt > gp.y - 2.0:
						continue
					var wx := cover_rect.position.x + (xi + 0.5) * CELL
					var wz := cover_rect.position.y + (zi + 0.5) * CELL
					if absf(wz - gp.z) > gz or absf(wx - gp.x) > shaft_half_width:
						continue
					if is_in_beam(wx, hgt):
						lit += 1
						sum += Vector3(wx, hgt, wz)
			if lit >= 30:
				var c := sum / lit
				pools.append([Vector4(c.x, c.y + 3.0, c.z, 8.0), Vector4(0.80, 0.90, 1.0, 0.65)])
	pools = pools.slice(0, 28)
	pool_count = pools.size()
	lamp_pools.extra = pools
	lamp_pools.apply()


## Low snow mounds (10-25 cm) along every drop edge and wall base of the surfaces under the gap.
func _add_mounds() -> void:
	var gp := global_position
	var gz := gap_half_length()
	var w := cover_image.get_width()
	var h := cover_image.get_height()
	var cands: Array = []
	for zi in range(2, h - 2, 2):
		for xi in range(2, w - 2, 2):
			var hgt := cover_height(xi, zi)
			if hgt < gp.y - 120.0 or hgt > gp.y - 2.0:
				continue
			var wx := cover_rect.position.x + (xi + 0.5) * CELL
			var wz := cover_rect.position.y + (zi + 0.5) * CELL
			if absf(wz - gp.z) > gz or absf(wx - gp.x) > shaft_half_width:
				continue
			for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				var nh := cover_height(xi + d.x, zi + d.y)
				if nh < hgt - 1.5 or nh > hgt + 2.0:
					cands.append(Vector3(wx, hgt, wz))
					break
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var kit := PropKit.new(0.0, 3)
	var count := 0
	for c: Vector3 in cands:
		if count >= 320 or rng.randf() > minf(1.0, 320.0 / maxf(cands.size(), 1.0) * 1.2):
			continue
		var r := rng.randf_range(0.35, 0.8)
		var hh := rng.randf_range(0.1, 0.25)
		var local := to_local(c)
		kit.blob(local + Vector3(0, hh * 0.25, 0), Vector3(r, hh, r * rng.randf_range(0.8, 1.4)), SNOW, rng)
		count += 1
	mound_count = count
	var old := get_node_or_null("Mounds")
	if old != null:
		old.free()
	if count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Mounds"
	mi.mesh = kit.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"prop_part", true)
	add_child(mi)
