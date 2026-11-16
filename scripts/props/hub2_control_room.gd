class_name Hub2ControlRoom
extends Node3D

# hub2's crane control room (docs/specs/hub2-control-room.md): the long box on room B's east wall, turned
# into the room the crane operators worked from. Place the node at the world origin. Everything is built
# in code (PropKit, vertex colour, drawn screens); nothing is saved into the scene.
#
#   cut_panes()   the six window quads of the map mesh (and any decals on them) are removed, visual only
#                 (collision stays solid), and a separate dirty-glass mesh takes their place
#   furniture     racks + breaker panel + cable trays (south), the long crane console with two stations
#                 and raised chairs, lockers and an extinguisher by the door, the yard-map board, comms
#                 and supervisor desks (north), fluorescent strips (mostly dead)
#   door          a steel bulkhead closes the corridor end of the entry stub; one SLIDE Hub2Door in it
#   power         emergency power: screens, LEDs and strips are lit; nothing is interactive but the door
#
# World space. Room interior x -72.4..-61.8 (slanted nose on the west side), z -83.1..-22.3, floor 43.56,
# ceiling 50.8. Entry: the gap in the east wall at z -44.33..-36.235, a 3.4 m stub to x -58.4.

const GLASS_SHADER := preload("res://shaders/hub2_glass.gdshader")
const SCREEN_SHADER := preload("res://shaders/hub2_screen.gdshader")

const FY := 43.561
const CEIL := 50.82
const X_EAST := -61.8
const Z_SOUTH := -83.1
const Z_NORTH := -22.3
const DOOR_X := -58.4
const DOOR_Z0 := -44.33
const DOOR_Z1 := -36.235
const DOOR_W := 1.8
const DOOR_H := 2.6

## Where the panes are: x of the two slants, z of the whole run, the y band of the lower / upper row.
## The whole west wall is glass (user, 2026-11-15): both slants, floor to ceiling, the full length. Rows split at the kink.
const PANE_X := Vector2(-72.5, -69.8)
const PANE_Z := Vector2(-83.2, -22.2)
const PANE_BANDS: Array[Vector2] = [Vector2(43.5, 47.2), Vector2(47.2, 50.85)]
const ROOM_BOX := AABB(Vector3(-73.0, 43.0, -84.0), Vector3(12.0, 9.0, 63.0))

const STEEL := Color(0.42, 0.44, 0.46)
const STEEL_DARK := Color(0.20, 0.21, 0.23)
const CONSOLE := Color(0.30, 0.34, 0.33)
const PLASTIC := Color(0.52, 0.51, 0.46)
const BLACK := Color(0.07, 0.07, 0.08)

## The imported map GLB instance (its window quads get cut).
@export var map: Node3D
## Hub2Wear, which must already have run (its baked meshes are what get cut).
@export var wear: Hub2Wear
## Gets the room's screen / strip glow as fixed light pools.
@export var lamp_pools: Hub2LampPools
@export_range(0.0, 1.0, 0.05) var wear_amount := 0.5
@export var omni_lights := true

var door: Hub2Door
var glass: MeshInstance3D
var furniture: MeshInstance3D
var furniture_body: StaticBody3D
var bulkhead_body: StaticBody3D
var cut_report: Dictionary = {}
var pane_tris := 0
var screen_count := 0

var _clean_meshes: Dictionary = {}   # instance ids of meshes known to hold no pane triangles
var _rng := RandomNumberGenerator.new()
var _screen_mats: Dictionary = {}
var _lamp_mats: Dictionary = {}
var _boxes: Array = []
var _lamps: Array = []     # [Vector4(x, y, z, radius), Vector4(r, g, b, strength)]


func _ready() -> void:
	_rng.seed = 6112
	cut_panes()
	_build_furniture()
	_build_bulkhead()
	_build_door()
	if omni_lights:
		_build_lights()
	_register_pools()
	_watch_cut()


# -- the windows -----------------------------------------------------------------------------------

## Which pane row (0 lower, 1 upper) the world triangle belongs to, or -1.
static func pane_row(a: Vector3, b: Vector3, c: Vector3) -> int:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return -1
	n = n.normalized()
	if absf(n.x) < 0.7:
		return -1
	var lo := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
	var hi := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
	if lo.x < PANE_X.x or hi.x > PANE_X.y or lo.z < PANE_Z.x or hi.z > PANE_Z.y:
		return -1
	if lo.y < PANE_BANDS[0].x or hi.y > PANE_BANDS[1].y:
		return -1
	return 0 if (a.y + b.y + c.y) / 3.0 < PANE_BANDS[0].y else 1


## Something (a late Hub2Wear swap, a look rig) can put an uncut mesh back over the wall: look again for a few
## seconds after load and cut again when pane triangles show up.
func _watch_cut() -> void:
	for i in 8:
		await get_tree().create_timer(0.5 + i * 0.5).timeout
		if not is_inside_tree():
			return
		ensure_cut()


## Cuts again when any map mesh near the room has pane triangles back. True when it had to.
func ensure_cut() -> bool:
	if map == null:
		return false
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# A mesh already cut / found clean is skipped: re-reading every vertex of the big map meshes cost ~170 ms
		# per call (hitches in the first ~18 s). Only a swapped-in mesh is new to us.
		if mi == null or mi.mesh == null or _clean_meshes.has(mi.mesh.get_instance_id()):
			continue
		if not (global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()).intersects(ROOM_BOX):
			continue
		if _strip_panes(mi.mesh, mi.global_transform, PackedVector3Array(), PackedInt32Array()) != null:
			push_warning("Hub2ControlRoom: window triangles were back in %s; cutting again." % mi.name)
			cut_panes()
			return true
		_clean_meshes[mi.mesh.get_instance_id()] = true
	return false


## Removes every pane triangle from the map's visual meshes (and its decals) and builds the glass from
## them. Collision is left alone, so the glass is solid. Returns how many triangles became glass.
func cut_panes() -> int:
	if map == null:
		push_warning("Hub2ControlRoom: no map assigned.")
		return 0
	var glass_tris := PackedVector3Array()
	var rows := PackedInt32Array()
	var meshes := 0
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var is_decals := mi.name == Hub2Wear.DECAL_NODE
		var world_box := global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		if not world_box.intersects(ROOM_BOX):
			continue
		var found := PackedVector3Array()
		var found_rows := PackedInt32Array()
		var cut := _strip_panes(mi.mesh, mi.global_transform, found, found_rows)
		if cut == null:
			_clean_meshes[mi.mesh.get_instance_id()] = true
			continue
		mi.mesh = cut
		_clean_meshes[cut.get_instance_id()] = true
		meshes += 1
		if not is_decals:
			glass_tris.append_array(found)
			rows.append_array(found_rows)
	cut_report = {"meshes": meshes, "tris": rows.size()}
	pane_tris = rows.size()
	if rows.size() > 0:
		if glass != null:
			glass.free()
			glass = null
		_build_glass(glass_tris, rows)
	return rows.size()


