extends "res://tests/test_case.gd"

const APPLIER_PATH := "res://scripts/rendering/apply_stylized.gd"

func _applier() -> GDScript:
	# Runtime load, not preload: preload of a missing script is a parse-time
	# failure, which makes --script fall back to running main.tscn and hang.
	return load(APPLIER_PATH) as GDScript

# A stand-in for the material the applier is pointed at in a scene.
#
# Deliberately shaderless. Nothing the applier does depends on which shader is
# loaded: it duplicates the material, stamps parameters, and compares instances,
# and ShaderMaterial stores a parameter whether or not the shader declares it,
# so the derive tests below read albedo_color and gradient_color back either
# way. Naming a shader file here only buys two problems - the suite breaks every
# time an art-direction shader is renamed or archived (this used to load
# res://shaders/stylized.gdshader, which now lives under shaders/archive/), and
# the headless dummy renderer errors on a real shader assigned to a mesh that
# was never drawn.
func _mat() -> ShaderMaterial:
	return ShaderMaterial.new()

# An imported GLB is a Node3D root with MeshInstance3D nodes nested underneath,
# and material_override does not propagate down from that root. The whole reason
# this helper exists is to reach every mesh at any depth.
func test_applies_material_to_every_mesh_at_any_depth() -> void:
	var applier := _applier()
	if applier == null:
		fail("%s does not exist" % APPLIER_PATH)
		return

	var root := Node3D.new()
	var shallow := MeshInstance3D.new()
	var branch := Node3D.new()
	var deep := MeshInstance3D.new()
	var plain := Node.new()
	root.add_child(shallow)
	root.add_child(branch)
	branch.add_child(deep)
	branch.add_child(plain)

	var mat := _mat()
	var count: int = applier.apply_to(root, mat)

	eq(count, 2, "should report every MeshInstance3D it touched")
	eq(shallow.material_override, mat, "shallow mesh should get the override")
	eq(deep.material_override, mat, "mesh nested under a Node3D should get the override")
	root.free()

# In test.tscn the helper sits as a plain node pointed at the hub and the
# landmark, so target resolution across several subtrees is the behaviour the
# scene depends on.
func test_applies_to_each_configured_target_subtree() -> void:
	var applier_script := _applier()
	if applier_script == null:
		fail("%s does not exist" % APPLIER_PATH)
		return

	var scene_root := Node3D.new()
	var hub := Node3D.new()
	hub.name = "Hub"
	var hub_mesh := MeshInstance3D.new()
	hub.add_child(hub_mesh)

	var landmark := Node3D.new()
	landmark.name = "Landmark"
	var landmark_mesh := MeshInstance3D.new()
	landmark.add_child(landmark_mesh)

	var untouched := MeshInstance3D.new()
	untouched.name = "NotATarget"

	scene_root.add_child(hub)
	scene_root.add_child(landmark)
	scene_root.add_child(untouched)

	var applier: Node = applier_script.new()
	scene_root.add_child(applier)
	applier.material = _mat()
	var target_paths: Array[NodePath] = [NodePath("../Hub"), NodePath("../Landmark")]
	applier.targets = target_paths

	var count: int = applier.apply_now()

	eq(count, 2, "should apply across every configured target subtree")
	eq(hub_mesh.material_override, applier.material, "hub mesh should be overridden")
	eq(landmark_mesh.material_override, applier.material, "landmark mesh should be overridden")
	eq(untouched.material_override, null, "a mesh outside the targets must be left alone")
	scene_root.free()

# Re-importing a GLB rebuilds the instanced subtree, so by the time the editor
# saves the scene the recorded entries can be pointing at meshes that no longer
# exist. Clearing has to walk past those quietly: the freed ones are already
# gone, and the survivors still need putting back. Godot errors on assigning a
# freed instance to a typed variable, so this used to print one error per stale
# entry on every save.
func test_clear_walks_past_meshes_that_have_since_been_freed() -> void:
	var applier_script := _applier()
	if applier_script == null:
		fail("%s does not exist" % APPLIER_PATH)
		return

	var scene_root := Node3D.new()
	var hub := Node3D.new()
	hub.name = "Hub"
	var reimported := MeshInstance3D.new()
	var survivor := MeshInstance3D.new()
	hub.add_child(reimported)
	hub.add_child(survivor)
	scene_root.add_child(hub)

	var applier: Node = applier_script.new()
	scene_root.add_child(applier)
	applier.material = _mat()
	var target_paths: Array[NodePath] = [NodePath("../Hub")]
	applier.targets = target_paths

	eq(applier.apply_now(), 2, "precondition: both meshes should be overridden")
	# The re-import: one of the meshes this node is holding is replaced out from
	# under it.
	reimported.free()

	eq(applier.clear_now(), 1, "the surviving mesh should still be put back")
	eq(survivor.material_override, null, "and put back to its imported material")
	scene_root.free()

