class_name PixelLook
extends Node

# The LOOK switch: CEL (today's cel + black ink) or PIXEL (stepped soft light, surface clumps, warm
# haze, no ink).
# See docs/specs/pixel-look.md.
#
# PIXEL swaps every material running the cel base shader for a twin on the pixel-look shader,
# with the same colour, texture, tiling and anchor and no next_pass (that is the outline and the
# crease ink gone). It records every slot it touched, so CEL puts back exactly what was there,
# including "no override" on slots that only had the mesh's own material. Nodes that enter the
# tree while PIXEL is on are swapped as they arrive.
#
# The block size and the colour banding are PixelWorld's; Settings sends them there. This node owns the
# materials, the environment and pilot9's rim light.
#
# It works on its parent's subtree (in trial.tscn, the whole scene), plus anything added anywhere
# while PIXEL is on.
#
# QA key: I cycles LOOK (CEL, PIXEL, RETRO), through Settings so the menu row agrees. RETRO is
# RetroLook, a subclass of this node - see docs/specs/retro-look.md.

const CEL_SHADER := preload("res://shaders/cel/cel-shader-base.gdshader")
const PIXEL_SHADER := preload("res://shaders/pixel_look/pixel-look.gdshader")

## Uniforms the two shaders share by name, carried onto a twin.
const SHARED_PARAMS: Array[StringName] = [&"color", &"base_texture", &"uv_scale", &"uv_offset"]

@export_group("Haze")
## Exponential fog density in PIXEL. 0.008 is about a third gone at 50 m and half at 90 m.
@export_range(0.0, 0.05, 0.0005) var fog_density := 0.008
## The haze colour: the golden olive of the field reference, on every map.
@export var fog_color := Color(0.70, 0.64, 0.45)
## How much distant geometry takes on the sky's colour instead of fog_color. 0: the map's own sky
## (blue in trial) would cool the haze back down.
@export_range(0.0, 1.0, 0.01) var fog_aerial_perspective := 0.0
## How much the haze covers the sky itself, so the sky goes golden too and the horizon melts.
@export_range(0.0, 1.0, 0.01) var fog_sky_affect := 0.85

@export_group("Grade")
@export_range(0.0, 2.0, 0.01) var saturation := 0.9
@export_range(0.0, 2.0, 0.01) var contrast := 0.95
## Where black lands: a warm lift, so shadows read brown-olive rather than grey.
@export var shadow_lift := Color(0.07, 0.05, 0.015)
## Where white lands: a little warm.
@export var highlight := Color(1.0, 0.97, 0.88)

var pixel := false
## source cel material -> its pixel twin. Shared materials share a twin.
var _twins: Dictionary = {}
## One entry per slot swapped: { "node": GeometryInstance3D, "slot": int, "original": Material }.
## slot SLOT_OVERRIDE is material_override; 0+ is a MeshInstance3D surface override.
var _swapped: Array[Dictionary] = []
## instance id -> true for every node with an entry in _swapped, so a node added twice (reparented)
## is not swapped onto its own twin's record.
var _swapped_ids: Dictionary = {}
var _env_node: WorldEnvironment
var _cel_env: Environment
var _pixel_env: Environment

const SLOT_OVERRIDE := -1


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_to_group(&"pixel_look")
	var settings := get_node_or_null(^"/root/Settings")
	if settings and settings.look == "pixel":
		# Deferred: the generated maps and the appliers build their materials in their own
		# _ready, some of them after this one.
		apply_look.call_deferred(true)


func _exit_tree() -> void:
	if pixel:
		apply_look(false)


## Called by Settings when LOOK changes, and on _ready().
func apply_look(on: bool) -> void:
	if on == pixel:
		return
	pixel = on
	var tree := get_tree()
	if on:
		swap_subtree(get_parent())
		tree.node_added.connect(_on_node_added)
	else:
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
		restore_all()
	_apply_environment(on)
	for pilot in tree.get_nodes_in_group(&"player"):
		if &"rim_light_suppressed" in pilot:
			pilot.rim_light_suppressed = on


