## What is left of pilot9's body under his trench coat: a copy of a body mesh with everything the
## coat covers cut away, so the coat can sit close and nothing can come through it. Only the front
## strip the open coat shows (chest, stomach, belt) and what stands inside the collar stay. Legs,
## head and hands are never touched. See docs/specs/pilot9-trench-coat.md, "The fitted cut".
##
## The cut is decided in his skeleton's REST pose (the space the coat is modelled in), by where a
## triangle sits and which bones carry it - not by which mesh it is, so it works on any body.
extends RefCounted

const _CoatMesh := preload("res://scripts/items/trench_coat_mesh.gd")

## Bones that carry his trunk, and bones that carry his shoulders (pads, balls, armpits).
const TRUNK_BONES := ["Hips", "Spine", "Chest", "UpperChest"]
const SHOULDER_BONES := ["Shoulder", "UpperArm"]
## A mesh is looked at only if this share of it rides those bones.
const MIN_SHARE := 0.02
## The strip kept at the front reaches this far past the coat's front edge, under the panel.
const STRIP_MARGIN := 0.03
## ...and is only what faces forward of this z.
const STRIP_Z := 0.0
## What stands inside the collar stays: above this height and within this half-width.
## (The low top, 2026-11-12: down to the coat's lowered collar and out to the scarf's width, so
## the scarf shows above the coat; 0.10 wide so the vest straps and shirt beside it stay cut.)
const COLLAR_Y := 1.53
const COLLAR_X := 0.10
## Nothing of the trunk is cut above the coat's shoulder line.
const TOP_Y := 1.62

const OTHER := 0
const TRUNK := 1
const SHOULDER := 2


## Whether the coat covers a trunk point (rest pose, model space).
static func covers(p: Vector3) -> bool:
	if p.y >= TOP_Y:
		return false
	if p.y >= COLLAR_Y and absf(p.x) <= COLLAR_X:
		return false
	if p.z > STRIP_Z and absf(p.x) < _CoatMesh.front_edge_x(p.y) + STRIP_MARGIN:
		return false
	return true


## TRUNK, SHOULDER or OTHER for a bone name.
static func bone_class(bone_name: String) -> int:
	for part: String in SHOULDER_BONES:
		if bone_name.ends_with(part):
			return SHOULDER
	return TRUNK if TRUNK_BONES.has(bone_name) else OTHER


## The share of `mesh`'s vertices whose heaviest bone's name ends with one of `parts` (sampled:
## a few hundred vertices a surface is plenty to tell one body piece from another).
static func bone_share(mesh: ArrayMesh, skin: Skin, parts: Array) -> float:
	if mesh == null or skin == null:
		return 0.0
	var hit := PackedByteArray()
	for b in skin.get_bind_count():
		var bind_name := String(skin.get_bind_name(b))
		var found := 0
		for part: String in parts:
			if bind_name.ends_with(part):
				found = 1
		hit.append(found)
	var seen := 0
	var hits := 0
	for s in mesh.get_surface_count():
		if not (mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES):
			continue
		var arrays := mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if count == 0:
			continue
		@warning_ignore("integer_division")
		var per := bones.size() / count
		@warning_ignore("integer_division")
		var stride := maxi(1, count / 400)
		for i in range(0, count, stride):
			var best := 0
			for j in range(1, per):
				if weights[i * per + j] > weights[i * per + best]:
					best = j
			var bind := bones[i * per + best]
			seen += 1
			if bind < hit.size() and hit[bind] == 1:
				hits += 1
	return float(hits) / float(seen) if seen > 0 else 0.0


## `mesh` without the triangles the coat covers. Returns [cut mesh, triangles kept], or [] if
## nothing goes. A triangle goes when all of it rides his shoulders, or all of it rides his trunk
## or shoulders and its centre is somewhere covers() says.
static func cut(mesh: ArrayMesh, skin: Skin, skeleton: Skeleton3D) -> Array:
	if mesh == null or skin == null or skeleton == null:
		return []
	if bone_share(mesh, skin, TRUNK_BONES + SHOULDER_BONES) < MIN_SHARE:
		return []
	# Per bind: what it is, and where it puts a vertex in the rest pose.
	var kind := PackedByteArray()
	var to_rest: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0 or skin.get_bind_name(b) != &"":
			bone = skeleton.find_bone(skin.get_bind_name(b))
		if bone < 0:
			kind.append(OTHER)
			to_rest.append(Transform3D.IDENTITY)
			continue
		kind.append(bone_class(skeleton.get_bone_name(bone)))
		to_rest.append(skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(b))
	var out := ArrayMesh.new()
	out.resource_name = mesh.resource_name
	var dropped := 0
	var kept_total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var flags := mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty() \
				or mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
			_carry(out, mesh, s)
			continue
		var index = arrays[Mesh.ARRAY_INDEX]
		if index == null:
			index = PackedInt32Array(range(verts.size()))
		@warning_ignore("integer_division")
		var per: int = (bones as PackedInt32Array).size() / verts.size()
		var vertex_kind := PackedByteArray()
		vertex_kind.resize(verts.size())
		var at := PackedVector3Array()
		at.resize(verts.size())
		for i in verts.size():
			var p := Vector3.ZERO
			var best := -1
			var best_w := 0.0
			for j in per:
				var w: float = weights[i * per + j]
				if w <= 0.0:
					continue
				var bind: int = bones[i * per + j]
				p += (to_rest[bind] * verts[i]) * w
				if w > best_w:
					best_w = w
					best = bind
			at[i] = p
			vertex_kind[i] = kind[best] if best >= 0 else OTHER
		var kept := PackedInt32Array()
		@warning_ignore("integer_division")
		for t in (index as PackedInt32Array).size() / 3:
			var a: int = index[t * 3]
			var b: int = index[t * 3 + 1]
			var c: int = index[t * 3 + 2]
			var lowest := mini(vertex_kind[a], mini(vertex_kind[b], vertex_kind[c]))
			if lowest == SHOULDER or (lowest == TRUNK and covers((at[a] + at[b] + at[c]) / 3.0)):
				dropped += 1
				continue
			kept.append_array([a, b, c])
		@warning_ignore("integer_division")
		kept_total += kept.size() / 3
		# A surface cut to nothing keeps one degenerate triangle, so surface indices still line
		# up with his material overrides.
		if kept.is_empty():
			kept = PackedInt32Array([0, 0, 0])
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		_carry(out, mesh, s)
	return [out, kept_total] if dropped > 0 else []


static func _carry(out: ArrayMesh, mesh: ArrayMesh, s: int) -> void:
	out.surface_set_material(s, mesh.surface_get_material(s))
	out.surface_set_name(s, mesh.surface_get_name(s))
