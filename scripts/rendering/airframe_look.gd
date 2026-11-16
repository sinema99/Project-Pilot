class_name AirframeLook
extends JetpackLook

# The AIRFRAME look: Jetpack's Airframe Ultra / PS1 look as the third LOOK in a gameplay map
# (trial), turned down to `intensity` 0.75. See docs/specs/airframe-trial.md.
#
# Settings switches it (set_active) like RETRO: the look being left lets go of its materials first.
# While it is on:
# - every eligible material slot under this node's parent is recorded and given a PS1 material of
#   its colour (cel-base, metre grid, and opaque lit StandardMaterial3D; glows, transparent and
#   effect shaders keep theirs). Ink goes with the cel material (the PS1 one has no next_pass).
#   World-projected pixels for the level, object-projected for things that move, rest-pose
#   projected for skinned bodies (their mesh is swapped for a CUSTOM0/1 copy and put back after).
#   Nodes that arrive while it is on are swapped as they arrive.
# - the WorldEnvironment wears resources/airframe_environment.tres (Jetpack's, shared), no
#   compositor; the sun takes Jetpack's colour, energy and biases at `sun_elevation_deg`, keeping
#   the map's own compass direction; directional shadows are hard.
# - the screen filter is up; QA keys 5-9 work and flash the label for LABEL_SECONDS.
# Off puts back every slot, mesh, the environment, the sun and the shadow filter.
#
# A node can opt out with the meta `airframe_skip` = true (itself and everything under it).

const CEL_SHADER := preload("res://shaders/cel/cel-shader-base.gdshader")
const GRID_SHADER := preload("res://shaders/metre_grid.gdshader")
const ENVIRONMENT := preload("res://resources/airframe_trial_environment.tres")
const LABEL_SECONDS := 3.0
const SKIP_META := &"airframe_skip"
const CHARACTER_META := &"airframe_character"

## A map's own environment (fog, sky, ambient) in place of the shared trial one. Empty = the shared.
@export var environment_override: Environment

@export_group("Sun")
## The sun's height while AIRFRAME is on (Jetpack's 45). Its compass direction stays the map's.
@export_range(5.0, 90.0, 1.0) var sun_elevation_deg := 45.0
@export var sun_color := Color(1.0, 0.96, 0.88)
@export var sun_energy := 1.6
# Hard shadows on a grazing ground draw curved acne rings (shadow-map moire) at the old 0.03 / 1.0.
@export var sun_shadow_bias := 0.15
@export var sun_shadow_normal_bias := 2.5

## 0 = hard shadows (the look's default). Above 0 the sun's shadow filter follows the SHADOW QUALITY
## setting instead and the sun gets this angular size in degrees, so a shadow's edge blurs wider the
## farther it falls from what casts it (about 1 degree = 1-2 m of fade on a far wall).
@export_range(0.0, 5.0, 0.05) var soft_sun_angle_deg := 0.0

var active := false
var _swapped_ids: Dictionary = {}
## [mapping, colour, vertex colour] -> shared PS1 material.
var _cache: Dictionary = {}
## Original ArrayMesh -> its rest-pose copy, kept across toggles (the bake is the slow part).
var _rest_meshes: Dictionary = {}
## [MeshInstance3D, original mesh, rest-pose mesh] for every body wearing a rest-pose copy.
var _mesh_swaps: Array = []
var _texture_means: Dictionary = {}
## Character meshes put on PixelWorld.CHAR_LAYER while this look is on.
var _tagged: Array = []
var _env_node: WorldEnvironment
var _saved_env: Environment
var _saved_compositor: Compositor
var _saved_sun: Dictionary = {}
var _label_left := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	label_title = "AIRFRAME LOOK"


func _enter_tree() -> void:
	# On enter, so RetroLook's _ready already sees this map has one.
	add_to_group(&"airframe_look")


func _ready() -> void:
	_base_texels = texels_per_metre
	_build_filter()
	_build_label()
	apply()
	var settings := get_node_or_null(^"/root/Settings")
	if settings and settings.look == "airframe":
		# Deferred: the cel appliers and the generated maps set their materials in their own _ready.
		set_active.call_deferred(true)


func _exit_tree() -> void:
	if active:
		set_active(false)


func _process(delta: float) -> void:
	super(delta)
	if _label_left > 0.0:
		_label_left -= delta
		if _label_left <= 0.0:
			_update_label()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not active or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode < KEY_5 or key.physical_keycode > KEY_9:
		return
	_label_left = LABEL_SECONDS
	super(event)


