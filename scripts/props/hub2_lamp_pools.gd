class_name Hub2LampPools
extends Node

# Feeds hub2's PS1 light pools from real fixtures (docs/specs/hub2-storage.md): every lit
# Hub2Prop lamp under `dressing` becomes one entry of the `lamp_pos` / `lamp_col` lists of the
# hub2 surface and decal materials (shaders/hub2_ps1.gdshaderinc). Static: read once at load, after
# Hub2Wear has put its materials on. No real-time lights.

const LAMP_MAX := 160

@export var dressing: Node
@export var wear: Hub2Wear
## Pool radius per lamp kind, metres.
@export var highbay_radius := 11.0
@export var bulkhead_radius := 5.0
@export var flood_radius := 14.0
@export var tint := Color(1.0, 0.55, 0.18)
@export var strength := 0.45

var count := 0
## Extra pools other nodes register before apply(): each [Vector4(x, y, z, radius), Vector4(r, g, b, strength)].
## The roof door's daylight patches come in this way.
var extra: Array = []
## Fixed pools other nodes add once and keep (the crane control room's screens and strips): same entries as `extra`,
## but nothing overwrites them.
var fixed: Array = []
## World boxes (the control room) whose floor only takes pools from lamps INSIDE the box: pools have no occlusion,
## so the yard's amber highbays outside the glass would otherwise tint the room's floor orange.
var keep_out: Array[AABB] = []


func _ready() -> void:
	apply.call_deferred()


func apply() -> int:
	if dressing == null or wear == null:
		return 0
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	for e: Array in collect(dressing):
		if _leaks_into_keep_out(e[0]):
			continue
		if pos.size() >= LAMP_MAX:
			push_warning("Hub2LampPools: more than %d lit lamps; the rest give no pool." % LAMP_MAX)
			break
		pos.append(e[0])
		col.append(e[1])
	for e: Array in extra + fixed:
		if pos.size() >= LAMP_MAX:
			break
		pos.append(e[0])
		col.append(e[1])
	count = pos.size()
	pos.resize(LAMP_MAX)
	col.resize(LAMP_MAX)
	var mats: Array[ShaderMaterial] = []
	if wear.surface_material != null:
		mats.append(wear.surface_material)
	var decals := wear.map.get_node_or_null(Hub2Wear.DECAL_NODE) as MeshInstance3D if wear.map != null else null
	if decals != null and decals.material_override is ShaderMaterial:
		mats.append(decals.material_override)
	for m in mats:
		m.set_shader_parameter(&"lamp_count", count)
		m.set_shader_parameter(&"lamp_pos", pos)
		m.set_shader_parameter(&"lamp_col", col)
	return count


## True when the lamp (x, y, z, radius) sits outside a keep_out box that its pool sphere reaches into.
func _leaks_into_keep_out(l: Vector4) -> bool:
	var c := Vector3(l.x, l.y, l.z)
	for box in keep_out:
		if box.has_point(c):
			continue
		if box.grow(l.w).has_point(c):
			return true
	return false


## [[Vector4(x, y, z, radius), Vector4(r, g, b, strength)], ...] for every lit lamp under `root`:
## the Hub2Prop lamps of a source scene, plus the entries a Hub2DressingBaked carries.
func collect(root: Node) -> Array:
	var out: Array = []
	for node in root.find_children("*", "Hub2Prop", true, false):
		var prop := node as Hub2Prop
		if not prop.is_lit_lamp():
			continue
		var r := highbay_radius
		if prop.kind == Hub2Prop.Kind.LAMP_BULKHEAD:
			r = bulkhead_radius
		elif prop.kind == Hub2Prop.Kind.FLOODLIGHT:
			r = flood_radius
		if prop.pool_radius > 0.0:
			r = prop.pool_radius
		var p := prop.lamp_point()
		var c := Vector4(tint.r, tint.g, tint.b, strength)
		if prop.pool_tint.a > 0.0:
			c = Vector4(prop.pool_tint.r, prop.pool_tint.g, prop.pool_tint.b, prop.pool_tint.a)
		out.append([Vector4(p.x, p.y, p.z, r), c])
	for node in root.find_children("*", "Hub2Piece", true, false):
		var piece := node as Hub2Piece
		if not piece.is_lit_lamp():
			continue
		var pl: Array = piece.pool()
		var lp := piece.lamp_point()
		var pc: Color = pl[1]
		out.append([Vector4(lp.x, lp.y, lp.z, pl[0]), Vector4(pc.r, pc.g, pc.b, pc.a)])
	if root.has_method(&"lamp_entries"):
		out.append_array(root.call(&"lamp_entries"))
	return out
