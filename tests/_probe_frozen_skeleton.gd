extends SceneTree

# Throwaway probe, WINDOWED: is the "frozen skeleton" afterimage cheap? Builds 6 ghosts at load
# (own Skeleton3D + MeshInstance3Ds sharing pilot9's mesh and skin), then times posing one and
# measures frame time with all 6 on screen. Also checks whether the staff-arm modifier's pose is
# readable outside skeleton_updated. Run:
#   godot --path . --script tests/_probe_frozen_skeleton.gd

const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")
const FILL_SHADER := preload("res://shaders/cel/vfx/afterimage.gdshader")
const LINE_SHADER := preload("res://shaders/cel/vfx/afterimage_outline.gdshader")

var _pilot: Node
var _frames := 0
var _last_us := 0
var _src_skel: Skeleton3D
var _ghosts: Array[Skeleton3D] = []
var _signal_poses: Array[Transform3D] = []
var _samples := {}
var _phase := ""

func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_d: float) -> bool:
	_frames += 1
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	if _pilot == null:
		_pilot = _find(current_scene) if current_scene != null else null
		return _frames > 600
	if _phase != "" and _frames > 200:
		_samples.get_or_add(_phase, []).append(dt)
		if dt > 12.0:
			print("SPIKE frame %d: %.1f ms (phase %s)" % [_frames, dt, _phase])
	if _frames == 150:
		_src_skel = _find_skel(_pilot.character)
		_src_skel.skeleton_updated.connect(_on_updated)
		var t := Time.get_ticks_usec()
		_build()
		print("build 6 ghosts at load: %.2f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	if _frames == 200:
		_phase = "idle, ghosts hidden"
	if _frames == 260:
		# The game's own baked ghosts off, so only the prototype's are measured.
		root.get_node("/root/Settings")._values[&"movement_effects"] = "off"
		_pilot._start_dash(Vector3.LEFT)
	if _frames >= 262 and _frames < 274 and _frames % 2 == 0:
		var i := (_frames - 262) / 2
		var t := Time.get_ticks_usec()
		_pose(_ghosts[i], _pilot.character.global_transform)
		print("pose + show ghost %d: %.3f ms" % [i, (Time.get_ticks_usec() - t) / 1000.0])
		_phase = "6 ghosts on screen"
	if _frames == 265:
		_check_arm()
	if _frames == 280:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OS.get_cmdline_user_args()[0])
		print("modifiers on skeleton: ", _src_skel.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return "%s active=%s" % [c.name, c.active]))
	if _frames == 360:
		_phase = ""
		for k in _samples:
			var a: Array = _samples[k]
			var worst := 0.0
			var total := 0.0
			for v in a:
				worst = maxf(worst, v)
				total += v
			print("%-22s frames=%3d  avg=%6.2f ms  worst=%6.2f ms" % [k, a.size(), total / a.size(), worst])
		return true
	return false

func _build() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FILL_SHADER
	var line := ShaderMaterial.new()
	line.shader = LINE_SHADER
	mat.next_pass = line
	var meshes: Array[MeshInstance3D] = []
	_ApplyStylized.collect_meshes(_pilot.character, meshes)
	for g in 6:
		var skel := Skeleton3D.new()
		for b in _src_skel.get_bone_count():
			skel.add_bone(_src_skel.get_bone_name(b))
		for b in _src_skel.get_bone_count():
			skel.set_bone_parent(b, _src_skel.get_bone_parent(b))
			skel.set_bone_rest(b, _src_skel.get_bone_rest(b))
		skel.top_level = true
		skel.visible = false
		root.add_child(skel)
		for mi in meshes:
			if mi.skin == null:
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.skin = mi.skin
			copy.material_override = mat
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			skel.add_child(copy)
			copy.transform = _src_skel.global_transform.affine_inverse() * mi.global_transform
			copy.skeleton = copy.get_path_to(skel)
			copy.set_instance_shader_parameter(&"ghost_color", Color(0.3, 0.9, 1.0))
		_ghosts.append(skel)

func _pose(skel: Skeleton3D, _at: Transform3D) -> void:
	for b in _src_skel.get_bone_count():
		skel.set_bone_pose(b, _src_skel.get_bone_pose(b))
	skel.global_transform = _src_skel.global_transform
	skel.visible = true
	skel.reset_physics_interpolation()

func _on_updated() -> void:
	_signal_poses.clear()
	for b in _src_skel.get_bone_count():
		_signal_poses.append(_src_skel.get_bone_global_pose(b))

func _check_arm() -> void:
	var worst := 0.0
	var worst_bone := ""
	for b in _src_skel.get_bone_count():
		var d := _src_skel.get_bone_global_pose(b).origin.distance_to(_signal_poses[b].origin)
		if d > worst:
			worst = d
			worst_bone = _src_skel.get_bone_name(b)
	print("modifier check: worst bone gap between _process read and skeleton_updated read: %.4f m (%s)" % [worst, worst_bone])

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var f := _find_skel(c)
		if f != null: return f
	return null

func _find(n: Node) -> Node:
	if n == null: return null
	if n.get_script() != null and n.get_script().resource_path == "res://scripts/pilot9.gd": return n
	for c in n.get_children():
		var f := _find(c)
		if f != null: return f
	return null
