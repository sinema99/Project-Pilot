class_name Hub2Wear
extends Node

# Dresses hub2's map as an industrial place (docs/specs/hub2-industrial.md): swaps each glb mesh for
# its baked copy (tools/bake_hub2_wear.gd -> assets/hub2_wear/<mesh name>.res), puts the weathering
# shader on it, and adds the baked decals as one extra mesh. Visual only: the map keeps its own
# collision, which hangs off the original mesh nodes and is untouched.
#
# The material is a plain ShaderMaterial override, so AirframeLook leaves it alone (it only swaps cel
# and standard materials) and it shows under every look. A mesh whose bake no longer matches the
# glb (a re-export) keeps its plain look and warns; re-run the bake.

const WEAR_DIR := "res://assets/hub2_wear"
const SURFACE_SHADER := preload("res://shaders/hub2_wear.gdshader")
const DECAL_SHADER := preload("res://shaders/hub2_decal.gdshader")
const DECAL_NODE := "WearDecals"
const BAKED_META := &"hub2_baked"

## The imported map GLB instance.
@export var map: Node3D
@export var apply_on_ready := true

var surface_material: ShaderMaterial


func _ready() -> void:
	if apply_on_ready:
		apply()


## Swaps in every baked mesh and the decals. Returns how many meshes were dressed.
func apply() -> int:
	if map == null:
		push_warning("Hub2Wear: no map assigned.")
		return 0
	var meshes: Array[MeshInstance3D] = []
	for node in map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.name != DECAL_NODE and mi.mesh != null and not mi.has_meta(BAKED_META):
			meshes.append(mi)
	var dressed: Array[Dictionary] = []
	var y_min := INF
	for mi in meshes:
		var path := "%s/%s.res" % [WEAR_DIR, mi.name]
		if not ResourceLoader.exists(path):
			push_warning("Hub2Wear: no bake for %s (run tools/bake_hub2_wear.gd)." % mi.name)
			continue
		var baked := load(path) as ArrayMesh
		if baked == null or int(baked.get_meta(&"source_vertex_count", -1)) != mi.mesh.surface_get_array_len(0):
			push_warning("Hub2Wear: %s no longer matches its bake (re-exported?); re-run tools/bake_hub2_wear.gd." % mi.name)
			continue
		dressed.append({"mi": mi, "mesh": baked})
		y_min = minf(y_min, float(baked.get_meta(&"y_min", 0.0)))
	if dressed.is_empty():
		return 0
	surface_material = make_surface_material(y_min)
	for d in dressed:
		var mi: MeshInstance3D = d["mi"]
		mi.mesh = d["mesh"]
		mi.material_override = surface_material
		mi.set_meta(BAKED_META, true)
	_add_decals()
	return dressed.size()


static func make_surface_material(ground_y: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter(&"ground_y", ground_y)
	return m


func _add_decals() -> void:
	var existing := map.get_node_or_null(DECAL_NODE)
	if existing != null:
		existing.free()
	var path := WEAR_DIR + "/decals.res"
	if not ResourceLoader.exists(path):
		return
	var mesh := load(path) as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mat := ShaderMaterial.new()
	mat.shader = DECAL_SHADER
	mat.set_shader_parameter(&"sheet", load(WEAR_DIR + "/decals_color.res"))
	mat.set_shader_parameter(&"glow_sheet", load(WEAR_DIR + "/decals_glow.res"))
	var mi := MeshInstance3D.new()
	mi.name = DECAL_NODE
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(BAKED_META, true)
	map.add_child(mi)
