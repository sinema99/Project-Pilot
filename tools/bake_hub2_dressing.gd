extends SceneTree

# Bakes hub2's storage dressing into its runtime form (docs/specs/hub2-load-time.md):
#   godot --path . --script tools/bake_hub2_dressing.gd          (windowed or --headless both work)
# Reads scenes/hub2_dressing_src.tscn (the editable source: ~2,500 Hub2Prop / CargoContainer /
# Hub2PipeRun / Hub2Crane nodes) and writes scenes/hub2_dressing.scn: every mesh merged into chunks
# per (material, CELL m square) and every box collider put in one static body per BODY_CELL square,
# plus the lamp light-pool list. Re-run after the generator or any hand edit of the source.

const SRC := "res://scenes/hub2_dressing_src.tscn"
const OUT := "res://scenes/hub2_dressing.scn"
## Meshes are merged per this many metres of x / z (smaller = better culling, more draws).
const CELL := 12.0
const BODY_CELL := 48.0
## Instanced meshes (containers) group per this many metres: bigger, because each group is one draw.
const MM_CELL := 40.0
## Items longer than this (cranes, long pipe runs) stay their own chunk so one never spans the map.
const BIG := 36.0
## A chunk's visibility range is its members' plus this, so a prop never vanishes sooner than before.
const RANGE_MARGIN := 9.0

var _frames := 0
var _src: Node3D


func _initialize() -> void:
	_src = (load(SRC) as PackedScene).instantiate()
	root.add_child(_src)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_bake()
	return true


