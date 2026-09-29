## Holds a fixed set of bone rotations on top of whatever the AnimationTree posed, weighted by
## `influence`, which eases toward `target` over `blend_time`. The held item's arm layer - built
## as a SkeletonModifier3D rather than a filtered blend in the tree because the tree's root IS
## the locomotion state machine, and wrapping it would move every `parameters/...` path in the
## project. See docs/specs/pilot9-held-item.md, "How it is built".
extends SkeletonModifier3D

## bone index -> the rotation (bone pose, parent-relative) to hold it at. Empty holds nothing.
var pose: Dictionary = {}
## 0 or 1 - where influence is heading. Set by scripts/items/item_holder.gd every frame.
var target: float = 0.0
## Seconds a full 0 -> 1 fade takes. The spec's ~0.15 s.
var blend_time: float = 0.15


func _init() -> void:
	influence = 0.0


## Eases influence toward target. Separate from the modification itself so a test can step it
## without a skeleton update.
func step(delta: float) -> void:
	if blend_time <= 0.0:
		influence = target
	else:
		influence = move_toward(influence, target, delta / blend_time)


func _process_modification_with_delta(delta: float) -> void:
	step(delta)
	var skel := get_skeleton()
	if skel == null:
		return
	for bone in pose:
		skel.set_bone_pose_rotation(bone, pose[bone])

