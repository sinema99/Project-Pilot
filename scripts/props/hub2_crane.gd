@tool
class_name Hub2Crane
extends StaticBody3D

# Overhead cranes for hub2 (docs/specs/hub2-storage.md), code-built PS1 like Hub2Prop.
#
# BRIDGE: two runway beams along Z at `rail_height`, `span` apart, carried on columns down to the
#   floor every `column_pitch`; a box-girder bridge across them at `bridge_z`, a trolley on it at
#   `trolley_x`, the hook block `hook_drop` below the bridge on four cables. Origin = floor centre.
# POLAR: a ring rail of radius `span` / 2 at `rail_height`, bracketed `bracket_in` metres inward
#   onto the wall it runs round (hub2's suspended tower), and a slewing jib riding it that reaches
#   `runway_length` metres OUTWARD at `bridge_angle` degrees; trolley at `trolley_x` along the jib,
#   same hook. Origin = floor point under the ring's centre.
# Collision: columns and the hook block only (the high steel is out of reach anyway).

# WALL (room A, docs/specs/hub2-storage.md "Room A storage hall"): one runway girder along Z bracketed
#   onto a wall at `rail_height` (origin = floor point on the wall face at the rail's height, local +X = into the
#   room, Z along the wall), `runway_length` long, with gusset brackets at `bracket_zs`. Riding it, one
#   cantilever travelling jib per entry of `bridge_zs`: twin box girders reaching `span` metres into the room,
#   a mast and back-stays, a trolley at `trolley_xs[i]` and a hook `hook_drops[i]` below the rail. Nothing
#   crosses the middle of the room. No collision (all of it is far out of reach).

enum Type { BRIDGE, POLAR, WALL }

@export var bridge_zs := PackedFloat32Array():
	set(v):
		bridge_zs = v
		_queue()
@export var trolley_xs := PackedFloat32Array():
	set(v):
		trolley_xs = v
		_queue()
@export var hook_drops := PackedFloat32Array():
	set(v):
		hook_drops = v
		_queue()
@export var bracket_zs := PackedFloat32Array():
	set(v):
		bracket_zs = v
		_queue()

## BRIDGE: runway columns left out because they would stand inside the map (room C's south pair on the
## dock ledge / ramp). One entry per column: x = side (-1 or +1), y = z along the runway from the middle.
## A skipped column gets no mesh and no collision; the runway girder is unchanged.
@export var skip_columns := PackedVector2Array():
	set(v):
		skip_columns = v
		_queue()

@export var type: Type = Type.BRIDGE:
	set(v):
		type = v
		_queue()
@export var span := 30.0:
	set(v):
		span = v
		_queue()
@export var runway_length := 80.0:
	set(v):
		runway_length = v
		_queue()
@export var rail_height := 30.0:
	set(v):
		rail_height = v
		_queue()
## POLAR: how far the ring's brackets reach in to the wall.
@export var bracket_in := 6.0:
	set(v):
		bracket_in = v
		_queue()
@export var column_pitch := 16.0:
	set(v):
		column_pitch = v
		_queue()
## POLAR: > 0 hangs the ring from a ceiling that many metres above its top (hangers and anchor plates
## instead of brackets into a wall; room A's ring round the shaft mouth).
@export var hang_up := 0.0:
	set(v):
		hang_up = v
		_queue()
## Bridge position along the runway (BRIDGE), metres from the middle.
@export var bridge_z := 0.0:
	set(v):
		bridge_z = v
		_queue()
## Bridge heading for POLAR, degrees.
@export var bridge_angle := 0.0:
	set(v):
		bridge_angle = v
		_queue()
## Trolley position along the bridge, metres from the middle.
@export var trolley_x := 0.0:
	set(v):
		trolley_x = v
		_queue()
## Hook block depth below the bridge.
@export var hook_drop := 10.0:
	set(v):
		hook_drop = v
		_queue()
## Below the hook: one cable keeps going this much further and lies slack (0 = none).
@export var dangling := 0.0:
	set(v):
		dangling = v
		_queue()
@export var wear := 0.8:
	set(v):
		wear = v
		_queue()

const GIRDER := Color(0.86, 0.66, 0.12)
const STEEL_DARK := Color(0.20, 0.21, 0.23)
const COLUMN := Color(0.32, 0.34, 0.37)
const BLACK := Color(0.07, 0.07, 0.08)

