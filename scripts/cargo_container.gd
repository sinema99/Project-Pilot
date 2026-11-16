@tool
class_name CargoContainer
extends StaticBody3D

# A 20 ft shipping container: solid, static decoration for the hub2 map. Built in code from a
# `palette` preset; pick it in the inspector and the editor viewport recolours live.
# See docs/specs/cargo-container.md.
#
# The mesh is one ArrayMesh with vertex colours (corrugated sides and roof, frame rails, corner
# castings with bolt holes, door rods and handles at the +X end, a plain panel at the -X end). It
# carries no textures and no UVs: under the AIRFRAME look the vertex-colour material is cut into
# 16-texel-per-metre pixels like the rest of the level. The collision is ONE box round the shell.
#
# Origin: bottom centre. Length runs along X, doors at +X, width along Z, up is Y.
# Like ApplyStylized this builds children in code with no owner, so none of it is saved in a scene.

enum Palette {
	ORANGE_RED, BLUE, PALE_YELLOW, TEAL, BLACK, PINK, BROWN, ORANGE, GREY, CYAN,
}

## Base colour of each preset (sRGB), read off the reference image.
const BASES := {
	Palette.ORANGE_RED: Color(0.80, 0.30, 0.12),
	Palette.BLUE: Color(0.20, 0.26, 0.86),
	Palette.PALE_YELLOW: Color(0.78, 0.78, 0.44),
	Palette.TEAL: Color(0.14, 0.62, 0.48),
	Palette.BLACK: Color(0.13, 0.13, 0.16),
	Palette.PINK: Color(0.92, 0.58, 0.64),   # kept off pure magenta: PixelWorld keys r,b high + g low as its character marker
	Palette.BROWN: Color(0.40, 0.26, 0.10),
	Palette.ORANGE: Color(0.86, 0.45, 0.12),
	Palette.GREY: Color(0.58, 0.58, 0.60),
	Palette.CYAN: Color(0.38, 0.70, 0.82),
}

## A standard 20 ft container, metres.
const LENGTH := 6.058
const WIDTH := 2.438
const HEIGHT := 2.591

const RAIL := Color(0.15, 0.15, 0.17)
const BOLT := Color(0.02, 0.02, 0.03)
const RIB_PITCH := 0.30
const RIB_WIDTH := 0.16
const FRAME := 0.12     # frame rail thickness
const SKIRT := 0.16     # dark base rail height

@export var palette: Palette = Palette.ORANGE_RED:
	set(value):
		palette = value
		if _built:
			_rebuild()

## Weathering painted into the vertex colours (docs/specs/hub2-storage.md): 0 = clean (default),
## 1 = abandoned for decades. hub2 sets it worn.
@export_range(0.0, 1.0, 0.05) var wear := 0.0:
	set(value):
		wear = value
		if _built:
			_rebuild()
## Picks one of a few weathering patterns so worn boxes of one colour differ.
@export_range(0, 3) var wear_seed := 0:
	set(value):
		wear_seed = value
		if _built:
			_rebuild()

var _built := false
## Palette -> shared ArrayMesh (ten containers of one colour build the mesh once).
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D


func _ready() -> void:
	_built = true
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta(&"cargo_part"):
			child.free()
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh_for(palette) if wear <= 0.0 else worn_mesh_for(palette, wear, wear_seed)
	visual.visibility_range_end = 120.0
	visual.set_meta(&"cargo_part", true)
	add_child(visual)
	var shape := CollisionShape3D.new()
	shape.name = "Shell"
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTH, HEIGHT, WIDTH)
	shape.shape = box
	shape.position.y = HEIGHT * 0.5
	shape.set_meta(&"cargo_part", true)
	add_child(shape)


## The container mesh for a preset, one shared copy per colour.
static func mesh_for(p: Palette) -> ArrayMesh:
	if _meshes.has(p):
		return _meshes[p]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build(st, BASES[p])
	var mesh := st.commit()
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
		_material.metallic_specular = 0.0
	mesh.surface_set_material(0, _material)
	_meshes[p] = mesh
	return mesh


## A weathered copy of the preset's mesh: every vertex colour run through PropKit.weather (fade,
## rust blotches, rust on the frame ends and edges, grime up from the floor). Shared per settings.
static func worn_mesh_for(p: Palette, w: float, s: int) -> ArrayMesh:
	var key := [p, snappedf(w, 0.05), s]
	if _meshes.has(key):
		return _meshes[key]
	var made := PropMeshCache.fetch("cargo", [p, snappedf(w, 0.05), s], func() -> Dictionary: return {"mesh": _build_worn(p, w, s), "boxes": []})
	_meshes[key] = made["mesh"]
	return made["mesh"]