## `mesh` with every pane triangle collapsed / dropped; fills `found` with their world corners.
func _strip_panes(mesh: Mesh, to_world: Transform3D, found: PackedVector3Array, found_rows: PackedInt32Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	var to_room := global_transform.affine_inverse() * to_world
	var changed := false
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var fmt: int = mesh.surface_get_format(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		var indexed: bool = index != null and (index as PackedInt32Array).size() > 0
		var n := (index as PackedInt32Array).size() if indexed else verts.size()
		var keep_idx := PackedInt32Array()
		var i := 0
		while i + 2 < n:
			var ia := (index as PackedInt32Array)[i] if indexed else i
			var ib := (index as PackedInt32Array)[i + 1] if indexed else i + 1
			var ic := (index as PackedInt32Array)[i + 2] if indexed else i + 2
			var a := to_world * verts[ia]
			var b := to_world * verts[ib]
			var c := to_world * verts[ic]
			# pane_row works in the room's own frame, so the map can sit anywhere (hub.tscn offsets Hub2).
			var row := pane_row(to_room * verts[ia], to_room * verts[ib], to_room * verts[ic])
			if row >= 0:
				changed = true
				found.append(a)
				found.append(b)
				found.append(c)
				found_rows.append(row)
				if not indexed:
					# Collapse onto the first corner (zero area), every attribute stays aligned.
					verts[ib] = verts[ia]
					verts[ic] = verts[ia]
			elif indexed:
				keep_idx.append(ia)
				keep_idx.append(ib)
				keep_idx.append(ic)
			i += 3
		if indexed:
			arrays[Mesh.ARRAY_INDEX] = keep_idx
		arrays[Mesh.ARRAY_VERTEX] = verts
		var flags := 0
		for k in 4:
			flags |= fmt & (7 << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + 3 * k))
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
	if not changed:
		return null
	for k in mesh.get_meta_list():
		out.set_meta(k, mesh.get_meta(k))
	return out


func _build_glass(tris: PackedVector3Array, rows: PackedInt32Array) -> void:
	var inv := global_transform.affine_inverse()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var normals := PackedVector3Array()
	for t in rows.size():
		var band := PANE_BANDS[rows[t]]
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var nrm := (b - a).cross(c - a).normalized()
		for p in [a, b, c]:
			verts.append(inv * p)
			normals.append(nrm)
			cols.append(Color(clampf((p.y - band.x) / (band.y - band.x), 0.0, 1.0), 0, 0, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mesh.surface_set_material(0, mat)
	glass = MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = mesh
	# Casts shadow: the room stays as dim as it was with the opaque wall (the sun does not flood the desks).
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	glass.set_meta(&"prop_part", true)
	add_child(glass)


# -- screens + lamps ----------------------------------------------------------------------------------

## A shader material for a screen drawn from `kind` (an image) with an optional blink.
func _screen_mat(kind: String, blink := 0.0) -> ShaderMaterial:
	var key := "%s|%s" % [kind, blink]
	if _screen_mats.has(key):
		return _screen_mats[key]
	var m := ShaderMaterial.new()
	m.shader = SCREEN_SHADER
	m.set_shader_parameter(&"img", Hub2ControlRoomScreens.image(kind))
	m.set_shader_parameter(&"blink", blink)
	_screen_mats[key] = m
	return m


## A plain lit lamp / strip material: colour, blink Hz (0 steady), phase, flicker amount.
func _lamp_mat(c: Color, blink := 0.0, phase := 0.0, flick := 0.0) -> ShaderMaterial:
	var key := [c, blink, phase, flick]
	if _lamp_mats.has(key):
		return _lamp_mats[key]
	var m := ShaderMaterial.new()
	m.shader = SCREEN_SHADER
	m.set_shader_parameter(&"img", Hub2ControlRoomScreens.image("white"))
	m.set_shader_parameter(&"tint", c)
	m.set_shader_parameter(&"scan", 0.0)
	m.set_shader_parameter(&"brightness", 1.0)
	m.set_shader_parameter(&"blink", blink)
	m.set_shader_parameter(&"phase", phase)
	m.set_shader_parameter(&"flick", flick)
	_lamp_mats[key] = m
	return m


## A screen quad in frame `xf`: a bottom-left, b bottom-right, c top-right, d top-left, as seen from the front.
func _screen(kit: PropKit, kind: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, blink := 0.0) -> void:
	kit.screen_quad(xf * a, xf * b, xf * c, xf * d, kit.extra_surface(_screen_mat(kind, blink)))
	screen_count += 1


func _lamp(kit: PropKit, xf: Transform3D, lo: Vector3, hi: Vector3, mat: ShaderMaterial) -> void:
	kit.box(lo, hi, Color.WHITE, xf, false, kit.extra_surface(mat))


func _pool(p: Vector3, radius: float, c: Color, strength: float) -> void:
	_lamps.append([Vector4(p.x, p.y, p.z, radius), Vector4(c.r, c.g, c.b, strength)])


# -- furniture ----------------------------------------------------------------------------------------

func _solid(centre: Vector3, size: Vector3) -> void:
	_boxes.append([centre, size])


## World transform of a thing standing at `pos` whose local +Z faces yaw `yaw` (0 north +Z, PI/2 east +X).
static func _at(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func _build_furniture() -> void:
	var kit := PropKit.new(wear_amount, 5503)
	kit.floor_y = FY
	kit.grime_height = 1.5
	_equipment_bay(kit)
	_crane_console(kit)
	_entrance(kit)
	_supervisor_area(kit)
	_ceiling(kit)
	_mullions(kit)
	furniture = MeshInstance3D.new()
	furniture.name = "Furniture"
	furniture.mesh = kit.commit()
	furniture.set_meta(&"prop_part", true)
	add_child(furniture)
	furniture_body = StaticBody3D.new()
	furniture_body.name = "FurnitureBody"
	furniture_body.set_meta(&"prop_part", true)
	add_child(furniture_body)
	var i := 0
	for b: Array in _boxes:
		var cs := CollisionShape3D.new()
		cs.name = "Box%d" % i
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		furniture_body.add_child(cs)
		i += 1


## A CRT monitor in frame xf: housing, bezel, screen facing +Z. Origin = bottom centre of the foot.
func _crt(kit: PropKit, xf: Transform3D, kind: String, w := 0.78, h := 0.6, blink := 0.0) -> void:
	kit.box(Vector3(-0.2, 0.0, -0.2), Vector3(0.2, 0.06, 0.2), PLASTIC.darkened(0.2), xf)
	kit.box(Vector3(-w * 0.5, 0.06, -0.5), Vector3(w * 0.5, 0.06 + h, 0.06), PLASTIC, xf)
	kit.box(Vector3(-w * 0.35, 0.06 + h * 0.1, -0.7), Vector3(w * 0.35, 0.06 + h * 0.9, -0.5), PLASTIC.darkened(0.12), xf)
	kit.box(Vector3(-w * 0.5, 0.06, 0.06), Vector3(w * 0.5, 0.14, 0.09), BLACK, xf, false)
	_screen(kit, kind, xf, Vector3(-w * 0.5 + 0.05, 0.14, 0.092), Vector3(w * 0.5 - 0.05, 0.14, 0.092),
		Vector3(w * 0.5 - 0.05, 0.06 + h - 0.04, 0.092), Vector3(-w * 0.5 + 0.05, 0.06 + h - 0.04, 0.092), blink)


## A rack of equipment against the east wall, front facing west. Origin = floor, centre of its footprint.
func _rack(kit: PropKit, pos: Vector3, i: int) -> void:
	var xf := _at(pos, -PI * 0.5)
	kit.box(Vector3(-0.45, 0.0, -0.4), Vector3(0.45, 2.1, 0.4), STEEL_DARK, xf)
	kit.box(Vector3(-0.48, 2.1, -0.42), Vector3(0.48, 2.14, 0.42), STEEL, xf)
	kit.box(Vector3(-0.42, 0.1, 0.4), Vector3(0.42, 2.0, 0.42), Color(0.12, 0.13, 0.14), xf, false)
	var units := 9
	for u in units:
		var y0 := 0.14 + u * 0.205
		var tone := Color(0.30 + 0.05 * (u % 3), 0.31, 0.30)
		kit.box(Vector3(-0.4, y0, 0.42), Vector3(0.4, y0 + 0.17, 0.455), tone, xf)
		kit.box(Vector3(-0.38, y0 + 0.07, 0.455), Vector3(-0.18, y0 + 0.1, 0.46), Color(0.12, 0.12, 0.12), xf, false)   # drive slot
		var seed_i := (i * 7 + u * 3) % 5
		var lc: Color = [Color(0.2, 0.95, 0.35), Color(1.0, 0.65, 0.12), Color(0.2, 0.95, 0.35), Color(0.95, 0.15, 0.1), Color(0.3, 0.8, 1.0)][seed_i]
		var blink: float = [0.0, 1.7, 0.6, 2.4, 0.9][(i + u) % 5]
		var phase := float((i * 3 + u) % 7) / 7.0
		_lamp(kit, xf, Vector3(0.2, y0 + 0.05, 0.455), Vector3(0.26, y0 + 0.11, 0.47), _lamp_mat(lc, blink, phase))
		_lamp(kit, xf, Vector3(0.29, y0 + 0.05, 0.455), Vector3(0.35, y0 + 0.11, 0.47), _lamp_mat(Color(0.2, 0.95, 0.35), 0.0, 0.0))
	if i % 3 == 0:
		_screen(kit, "text", xf, Vector3(-0.3, 1.5, 0.475), Vector3(0.3, 1.5, 0.475), Vector3(0.3, 1.85, 0.475), Vector3(-0.3, 1.85, 0.475))
	_solid(pos + Vector3(0, 1.05, 0), Vector3(0.8, 2.1, 0.9))


func _equipment_bay(kit: PropKit) -> void:
	# Six racks along the east wall (x -62.7..-61.9), south to north.
	for i in 6:
		_rack(kit, Vector3(-62.3, FY, -81.6 + i * 1.9), i)
	# Breaker panel on the east wall past the last rack: a grey cabinet with rows of toggles + lamps.
	var bx0 := _at(Vector3(X_EAST - 0.02, FY, -69.6), -PI * 0.5)
	kit.box(Vector3(-0.8, 0.9, 0.0), Vector3(0.8, 2.7, 0.2), STEEL, bx0)
	var bx := bx0 * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.2))
	kit.box(Vector3(-0.72, 1.0, 0.0), Vector3(0.72, 2.6, 0.03), Color(0.30, 0.33, 0.32), bx)
	for r in 5:
		for c in 12:
			var x := -0.62 + c * 0.113
			var y := 1.12 + r * 0.26
			kit.box(Vector3(x, y, 0.03), Vector3(x + 0.07, y + 0.1, 0.06), BLACK, bx, false)
			if (r * 5 + c) % 4 != 1:
				kit.box(Vector3(x + 0.02, y + 0.1, 0.06), Vector3(x + 0.05, y + 0.15, 0.07), Color(0.7, 0.7, 0.66), bx, false)
	_lamp(kit, bx, Vector3(-0.6, 2.45, 0.03), Vector3(-0.5, 2.55, 0.05), _lamp_mat(Color(1.0, 0.15, 0.1), 1.2))
	_lamp(kit, bx, Vector3(-0.4, 2.45, 0.03), Vector3(-0.3, 2.55, 0.05), _lamp_mat(Color(0.2, 0.95, 0.35)))
	_lamp(kit, bx, Vector3(-0.2, 2.45, 0.03), Vector3(-0.1, 2.55, 0.05), _lamp_mat(Color(1.0, 0.65, 0.12), 0.5, 0.3))
	Hub2PieceBuild.paint_text(kit, "BREAKERS", Vector3(0.05, 2.44, 0.03), Vector3.RIGHT, Vector3.UP, 0.02, Color(0.85, 0.83, 0.75), bx)
	_solid(Vector3(X_EAST - 0.17, FY + 1.8, -69.6), Vector3(0.35, 1.8, 1.6))
	# Cable trays: along z over the racks, then across to the console, rods to the ceiling.
	var tray := Color(0.36, 0.37, 0.36)
	kit.box(Vector3(-62.8, 49.35, -83.0), Vector3(-62.2, 49.47, -69.0), tray)
	kit.box(Vector3(-62.8, 49.47, -83.0), Vector3(-62.74, 49.6, -69.0), tray)
	kit.box(Vector3(-62.26, 49.47, -83.0), Vector3(-62.2, 49.6, -69.0), tray)
	kit.box(Vector3(-69.0, 49.35, -75.5), Vector3(-62.2, 49.47, -75.0), tray)
	kit.box(Vector3(-68.8, 49.35, -83.0), Vector3(-68.2, 49.47, -46.0), tray)
	for z in range(-82, -46, 6):
		kit.tube(Vector3(-68.5, 49.47, float(z)), Vector3(-68.5, CEIL, float(z)), 0.025, STEEL_DARK, 4, Transform3D.IDENTITY, false)
	for z in range(-82, -70, 4):
		kit.tube(Vector3(-62.5, 49.6, float(z)), Vector3(-62.5, CEIL, float(z)), 0.025, STEEL_DARK, 4, Transform3D.IDENTITY, false)
	# Cable bundles in the trays and down to the console (one thick drop per station).
	for k in 5:
		var z0 := -82.5 + k * 2.8
		kit.tube(Vector3(-62.55 - 0.05 * k, 49.5, z0), Vector3(-62.45 + 0.05 * k, 49.5, z0 + 2.6), 0.05, BLACK, 5, Transform3D.IDENTITY, false)
	_pool(Vector3(-62.9, FY + 1.5, -77.0), 7.0, Color(0.3, 0.95, 0.5), 0.35)


## Profile of the console (x, height above the floor), operator side first. The panel slopes up away
## from the operator, the monitors stand on the back shelf.
const CONSOLE_PROFILE: Array[Vector2] = [
	Vector2(-68.0, 0.0), Vector2(-68.0, 0.78), Vector2(-68.7, 1.0), Vector2(-69.6, 1.0), Vector2(-69.6, 0.0),
]
const CONSOLE_Z := Vector2(-69.0, -47.0)


## Panel y at world x on the sloped part of the console.
static func _slope_y(x: float) -> float:
	return FY + 0.78 + clampf((-68.0 - x) / 0.7, 0.0, 1.0) * 0.22


func _facing_quad(kit: PropKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) < 0.0:
		kit.quad(d, c, b, a, col)
	else:
		kit.quad(a, b, c, d, col)


func _crane_console(kit: PropKit) -> void:
	var z0 := CONSOLE_Z.x
	var z1 := CONSOLE_Z.y
	var p: Array[Vector3] = []
	for pr in CONSOLE_PROFILE:
		p.append(Vector3(pr.x, FY + pr.y, 0.0))
	# Sides of the profile, extruded along z.
	var outs := [Vector3(1, 0, 0), Vector3(0.3, 1, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0)]
	for i in 4:
		var a := p[i]
		var b := p[i + 1]
		_facing_quad(kit, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), outs[i], CONSOLE if i != 1 else CONSOLE.lightened(0.04))
	# End caps (the profile polygon as a fan from the bottom-front corner).
	for zz in [z0, z1]:
		var out := Vector3(0, 0, -1.0 if zz == z0 else 1.0)
		for i in range(1, 4):
			var tri := [Vector3(p[0].x, p[0].y, zz), Vector3(p[i].x, p[i].y, zz), Vector3(p[i + 1].x, p[i + 1].y, zz)]
			var n := ((tri[1] - tri[0]) as Vector3).cross((tri[2] - tri[0]) as Vector3)
			if n.dot(out) > 0.0:
				kit.tri(tri[0], tri[1], tri[2], CONSOLE.darkened(0.2))
			else:
				kit.tri(tri[0], tri[2], tri[1], CONSOLE.darkened(0.2))
	# Kick plate along the foot, panel seams every 2 m on the operator face.
	kit.box(Vector3(-68.03, FY, z0), Vector3(-68.0, FY + 0.12, z1), BLACK, Transform3D.IDENTITY, false)
	var z := z0 + 2.0
	while z < z1:
		kit.box(Vector3(-68.012, FY + 0.12, z - 0.02), Vector3(-68.0, FY + 0.78, z + 0.02), CONSOLE.darkened(0.35), Transform3D.IDENTITY, false)
		z += 2.0
	_solid(Vector3(-68.8, FY + 0.5, (z0 + z1) * 0.5), Vector3(1.6, 1.0, z1 - z0))
	# Two crane stations, centres z -63.5 and -52.5, then the wings.
	var station_z := [-63.5, -52.5]
	for s in 2:
		_station(kit, station_z[s], s + 1)
	# West wing (z -69..-66): yard schematic + power; east wing (z -49.5..-47): alarm + switch banks.
	_wing_panels(kit)
	# Operator chairs, raised, one turned a little.
	_chair(kit, Vector3(-66.6, FY, station_z[0] + 0.3), PI * 0.5 + 0.2)
	_chair(kit, Vector3(-66.9, FY, station_z[1] - 0.4), PI * 0.5 - 0.35)
	# Foot rail the raised chairs sit behind.
	kit.box(Vector3(-67.3, FY, -69.0), Vector3(-67.2, FY + 0.08, -47.0), STEEL_DARK)
	_pool(Vector3(-68.0, FY + 1.6, -63.5), 6.0, Color(0.35, 1.0, 0.5), 0.45)
	_pool(Vector3(-68.0, FY + 1.6, -52.5), 6.0, Color(1.0, 0.68, 0.2), 0.45)


func _station(kit: PropKit, z: float, n: int) -> void:
	var top := FY + 1.0
	var kind := "crane%d" % n
	# Three monitors on the back shelf, the outer two toed in.
	for k in 3:
		var off := (k - 1) * 1.45
		var toe := (-(k - 1)) * 0.22
		_crt(kit, _at(Vector3(-69.05, top, z + off), PI * 0.5 + toe), kind if k == 1 else ("text" if k == 0 else "yard"), 0.84, 0.64)
	# Joystick pair on the sloped panel, near the operator edge.
	for js in [-0.85, 0.85]:
		var jx := -68.3
		var jy := _slope_y(jx)
		kit.box(Vector3(jx - 0.14, jy, z + js - 0.14), Vector3(jx + 0.14, jy + 0.05, z + js + 0.14), STEEL_DARK)
		kit.tube(Vector3(jx, jy + 0.05, z + js), Vector3(jx + 0.07, jy + 0.36, z + js), 0.035, BLACK, 5)
		kit.obox(Vector3(jx + 0.08, jy + 0.42, z + js), Vector3(0.07, 0.14, 0.09), BLACK, Basis(Vector3.BACK, -0.2))
		kit.box(Vector3(jx + 0.05, jy + 0.44, z + js - 0.045), Vector3(jx + 0.08, jy + 0.48, z + js - 0.02), Color(0.8, 0.12, 0.08), Transform3D.IDENTITY, false)
	# Button grid, 6 x 3, a few lit.
	for r in 3:
		for c in 6:
			var bx := -68.45 - r * 0.13
			var bz := z + 1.2 + c * 0.16
			var by := _slope_y(bx)
			var lit := (r * 6 + c + n) % 5 == 0
			var tone: Color = [Color(0.72, 0.62, 0.15), Color(0.55, 0.12, 0.1), Color(0.25, 0.35, 0.5), Color(0.5, 0.5, 0.46)][(r + c) % 4]
			kit.box(Vector3(bx - 0.045, by, bz - 0.055), Vector3(bx + 0.045, by + 0.04, bz + 0.055), tone, Transform3D.IDENTITY, false)
			if lit:
				_lamp(kit, Transform3D.IDENTITY, Vector3(bx - 0.03, by + 0.04, bz - 0.04), Vector3(bx + 0.03, by + 0.05, bz + 0.04), _lamp_mat(Color(0.3, 1.0, 0.45) if c % 2 == 0 else Color(1.0, 0.7, 0.2), 0.0 if c < 3 else 1.3, float(c) * 0.17))
	# Throttle levers left of the sticks.
	for k in 2:
		var lx := -68.3 - k * 0.2
		kit.box(Vector3(lx - 0.03, _slope_y(lx), z - 2.3), Vector3(lx + 0.03, _slope_y(lx) + 0.04, z - 1.7), STEEL_DARK)
		kit.obox(Vector3(lx, _slope_y(lx) + 0.15, z - 2.0 + k * 0.15), Vector3(0.05, 0.28, 0.06), Color(0.7, 0.12, 0.08), Basis(Vector3.BACK, 0.35))
	# Name plate hanging from the ceiling over the station, facing the operators (east).
	var px := 0.045
	var label := "CRANE %d" % n
	var tw := Hub2PieceBuild.text_width(label, px)
	kit.box(Vector3(-68.75, 49.1, z - 1.35), Vector3(-68.65, 49.75, z + 1.35), Color(0.20, 0.23, 0.24))
	kit.box(Vector3(-68.65, 49.1, z - 1.35), Vector3(-68.64, 49.15, z + 1.35), Hub2PieceBuild.SAFETY_YELLOW.darkened(0.2), Transform3D.IDENTITY, false)
	Hub2PieceBuild.paint_text(kit, label, Vector3(-68.64, 49.3, z + tw * 0.5), Vector3(0, 0, -1), Vector3.UP, px, Color(0.88, 0.85, 0.72))
	for rz in [-1.2, 1.2]:
		kit.tube(Vector3(-68.7, 49.75, z + rz), Vector3(-68.7, CEIL, z + rz), 0.02, STEEL_DARK, 4, Transform3D.IDENTITY, false)


func _wing_panels(kit: PropKit) -> void:
	# South wing: a wide yard-map screen and the power panel.
	var xf := _at(Vector3(-69.05, FY + 1.0, -67.3), PI * 0.5 + 0.18)
	_crt(kit, xf, "yard", 0.9, 0.7)
	_crt(kit, _at(Vector3(-69.05, FY + 1.0, -65.9), PI * 0.5 - 0.12), "power", 0.7, 0.55)
	# North wing: the alarm screen (flashing) and a bank of switches.
	_crt(kit, _at(Vector3(-69.05, FY + 1.0, -48.2), PI * 0.5 - 0.2), "alarm", 0.8, 0.62, 1.4)
	for r in 2:
		for c in 8:
			var bx := -68.55 - r * 0.2
			var bz := -50.4 + c * 0.17
			var by := _slope_y(bx)
			kit.box(Vector3(bx - 0.04, by, bz - 0.05), Vector3(bx + 0.04, by + 0.03, bz + 0.05), STEEL_DARK, Transform3D.IDENTITY, false)
			kit.obox(Vector3(bx, by + 0.07, bz), Vector3(0.03, 0.09, 0.03), Color(0.75, 0.74, 0.7), Basis(Vector3.BACK, 0.4 if (r + c) % 3 else -0.4), Transform3D.IDENTITY, false)
	_pool(Vector3(-68.5, FY + 1.6, -48.5), 4.5, Color(1.0, 0.12, 0.08), 0.5)


func _chair(kit: PropKit, pos: Vector3, yaw: float) -> void:
	var xf := _at(pos, yaw)
	var seat := Color(0.20, 0.25, 0.27)
	# Star base, pedestal, footring (raised chair).
	for k in 5:
		var a := TAU * k / 5.0
		kit.tube(Vector3(0, 0.12, 0), Vector3(cos(a) * 0.32, 0.06, sin(a) * 0.32), 0.025, STEEL_DARK, 4, xf, false)
	kit.tube(Vector3(0, 0.12, 0), Vector3(0, 0.78, 0), 0.04, STEEL_DARK, 6, xf, false)
	for k in 12:
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		kit.tube(Vector3(cos(a0) * 0.3, 0.4, sin(a0) * 0.3), Vector3(cos(a1) * 0.3, 0.4, sin(a1) * 0.3), 0.012, STEEL, 4, xf, false)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		kit.tube(Vector3(0, 0.55, 0), Vector3(cos(a) * 0.3, 0.4, sin(a) * 0.3), 0.012, STEEL, 4, xf, false)
	kit.box(Vector3(-0.25, 0.78, -0.25), Vector3(0.25, 0.86, 0.25), seat, xf)
	kit.box(Vector3(-0.23, 0.86, -0.28), Vector3(0.23, 1.38, -0.22), seat, xf)
	kit.box(Vector3(-0.3, 0.9, -0.2), Vector3(-0.26, 1.0, 0.15), STEEL_DARK, xf)   # armrests
	kit.box(Vector3(0.26, 0.9, -0.2), Vector3(0.30, 1.0, 0.15), STEEL_DARK, xf)


func _entrance(kit: PropKit) -> void:
	# Lockers on the east wall just north of the door, front facing into the room (west).
	var lx := _at(Vector3(X_EAST - 0.02 - 0.5, FY, -32.2), -PI * 0.5)
	# Local frame: front at z 0, depth to -0.5 (the wall side), width along x.
	kit.box(Vector3(-1.5, 0.0, -0.5), Vector3(1.5, 0.08, 0.0), BLACK, lx)
	kit.box(Vector3(-1.5, 0.08, -0.5), Vector3(1.5, 1.95, -0.47), Color(0.36, 0.42, 0.44).darkened(0.3), lx)
	kit.box(Vector3(-1.5, 1.92, -0.5), Vector3(1.5, 1.98, 0.0), Color(0.36, 0.42, 0.44), lx)
	for i in 7:
		var x := -1.5 + i * 0.5
		kit.box(Vector3(x - 0.015, 0.08, -0.5), Vector3(x + 0.015, 1.92, 0.0), Color(0.36, 0.42, 0.44), lx)
	for i in 6:
		var x := -1.5 + i * 0.5
		kit.box(Vector3(x + 0.02, 0.08, -0.47), Vector3(x + 0.48, 1.92, -0.46), Color(0.10, 0.10, 0.10), lx, false)
		var open := i == 2 or i == 5
		var xd := Transform3D(Basis(Vector3.UP, -0.0 if not open else -1.1), Vector3(x + 0.02, 0, 0.0))
		kit.box(Vector3(0, 0.1, 0.0), Vector3(0.46, 1.9, 0.025), Color(0.38, 0.44, 0.46), lx * xd)
		kit.box(Vector3(0.12, 1.6, 0.025), Vector3(0.34, 1.66, 0.03), BLACK, lx * xd, false)
		Hub2PieceBuild.paint_text(kit, str(i + 1), Vector3(0.18, 1.3, 0.03), Vector3.RIGHT, Vector3.UP, 0.03, Color(0.85, 0.85, 0.8), lx * xd)
	_solid(Vector3(X_EAST - 0.27, FY + 1.0, -32.2), Vector3(0.5, 2.0, 3.0))
	# Fire extinguisher on the wall south of the door (a stock hub2 prop, faces west).
	var ext := Hub2Prop.new()
	ext.name = "Extinguisher"
	ext.kind = Hub2Prop.Kind.EXTINGUISHER
	ext.wear = wear_amount
	ext.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(X_EAST - 0.02, FY, -45.1))
	add_child(ext)