func _bake() -> void:
	var inv := _src.global_transform.affine_inverse()
	# group key -> {mat, shadow, range, entries: [[arrays, xf]]}
	var groups: Dictionary = {}
	var big: Array = []
	var n_inst := 0
	# A mesh used three or more times (the containers) is instanced, not merged: merging would copy
	# its vertices into every chunk (138 MB for the dressing) instead of sharing them.
	var uses: Dictionary = {}
	for node in _src.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		if _in_door(m):
			continue
		if m.mesh != null:
			if not uses.has(m.mesh):
				uses[m.mesh] = []
			uses[m.mesh].append(m)
	var shared: Array = []
	for node in _src.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or _in_door(mi):
			continue
		n_inst += 1
		if uses[mi.mesh].size() >= 3:
			continue
		var xf := inv * mi.global_transform
		var box := xf * mi.mesh.get_aabb()
		var cell := Vector2i(floori(box.get_center().x / CELL), floori(box.get_center().z / CELL))
		var is_big := maxf(box.size.x, box.size.z) > BIG
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var arrays := mi.mesh.surface_get_arrays(s)
			var entry := [arrays, xf]
			var mk := PropMeshCache.material_key(mat)
			if mk == "" and mat != null:
				mk = "id%d" % mat.get_instance_id()
			var shadow := int(mi.cast_shadow)
			var rng := mi.visibility_range_end
			if is_big:
				big.append({"mat": mat, "shadow": shadow, "range": rng, "entries": [entry], "name": "Big"})
				continue
			var key := [mk, shadow, rng, cell]
			if not groups.has(key):
				groups[key] = {"mat": mat, "shadow": shadow, "range": rng, "entries": [], "name": "Chunk"}
			groups[key]["entries"].append(entry)
	var out := Hub2DressingBaked.new()
	out.name = "Dressing"
	var chunks := 0
	var tris := 0
	var all: Array = groups.values()
	all.append_array(big)
	for g: Dictionary in all:
		var built := _merge(g["entries"])
		if built.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % [g["name"], chunks]
		out.add_child(mi)
		mi.owner = out
		mi.position = built["center"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built["arrays"])
		mesh.surface_set_material(0, g["mat"])
		mi.mesh = mesh
		mi.cast_shadow = g["shadow"] as GeometryInstance3D.ShadowCastingSetting
		if g["range"] > 0.0:
			mi.visibility_range_end = g["range"] + RANGE_MARGIN
		chunks += 1
		tris += (built["arrays"][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var instanced := 0
	var multis := 0
	for mesh: Mesh in uses:
		if uses[mesh].size() < 3:
			continue
		var cells := {}
		for m: MeshInstance3D in uses[mesh]:
			var o := (inv * m.global_transform).origin
			var key := [int(m.cast_shadow), m.visibility_range_end, Vector2i(floori(o.x / MM_CELL), floori(o.z / MM_CELL))]
			if not cells.has(key):
				cells[key] = []
			cells[key].append(m)
		for key: Array in cells:
			var members: Array = cells[key]
			var center := Vector3.ZERO
			for m: MeshInstance3D in members:
				center += (inv * m.global_transform).origin
			center /= members.size()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = members.size()
			for i in members.size():
				var t: Transform3D = inv * (members[i] as MeshInstance3D).global_transform
				t.origin -= center
				mm.set_instance_transform(i, t)
			var node := MultiMeshInstance3D.new()
			node.name = "Multi%d" % multis
			out.add_child(node)
			node.owner = out
			node.position = center
			node.multimesh = mm
			node.cast_shadow = key[0] as GeometryInstance3D.ShadowCastingSetting
			if key[1] > 0.0:
				node.visibility_range_end = key[1] + MM_CELL * 0.7
			multis += 1
			instanced += members.size()
	var shapes := _bake_colliders(out, inv)
	# Doors stay live (they move and take input): copied as plain Hub2Door nodes, which load their
	# meshes from PropMeshCache in _ready.
	var doors := 0
	var door_root := Node3D.new()
	door_root.name = "Doors"
	out.add_child(door_root)
	door_root.owner = out
	for node in _src.find_children("*", "Hub2Door", true, false):
		var d := node as Hub2Door
		var c := Hub2Door.new()
		c.type = d.type
		c.width = d.width
		c.height = d.height
		c.gap = d.gap
		c.start_open = d.start_open
		c.keypad = d.keypad
		c.wear = d.wear
		c.transform = inv * d.global_transform
		c.name = d.name
		door_root.add_child(c)
		c.owner = out
		doors += 1
	print("bake_hub2_dressing: %d live doors" % doors)
	var lp := Hub2LampPools.new()
	out.lamps = lp.collect(_src)
	lp.free()
	var packed := PackedScene.new()
	var err := packed.pack(out)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("bake_hub2_dressing: %d mesh instances -> %d merged chunks (%d tris) + %d multimeshes (%d instances), %d box shapes, %d lamps; saved %s: %s" % [
			n_inst, chunks, tris, multis, instanced, shapes, out.lamps.size(), OUT, error_string(err)])
	out.free()
	_src.free()


## One merged surface (chunk-local, origin at the members' bounding-box centre) from [[arrays, xf]].
func _merge(entries: Array) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var has_n := false
	var has_c := false
	var has_uv := false
	for e: Array in entries:
		var arrays: Array = e[0]
		var xf: Transform3D = e[1]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if v == null or v.is_empty():
			continue
		for p in v:
			var q := xf * p
			lo = lo.min(q)
			hi = hi.max(q)
		has_n = has_n or arrays[Mesh.ARRAY_NORMAL] != null
		has_c = has_c or arrays[Mesh.ARRAY_COLOR] != null
		has_uv = has_uv or arrays[Mesh.ARRAY_TEX_UV] != null
	if lo.x == INF:
		return {}
	var center := (lo + hi) * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for e: Array in entries:
		var arrays: Array = e[0]
		var xf: Transform3D = e[1]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if v == null or v.is_empty():
			continue
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for p in v:
			verts.append(xf * p - center)
		if has_n:
			var n: Variant = arrays[Mesh.ARRAY_NORMAL]
			for i in v.size():
				norms.append((nb * (n as PackedVector3Array)[i]).normalized() if n != null else Vector3.UP)
		if has_c:
			var c: Variant = arrays[Mesh.ARRAY_COLOR]
			for i in v.size():
				cols.append((c as PackedColorArray)[i] if c != null else Color.WHITE)
		if has_uv:
			var u: Variant = arrays[Mesh.ARRAY_TEX_UV]
			for i in v.size():
				uvs.append((u as PackedVector2Array)[i] if u != null else Vector2.ZERO)
		var ix: Variant = arrays[Mesh.ARRAY_INDEX]
		if ix != null and (ix as PackedInt32Array).size() > 0:
			for i: int in ix:
				idx.append(base + i)
		else:
			for i in v.size():
				idx.append(base + i)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	if has_n:
		out[Mesh.ARRAY_NORMAL] = norms
	if has_c:
		out[Mesh.ARRAY_COLOR] = cols
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = idx
	return {"arrays": out, "center": center}


## Every BoxShape3D under the source, in one StaticBody3D per BODY_CELL square. Returns the shape count.
func _bake_colliders(out: Node3D, inv: Transform3D) -> int:
	var bodies := {}
	var shapes := {}
	var count := 0
	var other := 0
	for node in _src.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if _in_door(cs):
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			other += 1
			continue
		var xf := inv * cs.global_transform
		var cell := Vector2i(floori(xf.origin.x / BODY_CELL), floori(xf.origin.z / BODY_CELL))
		if not bodies.has(cell):
			var b := StaticBody3D.new()
			b.name = "Colliders_%d_%d" % [cell.x, cell.y]
			out.add_child(b)
			b.owner = out
			bodies[cell] = b
		var key := "%.3f,%.3f,%.3f" % [box.size.x, box.size.y, box.size.z]
		if not shapes.has(key):
			shapes[key] = box
		var c := CollisionShape3D.new()
		c.name = "S%d" % count
		c.shape = shapes[key]
		c.transform = xf
		bodies[cell].add_child(c)
		c.owner = out
		count += 1
	if other > 0:
		push_warning("bake_hub2_dressing: %d collision shapes were not boxes and were dropped." % other)
	return count


func _in_door(n: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != _src:
		if p is Hub2Door:
			return true
		p = p.get_parent()
	return false