# The editor pre-save pass strips the overrides so they never get serialised
# into test.tscn as per-node overrides on the instanced GLB subtree. That round
# trip has to land the meshes back on their imported material (null override).
func test_clear_restores_meshes_to_their_imported_material() -> void:
	var applier_script := _applier()
	if applier_script == null:
		fail("%s does not exist" % APPLIER_PATH)
		return

	var scene_root := Node3D.new()
	var hub := Node3D.new()
	hub.name = "Hub"
	var hub_mesh := MeshInstance3D.new()
	hub.add_child(hub_mesh)
	scene_root.add_child(hub)

	var applier: Node = applier_script.new()
	scene_root.add_child(applier)
	applier.material = _mat()
	var target_paths: Array[NodePath] = [NodePath("../Hub")]
	applier.targets = target_paths

	applier.apply_now()
	eq(hub_mesh.material_override, applier.material, "precondition: mesh should be overridden")

	var cleared: int = applier.clear_now()

	eq(cleared, 1, "should report every mesh it put back")
	eq(hub_mesh.material_override, null, "mesh should fall back to its imported material")
	scene_root.free()

# Re-applying must not double-count or strand meshes under a stale material, so
# that the tool button and the post-save pass are safe to fire repeatedly.
func test_reapplying_is_idempotent() -> void:
	var applier_script := _applier()
	if applier_script == null:
		fail("%s does not exist" % APPLIER_PATH)
		return

	var scene_root := Node3D.new()
	var hub := Node3D.new()
	hub.name = "Hub"
	hub.add_child(MeshInstance3D.new())
	scene_root.add_child(hub)

	var applier: Node = applier_script.new()
	scene_root.add_child(applier)
	applier.material = _mat()
	var target_paths: Array[NodePath] = [NodePath("../Hub")]
	applier.targets = target_paths

	eq(applier.apply_now(), 1, "first pass should touch the one mesh")
	eq(applier.apply_now(), 1, "second pass should report the same count, not accumulate")
	eq(applier.clear_now(), 1, "clear should still know about exactly one mesh")
	scene_root.free()

# A mesh someone overrode by hand is not ours to reset, otherwise the pre-save
# pass would quietly eat deliberate per-mesh material work.
func test_clear_leaves_foreign_overrides_alone() -> void:
	var applier_script := _applier()
	if applier_script == null:
		fail("%s does not exist" % APPLIER_PATH)
		return

	var scene_root := Node3D.new()
	var hub := Node3D.new()
	hub.name = "Hub"
	var hub_mesh := MeshInstance3D.new()
	hub.add_child(hub_mesh)
	scene_root.add_child(hub)

	var applier: Node = applier_script.new()
	scene_root.add_child(applier)
	applier.material = _mat()
	var target_paths: Array[NodePath] = [NodePath("../Hub")]
	applier.targets = target_paths
	applier.apply_now()

	var hand_authored := _mat()
	hub_mesh.material_override = hand_authored

	eq(applier.clear_now(), 0, "should not claim a mesh it no longer owns")
	eq(hub_mesh.material_override, hand_authored, "hand-set override must survive")
	scene_root.free()

# --- per-surface derive mode ----------------------------------------------
# Setsuna imports as one mesh per body part with one surface per Blender
# material slot. These cover the path that turns those slots into colours.

# A StandardMaterial3D standing in for an imported glTF material: resource_name
# is the Blender slot name, albedo_color is what the importer wrote there.
func _imported(slot: String, colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = slot
	m.albedo_color = colour
	return m

# An ArrayMesh with one degenerate triangle per entry in `slots`, each surface
# carrying that entry's material (null entries leave the surface bare).
func _mesh_with_slots(slots: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for slot_material in slots:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if slot_material != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, slot_material)
	return mesh

# Builds a scene_root -> Model -> MeshInstance3D(mesh) rig with the applier
# pointed at Model in derive mode. Returns [scene_root, applier, mesh_instance].
func _derive_rig(mesh: ArrayMesh) -> Array:
	var scene_root := Node3D.new()
	var model := Node3D.new()
	model.name = "Model"
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	model.add_child(mi)
	scene_root.add_child(model)

	var applier: Node = _applier().new()
	scene_root.add_child(applier)
	applier.material = _mat()
	var target_paths: Array[NodePath] = [NodePath("../Model")]
	applier.targets = target_paths
	applier.derive_from_surfaces = true
	return [scene_root, applier, mi]

# Tears down a rig built by _derive_rig.
#
# Drops the applier's overrides before freeing the tree. Freeing outright
# releases the applier's reference to the material first, while the
# MeshInstance3D under it still points at that material, and the headless dummy
# renderer reports that ordering as 'Parameter "material" is null' on the way
# out. Nothing is wrong with the applier - but noise in the suite output is
# where a real failure goes to hide.
func _free_rig(rig: Array) -> void:
	var applier: Node = rig[1]
	applier.clear_now()
	rig[0].free()

# The core claim: one material per slot, each carrying its own colour.
#
# The colour crosses over untouched. Godot's glTF importer has already
# sRGB-encoded the linear baseColorFactor, and albedo_color is a source_color
# uniform that expects that same encoding — converting again lands everything
# visibly washed out, and washed out still *looks* like a plausible art choice
# rather than a bug. A slot authored at mid grey must come out mid grey.
func test_each_surface_gets_its_slot_colour() -> void:
	var primary := Color(0.5, 0.5, 0.5)
	var highlight := Color(0.1, 0.2, 0.3)
	var mesh := _mesh_with_slots([_imported("Primary", primary), _imported("Highlights", highlight)])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]

	var count: int = applier.apply_now()

	eq(count, 2, "should report surfaces touched, not meshes")
	var first := mi.get_surface_override_material(0) as ShaderMaterial
	var second := mi.get_surface_override_material(1) as ShaderMaterial
	check(first != null and second != null, "both surfaces should carry an override")
	if first != null and second != null:
		check(first != second, "different slots must not share a material")
		eq(first.get_shader_parameter("albedo_color"), primary, "mid grey in must be mid grey out - no colour-space conversion")
		eq(second.get_shader_parameter("albedo_color"), highlight, "second slot should carry its own colour")
		eq(first.get_shader_parameter("gradient_color"), primary, "gradient_color should be stamped alongside albedo")
		eq(first.resource_name, "stylized:Primary", "derived materials should be identifiable in the remote inspector")
	_free_rig(rig)