func _supervisor_area(kit: PropKit) -> void:
	# Lit yard-map board on the north wall (x -69.0..-63.2 is the usable wall at eye height).
	var bx := _at(Vector3(-66.1, FY, Z_NORTH - 0.02), PI)
	kit.box(Vector3(-2.9, 1.2, 0.0), Vector3(2.9, 3.7, 0.06), STEEL_DARK, bx)
	kit.box(Vector3(-2.75, 1.35, 0.06), Vector3(2.75, 3.55, 0.1), Color(0.05, 0.06, 0.06), bx, false)
	_screen(kit, "board", bx, Vector3(-2.7, 1.4, 0.102), Vector3(2.7, 1.4, 0.102), Vector3(2.7, 3.5, 0.102), Vector3(-2.7, 3.5, 0.102))
	Hub2PieceBuild.paint_text(kit, "YARD B", Vector3(1.2, 3.62, 0.06), Vector3.RIGHT, Vector3.UP, 0.05, Color(0.85, 0.83, 0.75), bx)
	_pool(Vector3(-66.1, FY + 2.5, Z_NORTH - 1.2), 7.0, Color(0.45, 0.85, 0.7), 0.5)
	# Supervisor desk facing the board (they sit on its south side), one monitor facing them.
	var dk := Color(0.46, 0.46, 0.43)
	kit.box(Vector3(-67.1, 0.72 + FY, -28.3), Vector3(-65.3, 0.76 + FY, -27.5), dk)
	kit.box(Vector3(-67.05, FY, -28.25), Vector3(-67.0, FY + 0.72, -27.55), dk.darkened(0.15))
	kit.box(Vector3(-65.4, FY, -28.25), Vector3(-65.35, FY + 0.72, -27.55), dk.darkened(0.15))
	kit.box(Vector3(-67.0, FY + 0.3, -27.58), Vector3(-65.4, FY + 0.72, -27.55), dk.darkened(0.2))
	kit.box(Vector3(-65.95, FY + 0.05, -28.25), Vector3(-65.4, FY + 0.72, -27.6), dk.darkened(0.1))
	_crt(kit, _at(Vector3(-66.6, FY + 0.76, -27.8), PI - 0.15), "crane1", 0.7, 0.55)
	for k in 4:
		kit.obox(Vector3(-65.8 + k * 0.1, FY + 0.765, -28.05 - k * 0.04), Vector3(0.21, 0.004, 0.3), Color(0.82, 0.8, 0.72), Basis(Vector3.UP, 0.5 + k * 0.9), Transform3D.IDENTITY, false)
	_solid(Vector3(-66.2, FY + 0.4, -27.9), Vector3(1.9, 0.8, 0.9))
	_chair_plain(kit, Vector3(-66.4, FY, -29.3), 0.0)
	# Comms desk against the east wall with a radio rack and a coiled handset.
	var cx := _at(Vector3(X_EAST - 0.02, FY, -26.4), -PI * 0.5)
	kit.box(Vector3(-0.9, 0.74, 0.0), Vector3(0.9, 0.78, 0.8), dk, cx)
	kit.box(Vector3(-0.88, 0.0, 0.02), Vector3(-0.84, 0.74, 0.78), dk.darkened(0.15), cx)
	kit.box(Vector3(0.84, 0.0, 0.02), Vector3(0.88, 0.74, 0.78), dk.darkened(0.15), cx)
	kit.box(Vector3(-0.88, 0.05, 0.0), Vector3(0.88, 0.74, 0.04), dk.darkened(0.2), cx)
	kit.box(Vector3(-0.7, 0.78, 0.08), Vector3(0.05, 1.5, 0.4), Color(0.18, 0.19, 0.2), cx)
	for u in 4:
		kit.box(Vector3(-0.66, 0.84 + u * 0.17, 0.4), Vector3(0.01, 0.97 + u * 0.17, 0.43), Color(0.3, 0.31, 0.3), cx)
		_lamp(kit, cx, Vector3(-0.1, 0.88 + u * 0.17, 0.43), Vector3(-0.04, 0.93 + u * 0.17, 0.45), _lamp_mat([Color(0.2, 0.95, 0.35), Color(1.0, 0.65, 0.12)][u % 2], 0.8 + u * 0.4, u * 0.23))
	_screen(kit, "text", cx, Vector3(-0.6, 1.2, 0.432), Vector3(-0.2, 1.2, 0.432), Vector3(-0.2, 1.45, 0.432), Vector3(-0.6, 1.45, 0.432))
	kit.box(Vector3(0.3, 0.78, 0.25), Vector3(0.5, 0.86, 0.45), BLACK, cx)         # handset cradle
	kit.obox(Vector3(0.4, 0.9, 0.35), Vector3(0.05, 0.05, 0.22), BLACK, Basis(Vector3.UP, 0.3), cx)
	kit.tube(Vector3(0.4, 0.8, 0.5), Vector3(0.3, 0.76, 0.7), 0.012, BLACK, 4, cx, false)
	_solid(Vector3(X_EAST - 0.4, FY + 0.75, -26.4), Vector3(0.8, 1.5, 1.8))
	_chair_plain(kit, Vector3(-64.4, FY, -26.3), PI * 0.5 + 0.3)
	# Filing cabinet in the north-east corner.
	var fx := _at(Vector3(-62.4, FY, -23.0), -PI * 0.5)
	kit.box(Vector3(-0.3, 0.0, -0.3), Vector3(0.3, 1.35, 0.3), Color(0.40, 0.42, 0.40), fx)
	for k in 3:
		kit.box(Vector3(-0.27, 0.06 + k * 0.42, 0.3), Vector3(0.27, 0.4 + k * 0.42, 0.32), Color(0.44, 0.46, 0.44), fx)
		kit.box(Vector3(-0.08, 0.22 + k * 0.42, 0.32), Vector3(0.08, 0.26 + k * 0.42, 0.35), STEEL_DARK, fx)
	_solid(Vector3(-62.4, FY + 0.68, -23.0), Vector3(0.6, 1.36, 0.6))


