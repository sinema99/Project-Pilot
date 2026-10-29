class_name MissionMap
extends Node3D

# A mission scene's root: puts the pilot on the map's spawn empty at load, and puts him back
# there whenever he falls below the kill height. See docs/specs/starter-map.md.
#
# The spawn lives in the .blend (an empty named `spawn`), not in this scene, so a re-export of
# the greybox moves the start with the layout. No empty yet = the origin, facing +Z.
#
# Checkpoints (docs/specs/internals-map.md): a rest pad calls set_checkpoint() and every later
# respawn lands on it instead of the spawn. Kill volumes call respawn(). Both find the mission
# they belong to with MissionMap.of().

## The imported map GLB instance.
@export var map: Node3D
## The pilot9 instance placed and respawned.
@export var pilot: CharacterBody3D
## Name of the empty in `map` he starts on. He faces the empty's Godot -Z (Blender +Y).
@export var spawn_name := "spawn"
## World height below which he has fallen off and is put back on the spawn.
@export var kill_height := -30.0
## Metres above the spawn his feet are placed, so he never starts inside the floor.
@export var spawn_lift := 0.1

## The node respawns land on once a rest pad has been touched; null = the spawn.
var checkpoint: Node3D

## The MissionMap `node` sits under, or null.
static func of(node: Node) -> MissionMap:
	while node != null and not node is MissionMap:
		node = node.get_parent()
	return node as MissionMap

func _ready() -> void:
	respawn()

## Later respawns land on `node` (its transform: origin = feet, -Z = facing).
func set_checkpoint(node: Node3D) -> void:
	checkpoint = node

func _physics_process(_delta: float) -> void:
	if pilot != null and pilot.global_position.y < kill_height:
		respawn()

## The respawn point as a world transform: the checkpoint's, else the empty's, or the origin facing +Z when there is none.
func spawn_transform() -> Transform3D:
	if is_instance_valid(checkpoint):
		return checkpoint.global_transform
	var empty := map.find_child(spawn_name, true, false) as Node3D if map != null else null
	if empty == null:
		return Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	return empty.global_transform

## Puts him on the spawn, standing still, facing the spawn's forward with the camera behind him.
func respawn() -> void:
	if pilot == null:
		return
	var t := spawn_transform()
	var forward := -t.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.BACK
	# Never rotate the pilot9 root: pilot9.gd writes character yaw as a WORLD yaw and CameraPivot
	# is top_level (docs/specs/ichi-parked-ship.md). Turn the two children he faces with.
	var yaw := atan2(forward.x, forward.z)
	pilot.global_position = t.origin + Vector3.UP * spawn_lift
	pilot.velocity = Vector3.ZERO
	var character := pilot.get_node_or_null("character") as Node3D
	if character != null:
		character.rotation.y = yaw
	var pivot := pilot.get_node_or_null("CameraPivot") as Node3D
	if pivot != null:
		pivot.rotation.y = yaw + PI
	if pilot.has_method("_reseed_body_lean") and pilot.is_node_ready():
		pilot.call("_reseed_body_lean")