# Setsuna's torso is fifteen shells sharing one slot. That has to be one
# material, not fifteen, or every colour tweak in the inspector edits a copy.
func test_surfaces_sharing_a_slot_share_one_material() -> void:
	var grey := Color(0.4, 0.4, 0.4)
	var mesh := _mesh_with_slots([_imported("Secondary", grey), _imported("Secondary", grey)])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]

	applier.apply_now()

	eq(mi.get_surface_override_material(0), mi.get_surface_override_material(1),
		"two surfaces on the same slot should share one material instance")
	_free_rig(rig)

# Blender writes slot names verbatim, trailing space and all - Setsuna's own
# export ships a slot called "Secondary ". A key that has to be typed with an
# invisible character is a key nobody can match.
func test_slot_names_are_trimmed() -> void:
	var mesh := _mesh_with_slots([_imported("Secondary ", Color(0.4, 0.4, 0.4))])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]

	applier.apply_now()

	var mat := mi.get_surface_override_material(0)
	eq(mat.resource_name, "stylized:Secondary", "a trailing space in the slot name should be trimmed away")
	_free_rig(rig)

# The escape hatch for a slot that wants more than a colour. None ship yet; the
# mechanism exists so the first one is a scene edit rather than a code change.
func test_slot_override_wins_over_derivation() -> void:
	var mesh := _mesh_with_slots([_imported("Primary", Color(0.5, 0.5, 0.5))])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]
	var hand_authored := _mat()
	var overrides: Dictionary[String, Material] = {"Primary": hand_authored}
	applier.slot_overrides = overrides

	applier.apply_now()

	eq(mi.get_surface_override_material(0), hand_authored, "a configured slot override should win")
	_free_rig(rig)

# A surface Blender left without a material must not render default white or
# error out; it falls back to the base swatch.
func test_surface_without_a_material_falls_back_to_the_base() -> void:
	var mesh := _mesh_with_slots([null])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]

	applier.apply_now()

	eq(mi.get_surface_override_material(0), applier.material, "a bare surface should get the base material")
	_free_rig(rig)

# The hub's contract, asserted rather than assumed: deriving colours from its
# imported flat grey would repaint the whole hub grey.
func test_default_mode_still_sets_material_override() -> void:
	var mesh := _mesh_with_slots([_imported("Primary", Color(0.5, 0.5, 0.5))])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]
	applier.derive_from_surfaces = false

	var count: int = applier.apply_now()

	eq(count, 1, "default mode should still count meshes")
	eq(mi.material_override, applier.material, "default mode should set the whole-mesh override")
	eq(mi.get_surface_override_material(0), null, "default mode must not touch surface overrides")
	_free_rig(rig)

# Same pre-save contract as the whole-mesh path: nothing this node set may
# survive into the .tscn, and nothing anyone else set may be eaten.
func test_clear_restores_surface_overrides() -> void:
	var mesh := _mesh_with_slots([_imported("Primary", Color(0.5, 0.5, 0.5)), _imported("Highlights", Color.BLACK)])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]
	applier.apply_now()

	eq(applier.clear_now(), 2, "should report every surface it put back")
	eq(mi.get_surface_override_material(0), null, "surface should fall back to its imported material")
	eq(mi.get_surface_override_material(1), null, "every surface should be cleared, not just the first")
	_free_rig(rig)

func test_clear_leaves_foreign_surface_overrides_alone() -> void:
	var mesh := _mesh_with_slots([_imported("Primary", Color(0.5, 0.5, 0.5)), _imported("Highlights", Color.BLACK)])
	var rig := _derive_rig(mesh)
	var applier: Node = rig[1]
	var mi: MeshInstance3D = rig[2]
	applier.apply_now()

	var hand_authored := _mat()
	mi.set_surface_override_material(1, hand_authored)

	eq(applier.clear_now(), 1, "should only claim the surface it still owns")
	eq(mi.get_surface_override_material(1), hand_authored, "hand-set surface override must survive")
	_free_rig(rig)
