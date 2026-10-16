class_name Storm
extends Node3D

# The Ichi blizzard: a two-tone distance fog that closes in on each gust, hard blowing snow and
# drift streaming along the ground. Drop one into a scene that has an overcast Environment; it
# builds the fog quad and all three snow layers in code.
# See docs/specs/ichi-snowstorm.md.
#
# The fog is a full-screen quad reading the depth buffer (shaders/storm/storm_fog.gdshader), the
# snow is two meshes of pre-scattered quads animated entirely by their vertex shader
# (shaders/storm/storm_snow.gdshader). Neither follows the player: both read the rendering
# camera's position, so they work under PixelWorld's copied camera too.

const FOG_SHADER := preload("res://shaders/storm/storm_fog.gdshader")
const SNOW_SHADER := preload("res://shaders/storm/storm_snow.gdshader")
const ROOF_BAKE_SHADER := preload("res://shaders/storm/storm_roof_bake.gdshader")

@export_group("Fog")
## Metres at which the world is 98% fog, between gusts.
@export_range(10.0, 500.0, 1.0, "or_greater") var visibility := 40.0
## The same at a gust's peak: the whiteout. Equal to visibility for a fixed wall.
@export_range(10.0, 500.0, 1.0, "or_greater") var gust_visibility := 25.0
## Fog close to the camera.
@export var near_color := Color(0.52, 0.58, 0.68)
## Fog at the visibility wall. The sky's horizon colour should match this.
@export var far_color := Color(0.80, 0.77, 0.86)
## Ink (outlines, creases) keeps this much of its darkness however deep in the fog, so far
## silhouettes linger as faint ghosts: the building is barely there from the ship.
@export_range(0.0, 1.0, 0.01) var ink_floor := 0.1

@export_group("Wind")
## Horizontal direction the snow travels (world XZ); normalised in the shader.
@export var wind_direction := Vector2(0.94, 0.33)
## Mean wind speed, m/s.
@export_range(0.0, 60.0, 0.5) var wind_speed := 28.0
## How far gusts swing the speed: 0.5 is 50% above and below the mean.
@export_range(0.0, 1.0, 0.01) var gust_amount := 0.6
## Seconds between gusts (the second, slower sine makes it irregular).
@export_range(2.0, 30.0, 0.5) var gust_period := 8.0
## Downward travel as a fraction of the horizontal speed; 0.18 is about 10 degrees.
@export_range(0.0, 1.0, 0.01, "or_greater") var fall_ratio := 0.18

@export_group("Snow")
@export var snow_tint := Color(0.92, 0.95, 1.0)
## Dense small flakes out to the visibility wall.
@export var fine_count := 20000
@export var fine_box := 50.0
@export var fine_width := 0.035
@export_range(0.0, 1.0, 0.01) var fine_opacity := 0.7
## Few large, fast-looking flakes close to the camera.
@export var near_count := 2400
@export var near_box := 30.0
@export var near_width := 0.07
@export_range(0.0, 1.0, 0.01) var near_opacity := 0.85
## Seconds of travel drawn as the streak.
@export_range(0.0, 0.2, 0.005) var streak_time := 0.04

@export_group("Drift")
## Long faint streaks blowing flat along the ground (the highest static surface, from the roof
## map), in snaking ribbons. Needs the roof map, so none headless.
@export var drift_count := 3000
@export var drift_box := 30.0
@export var drift_width := 0.12
@export_range(0.0, 1.0, 0.01) var drift_opacity := 0.3
## Metres above the surface the drift reaches; most of it stays near the bottom.
@export_range(0.0, 3.0, 0.05) var drift_height := 0.5
## Seconds of travel drawn as a drift streak: longer than the falling snow's.
@export_range(0.0, 0.3, 0.005) var drift_streak_time := 0.08
## Drift opacity between gusts as a fraction of drift_opacity; full at a gust's peak.
@export_range(0.0, 1.0, 0.01) var drift_calm := 0.4

