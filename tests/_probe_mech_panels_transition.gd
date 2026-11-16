extends SceneTree

# Throwaway probe, headless: the back boxes through the power-down (MECH_idle) and boot-up
# (MECH_launch), hung from their shoulder hinges at the angle mech.gd::_update_back_panels gives them
# (rev 6, docs/specs/exia-back-panels.md), against the skinned body. Clearance = how far the nearest
# body vertex sits in front of a box's front face; negative = inside the box.
#   godot --headless --path . --script tests/_probe_mech_panels_transition.gd            (check)
#   godot --headless --path . --script tests/_probe_mech_panels_transition.gd -- bake    (CLEARANCE)
# "bake" prints the CLEARANCE tables: per sample, the smallest shared angle at or above the pose
# angle that keeps the body out of BOTH boxes (0 = the pose angle already clears), then eased.

const Panels := preload("res://scripts/mech_back_panels.gd")
const Probe := preload("res://tests/_probe_mech_panels.gd")
const SAMPLES := 40
# Body vertices this far behind a box's back face still count (a body that has passed right through).
const DEPTH := 2.5
# The bake's ease, in samples (0.025 s each in the 1 s clips): ahead of a need (0.2 s), after it (0.35 s).
const EASE_IN := 8
const EASE_OUT := 14
const SWEEP_STEP := 0.25
# Parts the user accepted clipping (2026-11-12): parked on the kickstand the left box cuts the right
# upper arm and the right box the kneeling left leg (shin, foot, toes), and the ground wins.
# Vertices weighted mostly to these don't count. A moment no angle up to MAX_DEG can clear (the boot-up chest rising into the
# right box's hinge) gets no floor: the normal swing, clip accepted.
const ACCEPTED := ["upper_arm.R", "forearm.R", "hand.R", "shin.L", "foot.L", "toe.L", "toe.L.001"]
const MAX_DEG := 89.0
var _bake := false

var _mech: Node3D
var _frame := 0

func _initialize() -> void:
	_mech = load("res://scenes/mech.tscn").instantiate()
	root.add_child(_mech)
	_mech.set_physics_process(false)
	_mech.set_process(false)
	_bake = "bake" in OS.get_cmdline_user_args()

# The nearest body vertex's distance in front of the box's front face, over `verts` (body frame).
static func clearance(verts: PackedVector3Array, hinge: Vector3, deg: float) -> float:
	var inv := Panels.hung(hinge, deg).affine_inverse()
	var L := Panels.length()
	var T := Panels.THICKNESS
	var worst := INF
	for v in verts:
		var p := inv * v
		if absf(p.x) <= Panels.WIDTH * 0.5 and absf(p.y) <= L * 0.5 and p.z > -T * 0.5 - DEPTH:
			worst = minf(worst, p.z - T * 0.5)
	return worst

# Each vertex's heaviest bone, in Probe.skinned's order.
static func _owners(mi: MeshInstance3D, skel: Skeleton3D) -> PackedStringArray:
	var out := PackedStringArray()
	var mesh := mi.mesh as ArrayMesh
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		var per: int = bones.size() / n
		for i in n:
			var best := 0
			for k in per:
				if weights[i * per + k] > weights[i * per + best]:
					best = k
			var bind_idx: int = bones[i * per + best]
			var bone := mi.skin.get_bind_bone(bind_idx)
			out.append(skel.get_bone_name(bone) if bone >= 0 else String(mi.skin.get_bind_name(bind_idx)))
	return out

func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var ap: AnimationPlayer = _mech.anim_player
	var skel: Skeleton3D = _mech._skeleton
	var bodies: Array[MeshInstance3D] = []
	for m in _mech.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).skin != null:
			bodies.append(m)
	var inv_mech := _mech.global_transform.affine_inverse()
	var worst_all := INF
	for clip in ["MECH_idle", "MECH_launch"]:
		var a := ap.get_animation(clip)
		var steps := SAMPLES if _bake else SAMPLES * 4
		var raw := []
		for i in steps + 1:
			var t := a.length * i / steps
			ap.play(clip)
			ap.seek(t, true)
			ap.pause()
			skel.force_update_all_bone_transforms()
			var hinges := {}
			var lowest := INF
			for side: float in _mech._panels:
				var attach: BoneAttachment3D = _mech._panels[side]
				var shoulder: Transform3D = _mech._panel_skeleton_in_body \
					* skel.get_bone_global_pose(skel.find_bone(attach.bone_name))
				hinges[side] = Panels.hinge(shoulder, attach.get_meta("hinge_offset"))
				lowest = minf(lowest, hinges[side].y)
			var all := PackedVector3Array()
			for mi in bodies:
				var verts := Probe.skinned(mi, skel)
				var owners := _owners(mi, skel)
				for k in verts.size():
					if not (owners[k] in ACCEPTED):
						all.append(inv_mech * verts[k])
			# Rotation about X keeps x: only each box's lane can ever touch it.
			var lane := {}
			for side: float in hinges:
				var vs := PackedVector3Array()
				for v in all:
					if absf(v.x - hinges[side].x) <= Panels.WIDTH * 0.5:
						vs.append(v)
				lane[side] = vs
			var kneel := Panels.kneel_target(clip, t, a.length, true)
			var pose := Panels.angle(0.0, kneel, 0.0, Panels.kickstand_deg(lowest), Panels.NO_FLOOR)
			var floor_deg := Panels.NO_FLOOR if _bake else Panels.clearance_for(clip, t / a.length)
			var deg := maxf(pose, floor_deg)
			var line := "%s t=%.3f kneel %.2f pose %5.1f deg %5.1f:" % [clip, t, kneel, pose, deg]
			for side: float in hinges:
				var c := clearance(lane[side], hinges[side], deg)
				line += "  %s %6.2f" % ["L" if side < 0 else "R", c]
				worst_all = minf(worst_all, c)
			if _bake:
				var need := deg
				while need < MAX_DEG:
					var ok := true
					for side: float in hinges:
						if clearance(lane[side], hinges[side], need) < Panels.GAP:
							ok = false
							break
					if ok:
						break
					need += SWEEP_STEP
				line += "  need %5.2f%s" % [need, "  UNFIXABLE, no floor" if need >= MAX_DEG else ""]
				raw.append(0.0 if need <= pose or need >= MAX_DEG else snappedf(need, 0.01))
			print(line)
		if _bake:
			# Eased envelope (rev 4c): every sample's need spreads to its neighbours on a smoothstep
			# falloff, EASE_IN samples ahead (the box starts swinging before the body arrives) and
			# EASE_OUT behind (it settles back slowly). Never under the raw need. The first and last
			# samples keep their own need.
			var eased := []
			for i in raw.size():
				var v := 0.0
				for j in raw.size():
					var d := j - i
					var k := mini(EASE_IN, j) if d > 0 else mini(EASE_OUT, raw.size() - 1 - j)
					if k <= 0 and d != 0:
						continue
					var w := 1.0 if d == 0 else 1.0 - smoothstep(0.0, float(k), absf(d))
					v = maxf(v, float(raw[j]) * w)
				eased.append(v)
			# Widened one sample each way (not the ends), so the lerp never dips under a need that
			# peaks between samples.
			var out := []
			for i in eased.size():
				var v: float = eased[i]
				if i > 0 and i < eased.size() - 1:
					v = maxf(v, maxf(eased[i - 1], eased[i + 1]))
				out.append(snappedf(v, 0.01))
			print("BAKE %s %s" % [clip, out])
	print("WORST %.3f" % worst_all)
	return true
