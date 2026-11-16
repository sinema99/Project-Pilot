extends SubViewport

# The inventory's left box: pilot9 in a studio of his own. See docs/specs/inventory.md,
# decision 8.
#
# Its own World3D (nothing from the level gets in), a camera, a key and a rim light, and a POSE
# MIRROR: a Skeleton3D that copies his final pose every frame (modifiers included - coat springs,
# staff hold), carrying copies of every mesh under his `character` that share his mesh, skin and
# materials. The afterimage's technique (scripts/pilot9_afterimage.gd), kept live instead of
# frozen. He is held still while the screen is open, so what it shows is his idle - in whatever
# he is wearing right now.
#
# Rendered at the screen's texel resolution, so it comes out chunky like the rest of it.

const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")

## Turn per screen pixel dragged, radians.
const DRAG_TURN := 0.012
## The default view: a little off his front.
const START_YAW := deg_to_rad(-20.0)
## Share of the box height his body fills.
const FILL := 0.86

var yaw := START_YAW

var _pilot: Node3D
var _skeleton: Skeleton3D
var _character: Node3D
var _turntable: Node3D
var _mirror: Skeleton3D
var _camera: Camera3D
var _sources: Array[MeshInstance3D] = []
var _copies: Array[MeshInstance3D] = []
var _pose: Array[Transform3D] = []
var _framed := false
# Frame by the meshes' bounds instead of the bone span. EXIA's bones sit well inside its armour, so
# its bone span frames a close-up of the torso; the pilot keeps the bone framing he was tuned on.
var _frame_by_mesh := false
# Mesh framing: the body's measured centre, moved onto the turntable's axis so it turns in place.
var _center := Vector3.ZERO


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_DISABLED
	screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(96, 240)


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.68)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_energy = 1.2
	key.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(35.0), 0.0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_energy = 1.4
	rim.light_color = Color(0.6, 0.95, 1.0)
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(200.0), 0.0)
	add_child(rim)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 30.0
	_camera.current = true
	add_child(_camera)
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	add_child(_turntable)


## Builds the mirror for `pilot` (or clears it with null) and starts rendering.
func show_pilot(pilot: Node3D) -> void:
	show_body(pilot)


## The mirror for any body: pilot9 (his `character` is the model) or EXIA (its `model`). See
## docs/specs/mech-stash.md, decision 4 - the mech gets exactly the pilot's treatment, framed by
## its own bone span.
func show_body(body: Node3D) -> void:
	_clear()
	_pilot = body
	yaw = START_YAW
	_framed = false
	_center = Vector3.ZERO
	var root: Variant = null
	if body != null:
		root = body.get("character") if body.get("character") is Node3D else body.get("model")
	if not (root is Node3D):
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_character = root
	_frame_by_mesh = not (body.get("character") is Node3D)
	var meshes: Array[MeshInstance3D] = []
	_ApplyStylized.collect_meshes(_character, meshes)
	for mi in meshes:
		if mi.skin != null and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
			_skeleton = mi.get_node(mi.skeleton)
			break
	_mirror = Skeleton3D.new()
	_mirror.name = "Mirror"
	if _skeleton != null:
		for b in _skeleton.get_bone_count():
			_mirror.add_bone(_skeleton.get_bone_name(b))
		for b in _skeleton.get_bone_count():
			_mirror.set_bone_parent(b, _skeleton.get_bone_parent(b))
			_mirror.set_bone_rest(b, _skeleton.get_bone_rest(b))
		_skeleton.skeleton_updated.connect(_snapshot)
	_turntable.add_child(_mirror)
	for mi in meshes:
		var copy := MeshInstance3D.new()
		copy.name = mi.name
		copy.mesh = mi.mesh
		copy.material_override = mi.material_override
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				copy.set_surface_override_material(s, mi.get_surface_override_material(s))
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _skeleton != null and mi.skin != null and mi.get_node_or_null(mi.skeleton) == _skeleton:
			copy.skin = mi.skin
			copy.skeleton = NodePath("..")
		else:
			copy.skeleton = NodePath()
		_mirror.add_child(copy)
		_sources.append(mi)
		_copies.append(copy)
	_snapshot()
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func hide_pilot() -> void:
	_clear()
	render_target_update_mode = SubViewport.UPDATE_DISABLED


func turn(pixels: float) -> void:
	yaw += pixels * DRAG_TURN


func mirror() -> Skeleton3D:
	return _mirror


func _clear() -> void:
	if _skeleton != null and is_instance_valid(_skeleton) \
			and _skeleton.skeleton_updated.is_connected(_snapshot):
		_skeleton.skeleton_updated.disconnect(_snapshot)
	if _mirror != null and is_instance_valid(_mirror):
		_mirror.queue_free()
	_mirror = null
	_skeleton = null
	_character = null
	_pilot = null
	_sources.clear()
	_copies.clear()
	_pose.clear()


## His final local pose, rebuilt from the global poses so whatever the modifiers wrote comes
## along. Only whole inside skeleton_updated.
func _snapshot() -> void:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return
	var n := _skeleton.get_bone_count()
	var globals: Array[Transform3D] = []
	globals.resize(n)
	for b in n:
		globals[b] = _skeleton.get_bone_global_pose(b)
	_pose.resize(n)
	for b in n:
		var parent := _skeleton.get_bone_parent(b)
		_pose[b] = globals[b] if parent < 0 else globals[parent].affine_inverse() * globals[b]


