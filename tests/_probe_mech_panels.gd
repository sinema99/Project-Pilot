extends SceneTree

# Throwaway probe, headless: the closest any skinned EXIA vertex comes to the front face of each back
# panel, over every clip EXIA plays (16 samples each), with the boxes as built on their shoulder hinges
# at the standing angle (rev 6; the run tilt and sway are not applied).
# Positive = clear. See docs/specs/exia-back-panels.md.
#   godot --headless --path . --script tests/_probe_mech_panels.gd

const Panels := preload("res://scripts/mech_back_panels.gd")
const CLIPS := ["MECH_standing", "MECH_idle", "MECH_launch", "MECH_stand_idle", "MECH_run", "MECH_sprint",
	"MECH_turn_step", "MECH_stop_L", "MECH_stop_R", "MECH_jump_crouch", "MECH_jump_air", "MECH_land"]
const SAMPLES := 16
# Vertices this far past a slab's edges still count, so a heel sliding past the side shows up.
const EDGE := 0.2

var _mech: Node3D
var _frame := 0

func _initialize() -> void:
	_mech = load("res://scenes/mech.tscn").instantiate()
	root.add_child(_mech)
	_mech.set_physics_process(false)
	_mech.set_process(false)

static func skinned(mi: MeshInstance3D, skel: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh := mi.mesh as ArrayMesh
	var skin := mi.skin
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones = arr[Mesh.ARRAY_BONES]
		var weights = arr[Mesh.ARRAY_WEIGHTS]
		var per: int = bones.size() / verts.size()
		for i in verts.size():
			var p := Vector3.ZERO
			for k in per:
				var w: float = weights[i * per + k]
				if w <= 0.0:
					continue
				var bind_idx: int = bones[i * per + k]
				var bone := skin.get_bind_bone(bind_idx)
				if bone < 0:
					bone = skel.find_bone(skin.get_bind_name(bind_idx))
				p += w * (skel.get_bone_global_pose(bone) * (skin.get_bind_pose(bind_idx) * verts[i]))
			out.append(skel.global_transform * p)
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
	var half_len := Panels.length() * 0.5
	var worst_all := INF
	for clip in CLIPS:
		if not ap.has_animation(clip):
			print("%-18s missing" % clip)
			continue
		var a := ap.get_animation(clip)
		var steps := 1 if a.length < 0.05 else SAMPLES
		var worst := INF
		var at := ""
		for i in steps:
			var t := a.length * i / steps
			ap.play(clip)
			ap.seek(t, true)
			ap.pause()
			skel.force_update_all_bone_transforms()
			var verts := PackedVector3Array()
			for mi in bodies:
				verts.append_array(skinned(mi, skel))
			for attach: BoneAttachment3D in _mech._panels.values():
				var slab := attach.get_child(0) as MeshInstance3D
				var bone_xf := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(attach.bone_name))
				var inv := (bone_xf * slab.transform).orthonormalized().affine_inverse()
				for v in verts:
					var p := inv * v
					if absf(p.x) <= Panels.WIDTH * 0.5 + EDGE and absf(p.y) <= half_len + EDGE:
						var cl := p.z - Panels.THICKNESS * 0.5
						if cl < worst:
							worst = cl
							at = "%s t=%.2f, %.1f m from the slab's top" % [slab.name, t, half_len - p.y]
		worst_all = minf(worst_all, worst)
		print("%-18s min clearance %6.2f m  (%s)" % [clip, worst, at])
	print("WORST %.2f m -> %s" % [worst_all, "clear" if worst_all > 0.0 else "CLIPS"])
	return true