var _built := false


func _ready() -> void:
	_built = true
	_rebuild()


func _queue() -> void:
	if _built:
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta(&"prop_part"):
			child.free()
	var kit := PropKit.new(wear, int(span * 13.0 + runway_length))
	kit.cell = 1.5
	kit.grime_height = 3.0
	var boxes: Array = []
	if type == Type.BRIDGE:
		_bridge_runways(kit, boxes)
		_bridge(kit, Transform3D(Basis.IDENTITY, Vector3(0, 0, bridge_z)), span, boxes)
	elif type == Type.WALL:
		_wall(kit)
	else:
		_ring(kit)
		_jib(kit, boxes)
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	mi.mesh = kit.commit()
	mi.set_meta(&"prop_part", true)
	add_child(mi)
	var i := 0
	for b: Array in boxes:
		var shape := CollisionShape3D.new()
		shape.name = "Box%d" % i
		var bs := BoxShape3D.new()
		bs.size = b[1]
		shape.shape = bs
		shape.position = b[0]
		shape.set_meta(&"prop_part", true)
		add_child(shape)
		i += 1


## The runway columns BRIDGE stands on: [side (-1 / +1), z from the runway middle], in build order.
func column_slots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var hz := runway_length * 0.5
	for side in [-1.0, 1.0]:
		var z := -hz
		while z <= hz + 0.01:
			out.append(Vector2(side, z))
			z += column_pitch
	return out


func is_column_skipped(side: float, z: float) -> bool:
	for s in skip_columns:
		if signf(s.x) == signf(side) and absf(s.y - z) < 0.05:
			return true
	return false


func _column(kit: PropKit, at: Vector3, boxes: Array) -> void:
	kit.box(at + Vector3(-0.4, 0.0, -0.4), at + Vector3(0.4, rail_height - 0.8, 0.4), COLUMN)
	kit.box(at + Vector3(-0.6, 0.0, -0.6), at + Vector3(0.6, 0.3, 0.6), COLUMN.darkened(0.2))
	# Bracing ladder rungs every 4 m, read as a lattice at PS1 resolution.
	var y := 4.0
	while y < rail_height - 2.0:
		kit.box(at + Vector3(-0.45, y, -0.45), at + Vector3(0.45, y + 0.15, 0.45), COLUMN.darkened(0.1))
		y += 4.0
	boxes.append([at + Vector3(0, (rail_height - 0.8) * 0.5, 0), Vector3(0.8, rail_height - 0.8, 0.8)])


func _bridge_runways(kit: PropKit, boxes: Array) -> void:
	var hz := runway_length * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * span * 0.5
		kit.box(Vector3(x - 0.5, rail_height - 0.8, -hz), Vector3(x + 0.5, rail_height, hz), COLUMN)
		kit.box(Vector3(x - 0.1, rail_height, -hz), Vector3(x + 0.1, rail_height + 0.15, hz), STEEL_DARK)
		var z := -hz
		while z <= hz + 0.01:
			if not is_column_skipped(side, z):
				_column(kit, Vector3(x, 0, z), boxes)
			z += column_pitch
		# End stops.
		for ez in [-hz, hz]:
			kit.box(Vector3(x - 0.4, rail_height, ez - 0.3), Vector3(x + 0.4, rail_height + 0.8, ez + 0.3), GIRDER)


