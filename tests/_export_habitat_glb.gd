extends SceneTree

# Throwaway: bakes the generated habitat into one GLB for Blender. Run:
#   godot --headless --path . --script tests/_export_habitat_glb.gd -- <out.glb>
# Cel shader materials become plain StandardMaterial3D (their colour param), MultiMeshes are
# merged into one mesh each, colliders are dropped.

var _frames := 0
var _hab: Node
var _out := "res://exports/habitat.glb"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_hab = (load("res://scenes/habitat.tscn") as PackedScene).instantiate()
	root.add_child(_hab)

func _std(m: Material) -> Material:
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var s := StandardMaterial3D.new()
		var c = sm.get_shader_parameter("color")
		s.albedo_color = c if c is Color else Color(0.3, 0.5, 0.7, 0.6)
		if sm.shader and sm.shader.resource_path.contains("water"):
			s.albedo_color = Color(0.2, 0.45, 0.6, 0.7)
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return s
	return m

func _walk(n: Node, list: Array) -> void:
	list.append(n)
	for c in n.get_children():
		_walk(c, list)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var all: Array = []
	_walk(_hab, all)
	var merged := 0
	for n in all:
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			var mm := mmi.multimesh
			var st := SurfaceTool.new()
			for i in mm.instance_count:
				st.append_from(mm.mesh, 0, mm.get_instance_transform(i))
			var mi := MeshInstance3D.new()
			mi.name = mmi.name
			mi.mesh = st.commit()
			mi.material_override = _std(mmi.material_override)
			mi.transform = mmi.transform
			mmi.get_parent().add_child(mi)
			mmi.get_parent().remove_child(mmi)
			merged += 1
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.material_override:
				mi.material_override = _std(mi.material_override)
			if mi.mesh:
				for s in mi.mesh.get_surface_count():
					var sm := mi.get_surface_override_material(s)
					if sm:
						mi.set_surface_override_material(s, _std(sm))
					elif mi.mesh.surface_get_material(s) is ShaderMaterial:
						mi.set_surface_override_material(s, _std(mi.mesh.surface_get_material(s)))
		elif n is CollisionShape3D or n is Light3D:
			pass
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(_hab, state)
	print("append err ", err, " merged multimeshes ", merged)
	err = doc.write_to_filesystem(state, _out)
	print("write err ", err, " -> ", ProjectSettings.globalize_path(_out))
	quit()
	return true