@export_group("Shelter")
## Pixels per side of the top-down roof map. It covers the static level's XZ bounds, so OP_1
## (about 850 m on its long side) is about 0.4 m per pixel at 2048.
@export var shelter_resolution := 2048
## A flake this far below the highest surface over it counts as under a roof. Keeps flakes
## skimming the ground or a rooftop from flickering.
@export_range(0.0, 2.0, 0.05) var shelter_margin := 0.3

var fog_material: ShaderMaterial
var fine_material: ShaderMaterial
var near_material: ShaderMaterial
var drift_material: ShaderMaterial

# The baked roof map (encoded per storm_roof_bake.gdshader) and where it sits in the world.
# Null until the bake finishes, and always null headless: the dummy renderer draws nothing.
var roof_image: Image
var roof_rect := Rect2()
var roof_y_min := 0.0
var roof_y_span := 1.0


func _ready() -> void:
	# pilot9's tredge finds the storm through this - see docs/specs/pilot9-tredge.md.
	add_to_group(GROUP)
	var fog := MeshInstance3D.new()
	fog.name = "Fog"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.custom_aabb = _huge_aabb()
	fog_material = ShaderMaterial.new()
	fog_material.shader = FOG_SHADER
	# Transparent objects sort by priority first: the fog goes down before the snow.
	fog_material.render_priority = -100
	fog.mesh = quad
	fog.material_override = fog_material
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)

	fine_material = _snow_material(fine_box, fine_width, fine_opacity)
	near_material = _snow_material(near_box, near_width, near_opacity)
	_add_snow("FineSnow", fine_count, fine_material, 1)
	_add_snow("NearSnow", near_count, near_material, 2)
	drift_material = _snow_material(drift_box, drift_width, drift_opacity)
	drift_material.set_shader_parameter(&"drift", true)
	_add_snow("Drift", drift_count, drift_material, 3)
	apply()
	if DisplayServer.get_name() != "headless":
		_bake_roof_map()


func _exit_tree() -> void:
	# The ink shaders are shared by every scene: switch their storm fog off with the storm.
	RenderingServer.global_shader_parameter_set(&"storm_fog", 0.0)


## Pushes every export to the shaders. Call after changing one at runtime.
func apply() -> void:
	if fog_material == null:
		return
	# The fog is globals (storm_fog.gdshaderinc) so the ink passes can fog themselves too.
	RenderingServer.global_shader_parameter_set(&"storm_fog", 1.0)
	RenderingServer.global_shader_parameter_set(&"storm_visibility", visibility)
	RenderingServer.global_shader_parameter_set(&"storm_gust_visibility", gust_visibility)
	RenderingServer.global_shader_parameter_set(&"storm_gust_period", gust_period)
	RenderingServer.global_shader_parameter_set(&"storm_near_color", near_color)
	RenderingServer.global_shader_parameter_set(&"storm_far_color", far_color)
	RenderingServer.global_shader_parameter_set(&"storm_ink_floor", ink_floor)
	for mat in [fine_material, near_material, drift_material]:
		mat.set_shader_parameter(&"wind_dir", Vector3(wind_direction.x, 0.0, wind_direction.y))
		mat.set_shader_parameter(&"wind_speed", wind_speed)
		mat.set_shader_parameter(&"gust_amount", gust_amount)
		mat.set_shader_parameter(&"gust_period", gust_period)
		mat.set_shader_parameter(&"fall_ratio", fall_ratio)
		mat.set_shader_parameter(&"streak_time", streak_time)
		mat.set_shader_parameter(&"visibility", visibility)
		mat.set_shader_parameter(&"gust_visibility", gust_visibility)
		mat.set_shader_parameter(&"near_tint", snow_tint)
		mat.set_shader_parameter(&"far_tint", far_color)
	fine_material.set_shader_parameter(&"box_size", fine_box)
	fine_material.set_shader_parameter(&"flake_width", fine_width)
	fine_material.set_shader_parameter(&"opacity", fine_opacity)
	near_material.set_shader_parameter(&"box_size", near_box)
	near_material.set_shader_parameter(&"flake_width", near_width)
	near_material.set_shader_parameter(&"opacity", near_opacity)
	drift_material.set_shader_parameter(&"box_size", drift_box)
	drift_material.set_shader_parameter(&"flake_width", drift_width)
	drift_material.set_shader_parameter(&"opacity", drift_opacity)
	drift_material.set_shader_parameter(&"streak_time", drift_streak_time)
	drift_material.set_shader_parameter(&"drift_height", drift_height)
	drift_material.set_shader_parameter(&"drift_calm", drift_calm)
	for mat in [fine_material, near_material, drift_material]:
		mat.set_shader_parameter(&"shelter_margin", shelter_margin)