## WALL: the runway girder, its brackets, and the cantilever jibs riding it.
func _wall(kit: PropKit) -> void:
	var hz := runway_length * 0.5
	var rh := rail_height
	kit.box(Vector3(0.0, rh - 1.6, -hz), Vector3(2.0, rh, hz), COLUMN)
	kit.box(Vector3(0.7, rh, -hz), Vector3(1.3, rh + 0.25, hz), STEEL_DARK)
	for ez in [-hz, hz]:
		kit.box(Vector3(0.2, rh, ez - 0.3), Vector3(1.8, rh + 1.0, ez + 0.3), GIRDER)
	for bz in bracket_zs:
		kit.box(Vector3(-0.5, rh - 8.0, bz - 1.4), Vector3(0.1, rh + 0.6, bz + 1.4), COLUMN.darkened(0.2))
		kit.tube(Vector3(1.6, rh - 1.6, bz - 0.6), Vector3(0.0, rh - 8.0, bz - 0.6), 0.3, COLUMN, 6)
		kit.tube(Vector3(1.6, rh - 1.6, bz + 0.6), Vector3(0.0, rh - 8.0, bz + 0.6), 0.3, COLUMN, 6)
		kit.tri(Vector3(1.9, rh - 1.6, bz), Vector3(0.0, rh - 1.6, bz), Vector3(0.0, rh - 8.0, bz), COLUMN.darkened(0.15))
		kit.tri(Vector3(0.0, rh - 1.6, bz), Vector3(1.9, rh - 1.6, bz), Vector3(0.0, rh - 8.0, bz), COLUMN.darkened(0.15))
	for i in bridge_zs.size():
		var z := bridge_zs[i]
		var tx := trolley_xs[i] if i < trolley_xs.size() else span * 0.5
		var drop := hook_drops[i] if i < hook_drops.size() else 30.0
		var deck := rh + 1.5
		var top := rh + 4.3
		# Carriage on the runway, twin girders reaching out, cross-ties, end plate with hazard stripes.
		kit.box(Vector3(0.0, rh, z - 3.4), Vector3(4.2, deck, z + 3.4), GIRDER.darkened(0.15))
		for gz in [-1.5, 1.5]:
			kit.box(Vector3(0.2, deck, z + gz - 0.5), Vector3(span, top, z + gz + 0.5), GIRDER)
		var x := 4.0
		while x < span - 1.0:
			kit.box(Vector3(x, deck + 0.3, z - 1.5), Vector3(x + 0.4, deck + 1.1, z + 1.5), GIRDER.darkened(0.2))
			x += 6.0
		kit.box(Vector3(span - 0.5, deck, z - 2.1), Vector3(span + 0.3, top, z + 2.1), GIRDER.darkened(0.1))
		for s in 4:
			kit.box(Vector3(span + 0.3, deck + 0.3 + s * 0.7, z - 2.0), Vector3(span + 0.34, deck + 0.7 + s * 0.7, z + 2.0), BLACK, Transform3D.IDENTITY, false)
		# Mast over the carriage and the back-stays to the girders' far end and middle.
		kit.box(Vector3(0.8, top, z - 0.8), Vector3(2.6, top + 9.0, z + 0.8), GIRDER.darkened(0.1))
		kit.tube(Vector3(1.7, top + 9.0, z), Vector3(span - 1.0, top, z), 0.12, BLACK, 4, Transform3D.IDENTITY, false)
		kit.tube(Vector3(1.7, top + 9.0, z), Vector3(span * 0.55, top, z), 0.12, BLACK, 4, Transform3D.IDENTITY, false)
		# Trolley and hook.
		var t := Vector3(tx, top, z)
		kit.box(t + Vector3(-1.8, 0.0, -2.2), t + Vector3(1.8, 1.2, 2.2), GIRDER.darkened(0.08))
		kit.tube(t + Vector3(-1.2, 1.7, 0), t + Vector3(1.2, 1.7, 0), 0.6, STEEL_DARK, 8)
		var hook := Vector3(tx, rh - drop, z)
		for o in [Vector3(-0.3, 0, -0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, 0.3)]:
			kit.tube(t + o + Vector3(0, 1.0, 0), hook + o * 0.5 + Vector3(0, 1.2, 0), 0.03, BLACK, 4, Transform3D.IDENTITY, false)
		_hook(kit, hook, Transform3D.IDENTITY)


