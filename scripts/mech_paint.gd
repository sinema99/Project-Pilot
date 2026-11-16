@tool
class_name MechPaint
extends Node

# EXIA's weathered factory paint (docs/specs/mech-weathering.md). A child of the Mech scene's root:
# pick the paint in the inspector and the editor viewport repaints live.
#
# It dresses every mesh under `model` with a material_override of shaders/mech_weathered.gdshader.
# A mesh with its own override is skipped by ApplyCelMech (derive mode) and left alone by the
# AIRFRAME look (not a cel or plain material), so the paint shows under both; RETRO's twins are for
# cel slots, so the mech wears this as it is there too.
#
# SHELL parts take the paint and the wear; FRAME parts are dark oily metal, worn the same way. Which is
# which, and how worn, is PARTS (mesh name -> [role, paint_left, extras]). The back boxes are built
# in code by Mech after this runs, so Mech hands them to dress_panels().
#
# WHERE the wear goes comes from the mesh shape (edges, seams, under-faces, height): each GLB part is
# swapped for its baked copy in assets/mech_wear/ (tools/bake_mech_wear.gd, re-run after a Mech_V1
# re-export). A part whose bake no longer matches keeps its own mesh and the shader's plain fallback.
#
# Like ApplyStylized this runs in the editor, and puts nothing into the saved scene: the overrides come
# off on PRE_SAVE and back on POST_SAVE, and so do the baked meshes. The baked copies carry the rest
# pose (CUSTOM0/1), so the patches ride the body in the game and in the editor alike.

enum Scheme { YELLOW, BLUE_GREEN, ORANGE }

const SHADER := preload("res://shaders/mech_weathered.gdshader")
const Applier := preload("res://scripts/rendering/apply_stylized.gd")
const SHELL := 0
const FRAME := 1

## Faded paints, then the shared wear colours. These are the user's picks, not derived.
const PAINTS := {
	Scheme.YELLOW: Color(0.80, 0.62, 0.10),
	Scheme.BLUE_GREEN: Color(0.16, 0.42, 0.40),
	Scheme.ORANGE: Color(0.86, 0.46, 0.10),
}
const BACK_BOX_LEFT := 0.6
const WEAR_DIR := "res://assets/mech_wear"
## Mesh name -> [role, paint_left, hazard?]. paint_left: the share still in its original finish.
## Chest, torso, shoulders ~85% painted, thighs ~70%; the frame rusts low and at the joints.
const PARTS := {
	"Cube_013": [SHELL, 0.85, false],   # chest
	"Cube_004": [SHELL, 0.85, false],   # torso
	"Sphere_002": [FRAME, 0.85, false], # shoulder
	"Sphere_003": [FRAME, 0.85, false],
	"Cube_003": [SHELL, 0.7, false],    # thigh
	"Cube_006": [SHELL, 0.7, false],
	"Cube_009": [SHELL, 0.7, false],    # shin
	"Cube_007": [SHELL, 0.7, false],
	"Cube_010": [SHELL, 0.65, false],   # ankle
	"Cube_008": [SHELL, 0.65, false],
	"Cube_012": [SHELL, 0.6, true],     # foot, hazard-striped
	"Cube_011": [SHELL, 0.6, true],
	"Sphere_004": [FRAME, 0.8, false],  # lower arm
	"Sphere_005": [FRAME, 0.8, false],
	"Cube_001": [SHELL, 0.8, false],    # hand
	"Cube_005": [SHELL, 0.8, false],
	"Cylinder": [SHELL, 0.85, false],
	"Cylinder_001": [SHELL, 0.85, false],
	"Sphere_006": [SHELL, 0.85, false], # the head ball: yellow like the body, no glow
}

@export var scheme := Scheme.YELLOW:
	set(value):
		scheme = value
		_recolour()
## 1 = the worn look as specced; 0 = clean paint; 2 = twice the rust.
@export_range(0.0, 2.0, 0.05) var wear := 1.0:
	set(value):
		wear = value
		_recolour()
## Where the meshes are, relative to this node.
@export var model_path := NodePath("../Model")

## [MeshInstance3D, ShaderMaterial, role, paint_left, the mesh it had before (or null)] for every
## mesh this dressed.
var _dressed: Array = []
var _restore_after_save := false


func _ready() -> void:
	dress_model()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_restore_after_save = not _dressed.is_empty()
			undress()
		NOTIFICATION_EDITOR_POST_SAVE:
			if _restore_after_save:
				_restore_after_save = false
				dress_model()