func _chair_plain(kit: PropKit, pos: Vector3, yaw: float) -> void:
	var xf := _at(pos, yaw)
	var c := Color(0.25, 0.30, 0.33)
	kit.box(Vector3(-0.22, 0.44, -0.22), Vector3(0.22, 0.48, 0.22), c, xf)
	kit.box(Vector3(-0.22, 0.48, -0.24), Vector3(0.22, 0.9, -0.2), c, xf)
	for x in [-0.19, 0.19]:
		for zz in [-0.19, 0.19]:
			kit.box(Vector3(x - 0.015, 0.0, zz - 0.015), Vector3(x + 0.015, 0.44, zz + 0.015), STEEL_DARK, xf)


## Steel ribs and rails holding the glass wall: a rib every ~5 m up both slants, a rail along the kink, the
## foot and the top.
func _mullions(kit: PropKit) -> void:
	var rib := Color(0.30, 0.32, 0.33)
	var foot := Vector3(-69.84, FY, 0.0)
	var kink := Vector3(-72.36, 47.2, 0.0)
	var top := Vector3(-69.84, CEIL - 0.02, 0.0)
	for k in 13:
		var z := Z_SOUTH + 0.1 + k * (Z_NORTH - Z_SOUTH - 0.2) / 12.0
		kit.tube(Vector3(foot.x, foot.y, z), Vector3(kink.x, kink.y, z), 0.07, rib, 4, Transform3D.IDENTITY, false)
		kit.tube(Vector3(kink.x, kink.y, z), Vector3(top.x, top.y, z), 0.07, rib, 4, Transform3D.IDENTITY, false)
	for pair in [[foot, foot], [kink, kink], [top, top]]:
		var p: Vector3 = pair[0]
		kit.tube(Vector3(p.x, p.y, Z_SOUTH + 0.1), Vector3(p.x, p.y, Z_NORTH - 0.1), 0.09, rib, 4, Transform3D.IDENTITY, false)


