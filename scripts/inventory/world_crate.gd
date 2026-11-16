class_name WorldCrate
extends Node3D

# A crate standing in the world: the cargo box a pilot carries in his hands to a mech's stash.
# A static prop - no physics body, it sits where it was put, exactly like a WorldItem. Bids into
# the shared InteractionPrompt with CARRY while he is in reach and facing it with empty hands.
# See docs/specs/pilot9-crate-carry.md.

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const CRATE_DEF := preload("res://resources/items/crate.tres")
const WORLD_ITEM := preload("res://scripts/inventory/world_item.gd")
const INTERACT_ACTION := &"interact"
const GROUP := &"world_crate"

## The crate's edge on the ground, metres (a 3 x 3 cell item).
const SIZE := 0.9

@export var def: ItemDef = CRATE_DEF

var _prompt: Node = null
var _mesh: MeshInstance3D

## Where it first stood: a crate set down over the void goes back here.
var home := Vector3.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	home = global_position
	_mesh = build_box(SIZE, def.color if def != null else Color(0.55, 0.42, 0.26))
	_mesh.name = "Mesh"
	_mesh.position.y = SIZE * 0.5
	add_child(_mesh)


## The crate's look at `edge` metres: a plain box in the item's colour with a darker strap round
## the middle. Shared with the carried one. Origin at the centre.
static func build_box(edge: float, color: Color) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * edge
	root.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	root.material_override = mat
	var strap := MeshInstance3D.new()
	strap.name = "Strap"
	var band := BoxMesh.new()
	band.size = Vector3(edge * 1.02, edge * 0.14, edge * 1.02)
	strap.mesh = band
	var smat := StandardMaterial3D.new()
	smat.albedo_color = color.darkened(0.45)
	smat.roughness = 1.0
	strap.material_override = smat
	root.add_child(strap)
	return root


func _physics_process(_delta: float) -> void:
	var ui := get_node_or_null(^"/root/UI")
	if ui != null and not ui.stack.is_empty():
		return
	var pilot := Inventory.player()
	var cam := get_viewport().get_camera_3d()
	if pilot == null or cam == null or pilot.get("frozen") == true or pilot.get("carry") == null:
		return
	if pilot.get("is_carrying") == true or not pilot.can_begin_carry():
		return
	if not WORLD_ITEM.in_pickup_reach(global_position, pilot.global_position, -cam.global_basis.z):
		return
	if _prompt == null:
		_prompt = PROMPT_SCRIPT.acquire(self)
	if _prompt != null:
		_prompt.offer(self, global_position.distance_to(pilot.global_position), INTERACT_ACTION, "CARRY")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(INTERACT_ACTION):
		return
	if _prompt == null or _prompt.current_source != self:
		return
	var pilot := Inventory.player()
	if pilot == null or pilot.get("carry") == null or not pilot.can_begin_carry():
		return
	get_viewport().set_input_as_handled()
	if pilot.carry.pick_up(def, home):
		_prompt.clear_now()
		remove_from_group(GROUP)
		queue_free()