## On: swap everything under the parent and dress the map. Off: put it all back.
func set_active(on: bool) -> void:
	# Settings can push the look before this node's _ready (its own _ready catches up then).
	if on == active or not is_inside_tree() or not is_node_ready():
		return
	active = on
	var tree := get_tree()
	if on:
		swap_subtree(get_parent())
		tree.node_added.connect(_on_node_added)
	else:
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
		_restore_all()
	_apply_world(on)
	# Characters are lit flat per face while AIRFRAME shows (ps1_surface and the mech's shader).
	RenderingServer.global_shader_parameter_set(&"airframe_char_flat", 1.0 if on else 0.0)
	apply()


func _update_filter() -> void:
	super()
	_filter_layer.visible = _filter_layer.visible and active


func _update_label() -> void:
	super()
	_label.visible = active and _label_left > 0.0


# -- swapping -------------------------------------------------------------------------------

## Swaps every eligible slot under `root` (itself included). Returns slots swapped.
func swap_subtree(root: Node) -> int:
	if root == null or root == self or root.get_meta(SKIP_META, false):
		return 0
	var count := 0
	if root is GeometryInstance3D:
		count += _swap_geometry(root)
	if root is Light3D:
		_tag_light(root)
	for child in root.get_children():
		count += swap_subtree(child)
	return count


func _swap_geometry(node: GeometryInstance3D) -> int:
	var id := node.get_instance_id()
	if _skipped(node):
		return 0
	_tag_character(node)
	if _swapped_ids.has(id):
		return 0
	if node.material_override != null:
		# A whole-node override hides every surface material, so it is the only slot that shows.
		var source := colour_source(node.material_override)
		if source.is_empty():
			return 0
		_swapped_ids[id] = true
		var map_kind := 1 if moves(node) else 0
		_record(node, -1, node.material_override, _ps1(source, map_kind, 1.0, node))
		return 1
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return 0
	var picks: Array = []
	for i in mi.mesh.get_surface_count():
		var override := mi.get_surface_override_material(i)
		var shown := override if override != null else mi.mesh.surface_get_material(i)
		var source := colour_source(shown)
		if not source.is_empty():
			# The mesh's own (GLB) material names a pilot body surface; the cel override is unnamed.
			picks.append([i, override, source, mi.mesh.surface_get_material(i)])
	if picks.is_empty():
		return 0
	_swapped_ids[id] = true
	var mapping := 0
	var scale := 1.0
	if is_skinned(mi) and _wear_rest_pose(mi):
		mapping = 2
		scale = _rest_scale(mi, mi.get_parent() as Skeleton3D)
	elif moves(mi):
		mapping = 1
	for p: Array in picks:
		var ps1: ShaderMaterial
		var kind := grime_kind(p[3]) if mapping == 2 and is_character(mi) else -1
		if mi.name == &"Coat":
			ps1 = _coat_ps1(mi, p[0], p[2], mapping, scale)
		elif kind >= 0:
			ps1 = _grime_ps1(mi, kind, p[2], scale)
		else:
			ps1 = _ps1(p[2], mapping, scale, mi)
		_record(mi, p[0], p[1], ps1)
	return picks.size()


func _record(node: GeometryInstance3D, slot: int, original: Material, ps1: ShaderMaterial) -> void:
	var entry := [node, slot, original, ps1]
	_world_surfaces.append(entry)
	show_slot(entry, look_enabled)


func _ps1(source: Array, mapping: int, scale: float, node: Node = null) -> ShaderMaterial:
	var tier := snap_tier(node, mapping)
	var character := node != null and is_character(node)
	var key := [mapping, source[0], source[1], snappedf(scale, 0.0001), tier, character]
	if not _cache.has(key):
		var made := new_ps1_colour(source[0], source[1], mapping, scale)
		made.set_meta(&"snap_tier", tier)
		made.set_shader_parameter(&"is_character", character)
		_cache[key] = made
	var m: ShaderMaterial = _cache[key]
	return m


## The trench coat's own PS1 material per surface: finer pixels, five tones, worn leather
## (JetpackLook._wear_coat). Never shared: its tones are not the project's.
func _coat_ps1(mi: MeshInstance3D, surface: int, source: Array, mapping: int, scale: float) -> ShaderMaterial:
	var key := [&"coat", mi.get_instance_id(), surface, mapping]
	if not _cache.has(key):
		var made := new_ps1_colour(source[0], source[1], mapping, scale)
		made.set_meta(&"snap_tier", snap_tier(mi, mapping))
		made.set_shader_parameter(&"is_character", true)
		# Outside faces only: the leather's inside otherwise z-fights the lining 6 mm behind it
		# (a dotted shimmer on the back panels). JetpackLook sets the same.
		made.set_shader_parameter(&"cull_back", true)
		_wear_coat(made, mi.get_parent() as Skeleton3D, surface)
		_cache[key] = made
	return _cache[key]