## Overhead fluorescent strips: mostly dead, a few lit (one flickers).
func _ceiling(kit: PropKit) -> void:
	var strips := [
		[-80.0, false], [-74.5, false], [-66.0, true], [-60.0, false], [-54.0, false], [-47.5, true],
		[-33.0, false], [-29.0, true], [-24.5, false],
	]
	var i := 0
	for s: Array in strips:
		var z: float = s[0]
		var lit: bool = s[1]
		for x in [-66.3]:
			kit.box(Vector3(x - 0.12, 50.42, z - 0.7), Vector3(x + 0.12, 50.5, z + 0.7), STEEL_DARK)
			var tube_lo := Vector3(x - 0.07, 50.38, z - 0.62)
			var tube_hi := Vector3(x + 0.07, 50.42, z + 0.62)
			if lit:
				_lamp(kit, Transform3D.IDENTITY, tube_lo, tube_hi, _lamp_mat(Color(0.82, 0.95, 1.0), 0.0, float(i) * 0.37, 0.8 if i == 2 else 0.0))
				_pool(Vector3(x, 49.5, z), 6.5, Color(0.7, 0.88, 1.0), 0.5)
			else:
				kit.box(tube_lo, tube_hi, Color(0.30, 0.31, 0.30), Transform3D.IDENTITY, false)
			for rz in [-0.5, 0.5]:
				kit.tube(Vector3(x, 50.42, z + rz), Vector3(x, CEIL, z + rz), 0.012, STEEL_DARK, 4, Transform3D.IDENTITY, false)
		i += 1