func _process(_delta: float) -> void:
	if _mirror == null or _character == null or not is_instance_valid(_character):
		return
	if _skeleton != null and is_instance_valid(_skeleton):
		if _pose.size() == _mirror.get_bone_count():
			for b in _pose.size():
				_mirror.set_bone_pose(b, _pose[b])
		# The skeleton where it sits on his model, his model facing +Z.
		_mirror.transform = Transform3D(Basis(), -_center) 			* _character.global_transform.affine_inverse() * _skeleton.global_transform
	_turntable.rotation = Vector3(0.0, yaw, 0.0)
	# Unskinned pieces (hat, staff) sit where they sit relative to his skeleton.
	var base: Transform3D = _skeleton.global_transform if _skeleton != null \
		else _character.global_transform
	var to_base := base.affine_inverse()
	for k in _sources.size():
		var mi := _sources[k]
		var copy := _copies[k]
		copy.visible = is_instance_valid(mi) and mi.is_visible_in_tree() and mi.mesh != null
		if copy.visible:
			copy.mesh = mi.mesh
			if copy.skeleton.is_empty():
				copy.transform = to_base * mi.global_transform
	if not _framed:
		_frame()


## Points the camera at his bones' height span, once, so any body or scale fills the box.
func _frame() -> void:
	if _frame_by_mesh:
		_frame_meshes()
		return
	if _mirror.get_bone_count() == 0:
		_camera.position = Vector3(0.0, 1.0, 4.0)
		_framed = true
		return
	var lo := INF
	var hi := -INF
	for b in _mirror.get_bone_count():
		var y := (_mirror.transform * _mirror.get_bone_global_pose(b).origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	# Bones stop short of the crown and the soles.
	var height := (hi - lo) * 1.12
	var mid := (hi + lo) * 0.5
	var dist := height / FILL * 0.5 / tan(deg_to_rad(_camera.fov) * 0.5)
	_camera.position = Vector3(0.0, mid, dist)
	_camera.look_at(Vector3(0.0, mid, 0.0))
	_framed = true


# The union of every visible copy's POSED vertices in turntable space, framed with the same FILL.
# A skinned mesh's get_aabb() is its bind-space box, nowhere near where the pose puts it, so the
# skinned copies are skinned here by hand (each vertex by its heaviest bone - EXIA's armour is
# rigid). Once per open; the low-poly mech is a few thousand vertices.
func _frame_meshes() -> void:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for copy in _copies:
		if not copy.visible or copy.mesh == null:
			continue
		for pt in _posed_points(copy):
			lo = lo.min(pt)
			hi = hi.max(pt)
	if lo == Vector3.INF:
		_camera.position = Vector3(0.0, 1.0, 4.0)
		_framed = true
		return
	var size_box := hi - lo
	# Onto the axis (x, z). The points were measured before this offset, so y stays as measured.
	_center = Vector3((hi.x + lo.x) * 0.5, 0.0, (hi.z + lo.z) * 0.5)
	_mirror.transform = Transform3D(Basis(), -_center) * _mirror.transform
	var mid := (hi.y + lo.y) * 0.5
	var aspect := float(size.x) / maxf(float(size.y), 1.0)
	var depth := maxf(size_box.x, size_box.z)
	# Tall enough for the height, wide enough for the widest side as it turns.
	var span := maxf(size_box.y, depth / maxf(aspect, 0.01))
	var dist := span / FILL * 0.5 / tan(deg_to_rad(_camera.fov) * 0.5) + depth * 0.5
	_camera.position = Vector3(0.0, mid, dist)
	_camera.look_at(Vector3(0.0, mid, 0.0))
	_framed = true


# A copy's vertices where they are drawn, in the turntable's frame (before its yaw).
func _posed_points(copy: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var skinned := not copy.skeleton.is_empty() and copy.skin != null
	var skin := copy.skin
	for surf in copy.mesh.get_surface_count():
		var arrays := copy.mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if not skinned:
			var xf := _mirror.transform * copy.transform
			for v in verts:
				out.append(xf * v)
			continue
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		@warning_ignore("integer_division")
		var per := (bones as Array).size() / verts.size() if bones is Array else int(bones.size() / verts.size())
		if per <= 0:
			continue
		var cache := {}
		for i in verts.size():
			var best := 0
			for k in per:
				if weights[i * per + k] > weights[i * per + best]:
					best = k
			var bind: int = bones[i * per + best]
			if not cache.has(bind):
				var bone := skin.get_bind_bone(bind) if bind < skin.get_bind_count() else -1
				if bone < 0 and bind < skin.get_bind_count():
					bone = _mirror.find_bone(skin.get_bind_name(bind))
				if bone < 0:
					cache[bind] = null
				else:
					cache[bind] = _mirror.transform * _mirror.get_bone_global_pose(bone) * skin.get_bind_pose(bind)
			var m = cache[bind]
			if m != null:
				out.append((m as Transform3D) * verts[i])
	return out
