## Swings pilot9's RIGHT upper arm forward while he stands still, so it hangs level with the left
## one. The stock idle clip leaves the right hand ~0.18 m behind the left (user, 2026-11-13).
## A SkeletonModifier3D on top of the tree, like the held item's arm layer, so no clip is touched
## and no rig rebuild is needed. Fades out as he starts to move.
extends SkeletonModifier3D

const BONE := &"RightUpperArm"
const LEFT_BONE := &"LeftUpperArm"

## Degrees the arm swings forward at full weight. 17 deg brings the hand level with the left's.
var forward_degrees: float = 17.0
## Seconds a full 0 -> 1 fade takes.
var blend_time: float = 0.2
## 0 or 1 - where the weight is heading. Set by pilot9 every frame.
var target: float = 0.0


func _init() -> void:
	influence = 0.0


## The weight idle wants at `horizontal` m/s: 1 standing still, 0 by half walking pace.
static func idle_target(horizontal: float, walk: float) -> float:
	var span := maxf(walk * 0.5, 0.01)
	return clampf(1.0 - horizontal / span, 0.0, 1.0)


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
	var arm := skel.find_bone(BONE)
	var other := skel.find_bone(LEFT_BONE)
	if arm < 0 or other < 0:
		return
	# Forward is read off the rig, not assumed: the way a hanging arm swings to lead the body,
	# found from the shoulder line (right -> left) and down. axis x down = forward.
	var side := skel.get_bone_global_pose(other).origin - skel.get_bone_global_pose(arm).origin
	side.y = 0.0
	if side.length() < 0.001:
		return
	var down := Vector3.DOWN
	var forward := side.normalized().cross(Vector3.UP)
	var axis := down.cross(forward).normalized()
	var gp := skel.get_bone_global_pose(arm)
	var swung := Basis(axis, deg_to_rad(forward_degrees)) * gp.basis
	skel.set_bone_global_pose(arm, Transform3D(swung, gp.origin))
