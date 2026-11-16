@tool
class_name Hub2Prop
extends StaticBody3D

# One code-built PS1 prop for hub2's storage-facility dressing (docs/specs/hub2-storage.md):
# crates, pallets, racking, vehicles, wall kit, terminals, lamps, plants. Pick `kind` + `variant`
# in the inspector and it rebuilds live. The mesh is shared between props with the same settings.
# Collision: a few boxes on solid things; hanging / thin / plant props have none.
#
# Origin: bottom centre on the floor for floor props; for wall props the wall plane, facing +Z
# (the prop sticks out along +Z); for hanging lamps and vines the ceiling attach point (it hangs
# down -Y by `length`).
# Like CargoContainer the children are built in code with no owner, so none of them is saved.

enum Kind {
	CRATE_WOOD, CRATE_METAL, TOTE, PALLET, RACKING,
	FORKLIFT, REACH_STACKER, SCISSOR_LIFT, PALLET_JACK, FUEL_STATION, WORKBENCH, DOCK_DOOR,
	DOCK_LEVELLER, SPREADER,
	CABINET, JUNCTION_BOX, HOSE_REEL, EXTINGUISHER, TERMINAL,
	LAMP_HIGHBAY, LAMP_BULKHEAD, FLOODLIGHT,
	MOSS, TUFT, SHRUB, TREE, VINE,
	LIGHT_SHAFT,
	HANGAR_DOOR,
	JERSEY_BARRIER, PLATE_SHIELD,
}

@export var kind: Kind = Kind.CRATE_WOOD:
	set(v):
		kind = v
		_queue()
## Kind-specific shape / colour preset (see Hub2PropBuild).
@export_range(0, 7) var variant := 0:
	set(v):
		variant = v
		_queue()
@export var prop_seed := 0:
	set(v):
		prop_seed = v
		_queue()
## 0 = clean, 1 = abandoned for decades.
@export_range(0.0, 1.0, 0.05) var wear := 0.8:
	set(v):
		wear = v
		_queue()
## Lamps: lit (also feeds the hub2 light pools). Terminals: screen on.
@export var powered := false:
	set(v):
		powered = v
		_queue()
## Hanging length (lamp chain, vine) in metres.
@export var length := 2.0:
	set(v):
		length = v
		_queue()

## Lamps: light-pool radius in metres; 0 = the kind's default (Hub2LampPools).
@export var pool_radius := 0.0
## Lamps: pool colour (alpha = strength); alpha 0 = Hub2LampPools' warm default.
@export var pool_tint := Color(0, 0, 0, 0)

var _built := false
static var _cache: Dictionary = {}


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
	var made := build_cached(kind, variant, prop_seed, wear, powered, length)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = made["mesh"]
	if kind != Kind.LIGHT_SHAFT and kind != Kind.HANGAR_DOOR:
		visual.visibility_range_end = 110.0
	visual.set_meta(&"prop_part", true)
	if kind >= Kind.MOSS and kind < Kind.JERSEY_BARRIER:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


## {mesh, boxes: [[centre, size, basis?]]} for these settings, shared.
static func build_cached(k: Kind, v: int, s: int, w: float, p: bool, l: float) -> Dictionary:
	var key := [k, v, s, snappedf(w, 0.05), p, snappedf(l, 0.1)]
	if not _cache.has(key):
		_cache[key] = PropMeshCache.fetch("prop", key, func() -> Dictionary: return Hub2PropBuild.build(k, v, s, w, p, l))
	return _cache[key]


## True for lamps that are lit (the generator writes these into the pool list).
func is_lit_lamp() -> bool:
	return powered and kind in [Kind.LAMP_HIGHBAY, Kind.LAMP_BULKHEAD, Kind.FLOODLIGHT, Kind.LIGHT_SHAFT]


## Where the light comes from, in world space.
func lamp_point() -> Vector3:
	match kind:
		Kind.LAMP_HIGHBAY:
			return global_transform * Vector3(0, -length - 0.6, 0)
		Kind.LAMP_BULKHEAD:
			return global_transform * Vector3(0, 0, 0.35)
		Kind.LIGHT_SHAFT:
			return global_transform * Vector3(0, -length + 3.0, 0)
		_:
			return global_transform * Vector3(0, -0.2, 0.6)
