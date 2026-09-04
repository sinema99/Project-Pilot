@tool
extends Node

# Applies the shared stylized ShaderMaterial across a subtree.
#
# material_override set on an imported GLB's root Node3D does not propagate to
# the MeshInstance3D nodes underneath it, so the hub blockout and landmarks need
# something to walk down and set it on each mesh.
#
# Two modes, see `derive_from_surfaces`:
#   - material_override per mesh: one colour for the whole subtree (hub, landmark).
#   - per-surface override: one derived colour per Blender material slot (Setsuna).
#
# Runs in the editor as well as at runtime (@tool). Without that, the editor
# viewport shows the raw imported greybox while the running game shows the
# stylized material, and you cannot art-direct lighting against a preview that
# shares no material with the build.
#
# Editor-side overrides are stripped on NOTIFICATION_EDITOR_PRE_SAVE and put
# back on NOTIFICATION_EDITOR_POST_SAVE, so they are never serialised into the
# .tscn as per-node overrides on the instanced GLB subtree. This script stays
# the single source of truth, and re-importing the blockout cannot leave stale
# override entries behind in the scene file.

# Collects every MeshInstance3D in `root`'s subtree (including `root` itself)
# into `out`, depth-first.
static func collect_meshes(root: Node, out: Array[MeshInstance3D]) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		collect_meshes(child, out)

# Sets `mat` as material_override on every MeshInstance3D in `root`'s subtree
# (including `root` itself). Returns how many meshes were touched.
static func apply_to(root: Node, mat: Material) -> int:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(root, meshes)
	for mi in meshes:
		mi.material_override = mat
	return meshes.size()

# --- scene-facing configuration -------------------------------------------
# Attached in test.tscn only; it does not touch scripts/hub_import.gd, so
# main.tscn is unaffected.

@export var material: Material
## Subtrees to walk. Each is resolved relative to this node.
@export var targets: Array[NodePath] = []
@export var apply_on_ready := true

## Off: one material_override per mesh, so every surface renders the base
## swatch. The hub and the landmark need this; their imported material is the
## flat grey hub_import.gd bakes in, so deriving from it would repaint the whole
## hub grey and throw away the sand swatch in stylized_material.tres.
##
## On: one override per *surface*, coloured from the Blender material slot on
## that surface. This is what gives Setsuna more than one colour.
@export var derive_from_surfaces := false

## Escape hatch, keyed by Blender material slot name, for a slot that needs more
## than a colour: hair wanting a heavier dot_density, skin wanting a higher
## shadow_floor. A hand-authored material here wins over the derived one.
## Names are matched after trimming whitespace, and are case-sensitive.
@export var slot_overrides: Dictionary[String, Material] = {}

## Re-walk the targets. Needed in the editor after re-importing a GLB, since the
## reimport rebuilds the instanced subtree and discards the overrides with it.
@export_tool_button("Re-apply now") var reapply_action: Callable = apply_now

# What we currently own, so the pre-save pass can put things back exactly as
# they were instead of guessing. One entry per override we set:
#   { "mesh": MeshInstance3D, "surface": int, "material": Material }
# surface == _WHOLE_MESH means the entry is a whole-mesh material_override.
var _applied: Array[Dictionary] = []
var _reapply_after_save := false

const _WHOLE_MESH := -1

func _ready() -> void:
	if apply_on_ready:
		apply_now()

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			# Only worth restoring afterwards if we actually had something applied.
			_reapply_after_save = not _applied.is_empty()
			clear_now()
		NOTIFICATION_EDITOR_POST_SAVE:
			if _reapply_after_save:
				_reapply_after_save = false
				apply_now()

