extends RefCounted

## Shrinks how far chosen joints swing in a cycle clip without moving their timing.
## See docs/specs/pilot9-run-arm-swing.md.
##
## "The middle of the swing" is the joint's average rotation over the cycle. Each key is slerped
## from that middle toward itself by `factor`, so its angular distance from the middle becomes
## `factor` of what it was along the same arc - the biggest key stays the biggest, which is what
## keeps the apex on its frame and the arms in time with the legs.

## Every rotation track in `anim` whose bone is in `bones`, scaled in place. Returns how many
## tracks it touched.
static func scale_swing(anim: Animation, bones: Array, factor: float) -> int:
	var touched := 0
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(anim.track_get_path(t)).get_slice(":", 1)
		if not bones.has(bone):
			continue
		var n := anim.track_get_key_count(t)
		if n < 2:
			continue
		var mid := track_mean(anim, t)
		for k in n:
			var q: Quaternion = anim.track_get_key_value(t, k)
			# The mean and the key can sit in opposite hemispheres of the double cover; slerp
			# already takes the short way, so this only keeps the stored sign stable.
			anim.track_set_key_value(t, k, mid.slerp(q, factor).normalized())
		touched += 1
	return touched

## The sign-aligned, normalised average of a rotation track's keys. Good enough as "the middle"
## for an arm swing - the keys span well under 90 degrees, where the plain average and the true
## spherical mean agree to a fraction of a degree.
static func track_mean(anim: Animation, t: int) -> Quaternion:
	var first: Quaternion = anim.track_get_key_value(t, 0)
	var sum := Vector4.ZERO
	for k in anim.track_get_key_count(t):
		var q: Quaternion = anim.track_get_key_value(t, k)
		if q.dot(first) < 0.0:
			q = -q
		sum += Vector4(q.x, q.y, q.z, q.w)
	sum = sum.normalized()
	return Quaternion(sum.x, sum.y, sum.z, sum.w)
