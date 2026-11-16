## pilot9's holstered weapons, shown on his body: the rifle upright along the left side of the
## backpack (diagonal across his back with no pack), the revolver outside his right thigh. Each is its
## own copy of the weapon's scene, parked on a bone. While a weapon is drawn the copy is gone; the
## equip animation's materialize runs it backwards here - the copy shrinks away behind the same cyan
## glow as the hand copy forms - so one weapon seems to travel between the body and the hand.
## Built at runtime by pilot9.gd::_setup_weapon_mounts(). See docs/specs/pilot9-weapon-mounts.md.
extends Node

const _SHELL_SHADER := preload("res://shaders/cel/vfx/materialize_shell.gdshader")
const SHELL_META := &"materialize_shell"

var _skeleton: Skeleton3D = null
var _holder: Node = null
var _equip: Node = null
var _backpack: Node = null
var _sockets: Dictionary = {}
## One per slotted weapon: {item, node, socket, shells, bare}
var _mounts: Array[Dictionary] = []
var _shell_mat: ShaderMaterial = null


# --- pure helpers, static so tests can check them without a rig ---------------------------------

## The item-frame basis for a weapon parked with its barrel along `muzzle` and the top of the gun
## toward `top` (both skeleton space). The item frame: -Z down the barrel, +Y the top, +X its left.
static func slot_basis(muzzle: Vector3, top: Vector3) -> Basis:
	var z := -muzzle.normalized()
	var y := (top - z * top.dot(z))
	if y.length_squared() < 0.000001:
		y = z.cross(Vector3.RIGHT) if absf(z.x) < 0.9 else z.cross(Vector3.UP)
	y = y.normalized()
	return Basis(y.cross(z).normalized(), y, z)


## How much of the weapon has formed in his hand, 0..1 - the hand copy's amount, so the body copy
## is the rest. `playing` is an equip animation running at timeline time `t`; otherwise the weapon
## is in his hand (1) when it is the one carried and drawn, else not (0).
static func hand_amount(is_carried: bool, drawn: bool, playing: bool, t: float, out_time: float,
		sweep_time: float) -> float:
	if not is_carried:
		return 0.0
	if playing:
		var x := clampf((t - out_time) / maxf(sweep_time, 0.0001), 0.0, 1.0)
		return 1.0 - (1.0 - x) * (1.0 - x)
	return 1.0 if drawn else 0.0


## The body copy's glow, 0..1: dark while whole, full as it nears gone.
static func slot_glow(amount: float, fade_part: float) -> float:
	return clampf(amount / maxf(fade_part, 0.0001), 0.0, 1.0)


# --- wiring -------------------------------------------------------------------------------------

func setup(skeleton: Skeleton3D, holder: Node, equip: Node, backpack: Node) -> void:
	_skeleton = skeleton
	_holder = holder
	_equip = equip
	_backpack = backpack
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = _SHELL_SHADER


## Shows exactly the weapons in `items` (a loadout's HeldItems) that have a body slot.
func set_items(items: Array) -> void:
	for m in _mounts:
		if is_instance_valid(m.node):
			m.node.queue_free()
			m.node.get_parent().remove_child(m.node)
	_mounts.clear()
	if _skeleton == null:
		return
	for it in items:
		var item := it as HeldItem
		if item == null or item.scene == null or item.slot_bone == &"" or item.can_reflect:
			continue
		var socket := _socket_for(item.slot_bone)
		if socket == null:
			continue
		var node := item.scene.instantiate() as Node3D
		if node == null:
			continue
		node.name = &"Mount_%s" % item.resource_path.get_file().get_basename()
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		socket.add_child(node)
		var m := {"item": item, "node": node, "socket": socket, "shells": [], "bare": null}
		_build_shells(node, m.shells)
		_mounts.append(m)
		_place(m)
		_update(m)


func _socket_for(bone: StringName) -> BoneAttachment3D:
	if _sockets.has(bone) and is_instance_valid(_sockets[bone]):
		return _sockets[bone]
	var s := BoneAttachment3D.new()
	s.name = StringName("WeaponMount" + String(bone))
	_skeleton.add_child(s)
	s.bone_name = bone
	if s.bone_idx < 0:
		push_error("weapon_mounts: skeleton has no bone '%s'" % bone)
		s.queue_free()
		_skeleton.remove_child(s)
		return null
	_sockets[bone] = s
	return s


func _build_shells(item: Node3D, out: Array) -> void:
	for node in item.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(SHELL_META):
			continue
		var sh := MeshInstance3D.new()
		sh.name = &"MountShell"
		sh.set_meta(SHELL_META, true)
		sh.set_meta(&"airframe_skip", true)
		sh.mesh = mi.mesh
		sh.material_override = _shell_mat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		sh.visible = false
		mi.add_child(sh)
		out.append(sh)


func _bare() -> bool:
	return _backpack == null or not _backpack.is_on


## The weapon's transform under its bone socket for the current pack state.
func _placement(m: Dictionary) -> Transform3D:
	var item: HeldItem = m.item
	var origin := item.slot_origin
	var muzzle := item.slot_muzzle_dir
	var top := item.slot_top_dir
	if _bare() and item.slot_bare_muzzle_dir != Vector3.ZERO:
		origin = item.slot_bare_origin
		muzzle = item.slot_bare_muzzle_dir
		top = item.slot_bare_top_dir
	var skel_xf := Transform3D(slot_basis(muzzle, top), origin)
	var socket: BoneAttachment3D = m.socket
	return _skeleton.get_bone_global_rest(socket.bone_idx).affine_inverse() * skel_xf


func _place(m: Dictionary) -> void:
	m["xf"] = _placement(m)
	m["bare"] = _bare()


## Whether `node` is part of a body copy - pilot9's rim light skips these.
func owns(node: Node) -> bool:
	for m in _mounts:
		if is_instance_valid(m.node) and (m.node == node or m.node.is_ancestor_of(node)):
			return true
	return false


func _process(_delta: float) -> void:
	for m in _mounts:
		if m.bare != _bare():
			_place(m)
		_update(m)


func _update(m: Dictionary) -> void:
	var node: Node3D = m.node
	if _holder == null:
		return
	var carried: bool = _holder.held_item == m.item and _holder.item_instance != null
	var playing: bool = _equip != null and _equip.direction != 0
	var out_t: float = _equip.out_time if _equip != null else 0.0
	var sweep_t: float = _equip.sweep_time if _equip != null else 0.0
	var tt: float = _equip.t if _equip != null else 0.0
	var amount := hand_amount(carried, _holder.is_drawn, playing, tt, out_t, sweep_t)
	var left := 1.0 - amount
	node.visible = left > 0.001
	if not node.visible:
		for sh in m.shells:
			sh.visible = false
		return
	node.transform = (m.xf as Transform3D) * Transform3D(Basis.from_scale(Vector3.ONE * left))
	var fade_part: float = _equip.edge_fade if _equip != null else 0.3
	var glow := slot_glow(amount, fade_part)
	for sh in m.shells:
		sh.visible = amount > 0.0 and glow > 0.0
	# Only the copy that is travelling drives the shared glow material.
	if amount <= 0.0:
		return
	if _equip != null:
		var c: Color = _equip.edge_color
		_shell_mat.set_shader_parameter(&"edge_color", Vector3(c.r, c.g, c.b))
		_shell_mat.set_shader_parameter(&"energy", _equip.edge_energy)
	_shell_mat.set_shader_parameter(&"fade", glow)
