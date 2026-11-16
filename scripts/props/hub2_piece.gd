@tool
class_name Hub2Piece
extends Node3D

# One hand-placed object of hub2's final dressing (docs/specs/hub2-final-pass.md): freight, vehicles,
# rubble, room furniture, signage, structure. The mesh is built in code by Hub2PieceBuild (PS1 low
# poly, vertex colour, weathering in the colours) and cached on disk by PropMeshCache, so a game run
# only ever LOADS meshes; the runtime map uses the baked scene anyway (tools/bake_hub2_dressing.gd).
#
# Origin: bottom centre on the floor unless the kind says otherwise; front faces +Z.

enum Kind {
	# freight
	BOX20, BOX40, REEFER, POD, LOADER, EXOFRAME, DRONE_RACK, DRONE, RAIL, CARRIER,
	# rubble + barricades
	SLAB, CEIL_PANEL, CABLE_TRAY, DEBRIS, SANDBAGS, JERSEY, SHEET, GIRDER_FALLEN, REBAR,
	# rooms
	LOCKERS, BENCH, VENDING, TABLE, CHAIR, DESK, BOARD, BEDROLL, CAMPFIRE, STRING_LIGHT, CHEMLIGHT,
	GENERATOR, FUEL_TANK, DRUM, PUMP, TANK_V, VENT_FAN, WEAPON_RACK, SCANNER_ARCH, BOOTH,
	INSPECT_TABLE, VEHICLE_LIFT, TOOL_WALL, BODY, HOLO_RING, CONE, BOLLARD, PAPERS, CANS, TARP,
	# signage + light
	STENCIL, TAG, BAY_NUMBER, LED_STRIP, KEYPAD, EMERGENCY_LAMP, PUDDLE, STAIN,
	# structure
	RAILING, STAIR, DECK, CABIN, SHED, FENCE, SHUTTER, BULKHEAD, LADDER, COLD_CAGE, SKYLIGHT,
	PIPE_FALLEN,
}

@export var kind: Kind = Kind.BOX20:
	set(v):
		kind = v
		_queue()
@export_range(0, 15) var variant := 0:
	set(v):
		variant = v
		_queue()
## Kind-specific state (containers: 0 closed, 1 open, 2 pried, 3 crushed, 4 burnt).
@export_range(0, 7) var state := 0:
	set(v):
		state = v
		_queue()
@export var prop_seed := 0:
	set(v):
		prop_seed = v
		_queue()
@export_range(0.0, 1.0, 0.05) var wear := 0.85:
	set(v):
		wear = v
		_queue()
## Parametric size for kinds that take one (railing length, stair width/rise/run, slab, deck...).
@export var size := Vector3.ONE:
	set(v):
		size = v
		_queue()
## Stencil / tag text.
@export var text := "":
	set(v):
		text = v
		_queue()
## Lit (campfire, chem light, emergency lamp, LED strip, bay number, string light).
@export var powered := false:
	set(v):
		powered = v
		_queue()
## Light pool for lit pieces (radius m, 0 = kind default) and colour (alpha = strength).
@export var pool_radius := 0.0
@export var pool_tint := Color(0, 0, 0, 0)

var _built := false
static var _cache: Dictionary = {}

## Kinds small enough to stop drawing beyond CLUTTER_RANGE.
const CLUTTER := [Kind.DEBRIS, Kind.CHEMLIGHT, Kind.CONE, Kind.PAPERS, Kind.CANS, Kind.DRONE, Kind.KEYPAD,
	Kind.TAG, Kind.STAIN, Kind.CHAIR, Kind.BEDROLL, Kind.REBAR, Kind.BOLLARD]
const CLUTTER_RANGE := 35.0
const MID_RANGE := 110.0
## Kinds that never fade (structure, landmarks).
const ALWAYS := [Kind.RAIL, Kind.CARRIER, Kind.STAIR, Kind.DECK, Kind.CABIN, Kind.SHED, Kind.BULKHEAD,
	Kind.SKYLIGHT, Kind.GIRDER_FALLEN, Kind.TANK_V, Kind.COLD_CAGE, Kind.SHUTTER, Kind.BOX40, Kind.BOX20,
	Kind.REEFER, Kind.POD, Kind.GENERATOR]