# -- the door -----------------------------------------------------------------------------------------

func _build_bulkhead() -> void:
	var kit := PropKit.new(wear_amount, 5517)
	kit.floor_y = FY
	kit.cell = 1.0
	var c := Color(0.40, 0.42, 0.43)
	var x0 := DOOR_X - 0.15
	var x1 := DOOR_X + 0.15
	var zc := (DOOR_Z0 + DOOR_Z1) * 0.5
	var dl := zc - DOOR_W * 0.5
	var dr := zc + DOOR_W * 0.5
	var dh := FY + DOOR_H
	kit.box(Vector3(x0, FY, DOOR_Z0), Vector3(x1, CEIL, dl), c)
	kit.box(Vector3(x0, FY, dr), Vector3(x1, CEIL, DOOR_Z1), c)
	kit.box(Vector3(x0, dh, dl), Vector3(x1, CEIL, dr), c)
	# Bare wall otherwise: with the leaf at the wall's middle the opening is a plain recess.
	# The slab wears the map's own world-space wall shader (zone paint, panel seams) so it reads as more of
	# the corridor / room walls, not a separate prop.
	bulkhead_body = StaticBody3D.new()
	bulkhead_body.name = "BulkheadBody"
	bulkhead_body.set_meta(&"prop_part", true)
	add_child(bulkhead_body)
	var parts: Array = [
		[Vector3(DOOR_X, (FY + CEIL) * 0.5, (DOOR_Z0 + dl) * 0.5), Vector3(0.3, CEIL - FY, dl - DOOR_Z0)],
		[Vector3(DOOR_X, (FY + CEIL) * 0.5, (dr + DOOR_Z1) * 0.5), Vector3(0.3, CEIL - FY, DOOR_Z1 - dr)],
		[Vector3(DOOR_X, (dh + CEIL) * 0.5, zc), Vector3(0.3, CEIL - dh, DOOR_W)],
	]
	var i := 0
	for b: Array in parts:
		var cs := CollisionShape3D.new()
		cs.name = "Box%d" % i
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		bulkhead_body.add_child(cs)
		i += 1
	var mi := MeshInstance3D.new()
	mi.name = "Bulkhead"
	mi.mesh = kit.commit()
	mi.material_override = _wall_material()
	mi.set_meta(&"prop_part", true)
	add_child(mi)

	# Simple frame: a near-black steel surround round the opening, proud of the wall on both faces, so the
	# door reads from across the room. Its own mesh: the wall shader above ignores vertex colours.
	var fk := PropKit.new(0.0, 5518)
	var fc := Color(0.40, 0.42, 0.43)
	var fw := 0.14
	var fx0 := DOOR_X - 0.19
	var fx1 := DOOR_X + 0.19
	# Inner edges stand 3 cm into the opening: flush with the slab's reveal faces they z-fought with the wall.
	var fi := 0.03
	fk.box(Vector3(fx0, FY, dl - fw), Vector3(fx1, dh + fw, dl + fi), fc)
	fk.box(Vector3(fx0, FY, dr - fi), Vector3(fx1, dh + fw, dr + fw), fc)
	fk.box(Vector3(fx0, dh - fi, dl + fi), Vector3(fx1, dh + fw, dr - fi), fc)
	var fm := MeshInstance3D.new()
	fm.name = "DoorFrame"
	fm.mesh = fk.commit()
	var mat := _grey_material(0.7)
	fm.material_override = mat
	fm.set_meta(&"prop_part", true)
	add_child(fm)