## pilot9's body material with grime (JetpackLook._grime), shared per kind / colour / scale.
func _grime_ps1(mi: MeshInstance3D, kind: int, source: Array, scale: float) -> ShaderMaterial:
	var tier := snap_tier(mi, 2)
	var key := [&"grime", kind, source[0], source[1], snappedf(scale, 0.0001), tier]
	if not _cache.has(key):
		var made := new_ps1_colour(source[0], source[1], 2, scale)
		made.set_meta(&"snap_tier", tier)
		made.set_shader_parameter(&"is_character", true)
		_grime(made, kind)
		_cache[key] = made
	return _cache[key]


## Vertex-snap grid rows for a surface: static world (mapping 0) none, anything that moves 480, and
## a node under an `airframe_snap_lines` meta (mech, speeder) that finer grid.
func snap_tier(node: Node, mapping: int) -> float:
	var n := node
	while n != null:
		if n.has_meta(&"airframe_snap_lines"):
			return float(n.get_meta(&"airframe_snap_lines"))
		n = n.get_parent()
	return 480.0 if mapping != 0 else 0.0


func snap_lines_for(m: ShaderMaterial) -> float:
	return float(m.get_meta(&"snap_tier", 0.0))


## Swaps a skinned body's mesh for its rest-pose copy. False if it can't be built.
func _wear_rest_pose(mi: MeshInstance3D) -> bool:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return false
	if not _rest_meshes.has(src):
		_rest_meshes[src] = rest_pose_mesh(src)
	set_mesh_keeping_overrides(mi, _rest_meshes[src])
	_mesh_swaps.append([mi, src, _rest_meshes[src]])
	return true


func _restore_all() -> void:
	for entry: Array in _world_surfaces:
		show_slot(entry, false)
	for swap: Array in _mesh_swaps:
		if not is_instance_valid(swap[0]):
			continue
		var mi := swap[0] as MeshInstance3D
		if mi.mesh == swap[2]:
			set_mesh_keeping_overrides(mi, swap[1])
	# Untyped on purpose: a typed loop var errors on a node already freed by scene teardown.
	for tagged in _tagged:
		if is_instance_valid(tagged):
			var node := tagged as VisualInstance3D
			node.layers &= ~PixelWorld.CHAR_MASK
	_tagged.clear()
	_world_surfaces.clear()
	_mesh_swaps.clear()
	_swapped_ids.clear()
	_cache.clear()
	_ps1_materials.clear()
	_grime_materials.clear()


func _skipped(node: Node) -> bool:
	var n := node
	while n != null and n != get_parent():
		if n.get_meta(SKIP_META, false):
			return true
		n = n.get_parent()
	return false


# A node's own _ready (where generated pieces set their materials) runs after node_added.
func _on_node_added(node: Node) -> void:
	if node is Light3D:
		_tag_light.call_deferred(node)
	elif node is GeometryInstance3D:
		_swap_late.call_deferred(node)


func _swap_late(node: Node) -> void:
	if active and is_instance_valid(node) and node.is_inside_tree() and get_parent().is_ancestor_of(node):
		_swap_geometry(node)


## [colour, vertex colour] a slot's material is drawn in, or [] if AIRFRAME leaves it alone:
## cel-base (its colour times its texture's mean), the metre grid (its base colour), and opaque lit
## StandardMaterial3D without emission. Anything see-through, glowing or unshaded keeps its own.
func colour_source(mat: Material) -> Array:
	var sm := mat as ShaderMaterial
	if sm != null:
		if sm.shader == CEL_SHADER:
			var c: Variant = sm.get_shader_parameter(&"color")
			var col: Color = c if c is Color else Color(1, 1, 1)
			var tex: Variant = sm.get_shader_parameter(&"base_texture")
			if tex is Texture2D:
				col *= _texture_mean(tex)
			if col.a < 0.98:
				return []
			col.a = 1.0
			return [col, false]
		if sm.shader == GRID_SHADER:
			var g: Variant = sm.get_shader_parameter(&"base_color")
			var col: Color = g if g is Color else Color(0.46, 0.48, 0.52)
			col.a = 1.0
			return [col, false]
		return []
	var std := mat as BaseMaterial3D
	if std == null:
		return []
	if std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			or std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or std.emission_enabled:
		return []
	var colour := std.albedo_color
	if std.albedo_texture != null:
		colour *= _texture_mean(std.albedo_texture)
	colour.a = 1.0
	return [colour, std.vertex_color_use_as_albedo]


