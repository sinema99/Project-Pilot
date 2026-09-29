## The hologram pause menu's rig: the shot, the timeline, the panel, the beam, the visor ring, the
## world dim and the input forwarding. Built at runtime by pilot9.gd::_setup_hologram() and driven
## by the UI autoload. See docs/specs/pilot9-hologram-pause.md.
##
## One timeline, `t` in 0..1 (0 gameplay, 1 fully open). Open plays it forward over OPEN_TIME,
## close plays it back over CLOSE_TIME, and Esc mid-way just flips the direction - so there is only
## ever one animation and no way to be half of two.
extends Node3D

## Emitted on the frame the close reaches t = 0 and the camera is handed back.
signal closed

const OPEN_TIME := 0.85
const CLOSE_TIME := 0.3
const CAMERA_TIME := 0.45
const USABLE_TIME := 0.55

const RING_ON := 0.10
const BEAM_IN := Vector2(0.15, 0.35)
const BEAM_OUT := Vector2(0.55, 0.85)
const PANEL_IN := Vector2(0.25, 0.55)

const PANEL_SHADER := preload("res://shaders/ui/hologram_panel.gdshader")
const BEAM_SHADER := preload("res://shaders/ui/hologram_beam.gdshader")
const DIM_SHADER := preload("res://shaders/ui/hologram_dim.gdshader")
const STENCIL_SHADER := preload("res://shaders/ui/hologram_stencil.gdshader")

@export_group("Shot")
@export var shot_back := 1.1
@export var shot_right := 0.55
@export var shot_up := 0.15
@export var shot_fov := 55.0
@export var shot_min_distance := 0.45
@export var sweep_radius := 0.15

@export_group("Panel")
@export var panel_resolution := Vector2i(1280, 800)
@export var panel_distance := 2.0
@export var panel_height_fraction := 0.72
@export var panel_max_width_fraction := 0.6
@export var panel_turn := 17.0
## Gap kept between the panel and the window edge, as a fraction of half the screen.
@export var panel_margin := 0.08

@export_group("Visor ring")
## Off: the glowing seam read badly on his head. Only the beam's origin still uses `ring_offset`.
@export var ring_enabled := false
@export var ring_radius := 0.11
@export var ring_thickness := 0.008
@export var ring_offset := Vector3(0.0, 0.08, 0.02)
@export var ring_tilt := Vector3.ZERO

var t := 0.0

var _body: Node3D
var _camera: Camera3D
var _skeleton: Skeleton3D
var _character: Node3D
var _head_bone := -1

var _active := false
var _opening := false

var _viewport: SubViewport
var _panel: MeshInstance3D
var _panel_mat: ShaderMaterial
var _panel_size := Vector2.ONE
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _dim: MeshInstance3D
var _dim_mat: ShaderMaterial
var _ring_attachment: BoneAttachment3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _stencil_mat: ShaderMaterial

var _saved_transform := Transform3D.IDENTITY
var _saved_fov := 75.0
var _saved_h := 0.0
var _saved_v := 0.0
var _start_global := Transform3D.IDENTITY
var _target_global := Transform3D.IDENTITY
var _head_pos := Vector3.ZERO
var _stenciled: Dictionary = {}
var _chained: Array[Material] = []

# --- pure rules (static, so the tests need no tree) ---------------------------

## Flat unless every condition holds. Decided once when Esc opens the shell.
static func hologram_mode(setting_on: bool, has_host: bool, pilot_visible: bool,
		camera_current: bool) -> bool:
	return setting_on and has_host and pilot_visible and camera_current

## Behind his head and to his RIGHT, off his facing (yaw only - the height of `forward` is
## ignored, so a tilted model gives the same shot as a level one).
static func shot_position(head: Vector3, forward: Vector3, back: float, right: float,
		up: float) -> Vector3:
	var f := Vector3(forward.x, 0.0, forward.z)
	f = f.normalized() if f.length() > 0.0001 else Vector3.FORWARD
	# His right is forward x up: the rig faces +Z with his right arm on -X.
	return head + Vector3.UP * up - f * back + f.cross(Vector3.UP) * right

## Where a sweep that found `safe` (0..1 of the way) puts the camera, never closer to `head` than
## `min_distance`. A readable menu beats a perfect shot, so a blocked minimum clips.
static func swept_position(head: Vector3, sweep_from: Vector3, target: Vector3, safe: float,
		min_distance: float) -> Vector3:
	var pos := sweep_from.lerp(target, clampf(safe, 0.0, 1.0))
	var away := pos - head
	if away.length() >= min_distance:
		return pos
	var dir := (target - head)
	dir = dir.normalized() if dir.length() > 0.0001 else Vector3.BACK
	return head + dir * min_distance

