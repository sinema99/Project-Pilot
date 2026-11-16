## The reload animation: arm poses keyed over the reload's 0..1 progress, and the code-built props
## that go with them (a magazine and a speedloader, spent brass). Built by gunplay.gd; pilot9's item
## holder asks it to lay the poses over the hold. No clips and no Blender: the guns have no named
## moving parts, so the arms and the whole gun do the work. The key poses are SOLVED, not authored -
## tests/_probe_solve_reload.gd searches the arm joints for rotations that put the gun and the left
## hand where this file's table wants them, and writes gun_reload_poses.gd. See
## docs/specs/pilot9-gunplay-pass2.md.
extends Node

const _Poses := preload("res://scripts/items/gun_reload_poses.gd")

## gun -> "EMPTY" / "TACTICAL" -> keys [time 0..1, pose name, optional event]. BASE is the hold the
## reload starts from and returns to; the poses are the solved ones. Between keys the arms ease.
const TIMELINES := {
	"REVOLVER": {
		"EMPTY": [[0.0, "BASE"], [0.18, "R1"], [0.34, "R1", "brass"], [0.5, "R1", "loader"],
			[0.66, "R2"], [0.74, "R2", "seat"], [0.84, "R2"], [1.0, "BASE"]],
		"TACTICAL": [[0.0, "BASE"], [0.2, "R1"], [0.34, "R1", "brass"], [0.5, "R1", "loader"],
			[0.66, "R2"], [0.74, "R2", "seat"], [0.86, "R2"], [1.0, "BASE"]],
	},
	"RIFLE": {
		"EMPTY": [[0.0, "BASE"], [0.14, "R1"], [0.2, "R1", "drop_mag"], [0.34, "R1", "new_mag"],
			[0.46, "R2"], [0.52, "R2", "seat"], [0.6, "R2"], [0.66, "R3"], [0.74, "R4"], [0.82, "R3"],
			[1.0, "BASE"]],
		"TACTICAL": [[0.0, "BASE"], [0.18, "R1"], [0.26, "R1", "drop_mag"], [0.42, "R1", "new_mag"],
			[0.62, "R2"], [0.7, "R2", "seat"], [0.8, "R2"], [1.0, "BASE"]],
	},
}

## Where the held prop rides, in the gun's own frame: [from, to]. It tracks the left hand's targets.
const PROP_PATH := {
	"new_mag": [Vector3(0.0, -0.30, -0.05), Vector3(0.0, -0.10, -0.05)],
	"loader": [Vector3(0.05, 0.14, -0.07), Vector3(0.05, 0.05, -0.07)],
}

var _pilot: Node = null
var _holder: Node = null
var _fx: Node = null
var _done := {}
var _props := {}
## Fed to the arm modifier: bone index -> weight, 0 leaves the animation's own rotation.
var weights := {}


func setup(pilot: Node, holder: Node, fx: Node) -> void:
	_pilot = pilot
	_holder = holder
	_fx = fx


static func timeline_for(gun_name: String, was_empty: bool) -> Array:
	var t: Dictionary = TIMELINES.get(gun_name, {})
	return t.get("EMPTY" if was_empty else "TACTICAL", [])


## The index of the key at or before `progress`, or the last key's index.
static func segment(keys: Array, progress: float) -> int:
	var i := 0
	while i < keys.size() - 2 and progress >= float(keys[i + 1][0]):
		i += 1
	return i


## Eased 0..1 across a segment.
static func segment_k(keys: Array, i: int, progress: float) -> float:
	var a := float(keys[i][0])
	var b := float(keys[i + 1][0])
	return smoothstep(0.0, 1.0, clampf((progress - a) / maxf(b - a, 0.0001), 0.0, 1.0))


## `base` (bone index -> Quaternion, the hip / aim hold) with the reload laid over it. A bone the
## hold does not set (the revolver's left arm) fades in from the animation's own rotation.
func overlay(base: Dictionary, gun_name: String, progress: float, was_empty: bool,
		skel: Skeleton3D) -> Dictionary:
	weights = {}
	var keys := timeline_for(gun_name, was_empty)
	if progress < 0.0 or skel == null or keys.is_empty() or not _Poses.POSES.has(gun_name):
		return base
	var i := segment(keys, progress)
	var k := segment_k(keys, i, progress)
	var a := _key_pose(keys[i][1], gun_name, base, skel)
	var b := _key_pose(keys[i + 1][1], gun_name, base, skel)
	var out := base.duplicate()
	for bone in _union(a, b):
		var ea = a.get(bone)
		var eb = b.get(bone)
		var qa = ea[0] if ea != null else null
		var qb = eb[0] if eb != null else null
		var wa: float = ea[1] if ea != null else 0.0
		var wb: float = eb[1] if eb != null else 0.0
		if qa == null and qb == null:
			continue
		var q: Quaternion
		if qa == null:
			q = qb
		elif qb == null:
			q = qa
		else:
			q = (qa as Quaternion).slerp(qb, k)
		out[bone] = q
		weights[bone] = lerpf(wa, wb, k)
	return out


