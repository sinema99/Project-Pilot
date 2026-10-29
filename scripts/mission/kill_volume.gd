class_name KillVolume
extends Area3D

# A pit floor: the pilot touching it is put back on his last rest pad (or the spawn). The game
# has no fall damage, so every lethal drop needs one of these. See docs/specs/internals-map.md.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var mission := MissionMap.of(self)
	if mission != null and body == mission.pilot:
		mission.respawn.call_deferred()