## The short way round from `from` to `to`, `s` of the way (0..1). 170 -> -190 degrees is 20
## degrees, not 360.
static func swing_yaw(from: float, to: float, s: float) -> float:
	return lerp_angle(from, to, s)

static func ease_out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)

## Seconds into the open timeline for a given t.
static func timeline_time(t_value: float) -> float:
	return t_value * OPEN_TIME

## Input only lands on a panel that has settled, and never while closing.
static func input_live(t_value: float, opening: bool) -> bool:
	return opening and timeline_time(t_value) >= USABLE_TIME - 0.0001

## Where a ray meets the panel, as UV in 0..1 with (0,0) the top-left, or null on a miss. With
## `clamp_to_edge` a ray that lands outside is pulled onto the nearest edge instead - used so a
## button release outside the quad still ends a slider drag.
static func ray_to_uv(origin: Vector3, direction: Vector3, panel: Transform3D, size: Vector2,
		clamp_to_edge := false) -> Variant:
	var normal := panel.basis.z.normalized()
	var denom := direction.dot(normal)
	if absf(denom) < 0.00001:
		return null
	var dist := (panel.origin - origin).dot(normal) / denom
	if dist < 0.0:
		return null
	var local := panel.affine_inverse() * (origin + direction * dist)
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		if not clamp_to_edge:
			return null
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	return uv

# --- setup --------------------------------------------------------------------

func setup(body: Node3D, camera: Camera3D, skeleton: Skeleton3D, character: Node3D) -> void:
	_body = body
	_camera = camera
	_skeleton = skeleton
	_character = character
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	add_to_group(&"hologram_host")
	if skeleton != null:
		_head_bone = skeleton.find_bone("Head")
	_build()
	set_process(false)

func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.size = panel_resolution
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_panel_mat = ShaderMaterial.new()
	_panel_mat.shader = PANEL_SHADER
	_panel_mat.render_priority = 40
	_panel_mat.set_shader_parameter(&"ui_tex", _viewport.get_texture())
	_panel = MeshInstance3D.new()
	_panel.mesh = QuadMesh.new()
	_panel.material_override = _panel_mat
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel.visible = false
	add_child(_panel)

	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.render_priority = 30
	_beam = MeshInstance3D.new()
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 100.0
	_beam.visible = false
	add_child(_beam)

	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = DIM_SHADER
	_dim_mat.render_priority = 0
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_dim = MeshInstance3D.new()
	_dim.mesh = quad
	_dim.material_override = _dim_mat
	_dim.extra_cull_margin = 16384.0
	_dim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dim.visible = false
	add_child(_dim)

	_stencil_mat = ShaderMaterial.new()
	_stencil_mat.shader = STENCIL_SHADER
	_stencil_mat.render_priority = -10

	if ring_enabled and _skeleton != null and _head_bone >= 0:
		_ring_attachment = BoneAttachment3D.new()
		_ring_attachment.name = &"HologramVisorRing"
		_ring_attachment.bone_name = "Head"
		_skeleton.add_child(_ring_attachment)
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ring_mat.albedo_color = Color(0.25, 0.95, 0.9, 0.0)
		_ring_mat.render_priority = 20
		var torus := TorusMesh.new()
		torus.inner_radius = ring_radius
		torus.outer_radius = ring_radius + ring_thickness
		torus.rings = 32
		torus.ring_segments = 6
		_ring = MeshInstance3D.new()
		_ring.mesh = torus
		_ring.material_override = _ring_mat
		_ring.position = ring_offset
		_ring.rotation_degrees = ring_tilt
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.visible = false
		_ring_attachment.add_child(_ring)

## Where the screens that live in the hologram are parented while it is up.
func screen_host() -> Node:
	return _viewport

# --- open / close -------------------------------------------------------------

func is_active() -> bool:
	return _active

func is_live() -> bool:
	return _active and input_live(t, _opening)

## Starts, or reverses a close in progress.
func open() -> void:
	if not _active:
		_begin()
	_opening = true
	set_process(true)

## Reverses toward gameplay. `closed` fires when the camera is home.
func close() -> void:
	if _active:
		_opening = false

func _begin() -> void:
	_active = true
	_saved_transform = _camera.transform
	_saved_fov = _camera.fov
	_saved_h = _camera.h_offset
	_saved_v = _camera.v_offset
	_start_global = _camera.global_transform
	_head_pos = _head_position()

	var forward := _facing()
	var target_pos := shot_position(_head_pos, forward, shot_back, shot_right, shot_up)
	var sweep_from := _head_pos + Vector3.UP * shot_up
	target_pos = _sweep(sweep_from, target_pos)
	var look := Basis.looking_at(Vector3(forward.x, 0.0, forward.z).normalized(), Vector3.UP)
	_target_global = Transform3D(look, target_pos)
	_place_panel()
	_build_beam()

	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_panel.visible = true
	_beam.visible = true
	_dim.visible = true
	if _ring != null:
		_ring.visible = true
	_set_pilot_stencil(true)
	_apply_t()

