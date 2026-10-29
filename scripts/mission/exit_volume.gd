class_name ExitVolume
extends Area3D

# The end of the mission. For now it only stops the HUD clock, so a greybox run can be timed.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var mission := MissionMap.of(self)
	if mission == null or body != mission.pilot:
		return
	var hud := MissionHud.of(self)
	if hud != null:
		hud.finish()