## Floor-to-first-seam height of the oxide band on the corridor's side walls (the shader's 15 m zone rows).
const BAND_Y := 45.0

## hub2's baked wall shader material, set to paint like the corridor's side walls (oxide below BAND_Y, teal
## above); null when Hub2Wear hasn't run (the vertex colours show instead). `tone` < 1 darkens it (the leaf).
func _wall_material(tone := 1.0) -> Material:
	if wear == null or wear.surface_material == null:
		return null
	var m := wear.surface_material.duplicate() as ShaderMaterial
	m.set_shader_parameter(&"force_paint", 1)
	m.set_shader_parameter(&"force_split_y", BAND_Y)
	m.set_shader_parameter(&"tone", tone)
	return m


## The wall's own shader forced to plain grey steel (no zone paint: it would turn the door red below the band).
## `tone` < 1 darkens it. Falls back to a flat grey when Hub2Wear hasn't run.
func _grey_material(tone := 1.0) -> Material:
	if wear != null and wear.surface_material != null:
		var m := wear.surface_material.duplicate() as ShaderMaterial
		m.set_shader_parameter(&"force_paint", 0)
		m.set_shader_parameter(&"force_steel", 1)
		m.set_shader_parameter(&"tone", tone)
		return m
	var f := StandardMaterial3D.new()
	f.albedo_color = Color(0.40, 0.42, 0.43) * tone
	f.roughness = 0.8
	return f


