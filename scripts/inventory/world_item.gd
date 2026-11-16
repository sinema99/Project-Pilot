class_name WorldItem
extends Node3D

# An item lying in the world: what the vicinity box lists and what F picks up. A placeholder box
# sized from the def's grid footprint (or the def's `world_mesh`), origin at its base. No physics
# body - it sits where it was put. See docs/specs/inventory.md.
#
# Bids into the shared InteractionPrompt exactly like a door button: TAKE when it fits, FULL when
# it does not, only while the camera is roughly looking at it and he is within PICKUP_REACH.

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const INTERACT_ACTION := &"interact"
const GROUP := &"world_item"

## Metres per grid cell for the placeholder box, and its height.
const CELL_M := 0.2
const BOX_H := 0.14

@export var def: ItemDef
@export var count := 1
## A container's own grid (a backpack's), kept while it lies here. Made empty in _ready() for a
## container placed in a scene. See docs/specs/pilot9-backpack.md.
var contents: ItemGrid = null

var _prompt: Node = null
var _mesh: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	if contents == null and def != null and def.is_container():
		contents = ItemGrid.make_container(def.container_size)
	_build()


func _build() -> void:
	if def != null and def.id == &"backpack":
		# Its own model, standing on its bottom, back face down-slope a touch.
		_mesh = preload("res://scripts/inventory/item_icons.gd")._backpack_node(true)
		_mesh.name = "Mesh"
		_mesh.rotation.x = deg_to_rad(-8.0)
		_mesh.position.z = -0.1
		add_child(_mesh)
		return
	var mi := MeshInstance3D.new()
	_mesh = mi
	_mesh.name = "Mesh"
	if def != null and def.world_mesh != null:
		mi.mesh = def.world_mesh
	else:
		var box := BoxMesh.new()
		var s := def.size if def != null else Vector2i.ONE
		box.size = Vector3(s.x * CELL_M, BOX_H, s.y * CELL_M)
		mi.mesh = box
		_mesh.position.y = BOX_H * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = def.color if def != null else Color.GRAY
		mi.material_override = mat
	add_child(_mesh)


## The prompt word this item would show right now.
func prompt_word() -> String:
	return "TAKE" if Inventory.can_take(self) else "FULL"


## True while `pilot` could press F on this: in reach and in front of `cam`.
static func in_pickup_reach(item_pos: Vector3, pilot_pos: Vector3, cam_forward: Vector3) -> bool:
	var to_item := item_pos - pilot_pos
	if to_item.length() > Inventory.PICKUP_REACH:
		return false
	var flat := Vector3(to_item.x, 0.0, to_item.z)
	var fwd := Vector3(cam_forward.x, 0.0, cam_forward.z)
	# Standing on top of it counts as facing it.
	if flat.length() < 0.3 or fwd.length() < 0.001:
		return true
	return flat.normalized().dot(fwd.normalized()) >= cos(deg_to_rad(Inventory.PICKUP_CONE_DEG))


func _physics_process(_delta: float) -> void:
	if def == null or count <= 0:
		return
	var ui := get_node_or_null(^"/root/UI")
	if ui != null and not ui.stack.is_empty():
		return
	var pilot := Inventory.player()
	var cam := get_viewport().get_camera_3d()
	if pilot == null or cam == null or pilot.get("frozen") == true:
		return
	if not in_pickup_reach(global_position, pilot.global_position, -cam.global_basis.z):
		return
	if _prompt == null:
		_prompt = PROMPT_SCRIPT.acquire(self)
	if _prompt != null:
		_prompt.offer(self, global_position.distance_to(pilot.global_position), INTERACT_ACTION,
			prompt_word())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(INTERACT_ACTION):
		return
	if _prompt == null or _prompt.current_source != self:
		return
	# FULL does nothing, but still swallows the press so EXIA / a door behind it stays put.
	get_viewport().set_input_as_handled()
	if Inventory.take(self) > 0 and count <= 0:
		_prompt.clear_now()