## A texture's mean colour (alpha included), from a 16x16 sample grid. White if unreadable.
func _texture_mean(tex: Texture2D) -> Color:
	if _texture_means.has(tex):
		return _texture_means[tex]
	var mean := Color(1, 1, 1)
	var img := tex.get_image()
	if img != null:
		img = img.duplicate() as Image
		if not img.is_compressed() or img.decompress() == OK:
			var sum := Color(0, 0, 0, 0)
			var w := img.get_width()
			var h := img.get_height()
			for y in 16:
				for x in 16:
					sum += img.get_pixel(int((x + 0.5) * w / 16.0), int((y + 0.5) * h / 16.0))
			mean = sum / 256.0
	_texture_means[tex] = mean
	return mean


## Skinned: a mesh with bone weights on a skeleton.
static func is_skinned(mi: MeshInstance3D) -> bool:
	if not (mi.get_parent() is Skeleton3D) or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	return (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES) != 0


## Alive or driven: under a CharacterBody3D (pilots, mech, speeder) or a node with the meta
## `airframe_character` (the range dummy, the knight). These are lit flat per face and, with
## CHARACTER PIXELS on, drawn in PixelWorld's CharView grid. See docs/specs/airframe-character-pixels.md.
static func is_character(node: Node) -> bool:
	var n := node
	while n != null:
		if n is CharacterBody3D or n.has_meta(CHARACTER_META):
			return true
		n = n.get_parent()
	return false


## Puts a character mesh on PixelWorld's CHAR_LAYER (as well as layer 1) so CharView can draw it.
func _tag_character(node: GeometryInstance3D) -> void:
	if is_character(node) and (node.layers & PixelWorld.CHAR_MASK) == 0:
		node.layers |= PixelWorld.CHAR_MASK
		_tagged.append(node)


## A light must share a layer with the camera that draws it, so every light is put on CHAR_LAYER
## too, or CharView's camera (which sees only that layer) would draw the characters unlit by the sun.
func _tag_light(light: Light3D) -> void:
	if (light.layers & PixelWorld.CHAR_MASK) == 0:
		light.layers |= PixelWorld.CHAR_MASK
		_tagged.append(light)


## Rides something that moves (a bone, a character, a physics or animated body): its pixels
## follow it in object space instead of swimming through a world grid.
static func moves(node: Node) -> bool:
	var n := node.get_parent()
	while n != null:
		if n is Skeleton3D or n is CharacterBody3D or n is RigidBody3D or n is AnimatableBody3D:
			return true
		n = n.get_parent()
	return false


# -- environment + sun ----------------------------------------------------------------------

func _apply_world(on: bool) -> void:
	if on:
		_env_node = PixelLook._find_world_environment(get_parent())
		if _env_node != null:
			_saved_env = _env_node.environment
			_saved_compositor = _env_node.compositor
			_env_node.environment = environment_override if environment_override != null else ENVIRONMENT
			_env_node.compositor = null
		if sun != null:
			_saved_sun = {"basis": sun.global_basis, "light_color": sun.light_color,
				"light_energy": sun.light_energy, "shadow_blur": sun.shadow_blur,
				"shadow_bias": sun.shadow_bias, "shadow_normal_bias": sun.shadow_normal_bias,
					"light_angular_distance": sun.light_angular_distance}
			sun.global_basis = sun_basis(sun.global_basis, sun_elevation_deg)
			sun.light_color = sun_color
			sun.light_energy = sun_energy
			sun.shadow_blur = 0.0
			sun.shadow_bias = sun_shadow_bias
			sun.shadow_normal_bias = sun_shadow_normal_bias
			sun.light_angular_distance = soft_sun_angle_deg
		if soft_sun_angle_deg > 0.0:
			restore_shadow_quality(self)
		else:
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		return
	if _env_node != null and is_instance_valid(_env_node):
		_env_node.environment = _saved_env
		_env_node.compositor = _saved_compositor
	_env_node = null
	_saved_env = null
	_saved_compositor = null
	if sun != null and is_instance_valid(sun) and not _saved_sun.is_empty():
		sun.global_basis = _saved_sun.basis
		for prop: String in ["light_color", "light_energy", "shadow_blur", "shadow_bias", "shadow_normal_bias", "light_angular_distance"]:
			sun.set(prop, _saved_sun[prop])
	_saved_sun = {}
	restore_shadow_quality(self)


## `basis` turned so the sun stands `elevation_deg` up, on the same compass bearing.
static func sun_basis(basis: Basis, elevation_deg: float) -> Basis:
	var towards := basis.z.normalized()
	var flat := Vector3(towards.x, 0.0, towards.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3(1, 0, 0)
	var e := deg_to_rad(elevation_deg)
	var new_towards := flat * cos(e) + Vector3.UP * sin(e)
	return Basis.looking_at(-new_towards, Vector3.UP)