func _ring(kit: PropKit) -> void:
	# 2026-11-14 review: the thin ring read as floating from A's floor. Now a deep plate girder with a
	# rail on top and chunky triangle brackets every column_pitch that run back INTO the tower wall
	# (bracket_in is deliberately past the wall: the tower's radius varies, the buried part is hidden).
	var r := span * 0.5
	var n := 48
	var top := rail_height
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1) + 0.05
		var b := Basis.looking_at((p1 - p0).normalized(), Vector3.UP)
		kit.obox(mid + Vector3(0, top - 1.2, 0), Vector3(0.5, 2.4, seg), COLUMN, b)           # web
		kit.obox(mid + Vector3(0, top - 0.15, 0), Vector3(1.8, 0.3, seg), COLUMN.darkened(0.1), b)   # top flange
		kit.obox(mid + Vector3(0, top - 2.25, 0), Vector3(1.8, 0.3, seg), COLUMN.darkened(0.1), b)   # bottom flange
		kit.obox(mid + Vector3(0, top + 0.2, 0), Vector3(0.35, 0.4, seg), STEEL_DARK, b)      # crane rail
	var cols := maxi(8, int(TAU * r / column_pitch))
	for i in cols:
		var a := TAU * (i + 0.5) / cols
		var d := Vector3(cos(a), 0, sin(a))
		if hang_up > 0.0:
			# Ceiling-hung: a pair of rods from the top flange up into the ceiling and an anchor plate where
			# they enter (buried past the ceiling on purpose; its height varies).
			for side in [-1.0, 1.0]:
				var at: Vector3 = d * r + Vector3(-d.z, 0, d.x) * float(side) * 0.6
				kit.box(at + Vector3(-0.25, top - 0.1, -0.25), at + Vector3(0.25, top + hang_up, 0.25), COLUMN.darkened(0.05))
			kit.obox(d * r + Vector3(0, top + hang_up - 0.4, 0), Vector3(2.6, 0.8, 2.6), COLUMN.darkened(0.2))
			continue
		var bb := Basis.looking_at(-d, Vector3.UP)   # local -Z = into the wall
		var arm_mid := d * (r - bracket_in * 0.5) + Vector3(0, top - 1.2, 0)
		# Top arm: the girder's depth, ring to wall.
		kit.obox(arm_mid, Vector3(0.7, 2.4, bracket_in), COLUMN.darkened(0.05), bb)
		# Raking strut from the ring's underside down to a wall plate 7 m below.
		var foot := d * (r - bracket_in) + Vector3(0, top - 9.0, 0)
		kit.tube(d * (r - 0.4) + Vector3(0, top - 2.3, 0), foot, 0.4, COLUMN, 6)
		# Gusset plate filling the triangle, and the plate the strut lands on.
		kit.tri(d * (r - 0.3) + Vector3(0, top - 2.4, 0), d * (r - bracket_in) + Vector3(0, top - 2.4, 0), foot, COLUMN.darkened(0.15))
		kit.tri(d * (r - bracket_in) + Vector3(0, top - 2.4, 0), d * (r - 0.3) + Vector3(0, top - 2.4, 0), foot, COLUMN.darkened(0.15))
		kit.obox(foot, Vector3(1.6, 1.6, 0.3), COLUMN.darkened(0.2), bb)


## POLAR's slewing jib: a carriage on the ring and a box girder reaching outward.
func _jib(kit: PropKit, boxes: Array) -> void:
	var r := span * 0.5
	var a := deg_to_rad(bridge_angle)
	var out := Vector3(cos(a), 0, sin(a))
	var b := Basis(Vector3.UP, -a)   # local +X = out
	var base := out * r
	var xf := Transform3D(b, base)
	var top := rail_height + 2.4
	kit.box(Vector3(-2.0, rail_height + 0.15, -3.0), Vector3(2.0, rail_height + 1.4, 3.0), GIRDER.darkened(0.15), xf)
	kit.box(Vector3(-2.0, rail_height + 1.4, -1.6), Vector3(runway_length, top, 1.6), GIRDER, xf)
	# Back-stay to a short mast over the ring.
	kit.box(Vector3(-1.0, top, -0.8), Vector3(1.0, top + 7.0, 0.8), GIRDER.darkened(0.1), xf)
	kit.tube(Vector3(0, top + 7.0, 0), Vector3(runway_length - 1.0, top, 0), 0.08, BLACK, 4, xf, false)
	kit.tube(Vector3(0, top + 7.0, 0), Vector3(-8.0, rail_height + 1.4, 0), 0.08, BLACK, 4, xf, false)
	var i := 0
	while i < 6:
		kit.box(Vector3(runway_length - 3.0 + i * 0.5, rail_height + 1.8, 1.6), Vector3(runway_length - 2.75 + i * 0.5, top - 0.4, 1.62), BLACK, xf, false)
		i += 1
	var t := Vector3(trolley_x, top, 0)
	kit.box(t + Vector3(-1.4, 0.0, -1.9), t + Vector3(1.4, 1.0, 1.9), GIRDER.darkened(0.08), xf)
	kit.tube(t + Vector3(-1.0, 1.5, 0), t + Vector3(1.0, 1.5, 0), 0.5, STEEL_DARK, 8, xf)
	var hook := Vector3(trolley_x, rail_height - hook_drop, 0)
	for o in [Vector3(-0.3, 0, -0.3), Vector3(0.3, 0, 0.3)]:
		kit.tube(t + o, hook + o * 0.5 + Vector3(0, 1.2, 0), 0.03, BLACK, 4, xf, false)
	_hook(kit, hook, xf)
	boxes.append([xf * (hook + Vector3(0, 0.7, 0)), Vector3(1.0, 1.4, 0.7)])


