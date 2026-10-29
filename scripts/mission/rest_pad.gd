class_name RestPad
extends Area3D

# A rest point (a bonfire in spirit): stepping on it makes it the respawn point. Its own
# transform is the respawn: origin = his feet, -Z = the way he faces. See
# docs/specs/internals-map.md.

## 1-based, for the HUD and the F1-F3 debug teleports.
@export var index := 1

func _ready() -> void:
	add_to_group(&"rest_pad")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var mission := MissionMap.of(self)
	if mission == null or body != mission.pilot or mission.checkpoint == self:
		return
	mission.set_checkpoint(self)
	MissionHud.say(self, "REST %d - SAVED" % index)
