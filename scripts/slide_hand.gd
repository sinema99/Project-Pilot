## The slide hand: his right elbow points back behind him and the forearm comes down to the
## floor beside him, instead of tucking under his chest. A two-bone solve on top of whatever the slide
## clip and the item's arm hold posed - so it works drawn or holstered. Built at runtime by
## pilot9.gd::_setup_slide_hand(), after the item holder, so it runs after the item's modifier.
## Tunables are pilot9's slide_hand_target / slide_elbow_pole.
extends SkeletonModifier3D

const UPPER := &"RightUpperArm"
const LOWER := &"RightLowerArm"
const HAND := &"RightHand"

## pilot9: is_sliding, slide_hand_target, slide_elbow_pole.
var body: Node = null
## Seconds a full 0 -> 1 fade takes.
var blend_time: float = 0.12

var _upper := -1
var _lower := -1
var _hand := -1


## An orthonormal basis with `along` as X and `hinge` (made perpendicular to it) as Y.
static func _frame(along: Vector3, hinge: Vector3) -> Basis:
	var y := (hinge - along * hinge.dot(along)).normalized()
	return Basis(along, y, along.cross(y))


func _init() -> void:
	influence = 0.0


func _ready() -> void:
	var skel := get_skeleton()
	if skel != null:
		_upper = skel.find_bone(UPPER)
		_lower = skel.find_bone(LOWER)
		_hand = skel.find_bone(HAND)


## Where the elbow goes for a shoulder at `s` reaching `t` with bones `l1` and `l2`, bent toward
## `pole`. Returns [elbow, hand]; the hand is `t` pulled in to what the arm can reach.
static func solve(s: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var to := t - s
	var dir := to.normalized() if to.length() > 0.0001 else Vector3.DOWN
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var a := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var p := pole - dir * pole.dot(dir)
	p = p.normalized() if p.length() > 0.0001 else dir.cross(Vector3.FORWARD).normalized()
	return [s + dir * a + p * h, s + dir * d]


func _process_modification_with_delta(delta: float) -> void:
	var target := 1.0 if body != null and body.is_sliding else 0.0
	influence = target if blend_time <= 0.0 else move_toward(influence, target, delta / blend_time)
	var skel := get_skeleton()
	if skel == null or _upper < 0 or _lower < 0 or _hand < 0 or influence <= 0.0:
		return
	var up := skel.get_bone_global_pose(_upper)
	var s := up.origin
	var e0 := skel.get_bone_global_pose(_lower).origin
	var h0 := skel.get_bone_global_pose(_hand).origin
	var got := solve(s, body.slide_hand_target, (e0 - s).length(), (h0 - e0).length(),
		body.slide_elbow_pole)
	var elbow: Vector3 = got[0]
	var hand: Vector3 = got[1]
	# The elbow is a hinge. Aim the upper arm AND twist it so the hinge the clip bent around
	# lies across the new bend plane, same way round - a bare shortest-arc aim leaves the twist
	# wherever it was and the forearm then folds backwards through the joint.
	var u0 := (e0 - s).normalized()
	# The hinge is the lower arm's own +X (the clip flexes it positively about X, which is the
	# same way round as upper x forearm).
	var n0 := skel.get_bone_global_pose(_lower).basis.x.normalized()
	var u1 := (elbow - s).normalized()
	var to: Vector3 = body.slide_hand_target - s
	var n1: Vector3 = (elbow - s - to.normalized() * (elbow - s).dot(to.normalized())).cross(to)
	if n1.length() < 0.0001:
		n1 = n0
	up.basis = _frame(u1, n1) * _frame(u0, n0).inverse() * up.basis
	skel.set_bone_global_pose(_upper, up)
	var lo := skel.get_bone_global_pose(_lower)
	var h1 := skel.get_bone_global_pose(_hand).origin
	# Fold only on the hinge (the lower arm's own X - the axis the clip bends it on), so the
	# forearm can't pick up a sideways twist on the way to the hand.
	var hinge := lo.basis.x.normalized()
	var want := hand - lo.origin
	want -= hinge * want.dot(hinge)
	var have := h1 - lo.origin
	have -= hinge * have.dot(hinge)
	if want.length() > 0.0001 and have.length() > 0.0001:
		lo.basis = Basis(hinge, have.signed_angle_to(want, hinge)) * lo.basis
	skel.set_bone_global_pose(_lower, lo)
	# The bones' hinge isn't quite square to the upper arm, so the fold lands a few cm wide.
	# Swing the whole arm about the shoulder onto the target - the elbow bend doesn't change.
	var h2 := skel.get_bone_global_pose(_hand).origin
	if (h2 - s).length() > 0.0001:
		up = skel.get_bone_global_pose(_upper)
		up.basis = Basis(Quaternion((h2 - s).normalized(), (hand - s).normalized())) * up.basis
		skel.set_bone_global_pose(_upper, up)