## Kinds that never cast shadows (flat or tiny).
const NO_SHADOW := [Kind.TAG, Kind.STENCIL, Kind.PUDDLE, Kind.STAIN, Kind.PAPERS, Kind.BAY_NUMBER,
	Kind.LED_STRIP, Kind.CHEMLIGHT, Kind.DEBRIS, Kind.CANS, Kind.STRING_LIGHT]


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
	var made := build_cached(kind, variant, state, prop_seed, wear, size, text, powered)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = made["mesh"]
	if kind in CLUTTER:
		visual.visibility_range_end = CLUTTER_RANGE
	elif not kind in ALWAYS:
		visual.visibility_range_end = MID_RANGE
	if kind in NO_SHADOW:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta(&"prop_part", true)
	add_child(visual)
	var i := 0
	for b: Array in made["boxes"]:
		var shape := CollisionShape3D.new()
		shape.name = "Box%d" % i
		var bs := BoxShape3D.new()
		bs.size = b[1]
		shape.shape = bs
		shape.transform = Transform3D(b[2] if b.size() > 2 else Basis.IDENTITY, b[0])
		shape.set_meta(&"prop_part", true)
		add_child(shape)
		i += 1


static func build_cached(k: Kind, v: int, st: int, s: int, w: float, sz: Vector3, t: String, p: bool) -> Dictionary:
	var key := [k, v, st, s, snappedf(w, 0.05), sz.snapped(Vector3.ONE * 0.05), t, p]
	if not _cache.has(key):
		_cache[key] = PropMeshCache.fetch("piece", key, func() -> Dictionary:
			return Hub2PieceBuild.build(k, v, st, s, w, sz.snapped(Vector3.ONE * 0.05), t, p))
	return _cache[key]


## Lit pieces feed Hub2LampPools.
func is_lit_lamp() -> bool:
	return powered and kind in [Kind.CAMPFIRE, Kind.CHEMLIGHT, Kind.EMERGENCY_LAMP, Kind.LED_STRIP,
		Kind.BAY_NUMBER, Kind.STRING_LIGHT, Kind.SKYLIGHT]


func lamp_point() -> Vector3:
	match kind:
		Kind.CAMPFIRE:
			return global_transform * Vector3(0, 0.6, 0)
		Kind.EMERGENCY_LAMP:
			return global_transform * Vector3(0, 0, 0.4)
		Kind.SKYLIGHT:
			return global_transform * Vector3(0, -size.y, 0)
		Kind.STRING_LIGHT:
			return global_transform * Vector3(size.x * 0.5, -0.6, 0)
		_:
			return global_transform * Vector3(0, 0.2, 0.3)


## [radius, Color(r, g, b, strength)] defaults per lit kind.
func pool() -> Array:
	var r := 6.0
	var c := Color(1.0, 0.55, 0.18, 0.45)
	match kind:
		Kind.CAMPFIRE:
			r = 9.0
			c = Color(1.0, 0.45, 0.12, 0.7)
		Kind.CHEMLIGHT:
			r = 3.0
			c = Color(0.3, 1.0, 0.35, 0.35)
		Kind.EMERGENCY_LAMP:
			r = 7.0
			c = Color(1.0, 0.12, 0.06, 0.55) if variant % 2 == 0 else Color(1.0, 0.55, 0.1, 0.5)
		Kind.LED_STRIP:
			r = 5.0
			c = Color(0.75, 0.9, 1.0, 0.35)
		Kind.BAY_NUMBER:
			r = 4.0
			c = Color(0.3, 0.8, 1.0, 0.35)
		Kind.STRING_LIGHT:
			r = maxf(size.x * 0.6, 4.0)
			c = Color(1.0, 0.7, 0.35, 0.4)
		Kind.SKYLIGHT:
			r = maxf(size.x, size.z) * 0.9
			c = Color(0.75, 0.82, 0.95, 0.6)
	if pool_radius > 0.0:
		r = pool_radius
	if pool_tint.a > 0.0:
		c = pool_tint
	return [r, c]