## Hands the snow a roof map: `image` encoded per storm_roof_bake.gdshader, `rect` its XZ
## footprint (position = x min, z min), heights normalised over [y_min, y_min + y_span].
func use_roof_map(image: Image, rect: Rect2, y_min: float, y_span: float) -> void:
	roof_image = image
	roof_rect = rect
	roof_y_min = y_min
	roof_y_span = y_span
	if fine_material == null:
		return
	var tex := ImageTexture.create_from_image(image)
	for mat in [fine_material, near_material, drift_material]:
		mat.set_shader_parameter(&"roof_map", tex)
		mat.set_shader_parameter(&"roof_rect", Vector3(rect.position.x, rect.position.y, rect.size.x))
		mat.set_shader_parameter(&"roof_y_min", y_min)
		mat.set_shader_parameter(&"roof_y_span", y_span)
		mat.set_shader_parameter(&"shelter_on", true)


## The group every Storm joins. One per scene.
const GROUP := &"storm"
## Shaders' TIME wraps here (rendering/limits/time/time_rollover_secs, default).
const TIME_ROLLOVER := 3600.0


## The shader's clock: seconds since the engine started, wrapped like TIME.
static func shader_time() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0, TIME_ROLLOVER)


## storm_gust_peak() from shaders/storm/storm_gust.gdshaderinc: 0 between gusts, 1 at a gust's
## peak. The same curve on the same clock, so whatever reads it lands on the whiteout's beat.
static func gust_peak_at(t: float, period: float) -> float:
	var w1 := TAU / period
	var w2 := w1 * 0.61
	var g := 0.6 * sin(w1 * t) + 0.4 * sin(w2 * t + 1.3)
	return smoothstep(0.15, 0.75, g)


## This storm's gust peak right now.
func gust_peak() -> float:
	return gust_peak_at(shader_time(), gust_period)


## World height of the highest static surface over `xz`, or -INF where there is none.
## The same decode the snow shader does.
func roof_height(xz: Vector2) -> float:
	if roof_image == null:
		return -INF
	var uv := (xz - roof_rect.position) / roof_rect.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return -INF
	var c := roof_image.get_pixelv(Vector2i(uv * Vector2(roof_image.get_size())))
	if c.a <= 0.5:
		return -INF
	return roof_y_min + (roundf(c.r * 255.0) + c.g) / 255.0 * roof_y_span


## True when no snow falls at `point`: it is more than shelter_margin under a static surface.
func is_sheltered(point: Vector3) -> bool:
	return point.y < roof_height(Vector2(point.x, point.z)) - shelter_margin


## The static level: every MeshInstance3D carrying the StaticBody3D that map_import.gd (or any
## create_trimesh_collision) gives it. Leaves out the pilot, VFX, the storm itself.
static func level_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			for child in node.get_children():
				if child is StaticBody3D:
					out.append(node)
					break
		stack.append_array(node.get_children())
	return out


## Group for box collision that should keep snow off what is under it without being level
## geometry - Sinestro2's hull in Ichi (docs/specs/ichi-parked-ship.md).
const ROOF_GROUP := &"storm_roof"