static func _build_worn(p: Palette, w: float, s: int) -> ArrayMesh:
	var src := mesh_for(p)
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var kit := PropKit.new(w, 9001 + s * 77 + int(p) * 5)
	kit.grime_height = 0.9
	var hx := LENGTH * 0.5
	for i in verts.size():
		var v := verts[i]
		var edge := 0.0
		edge = maxf(edge, 1.0 - (hx - absf(v.x)) / 0.4)
		edge = maxf(edge, 1.0 - (HEIGHT - v.y) / 0.3)
		if v.y < 0.4:
			edge = maxf(edge, 1.0 - v.y / 0.4)
		cols[i] = kit.weather(cols[i].linear_to_srgb(), v, clampf(edge, 0.0, 1.0)).srgb_to_linear()
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, src.surface_get_material(0))
	return mesh


# -- geometry --------------------------------------------------------------------------------

static func _build(st: SurfaceTool, base_srgb: Color) -> void:
	var base := base_srgb
	var light := base.lerp(Color.WHITE, 0.28)
	var dark := base.darkened(0.38)
	var casting := base.darkened(0.14)
	var rod := Color(0.60, 0.60, 0.63)
	if base.get_luminance() < 0.2:
		rod = Color(0.36, 0.36, 0.40)
	elif base.get_luminance() > 0.5 and absf(base.r - base.g) < 0.05:
		rod = Color(0.36, 0.36, 0.40)   # the grey box gets dark rods so they read
	var hx := LENGTH * 0.5
	var hz := WIDTH * 0.5
	var top := HEIGHT

	# Dark base rail and the shell core (the corrugation valleys).
	_box(st, Vector3(-hx, 0.0, -hz + 0.05), Vector3(hx, SKIRT, hz - 0.05), RAIL)
	_box(st, Vector3(-hx + 0.02, SKIRT, -hz + 0.08), Vector3(hx - 0.02, top - 0.07, hz - 0.08), dark)

	# Side ribs: vertical, base colour with a lit stripe down one edge.
	var ribs := int(floor((LENGTH - 0.4) / RIB_PITCH))
	var x0 := -(ribs - 1) * RIB_PITCH * 0.5
	for side in [-1.0, 1.0]:
		for i in ribs:
			var cx := x0 + i * RIB_PITCH
			var z_in: float = side * (hz - 0.08)
			var z_out: float = side * (hz - 0.02)
			var lo := Vector3(cx - RIB_WIDTH * 0.5, SKIRT + 0.14, minf(z_in, z_out))
			var hi := Vector3(cx + RIB_WIDTH * 0.5, top - FRAME - 0.02, maxf(z_in, z_out))
			_box(st, lo, hi, base)
			var stripe_lo := Vector3(cx - RIB_WIDTH * 0.5, lo.y, minf(z_in, z_out + side * 0.01))
			var stripe_hi := Vector3(cx - RIB_WIDTH * 0.5 + 0.045, hi.y, maxf(z_in, z_out + side * 0.01))
			_box(st, stripe_lo, stripe_hi, light)

	# Roof ribs: across the width, base colour with a lit stripe on the leading edge.
	for i in ribs:
		var cx := x0 + i * RIB_PITCH
		_box(st, Vector3(cx - RIB_WIDTH * 0.5, top - 0.07, -hz + FRAME), Vector3(cx + RIB_WIDTH * 0.5, top - 0.01, hz - FRAME), base)
		_box(st, Vector3(cx - RIB_WIDTH * 0.5, top - 0.07, -hz + FRAME), Vector3(cx - RIB_WIDTH * 0.5 + 0.045, top, hz - FRAME), light)

	# Long rails, top and bottom, both sides.
	for side in [-1.0, 1.0]:
		var za: float = side * (hz - FRAME)
		var zb: float = side * hz
		var zlo := minf(za, zb)
		var zhi := maxf(za, zb)
		_box(st, Vector3(-hx, top - FRAME, zlo), Vector3(hx, top, zhi), base)
		_box(st, Vector3(-hx, SKIRT, zlo), Vector3(hx, SKIRT + 0.14, zhi), base)

	# End frames: top and bottom beams, corner posts, at both ends.
	for end in [-1.0, 1.0]:
		var xa: float = end * (hx - FRAME)
		var xb: float = end * hx
		var xlo := minf(xa, xb)
		var xhi := maxf(xa, xb)
		_box(st, Vector3(xlo, top - FRAME, -hz), Vector3(xhi, top, hz), base)
		_box(st, Vector3(xlo, SKIRT, -hz), Vector3(xhi, SKIRT + 0.14, hz), base)
		for side in [-1.0, 1.0]:
			var za: float = side * (hz - FRAME)
			var zb: float = side * hz
			_box(st, Vector3(xlo, SKIRT, minf(za, zb)), Vector3(xhi, top, maxf(za, zb)), base)

	# Corner castings with bolt holes on their end, side and top/bottom faces.
	var c := 0.17
	for ex in [-1.0, 1.0]:
		for ez in [-1.0, 1.0]:
			for ey in [0, 1]:
				var cy0 := 0.0 if ey == 0 else top - c
				var xlo: float = minf(ex * hx, ex * (hx - c))
				var xhi: float = maxf(ex * hx, ex * (hx - c))
				var zlo: float = minf(ez * hz, ez * (hz - c))
				var zhi: float = maxf(ez * hz, ez * (hz - c))
				_box(st, Vector3(xlo, cy0, zlo), Vector3(xhi, cy0 + c, zhi), casting)
				var hole := 0.07
				var hy := cy0 + c * 0.5 - hole * 0.5
				# end face (+-X)
				var fx: float = ex * hx
				_box(st, Vector3(fx - 0.004 if ex > 0.0 else fx - 0.006, hy, ez * (hz - c * 0.5) - hole * 0.5),
					Vector3(fx + 0.006 if ex > 0.0 else fx + 0.004, hy + hole, ez * (hz - c * 0.5) + hole * 0.5), BOLT)
				# side face (+-Z)
				var fz: float = ez * hz
				_box(st, Vector3(ex * (hx - c * 0.5) - hole * 0.5, hy, fz - 0.004 if ez > 0.0 else fz - 0.006),
					Vector3(ex * (hx - c * 0.5) + hole * 0.5, hy + hole, fz + 0.006 if ez > 0.0 else fz + 0.004), BOLT)
				# top (or bottom) face
				var fy := top if ey == 1 else 0.0
				_box(st, Vector3(ex * (hx - c * 0.5) - hole * 0.5, fy - 0.004 if ey == 1 else fy - 0.006, ez * (hz - c * 0.5) - hole * 0.5),
					Vector3(ex * (hx - c * 0.5) + hole * 0.5, fy + 0.006 if ey == 1 else fy + 0.004, ez * (hz - c * 0.5) + hole * 0.5), BOLT)

	# Door end (+X): two doors with horizontal bands, a dark centre gap, locking rods and handles.
	var dx0 := hx - 0.10
	var dx1 := hx - 0.055
	var door_lo := SKIRT + 0.14
	var door_hi := top - FRAME
	var half := hz - FRAME
	_box(st, Vector3(dx0, door_lo, -half), Vector3(dx1, door_hi, half), dark)
	for side in [-1.0, 1.0]:
		var za: float = side * 0.02
		var zb: float = side * half
		var zlo := minf(za, zb)
		var zhi := maxf(za, zb)
		var y := door_lo + 0.12
		while y < door_hi - 0.2:
			_box(st, Vector3(dx0, y, zlo), Vector3(dx1 + 0.012, y + 0.07, zhi), base)
			_box(st, Vector3(dx0, y + 0.07, zlo), Vector3(dx1 + 0.012, y + 0.10, zhi), light)
			y += 0.34
		# Locking rods (two per door) and their handles.
		var centre: float = side * (0.02 + (half - 0.02) * 0.5)
		for k in [-1.0, 1.0]:
			var rz: float = centre + k * 0.24
			_box(st, Vector3(dx1 - 0.01, 0.20, rz - 0.03), Vector3(dx1 + 0.05, top - 0.06, rz + 0.03), rod)
			for hy in [0.62, 1.20, 1.78]:
				var dirn: float = -k
				_box(st, Vector3(dx1 + 0.05, hy, minf(rz, rz + dirn * 0.18)), Vector3(dx1 + 0.09, hy + 0.05, maxf(rz, rz + dirn * 0.18)), rod)
	# Dark gap between the doors.
	_box(st, Vector3(dx0, door_lo, -0.02), Vector3(dx1 + 0.002, door_hi, 0.02), RAIL)

	# Plain end (-X): a dark panel with horizontal ribs.
	var px0 := -hx + 0.055
	var px1 := -hx + 0.10
	_box(st, Vector3(px0, door_lo, -half), Vector3(px1, door_hi, half), dark)
	var y2 := door_lo + 0.14
	while y2 < door_hi - 0.2:
		_box(st, Vector3(-hx + 0.04, y2, -half + 0.05), Vector3(px1, y2 + 0.12, half - 0.05), base)
		_box(st, Vector3(-hx + 0.04, y2 + 0.12, -half + 0.05), Vector3(px1, y2 + 0.15, half - 0.05), light)
		y2 += 0.30


## One axis-aligned box with flat normals and one vertex colour. The colour goes in as linear so
## it matches what a StandardMaterial3D vertex colour (and the PS1 surface shader) expects.
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, color_srgb: Color) -> void:
	var col := color_srgb.srgb_to_linear()
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	# [corner a, b, c, d] counter-clockwise seen from outside (flipped when emitted), then the normal.
	var faces := [
		[4, 5, 6, 7, Vector3(0, 0, 1)],
		[1, 0, 3, 2, Vector3(0, 0, -1)],
		[5, 1, 2, 6, Vector3(1, 0, 0)],
		[0, 4, 7, 3, Vector3(-1, 0, 0)],
		[7, 6, 2, 3, Vector3(0, 1, 0)],
		[0, 1, 5, 4, Vector3(0, -1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[4]
		for idx in [0, 2, 1, 0, 3, 2]:   # Godot front faces wind clockwise
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p[f[idx]])
