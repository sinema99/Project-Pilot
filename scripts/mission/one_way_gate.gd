class_name OneWayGate
extends StaticBody3D

# A Dark Souls shortcut door: solid until the pilot reaches its child `Opener` area (placed on
# the side it opens from), then gone for the rest of the run. See docs/specs/internals-map.md.

func _ready() -> void:
	var opener := get_node_or_null("Opener") as Area3D
	if opener != null:
		opener.body_entered.connect(_on_opener_entered)

func _on_opener_entered(body: Node3D) -> void:
	var mission := MissionMap.of(self)
	if mission != null and body == mission.pilot:
		open()

func open() -> void:
	if not visible:
		return
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	collision_layer = 0
	MissionHud.say(self, "SHORTCUT OPENED")
