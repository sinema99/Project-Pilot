## pilot9's cowboy hat: a Head-bone socket with the hat mesh in it, shown or hidden as a snap.
## Built at runtime by pilot9.gd::_setup_hat() rather than saved into pilot9.tscn, so a rig swap
## by scripts/pilot9_build_scene.gd cannot drop it. See docs/specs/pilot9-cowboy-hat.md.
##
## While it is on, his head wears a "hatted" copy of its mesh with everything above the hatband cut
## away: his ear fins are part of the head mesh (no bone of their own), and the skull top that goes
## with them is under the crown anyway. The dash ghosts copy whichever mesh he is wearing.
extends Node

const _CowboyHatMesh := preload("res://scripts/items/cowboy_hat_mesh.gd")
const _CEL := preload("res://resources/pilot_cel_character.tres")

const HEAD_BONE := &"Head"
const FELT_COLOR := Color(0.27, 0.16, 0.09)
const BAND_COLOR := Color(0.11, 0.065, 0.04)
## A head triangle goes when its centre is this far above the brim's underside, in hat space.
const CUT_HEIGHT := 0.02
## A separate head piece (ear fin, antenna) goes whole if it reaches within this of CUT_HEIGHT -
## the second pilot's antennae come in two pieces, the lower one stopping just under the band.
const PIECE_REACH := 0.05
## How much of a vertex has to ride the Head bone to count as head.
const HEAD_WEIGHT := 0.5

var is_on: bool = false
var head_socket: BoneAttachment3D = null
## The hat's root; Felt and Band are its MeshInstance3D children.
var hat: Node3D = null
## MeshInstance3D -> [his own mesh, the hatted copy], for every mesh with head above the band.
var hatted: Dictionary = {}

var _skeleton: Skeleton3D = null


## `offset` places the hat in Head-bone space; `tilt` tips it back, in degrees.
func setup(skeleton: Skeleton3D, offset: Vector3, tilt: float) -> void:
	if skeleton == null:
		push_error("hat_holder: no skeleton - pilot9 will not be able to wear the hat")
		return
	_skeleton = skeleton
	head_socket = BoneAttachment3D.new()
	head_socket.name = &"HatSocket"
	skeleton.add_child(head_socket)
	# After add_child: BoneAttachment3D resolves the name against its parent skeleton.
	head_socket.bone_name = HEAD_BONE
	if head_socket.bone_idx < 0:
		push_error("hat_holder: skeleton has no bone '%s'" % HEAD_BONE)
	hat = Node3D.new()
	hat.name = &"CowboyHat"
	head_socket.add_child(hat)
	_part(&"Felt", _CowboyHatMesh.build_felt(), FELT_COLOR)
	_part(&"Band", _CowboyHatMesh.build_band(), BAND_COLOR)
	place(offset, tilt)
	set_on(false)


## Moves the hat and recuts the head to match.
func place(offset: Vector3, tilt: float) -> void:
	if hat == null:
		return
	hat.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-tilt)), offset)
	_build_hatted()
	_wear_meshes()


func toggle() -> void:
	set_on(not is_on)


func set_on(on: bool) -> void:
	is_on = on
	if hat != null:
		hat.visible = on
	_wear_meshes()


func _wear_meshes() -> void:
	for mi: MeshInstance3D in hatted:
		if is_instance_valid(mi):
			mi.mesh = hatted[mi][1] if is_on else hatted[mi][0]


func _part(part_name: StringName, mesh: Mesh, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = _tinted(color)
	hat.add_child(mi)


## pilot9's cel material in another colour; the ink pass is shared.
static func _tinted(color: Color) -> ShaderMaterial:
	var mat := _CEL.duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"color", color)
	return mat


## -- the hatted head -------------------------------------------------------------------------

func _build_hatted() -> void:
	# Back to his own meshes first, so a recut starts from them and not from the last cut.
	for mi: MeshInstance3D in hatted:
		if is_instance_valid(mi):
			mi.mesh = hatted[mi][0]
	hatted.clear()
	if _skeleton == null or head_socket.bone_idx < 0:
		return
	var to_hat := hat.transform.affine_inverse()
	for child in _skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null:
			continue
		var cut := cut_above(mi.mesh as ArrayMesh, mi.skin, head_socket.bone_idx, to_hat)
		if cut != null:
			hatted[mi] = [mi.mesh, cut]