## Swaps every cel slot under `root` (itself included). Returns slots swapped.
func swap_subtree(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	if root is GeometryInstance3D:
		count += _swap_geometry(root)
	for child in root.get_children():
		count += swap_subtree(child)
	return count


## Puts back every slot swap_subtree() touched, on nodes that still exist.
func restore_all() -> void:
	for entry in _swapped:
		var node: GeometryInstance3D = entry.node if is_instance_valid(entry.node) else null
		if node == null:
			continue
		if entry.slot == SLOT_OVERRIDE:
			node.material_override = entry.original
		else:
			var mi := node as MeshInstance3D
			if mi.mesh != null and entry.slot < mi.mesh.get_surface_count():
				mi.set_surface_override_material(entry.slot, entry.original)
	_swapped.clear()
	_swapped_ids.clear()


## Whether `mat` runs the cel base shader.
static func is_cel(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader == CEL_SHADER


## The pixel twin for a cel material: same colour, texture, tiling and anchor, no next_pass.
func twin_of(cel: ShaderMaterial) -> ShaderMaterial:
	if _twins.has(cel):
		return _twins[cel]
	var twin := ShaderMaterial.new()
	twin.shader = PIXEL_SHADER
	twin.render_priority = cel.render_priority
	for param in SHARED_PARAMS:
		var value: Variant = cel.get_shader_parameter(param)
		if value != null:
			twin.set_shader_parameter(param, value)
	var anchor: Variant = cel.get_shader_parameter(&"paint_anchor")
	twin.set_shader_parameter(&"clump_anchor", int(anchor) if anchor != null else 0)
	_twins[cel] = twin
	return twin



## The twin `node` gets for `cel`. PIXEL gives every node the same twin; RetroLook chooses per node
## (cel or painted background).
func twin_for(_node: GeometryInstance3D, cel: ShaderMaterial) -> ShaderMaterial:
	return twin_of(cel)

func _swap_geometry(node: GeometryInstance3D) -> int:
	var count := 0
	if _swapped_ids.has(node.get_instance_id()):
		return count
	if node.material_override != null:
		# A whole-node override hides every surface material, so it is the only slot that shows.
		if is_cel(node.material_override):
			_record(node, SLOT_OVERRIDE, node.material_override)
			node.material_override = twin_for(node, node.material_override)
			count += 1
		return count
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return count
	for i in mi.mesh.get_surface_count():
		var override := mi.get_surface_override_material(i)
		var shown := override if override != null else mi.mesh.surface_get_material(i)
		if is_cel(shown):
			_record(mi, i, override)
			mi.set_surface_override_material(i, twin_for(mi, shown))
			count += 1
	return count


func _record(node: GeometryInstance3D, slot: int, original: Material) -> void:
	_swapped.append({"node": node, "slot": slot, "original": original})
	_swapped_ids[node.get_instance_id()] = true


# A node's own _ready (where the generated maps set their materials) runs after node_added, so
# the swap waits a frame's worth of deferral.
func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_swap_late.call_deferred(node)


func _swap_late(node: Node) -> void:
	if pixel and is_instance_valid(node) and node.is_inside_tree():
		_swap_geometry(node)


# --- environment -----------------------------------------------------------------

func _apply_environment(on: bool) -> void:
	if on:
		_env_node = _find_world_environment(get_parent())
		if _env_node == null or _env_node.environment == null:
			return
		_cel_env = _env_node.environment
		_pixel_env = pixel_environment(_cel_env)
		_env_node.environment = _pixel_env
	elif _env_node != null and is_instance_valid(_env_node) and _cel_env != null:
		_env_node.environment = _cel_env
		_env_node = null
		_cel_env = null
		_pixel_env = null


## A copy of `cel_env` with the PIXEL haze and grade.
func pixel_environment(cel_env: Environment) -> Environment:
	var env := cel_env.duplicate() as Environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = fog_density
	env.fog_light_color = fog_color
	env.fog_aerial_perspective = fog_aerial_perspective
	env.fog_sky_affect = fog_sky_affect
	env.adjustment_enabled = true
	env.adjustment_saturation = saturation
	env.adjustment_contrast = contrast
	env.adjustment_brightness = 1.0
	env.adjustment_color_correction = grade_ramp()
	return env


## The per-channel curve the grade applies: black lifts to shadow_lift, white lands on highlight.
func grade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, shadow_lift)
	gradient.set_color(1, highlight)
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	ramp.width = 256
	return ramp


static func _find_world_environment(node: Node) -> WorldEnvironment:
	if node == null:
		return null
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_world_environment(child)
		if found:
			return found
	return null


# --- QA key ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_I:
		return
	var settings := get_node_or_null(^"/root/Settings")
	if settings:
		var looks: Array = settings.values_of(&"look")
		settings.set_value(&"look", looks[(looks.find(settings.look) + 1) % looks.size()])
