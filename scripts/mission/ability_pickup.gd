class_name AbilityPickup
extends Area3D

# A movement tech found in the map: touching it sets one pilot9 export (the double jump is
# `air_jumps` = 1) and hides the pickup. See docs/specs/internals-map.md.

@export var property := &"air_jumps"
@export var value: Variant = 1
@export var message := "DOUBLE JUMP"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var mission := MissionMap.of(self)
	if mission == null or body != mission.pilot or not visible:
		return
	body.set(property, value)
	visible = false
	MissionHud.say(self, message)