func _finish() -> void:
	_camera.transform = _saved_transform
	_camera.fov = _saved_fov
	_camera.h_offset = _saved_h
	_camera.v_offset = _saved_v
	_panel.visible = false
	_beam.visible = false
	_dim.visible = false
	if _ring != null:
		_ring.visible = false
	_set_pilot_stencil(false)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active = false
	_opening = false
	set_process(false)
	closed.emit()

func _exit_tree() -> void:
	if _active:
		_set_pilot_stencil(false)

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if _opening:
		t = minf(t + delta / OPEN_TIME, 1.0)
	else:
		t = maxf(t - delta / CLOSE_TIME, 0.0)
	_apply_t()
	if not _opening and t <= 0.0:
		_finish()

func _apply_t() -> void:
	var tt := timeline_time(t)
	var s := ease_out(tt / CAMERA_TIME)
	if not Settings.camera_motion:
		# A cut: the shot the moment the menu opens, home the moment it has closed.
		s = 1.0 if t > 0.0 else 0.0
	_drive_camera(s)

	_dim_mat.set_shader_parameter(&"amount", ease_out(tt / CAMERA_TIME))
	_panel_mat.set_shader_parameter(&"reveal",
		smoothstep(PANEL_IN.x, PANEL_IN.y, tt))
	var flare := smoothstep(BEAM_IN.x, BEAM_IN.y, tt) * (1.0 - smoothstep(BEAM_OUT.x, BEAM_OUT.y, tt))
	_beam_mat.set_shader_parameter(&"strength", flare)
	if _ring_mat != null:
		var lit := smoothstep(RING_ON, RING_ON + 0.08, tt)
		_ring_mat.albedo_color.a = lit

func _drive_camera(s: float) -> void:
	var from_rel := _start_global.origin - _head_pos
	var to_rel := _target_global.origin - _head_pos
	var from_angle := atan2(from_rel.x, from_rel.z)
	var to_angle := atan2(to_rel.x, to_rel.z)
	var angle := swing_yaw(from_angle, to_angle, s)
	var radius := lerpf(Vector2(from_rel.x, from_rel.z).length(),
		Vector2(to_rel.x, to_rel.z).length(), s)
	var height := lerpf(from_rel.y, to_rel.y, s)
	var pos := _head_pos + Vector3(sin(angle) * radius, height, cos(angle) * radius)
	var turned := _start_global.basis.get_rotation_quaternion().slerp(
		_target_global.basis.get_rotation_quaternion(), s)
	_camera.global_transform = Transform3D(Basis(turned), pos)
	_camera.fov = lerpf(_saved_fov, shot_fov, s)
	_camera.h_offset = lerpf(_saved_h, 0.0, s)
	_camera.v_offset = lerpf(_saved_v, 0.0, s)

# --- the shot ----------------------------------------------------------------

func _facing() -> Vector3:
	var local := Vector3.BACK
	if _body != null and _body.has_method(&"_facing"):
		local = _body.call(&"_facing")
	var world: Vector3 = _body.global_transform.basis * local if _body != null else local
	return Vector3(world.x, 0.0, world.z).normalized()

func _head_transform() -> Transform3D:
	if _skeleton != null and _head_bone >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)
	return Transform3D(Basis(), _body.global_position + Vector3.UP * 1.6)

func _head_position() -> Vector3:
	return _head_transform().origin

func _sweep(from: Vector3, target: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var safe := 1.0
	if space != null and from.distance_to(target) > 0.001:
		var shape := SphereShape3D.new()
		shape.radius = sweep_radius
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), from)
		query.motion = target - from
		if _body is CollisionObject3D:
			query.exclude = [(_body as CollisionObject3D).get_rid()]
			var arm = _body.get(&"spring_arm")
			if arm is SpringArm3D:
				query.collision_mask = (arm as SpringArm3D).collision_mask
		var result := space.cast_motion(query)
		if result.size() >= 1:
			safe = result[0]
	return swept_position(_head_pos, from, target, safe, shot_min_distance)