## `mesh` without the triangles that are head (mostly `head_bone`) and whose centre is above
## CUT_HEIGHT in hat space. `to_hat` takes Head-bone space to hat space. null if nothing goes.
static func cut_above(mesh: ArrayMesh, skin: Skin, head_bone: int, to_hat: Transform3D) -> ArrayMesh:
	if mesh == null:
		return null
	var head_binds := {}
	for b in skin.get_bind_count():
		if skin.get_bind_bone(b) == head_bone or skin.get_bind_name(b) == HEAD_BONE:
			head_binds[b] = skin.get_bind_pose(b)
	if head_binds.is_empty():
		return null
	# Pass 1, per surface: each head vertex's hat-space height and each piece's reach.
	var surfaces: Array[Dictionary] = []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var info := {"arrays": arrays}
		surfaces.append(info)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var index = arrays[Mesh.ARRAY_INDEX]
		if index == null:
			index = PackedInt32Array(range(verts.size()))
		var per := (bones as PackedInt32Array).size() / maxi(verts.size(), 1)
		# Per vertex: its hat-space height if it is head, else -INF.
		var height := PackedFloat32Array()
		height.resize(verts.size())
		for i in verts.size():
			height[i] = -INF
			for j in per:
				var bind: int = bones[i * per + j]
				if head_binds.has(bind) and float(weights[i * per + j]) > HEAD_WEIGHT:
					height[i] = (to_hat * ((head_binds[bind] as Transform3D) * verts[i])).y
		var island := _islands(verts, index)
		var below := {}
		var top := {}
		for t in (index as PackedInt32Array).size() / 3:
			var a: int = index[t * 3]
			var b: int = index[t * 3 + 1]
			var c: int = index[t * 3 + 2]
			var h := maxf(height[a], maxf(height[b], height[c]))
			if h == -INF:
				continue
			var id: int = island[a]
			if (height[a] + height[b] + height[c]) / 3.0 <= CUT_HEIGHT:
				below[id] = int(below.get(id, 0)) + 1
			top[id] = maxf(float(top.get(id, -INF)), h)
		info.merge({"index": index, "height": height, "island": island, "below": below, "top": top})
	# The skull is the head piece with the most triangles under the band, across every surface -
	# not the biggest piece (pilot9's ear fins outweigh his skull), and not one per surface (the
	# second pilot's antennae are a surface of their own). It is cut at the band. Every other head
	# piece that reaches up near the band goes whole, so no stub shows under the brim.
	var skull_surface := -1
	var skull := -1
	for s in surfaces.size():
		var below: Dictionary = surfaces[s].get("below", {})
		for id in below:
			if skull < 0 or below[id] > surfaces[skull_surface]["below"][skull]:
				skull_surface = s
				skull = id
	# Pass 2: the cut.
	var out := ArrayMesh.new()
	var dropped := 0
	for s in surfaces.size():
		var info: Dictionary = surfaces[s]
		var arrays: Array = info["arrays"]
		var flags := mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		if not info.has("height"):
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
			out.surface_set_material(s, mesh.surface_get_material(s))
			continue
		var index: PackedInt32Array = info["index"]
		var height: PackedFloat32Array = info["height"]
		var island: PackedInt32Array = info["island"]
		var top: Dictionary = info["top"]
		var kept := PackedInt32Array()
		for t in index.size() / 3:
			var a: int = index[t * 3]
			var b: int = index[t * 3 + 1]
			var c: int = index[t * 3 + 2]
			var id: int = island[a]
			var is_skull := s == skull_surface and id == skull
			var whole := not is_skull and float(top.get(id, -INF)) > CUT_HEIGHT - PIECE_REACH
			if whole or (height[a] + height[b] + height[c]) / 3.0 > CUT_HEIGHT:
				dropped += 1
				continue
			kept.append_array([a, b, c])
		# A surface cut to nothing keeps one degenerate triangle, so surface indices still line
		# up with his material overrides.
		if kept.is_empty():
			kept = PackedInt32Array([0, 0, 0])
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out if dropped > 0 else null


## Per vertex, an id shared by every vertex of its connected piece. Vertices at the same position
## count as joined, since an export splits them at UV seams and hard edges.
static func _islands(verts: PackedVector3Array, index: PackedInt32Array) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	var at := {}
	for i in verts.size():
		var key := Vector3i((verts[i] * 100000.0).round())
		if at.has(key):
			_join(parent, i, at[key])
		else:
			at[key] = i
	for t in index.size() / 3:
		_join(parent, index[t * 3], index[t * 3 + 1])
		_join(parent, index[t * 3], index[t * 3 + 2])
	var out := PackedInt32Array()
	out.resize(verts.size())
	for i in verts.size():
		out[i] = _root(parent, i)
	return out


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _join(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _root(parent, a)
	var rb := _root(parent, b)
	if ra != rb:
		parent[ra] = rb
