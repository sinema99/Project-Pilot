extends SceneTree

# Throwaway probe: boots trial.tscn and counts every geometry slot by the material it shows, so the
# AIRFRAME swap rules can be chosen from what is really there. See docs/specs/airframe-trial.md.
#   godot --headless --path . --script tests/_probe_airframe_inventory.gd

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 120 or current_scene == null:
		return false
	var counts := {}
	var examples := {}
	for node in current_scene.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		var mats: Array = []
		if gi.material_override != null:
			mats.append(gi.material_override)
		elif gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mi := gi as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				mats.append(m if m != null else mi.mesh.surface_get_material(i))
		else:
			mats.append(null)
		var top := str(current_scene.get_path_to(gi)).get_slice("/", 0)
		for m in mats:
			var kind := _kind(m)
			var key := "%s | %s | %s" % [top, gi.get_class(), kind]
			counts[key] = counts.get(key, 0) + 1
			if not examples.has(key):
				examples[key] = str(current_scene.get_path_to(gi))
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print(k, " x", counts[k], "   e.g. ", examples[k])
	return true

static func _kind(m: Material) -> String:
	if m == null:
		return "null"
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return "shader:" + (sh.resource_path.get_file() if sh != null else "none")
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var tags := []
		if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: tags.append("unshaded")
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: tags.append("transp")
		if b.emission_enabled: tags.append("emit")
		if b.albedo_texture != null: tags.append("tex")
		return "std" + ("(" + ",".join(tags) + ")" if not tags.is_empty() else "")
	return m.get_class()