func _bridge(kit: PropKit, xf: Transform3D, length: float, boxes: Array) -> void:
	var hx := length * 0.5 + 0.6
	var top := rail_height + 2.4
	# Twin box girders, end carriages, a walkway rail.
	for gz in [-1.6, 1.6]:
		kit.box(Vector3(-hx, rail_height + 0.15, gz - 0.5), Vector3(hx, top, gz + 0.5), GIRDER, xf)
	for ex in [-hx, hx - 1.2]:
		kit.box(Vector3(ex, rail_height + 0.15, -3.0), Vector3(ex + 1.2, rail_height + 1.2, 3.0), GIRDER.darkened(0.15), xf)
	kit.box(Vector3(-hx, top, 2.1), Vector3(hx, top + 0.05, 2.2), STEEL_DARK, xf)
	# Hazard stripes on the girder ends.
	for ex in [-hx, hx - 2.0]:
		var i := 0
		while i < 4:
			kit.box(Vector3(ex + i * 0.5, rail_height + 0.6, 2.1), Vector3(ex + i * 0.5 + 0.25, top - 0.4, 2.12), BLACK, xf, false)
			i += 1
	# Trolley with its hoist drum.
	var t := Vector3(trolley_x, top, 0)
	kit.box(t + Vector3(-1.8, 0.0, -2.2), t + Vector3(1.8, 1.2, 2.2), GIRDER.darkened(0.08), xf)
	kit.tube(t + Vector3(-1.2, 1.7, 0), t + Vector3(1.2, 1.7, 0), 0.6, STEEL_DARK, 8, xf)
	kit.box(t + Vector3(1.2, 1.1, -0.8), t + Vector3(1.8, 2.2, 0.8), COLUMN, xf)
	# Cables down to the hook block, through a gap between the girders.
	var hook := Vector3(trolley_x, rail_height - hook_drop, 0)
	for o in [Vector3(-0.3, 0, -0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, 0.3)]:
		kit.tube(t + o + Vector3(0, 1.0, 0), hook + o * 0.5 + Vector3(0, 1.2, 0), 0.03, BLACK, 4, xf, false)
	_hook(kit, hook, xf)
	boxes.append([xf * (hook + Vector3(0, 0.7, 0)), Vector3(1.0, 1.4, 0.7)])


func _hook(kit: PropKit, hook: Vector3, xf: Transform3D) -> void:
	kit.box(hook + Vector3(-0.5, 0.0, -0.35), hook + Vector3(0.5, 1.4, 0.35), GIRDER, xf)
	kit.tube(hook + Vector3(0, 0.0, 0), hook + Vector3(0, -0.6, 0), 0.12, STEEL_DARK, 6, xf)
	# The hook: three bent segments.
	var h0 := hook + Vector3(0, -0.6, 0)
	var h1 := h0 + Vector3(0, -0.5, 0)
	var h2 := h1 + Vector3(0.35, -0.15, 0)
	var h3 := h2 + Vector3(0.1, 0.35, 0)
	kit.tube(h0, h1, 0.1, STEEL_DARK, 6, xf)
	kit.tube(h1, h2, 0.1, STEEL_DARK, 6, xf)
	kit.tube(h2, h3, 0.08, STEEL_DARK, 6, xf)
	if dangling > 0.0:
		# One loose cable falling past the hook and lying in a short slack curl.
		var p := hook + Vector3(0.4, 1.0, 0.2)
		var end := hook + Vector3(0.8, -dangling, 0.4)
		kit.tube(p, end, 0.03, BLACK, 4, xf, false)
		kit.tube(end, end + Vector3(1.2, 0.0, 0.6), 0.03, BLACK, 4, xf, false)