## (Re)dresses every mesh under `model_path`. Returns how many it dressed.
func dress_model() -> int:
	undress()
	var root := get_node_or_null(model_path)
	if root == null:
		return 0
	var meshes: Array[MeshInstance3D] = []
	Applier.collect_meshes(root, meshes)
	var count := 0
	for mi in meshes:
		if mi.mesh == null or mi.material_override != null:
			continue
		var part: Array = PARTS.get(str(mi.name), [SHELL, 0.75, false])
		var mat := _new_material(part[0], part[1], mi, part[2])
		_dress(mi, mat, part[0], part[1], _baked_mesh(mi))
		count += 1
	_recolour()
	return count


## The two back boxes (rigid on a shoulder bone, so object-space pixels). Shell, heavier wear. They
## are true boxes, so the shader works their edges out from box_half; no ground grime (their local y
## is not the body's height).
func dress_panels(panels: Dictionary) -> void:
	for side: float in panels:
		for mi: MeshInstance3D in (panels[side] as Node).find_children("*", "MeshInstance3D", true, false):
			var mat := _new_material(SHELL, BACK_BOX_LEFT, mi, false)
			if mi.mesh is BoxMesh:
				mat.set_shader_parameter(&"box_half", (mi.mesh as BoxMesh).size * 0.5)
			mat.set_shader_parameter(&"ground_grime", false)
			_dress(mi, mat, SHELL, BACK_BOX_LEFT, null)
	_recolour()


## The part's baked copy (assets/mech_wear/<name>.res) if it still matches the live mesh, else null.
func _baked_mesh(mi: MeshInstance3D) -> ArrayMesh:
	var path := "%s/%s.res" % [WEAR_DIR, mi.name]
	if not ResourceLoader.exists(path):
		push_warning("MechPaint: no wear bake for %s; run tools/bake_mech_wear.gd" % mi.name)
		return null
	var baked := load(path) as ArrayMesh
	if baked == null or int(baked.get_meta(&"source_vertex_count", -1)) != mi.mesh.surface_get_array_len(0):
		push_warning("MechPaint: the wear bake for %s is stale; re-run tools/bake_mech_wear.gd" % mi.name)
		return null
	return baked


func _new_material(role: int, _left: float, mi: MeshInstance3D, hazard: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"is_frame", role == FRAME)
	mat.set_shader_parameter(&"seed", float(absi(str(mi.name).hash() + str(mi.get_parent().name).hash()) % 1000) / 10.0)
	mat.set_shader_parameter(&"hazard", hazard)
	return mat


func _dress(mi: MeshInstance3D, mat: ShaderMaterial, role: int, left: float, baked: ArrayMesh) -> void:
	var before: Mesh = null
	if baked != null:
		# The baked copy carries the rest pose and the wear distances.
		before = mi.mesh
		mi.mesh = baked
		mat.set_shader_parameter(&"use_rest", true)
		mat.set_shader_parameter(&"has_wear_map", true)
	elif not Engine.is_editor_hint() and AirframeLook.is_skinned(mi):
		# No bake: the running game still wants the pixels to ride the body.
		before = mi.mesh
		if JetpackLook.bake_rest_pose(mi):
			mat.set_shader_parameter(&"use_rest", true)
	mi.material_override = mat
	_dressed.append([mi, mat, role, left, before])


## Takes every override back off (the scene file never carries them).
func undress() -> void:
	for entry: Array in _dressed:
		var mi: Variant = entry[0]
		if is_instance_valid(mi) and (mi as MeshInstance3D).material_override == entry[1]:
			(mi as MeshInstance3D).material_override = null
			if entry[4] != null:
				(mi as MeshInstance3D).mesh = entry[4]
	_dressed.clear()


func _recolour() -> void:
	var paint: Color = PAINTS[scheme]
	for entry: Array in _dressed:
		var mat: ShaderMaterial = entry[1]
		mat.set_shader_parameter(&"paint_color", paint)
		# wear scales the rust share (1 - paint_left) around the specced value.
		var left := 1.0 - (1.0 - float(entry[3])) * wear
		# Wear 0 is clean paint: 1 or more turns every kind of wear off in the shader.
		mat.set_shader_parameter(&"paint_left", 1.01 if left >= 1.0 else maxf(left, 0.0))