func _place_panel() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)
	var tan_v := tan(deg_to_rad(shot_fov) * 0.5)
	var view_h := 2.0 * panel_distance * tan_v
	var panel_aspect := float(panel_resolution.x) / float(panel_resolution.y)
	var h := view_h * panel_height_fraction
	var w := h * panel_aspect
	var max_w := view_h * aspect * panel_max_width_fraction
	if w > max_w:
		w = max_w
		h = w / panel_aspect
	_panel_size = Vector2(w, h)
	(_panel.mesh as QuadMesh).size = _panel_size

	var facing := _target_global.basis * Basis(Vector3.UP, -deg_to_rad(panel_turn))
	var half_extent := _panel_size * 0.5
	var ndc_x := 0.97 - w / (view_h * aspect)
	# Fit against the real projection (the turn changes the edges' depth), shrinking and shifting
	# until every corner sits inside the window with `panel_margin` to spare.
	for _i in 12:
		var local := Vector3(ndc_x * panel_distance * tan_v * aspect,
			0.02 * panel_distance * tan_v, -panel_distance)
		var panel_local := Transform3D(_target_global.basis.inverse() * facing, local)
		var max_x := -INF
		var min_x := INF
		var max_y := 0.0
		for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var p: Vector3 = panel_local * Vector3(c.x * half_extent.x, c.y * half_extent.y, 0.0)
			var depth := maxf(-p.z, 0.01)
			var nx := p.x / depth / (tan_v * aspect)
			max_x = maxf(max_x, nx)
			min_x = minf(min_x, nx)
			max_y = maxf(max_y, absf(p.y / depth / tan_v))
		var limit := 1.0 - panel_margin
		if max_x <= limit and max_y <= limit:
			break
		if max_y > limit:
			var k := limit / max_y
			half_extent *= k
			_panel_size *= k
		if max_x > limit:
			ndc_x -= (max_x - limit) * 0.9
	(_panel.mesh as QuadMesh).size = _panel_size
	var final_local := Vector3(ndc_x * panel_distance * tan_v * aspect,
		0.02 * panel_distance * tan_v, -panel_distance)
	_panel.global_transform = Transform3D(facing, _target_global * final_local)

func _emitter_position() -> Vector3:
	return _head_transform() * ring_offset

func _build_beam() -> void:
	var apex := _emitter_position()
	var half := _panel_size * 0.5
	var corners: Array[Vector3] = []
	for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		corners.append(_panel.global_transform * Vector3(c.x * half.x, c.y * half.y, 0.0))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in 4:
		verts.append(apex)
		uvs.append(Vector2(0.5, 0.0))
		verts.append(corners[i])
		uvs.append(Vector2(float(i) / 4.0, 1.0))
		verts.append(corners[(i + 1) % 4])
		uvs.append(Vector2(float(i + 1) / 4.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_beam.mesh = mesh
	_beam.global_transform = Transform3D.IDENTITY

# --- the world dim -----------------------------------------------------------

## Chains a stencil-writing pass onto every pilot mesh (rim overlay's next_pass, or the overlay
## itself when the rim is off) so the dim quad skips him. Off again on close.
func _set_pilot_stencil(on: bool) -> void:
	if _character == null:
		return
	if on:
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(_character, meshes)
		for mi in meshes:
			var overlay := mi.material_overlay
			if overlay == null:
				_stenciled[mi] = null
				mi.material_overlay = _stencil_mat
			elif overlay != _stencil_mat:
				_stenciled[mi] = overlay
				if overlay.next_pass == null:
					overlay.next_pass = _stencil_mat
					_chained.append(overlay)
	else:
		for overlay in _chained:
			if is_instance_valid(overlay) and overlay.next_pass == _stencil_mat:
				overlay.next_pass = null
		_chained.clear()
		for mi in _stenciled:
			if is_instance_valid(mi) and mi.material_overlay == _stencil_mat:
				mi.material_overlay = null
		_stenciled.clear()

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

# --- input -------------------------------------------------------------------

## A mouse event over the main window, turned into the same event at the matching pixel of the
## panel. Dropped unless the panel is live and the cursor is over it (a release is pulled onto the
## edge instead, so a drag that ends off the panel still ends).
func forward_mouse(event: InputEventMouse) -> void:
	if not is_live():
		return
	var release := event is InputEventMouseButton and not (event as InputEventMouseButton).pressed
	var origin := _camera.project_ray_origin(event.position)
	var dir := _camera.project_ray_normal(event.position)
	var uv = ray_to_uv(origin, dir, _panel.global_transform, _panel_size, release)
	if uv == null:
		return
	var pixel: Vector2 = (uv as Vector2) * Vector2(_viewport.size)
	var copy := event.duplicate() as InputEventMouse
	copy.position = pixel
	copy.global_position = pixel
	_viewport.push_input(copy, true)

## Keyboard and gamepad, once the panel is live.
func forward_input(event: InputEvent) -> void:
	if is_live():
		_viewport.push_input(event)