## Every BoxShape3D CollisionShape3D under `root` in ROOF_GROUP.
static func roof_boxes(root: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for node in root.find_children("*", "CollisionShape3D", true, false):
		if node.is_in_group(ROOF_GROUP) and (node as CollisionShape3D).shape is BoxShape3D:
			out.append(node)
	return out


## What the roof bake draws: [mesh, global transform] pairs for the level meshes and, as boxes,
## the roof boxes.
static func roof_parts(root: Node) -> Array:
	var out := []
	for mi in level_meshes(root):
		out.append([mi.mesh, mi.global_transform])
	for cs in roof_boxes(root):
		var box := BoxMesh.new()
		box.size = (cs.shape as BoxShape3D).size
		out.append([box, cs.global_transform])
	return out


# Renders the static level from straight above, once, through storm_roof_bake.gdshader, reads it
# back and hands it to the snow. Its own World3D so only level meshes are drawn (no pilot, fog,
# snow). The viewport is HDR so the encoded height comes back linear and unclamped.
func _bake_roof_map() -> void:
	var parts := roof_parts(get_parent() if get_parent() != null else self)
	if parts.is_empty():
		return
	var bounds := AABB()
	for i in parts.size():
		var b: AABB = parts[i][1] * (parts[i][0] as Mesh).get_aabb()
		bounds = b if i == 0 else bounds.merge(b)
	var side := maxf(bounds.size.x, bounds.size.z) + 2.0
	var center := bounds.get_center()
	var rect := Rect2(center.x - side * 0.5, center.z - side * 0.5, side, side)
	var y_min := bounds.position.y - 1.0
	var y_span := bounds.size.y + 2.0

	var vp := SubViewport.new()
	vp.size = Vector2i(shelter_resolution, shelter_resolution)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.use_hdr_2d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.mesh_lod_threshold = 0.0
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var mat := ShaderMaterial.new()
	mat.shader = ROOF_BAKE_SHADER
	mat.set_shader_parameter(&"y_min", y_min)
	mat.set_shader_parameter(&"y_span", y_span)
	for part in parts:
		var copy := MeshInstance3D.new()
		copy.mesh = part[0]
		copy.material_override = mat
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.transform = part[1]
		vp.add_child(copy)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = side
	cam.near = 0.05
	cam.far = y_span + 20.0
	# Looking down -Y with screen-up = world -Z: pixel (0, 0) is (x min, z min), matching roof_rect.
	cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
		Vector3(center.x, y_min + y_span + 10.0, center.z))
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	add_child(vp)
	cam.current = true

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		push_warning("Storm: roof map bake came back empty; snow will fall indoors")
		return
	use_roof_map(img, rect, y_min, y_span)


func _snow_material(box: float, width: float, opacity: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SNOW_SHADER
	mat.set_shader_parameter(&"box_size", box)
	mat.set_shader_parameter(&"flake_width", width)
	mat.set_shader_parameter(&"opacity", opacity)
	return mat


func _add_snow(node_name: String, count: int, mat: ShaderMaterial, rng_seed: int) -> void:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = snow_mesh(count, rng_seed)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


## `count` quads sharing the storm_snow vertex contract. Static so a test can build one.
static func snow_mesh(count: int, rng_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(count * 4)
	uvs.resize(count * 4)
	cols.resize(count * 4)
	idx.resize(count * 6)
	for i in count:
		var c := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		for k in 4:
			var v: int = i * 4 + k
			verts[v] = Vector3(corners[k].x, corners[k].y, 0.0)
			uvs[v] = Vector2(corners[k].x + 0.5, corners[k].y + 0.5)
			cols[v] = c
		var base: int = i * 4
		var o: int = i * 6
		idx[o] = base
		idx[o + 1] = base + 1
		idx[o + 2] = base + 2
		idx[o + 3] = base
		idx[o + 4] = base + 2
		idx[o + 5] = base + 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader moves every vertex around the camera: never cull on the flat quads' bounds.
	mesh.custom_aabb = _huge_aabb()
	return mesh


static func _huge_aabb() -> AABB:
	return AABB(Vector3.ONE * -10000.0, Vector3.ONE * 20000.0)
