@tool
class_name ParkedShip
extends StaticBody3D

# A ship parked with its clips frozen on their last frame - Sinestro2 in Ichi, canopy open and
# gear down. See docs/specs/ichi-parked-ship.md.
#
# Not played through the AnimationPlayer: Godot's importer gives every clip rest tracks for the
# armatures it does not animate, so playing the clips in turn keeps only the last one's pose.
# Each clip's last key is written onto its own armature instead. @tool so the editor shows the
# parked pose and the ship can be placed by eye.

## Clip name -> the armature node (child of `model`) whose bones that clip poses.
@export var hold := {
	&"cockpit_open": ^"Armature_001",
	&"landingear": ^"Armature_002",
	&"Action": ^"Armature_003",
}
## The imported GLB instance.
@export var model: Node3D

func _ready() -> void:
	pose()

## Writes every held clip's last key onto its armature's bones. Returns how many tracks it wrote.
func pose() -> int:
	if model == null:
		return 0
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return 0
	var written := 0
	for clip: StringName in hold:
		if not player.has_animation(clip):
			push_warning("ParkedShip: no clip %s" % clip)
			continue
		var anim := player.get_animation(clip)
		var armature := String(hold[clip])
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			if path.get_name(0) != armature or anim.track_get_key_count(t) == 0:
				continue
			var skel := model.get_node_or_null(NodePath(String(path.get_concatenated_names()))) as Skeleton3D
			if skel == null:
				continue
			var bone := skel.find_bone(path.get_concatenated_subnames())
			if bone < 0:
				continue
			var value: Variant = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					skel.set_bone_pose_position(bone, value)
				Animation.TYPE_ROTATION_3D:
					skel.set_bone_pose_rotation(bone, value)
				Animation.TYPE_SCALE_3D:
					skel.set_bone_pose_scale(bone, value)
				_:
					continue
			written += 1
	return written