# Applies `material` across every configured target subtree. Returns the number
# of surfaces overridden in derive mode, or of meshes overridden otherwise.
func apply_now() -> int:
	if material == null:
		push_warning("apply_stylized: no material assigned; nothing applied.")
		return 0

	# Drop any previous pass first, so repeated calls (tool button, post-save)
	# cannot accumulate stale entries or strand a mesh under an old material.
	clear_now()

	# Per pass, so every surface sharing a slot name shares one material instance
	# instead of minting one duplicate per surface.
	var derived: Dictionary[String, Material] = {}

	var total := 0
	for path in targets:
		var node := get_node_or_null(path)
		if node == null:
			push_warning("apply_stylized: target '%s' not found." % path)
			continue
		var meshes: Array[MeshInstance3D] = []
		collect_meshes(node, meshes)
		for mi in meshes:
			if derive_from_surfaces:
				total += _apply_surfaces(mi, derived)
			else:
				mi.material_override = material
				_applied.append({"mesh": mi, "surface": _WHOLE_MESH, "material": material})
				total += 1

	return total

# Stamps a per-slot material onto each surface of `mi`. Returns surfaces touched.
func _apply_surfaces(mi: MeshInstance3D, derived: Dictionary[String, Material]) -> int:
	if mi.mesh == null:
		return 0
	var count := 0
	for i in mi.mesh.get_surface_count():
		var mat := _material_for_surface(mi, i, derived)
		mi.set_surface_override_material(i, mat)
		_applied.append({"mesh": mi, "surface": i, "material": mat})
		count += 1
	return count

# Picks the material for one surface: a slot override if one is configured, else
# a cached duplicate of the base material carrying that slot's imported colour,
# else the base material untouched.
func _material_for_surface(mi: MeshInstance3D, surface: int, derived: Dictionary[String, Material]) -> Material:
	var imported := mi.mesh.surface_get_material(surface)
	# Blender lets a slot name end in a space, and the importer keeps it verbatim.
	var slot := imported.resource_name.strip_edges() if imported != null else ""

	if slot_overrides.has(slot):
		return slot_overrides[slot]

	var source := imported as StandardMaterial3D
	if source == null:
		push_warning("apply_stylized: '%s' surface %d has no usable imported material; using the base swatch." % [mi.name, surface])
		return material

	if derived.has(slot):
		return derived[slot]

	# The importer has already sRGB-encoded glTF's linear baseColorFactor, and
	# the shader's source_color uniform expects exactly that encoding, so the
	# value crosses over untouched. Converting here washes everything out. This
	# is checked against the export's own baseColorFactor, never by eye.
	var colour := source.albedo_color
	var mat := material.duplicate() as Material
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		sm.set_shader_parameter("albedo_color", colour)
		# gradient_strength is 0 on the character material, so this changes
		# nothing today. It means raising the strength later fades toward the
		# slot's own colour instead of snapping back to the base swatch.
		sm.set_shader_parameter("gradient_color", colour)
		# shaders/cel/cel-shader-base.gdshader names its albedo uniform `color`.
		# set_shader_parameter just stores unknown names, so stylized.gdshader
		# (no `color` uniform) is unaffected; the cel materials in test3 pick
		# this up and render one colour per Blender slot.
		sm.set_shader_parameter("color", colour)
	elif mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = colour
	mat.resource_name = "stylized:%s" % slot

	derived[slot] = mat
	return mat

# Removes every override this node put on, leaving the imported material to show
# through again. Anything changed by something else since is left alone.
# Returns how many were cleared.
func clear_now() -> int:
	var cleared := 0
	for entry in _applied:
		# Held as a Variant until it has been checked. A mesh in here can have
		# been freed since the pass that recorded it - re-importing a GLB
		# rebuilds the whole instanced subtree, and the entries still point at
		# the nodes it replaced - and assigning a freed object to a *typed*
		# variable is itself the error ("Trying to assign invalid previously
		# freed instance"), so the check has to come before the narrowing
		# rather than after it. That is one error per stale entry, every time
		# the scene is saved, since the pre-save pass calls this.
		var node: Variant = entry["mesh"]
		if not is_instance_valid(node):
			continue
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var surface: int = entry["surface"]
		if surface == _WHOLE_MESH:
			if mi.material_override == entry["material"]:
				mi.material_override = null
				cleared += 1
		elif surface < mi.get_surface_override_material_count():
			if mi.get_surface_override_material(surface) == entry["material"]:
				mi.set_surface_override_material(surface, null)
				cleared += 1
	_applied.clear()
	return cleared
