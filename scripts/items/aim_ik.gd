## The gun aim, built from placement rather than posed angles: the gun goes where a shooter holds it
## ON HIS BODY (a rifle's butt in the right shoulder pocket, a pistol pushed out in front of the
## chest - never placed from the head), pointing at the aim point, then each arm reaches its grip on
## it with a two-bone solve. The upper body bends with the aim first (bend()). Everything here is in
## SKELETON space and static, so a test can drive it without a rig. See docs/specs/pilot9-gun-aim.md.
extends RefCounted


## The gun's frame (item frame: origin at the pistol grip, -Z down the barrel, +Y up): the item
## point `anchor_item` (the stock's butt, or a point on a pistol's barrel line) is pinned to `anchor`
## on his body, and the barrel points from there at `aim_pt`.
static func item_frame(anchor: Vector3, aim_pt: Vector3, up: Vector3, anchor_item: Vector3) -> Transform3D:
	var d := (aim_pt - anchor).normalized()
	var y := (up - d * up.dot(d)).normalized()
	var z := -d
	var x := y.cross(z).normalized()
	var basis := Basis(x, y, z)
	return Transform3D(basis, anchor - basis * anchor_item)


## Where the gun is pinned on his body: from the right shoulder joint (or, `center`, the midpoint of
## both shoulder joints) by `offset` = (right, up, forward) metres, in the frame of the aim itself -
## forward is toward the aim point, so the offset leans with his bent torso.
static func anchor_point(right_joint: Vector3, left_joint: Vector3, center: bool, offset: Vector3,
		aim_pt: Vector3, up: Vector3, left: Vector3) -> Vector3:
	var base := (right_joint + left_joint) * 0.5 if center else right_joint
	var f := (aim_pt - base).normalized()
	var u := (up - f * up.dot(f)).normalized()
	var r := f.cross(u).normalized()
	if r.dot(-left) < 0.0:
		r = -r
	return base + r * offset.x + u * offset.y + f * offset.z


## Rotates `bones` (in parent-to-child order) about `axis` (skeleton space) by `angles` radians each,
## on top of whatever they hold. Each bone reads its parent AFTER the earlier ones moved, so the
## angles add up along the chain. The upper-body bend of an aim up or down.
static func bend(skel: Skeleton3D, bones: Array, axis: Vector3, angles: Array) -> void:
	for i in bones.size():
		var bone: int = bones[i]
		if bone < 0 or absf(angles[i]) < 0.00001:
			continue
		var g := skel.get_bone_global_pose(bone).basis.orthonormalized()
		set_global_basis(skel, bone, Basis(axis.normalized(), angles[i]) * g)


## How far above level `aim_pt` is from `from`, radians (negative below), against `up`.
static func pitch_to(from: Vector3, aim_pt: Vector3, up: Vector3) -> float:
	var d := (aim_pt - from).normalized()
	return asin(clampf(d.dot(up), -1.0, 1.0))


## Sets `bone`'s GLOBAL basis (skeleton space) by writing its local rotation.
static func set_global_basis(skel: Skeleton3D, bone: int, basis: Basis) -> void:
	var p := skel.get_bone_parent(bone)
	var pg := skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	skel.set_bone_pose_rotation(bone, (pg.inverse() * basis.orthonormalized()).get_rotation_quaternion())


## Two-bone reach: the hand origin goes to `target` (clamped to what the arm can reach) with the
## elbow bent toward `pole` (a direction). The bones keep the roll the animation gave them - each is
## only swung - and the hand's own orientation is for the caller to set afterwards.
static func two_bone(skel: Skeleton3D, upper: int, lower: int, hand: int, target: Vector3,
		pole: Vector3) -> void:
	var s := skel.get_bone_global_pose(upper).origin
	var c1 := skel.get_bone_rest(lower).origin
	var c2 := skel.get_bone_rest(hand).origin
	var l1 := c1.length()
	var l2 := c2.length()
	var to := target - s
	var dist := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dir * pole.dot(dir)
	if perp.length() < 0.0001:
		perp = dir.cross(Vector3.RIGHT) if absf(dir.dot(Vector3.RIGHT)) < 0.9 else dir.cross(Vector3.UP)
	perp = perp.normalized()
	var elbow := s + dir * a + perp * h
	var wrist := s + dir * dist
	var gu := skel.get_bone_global_pose(upper).basis.orthonormalized()
	var swing_u := Quaternion((gu * c1).normalized(), (elbow - s).normalized())
	set_global_basis(skel, upper, Basis(swing_u) * gu)
	var gl := skel.get_bone_global_pose(lower).basis.orthonormalized()
	var swing_l := Quaternion((gl * c2).normalized(), (wrist - elbow).normalized())
	set_global_basis(skel, lower, Basis(swing_l) * gl)


## A direction given as (right, up, forward) in his frame, in skeleton space.
static func body_dir(v: Vector3, up: Vector3, left: Vector3) -> Vector3:
	return (-left) * v.x + up * v.y + left.cross(up).normalized() * v.z


## The whole aim, applied to `skel`: the gun is pinned to his body by anchor_point() / item_frame()
## and both arms reach their grips on it. `p` holds, all in skeleton space:
##   aim_pt, up (his up), left (his left), item (HeldItem), weight 0..1 (how far from the current
##   pose to the solved one).
## Returns the gun's frame, or an identity transform when it did nothing.
static func apply(skel: Skeleton3D, p: Dictionary) -> Transform3D:
	var item: HeldItem = p.item
	var w: float = p.weight
	if skel == null or item == null or w <= 0.001:
		return Transform3D.IDENTITY
	var names := [&"RightUpperArm", &"RightLowerArm", &"RightHand",
		&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"]
	var idx := {}
	var before := {}
	for n in names:
		idx[n] = skel.find_bone(n)
		if idx[n] < 0:
			return Transform3D.IDENTITY
		before[n] = skel.get_bone_pose_rotation(idx[n])
	var up: Vector3 = p.up
	var left: Vector3 = p.left
	var anchor := anchor_point(skel.get_bone_global_pose(idx[&"RightUpperArm"]).origin,
		skel.get_bone_global_pose(idx[&"LeftUpperArm"]).origin, item.aim_center,
		item.aim_anchor_offset, p.aim_pt, up, left)
	var gun := item_frame(anchor, p.aim_pt, up, item.aim_anchor_item)
	var right_hand := gun * item.hand_offset.affine_inverse()
	var left_hand := gun * item.aim_left_hand
	two_bone(skel, idx[&"RightUpperArm"], idx[&"RightLowerArm"], idx[&"RightHand"],
		right_hand.origin, body_dir(item.aim_right_pole, up, left))
	set_global_basis(skel, idx[&"RightHand"], right_hand.basis)
	two_bone(skel, idx[&"LeftUpperArm"], idx[&"LeftLowerArm"], idx[&"LeftHand"],
		left_hand.origin, body_dir(item.aim_left_pole, up, left))
	set_global_basis(skel, idx[&"LeftHand"], left_hand.basis)
	if w < 0.999:
		for n in names:
			var solved := skel.get_bone_pose_rotation(idx[n])
			skel.set_bone_pose_rotation(idx[n], (before[n] as Quaternion).slerp(solved, w))
	return gun
