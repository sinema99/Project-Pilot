## pilot9's backpack: the pack rigid on his UpperChest bone, the shoulder straps over each
## Shoulder bone and down round his ribs, shown or hidden as a snap by the inventory's BACK slot.
## Built at runtime by pilot9.gd::_setup_backpack(). Fitted to his bare back; the trench coat simply
## clips with it (user, 2026-11-14). See docs/specs/pilot9-backpack.md.
extends Node

const _BackpackMesh := preload("res://scripts/items/backpack_mesh.gd")
const _CEL := preload("res://resources/pilot_cel_character.tres")

const CHEST_BONE := &"UpperChest"

## Where the pack sits, in skeleton space (glTF: +Y up, his back faces -Z): the bottom centre of
## the face that lies on his back, and how far its top leans in toward him (degrees).
@export var pack_origin := Vector3(0.0, 1.04, -0.135):
	set(value):
		pack_origin = value
		_place()
@export var pack_lean := 4.0:
	set(value):
		pack_lean = value
		_place()
@export var pack_scale := 1.0:
	set(value):
		pack_scale = value
		_place()
## Squeezes the pack across his back only (1 = as modelled).
@export var pack_width := 0.85:
	set(value):
		pack_width = value
		_place()

@export_group("Colours")
@export var canvas_color := _BackpackMesh.COLOURS[0]
@export var seam_color := _BackpackMesh.COLOURS[1]
@export var leather_color := _BackpackMesh.COLOURS[2]
@export var metal_color := _BackpackMesh.COLOURS[3]
@export var thruster_color := _BackpackMesh.COLOURS[4]
## How hard the thruster caps glow.
@export var thruster_glow := 4.0

## Strap paths in skeleton space for his left side (+X); the right is the mirror. UPPER rides the
## Shoulder bone (pack top, over the shoulder, down the chest); LOWER rides the chest (chest, under
## the arm, round to the pack's bottom corner).
const STRAP_UPPER := [
	Vector3(0.10, 1.44, -0.12), Vector3(0.11, 1.53, -0.11), Vector3(0.12, 1.585, -0.07),
	Vector3(0.125, 1.595, 0.02), Vector3(0.13, 1.56, 0.11), Vector3(0.135, 1.47, 0.18),
	Vector3(0.14, 1.36, 0.208),
]
const STRAP_LOWER := [
	Vector3(0.14, 1.36, 0.208), Vector3(0.15, 1.27, 0.212), Vector3(0.19, 1.17, 0.175),
	Vector3(0.215, 1.10, 0.06), Vector3(0.205, 1.05, -0.08), Vector3(0.18, 1.02, -0.16),
]
const STRAP_CENTRE := Vector3(0.0, 1.33, 0.0)

var is_on := false
var chest_socket: BoneAttachment3D = null
## The pack's root (pack space under it, one MeshInstance3D per colour); straps hang off their own
## sockets.
var pack: Node3D = null
var straps: Array[MeshInstance3D] = []

var _skeleton: Skeleton3D = null
var _sockets: Array[BoneAttachment3D] = []


func setup(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		push_error("backpack_holder: no skeleton - pilot9 will not be able to wear the backpack")
		return
	_skeleton = skeleton
	chest_socket = _socket(CHEST_BONE)
	var mats := []
	for c in [canvas_color, seam_color, leather_color, metal_color]:
		mats.append(_tinted(c))
	mats.append(_tinted(thruster_color, thruster_glow))
	pack = _BackpackMesh.build_node(mats)
	pack.name = &"Backpack"
	chest_socket.add_child(pack)
	_place()
	# No shoulder straps: the user wants just the pack (2026-11-14). _strap() and the STRAP_ paths stay
	# for if they come back.
	set_on(false)


func toggle() -> void:
	set_on(not is_on)


func set_on(on: bool) -> void:
	is_on = on
	if pack != null:
		pack.visible = on
	for s in straps:
		s.visible = on


## The pack's transform in skeleton space.
func pack_transform() -> Transform3D:
	var b := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-pack_lean))
	return Transform3D(b * Basis.from_scale(Vector3(pack_width, 1.0, 1.0) * pack_scale), pack_origin)


func _place() -> void:
	if pack == null or _skeleton == null or chest_socket.bone_idx < 0:
		return
	pack.transform = _skeleton.get_bone_global_rest(chest_socket.bone_idx).affine_inverse() * pack_transform()


func _socket(bone: StringName) -> BoneAttachment3D:
	var s := BoneAttachment3D.new()
	s.name = StringName("Backpack" + String(bone))
	_skeleton.add_child(s)
	s.bone_name = bone
	if s.bone_idx < 0:
		push_error("backpack_holder: skeleton has no bone '%s'" % bone)
	_sockets.append(s)
	return s


## A strap built in skeleton space and parked in its socket so it lines up in the rest pose.
func _strap(socket: BoneAttachment3D, path: PackedVector3Array, side: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = StringName("Strap%s%d" % ["L" if side > 0.0 else "R", straps.size()])
	mi.mesh = _BackpackMesh.build_strap(path, STRAP_CENTRE)
	mi.material_override = _tinted(leather_color)
	socket.add_child(mi)
	if socket.bone_idx >= 0:
		mi.transform = _skeleton.get_bone_global_rest(socket.bone_idx).affine_inverse()
	straps.append(mi)


static func _mirror(points: Array, side: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector3 in points:
		out.append(Vector3(p.x * side, p.y, p.z))
	return out


## pilot9's cel material in another colour; the ink pass is shared.
static func _tinted(color: Color, glow: float = 0.0) -> ShaderMaterial:
	var mat := _CEL.duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"color", color)
	if glow > 0.0:
		mat.set_shader_parameter(&"emission", color)
		mat.set_shader_parameter(&"emission_energy", glow)
	return mat