func _build_door() -> void:
	door = Hub2Door.new()
	door.name = "ControlDoor"
	door.type = Hub2Door.Type.SLIDE
	door.keypad = 1
	door.wear = wear_amount
	door.surface_material = _grey_material()
	# Local +Z faces the corridor (east, +X): the leaf slides toward -Z along the wall.
	door.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(DOOR_X, FY, (DOOR_Z0 + DOOR_Z1) * 0.5))
	door.set_meta(&"prop_part", true)
	add_child(door)


# -- light ---------------------------------------------------------------------------------------------

func _build_lights() -> void:
	# A few dim real lights: cold from the lit strips, amber / green from the screens. No shadows.
	var rig := [
		[Vector3(-66.3, 49.6, -66.0), Color(0.75, 0.9, 1.0), 0.55, 9.0],
		[Vector3(-66.3, 49.6, -47.5), Color(0.75, 0.9, 1.0), 0.5, 9.0],
		[Vector3(-66.3, 49.6, -29.0), Color(0.75, 0.9, 1.0), 0.5, 9.0],
		[Vector3(-68.0, FY + 1.9, -63.5), Color(0.35, 1.0, 0.5), 0.35, 5.0],
		[Vector3(-68.0, FY + 1.9, -52.5), Color(1.0, 0.7, 0.25), 0.35, 5.0],
		[Vector3(-68.6, FY + 1.9, -48.5), Color(1.0, 0.15, 0.1), 0.3, 4.0],
		[Vector3(-63.0, FY + 1.6, -77.0), Color(0.3, 0.95, 0.5), 0.3, 6.0],
	]
	var i := 0
	for r: Array in rig:
		var l := OmniLight3D.new()
		l.name = "Light%d" % i
		l.position = r[0]
		l.light_color = r[1]
		l.light_energy = r[2]
		l.omni_range = r[3]
		l.shadow_enabled = false
		l.set_meta(&"prop_part", true)
		add_child(l)
		i += 1


func _register_pools() -> void:
	if lamp_pools == null:
		return
	lamp_pools.keep_out.append(global_transform * ROOM_BOX)
	lamp_pools.fixed.append_array(_lamps)
	lamp_pools.apply.call_deferred()
