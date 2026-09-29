extends "res://tests/test_case.gd"

# docs/specs/pilot9-rim-light.md. Wiring and the toggle only - how the rim looks is judged in play.

const SHADER_PATH := "res://shaders/cel/rim_light.gdshader"
const MATERIAL_PATH := "res://resources/pilot_rim_light.tres"
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const APPLY_STYLIZED := preload("res://scripts/rendering/apply_stylized.gd")

# One shared in-tree instance, for the reason tests/test_pilot9_dash.gd gives.
var _pilot: Node = null

func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.rim_light_enabled = true
	return _pilot

# His own meshes only: the held item rides under his skeleton but is deliberately left unlit -
# tests/test_pilot9_held_item.gd pins that half.
func _meshes(pilot: Node) -> Array[MeshInstance3D]:
	var all: Array[MeshInstance3D] = []
	APPLY_STYLIZED.collect_meshes(pilot.character, all)
	var out: Array[MeshInstance3D] = []
	for mi in all:
		if not pilot.item_holder.owns(mi):
			out.append(mi)
	return out

func test_shader_exposes_the_spec_tunables() -> void:
	var names := shader_uniform_names(SHADER_PATH)
	for u in ["rim_color", "rim_direction", "rim_width", "depth_threshold", "ink_tolerance", "rim_width_min", "rim_taper"]:
		check(names.has(u), "rim_light.gdshader is missing uniform '%s'" % u)

func test_material_is_on_the_rim_shader() -> void:
	var mat := load(MATERIAL_PATH) as ShaderMaterial
	check(mat != null, "%s missing or not a ShaderMaterial" % MATERIAL_PATH)
	if mat:
		eq(mat.shader.resource_path, SHADER_PATH, "rim material should use rim_light.gdshader")

func test_every_pilot_mesh_gets_the_rim_overlay() -> void:
	var pilot := _scene()
	check(pilot != null, "could not instance pilot9")
	if pilot == null:
		return
	var meshes := _meshes(pilot)
	check(meshes.size() > 0, "pilot9's character has no meshes to light")
	for mi in meshes:
		eq(mi.material_overlay, pilot.rim_light_material, "%s should carry the rim overlay" % mi.name)

func test_toggle_off_removes_it_and_on_puts_it_back() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.rim_light_enabled = false
	for mi in _meshes(pilot):
		eq(mi.material_overlay, null, "%s should lose the overlay when toggled off" % mi.name)
	pilot.rim_light_enabled = true
	for mi in _meshes(pilot):
		eq(mi.material_overlay, pilot.rim_light_material, "%s should get it back when toggled on" % mi.name)