func _union(a: Dictionary, b: Dictionary) -> Array:
	var u: Array = a.keys()
	for k in b:
		if not a.has(k):
			u.append(k)
	return u


## bone index -> [Quaternion, weight] for one key. BASE is the incoming hold (weight 1), and a
## bone only the poses set is [null, 0] there: nothing to hold, so the animation keeps it.
func _key_pose(pose_name: String, gun_name: String, base: Dictionary, skel: Skeleton3D) -> Dictionary:
	var out := {}
	if pose_name == "BASE":
		for bone in base:
			out[bone] = [base[bone], 1.0]
		for bone_name in _Poses.POSES[gun_name]["R1"]:
			var idx := skel.find_bone(bone_name)
			if idx >= 0 and not out.has(idx):
				out[idx] = [null, 0.0]
		return out
	var pose: Dictionary = _Poses.POSES[gun_name][pose_name]
	for bone_name in pose:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var d: Vector3 = pose[bone_name]
		out[idx] = [Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))), 1.0]
	return out


# --- props -------------------------------------------------------------------------------------

## Runs every frame: fires the reload's events as the progress passes them, and carries the held prop.
func step(g: GunDef, progress: float, was_empty: bool, _delta: float) -> void:
	if g == null or progress < 0.0:
		if not _done.is_empty() or not _props.is_empty():
			_clear()
		return
	var keys := timeline_for(g.display_name, was_empty)
	for key in keys:
		if key.size() > 2 and not _done.has(key[2]) and progress >= float(key[0]):
			_done[key[2]] = float(key[0])
			_fire(String(key[2]), keys)
	for prop_name in _props:
		_carry(prop_name, progress, keys)


func _fire(event: String, _keys: Array) -> void:
	match event:
		"drop_mag":
			_drop_mag()
		"brass":
			_dump_brass()
		"new_mag":
			_hold_prop("new_mag", Vector3(0.04, 0.16, 0.07), Color(0.2, 0.22, 0.2))
		"loader":
			_hold_prop("loader", Vector3(0.035, 0.035, 0.08), Color(0.78, 0.58, 0.2))
		"seat":
			for n in _props:
				if is_instance_valid(_props[n]):
					_props[n].queue_free()
			_props.clear()


func _clear() -> void:
	_done.clear()
	for n in _props:
		if is_instance_valid(_props[n]):
			_props[n].queue_free()
	_props.clear()


func _gun_node() -> Node3D:
	return _holder.item_instance if _holder != null else null


func _hold_prop(prop_name: String, size: Vector3, colour: Color) -> void:
	var gun := _gun_node()
	if gun == null:
		return
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = _fx.flat(colour)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun.add_child(m)
	m.position = PROP_PATH[prop_name][0]
	_props[prop_name] = m


## The held prop rides the left hand's own path: from its start to its seat between the key it
## appeared at and the "seat" key.
func _carry(prop_name: String, progress: float, keys: Array) -> void:
	var node: Node3D = _props[prop_name]
	if not is_instance_valid(node) or not _done.has(prop_name):
		return
	var t0: float = _done[prop_name]
	var t1 := 1.0
	for key in keys:
		if key.size() > 2 and key[2] == "seat":
			t1 = float(key[0])
	var k := smoothstep(0.0, 1.0, clampf((progress - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0))
	var path: Array = PROP_PATH[prop_name]
	node.position = (path[0] as Vector3).lerp(path[1], k)


## The old rifle magazine falls away from the well.
func _drop_mag() -> void:
	var gun := _gun_node()
	if gun == null:
		return
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.04, 0.16, 0.07)
	m.mesh = b
	m.material_override = _fx.flat(Color(0.12, 0.13, 0.14))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.debris(m, gun.global_transform * Vector3(0, -0.13, -0.05), Vector3.DOWN * 0.6, 1.4)


func _dump_brass() -> void:
	var gun := _gun_node()
	if gun == null:
		return
	var xf := gun.global_transform
	for i in 6:
		_fx.casing(xf * Vector3(0, 0.02, -0.08), Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)), 1.2)
