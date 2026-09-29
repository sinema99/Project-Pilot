class_name Pilot9Afterimage
extends Node3D

## The dash's Sandevistan trail: frozen, flat-coloured copies of pilot9 dropped every
## `afterimage_spacing` metres, held for the dash and cleared tail to head after it. See
## docs/specs/pilot9-dash.md, "The afterimages".
##
## This owns what the ghosts are and how they look and go. pilot9.gd only says when - begin() on
## launch, advance() each physics tick of the dash, end() when he reappears, clear() on boarding -
## the same split as pilot9_vfx.gd. Every knob is read off `pilot` at the moment of use, so they
## tune live in the Inspector.
##
## A ghost is not a baked mesh: it is a Skeleton3D of its own with his pose copied onto it,
## carrying copies of his meshes that share his mesh and skin, so the GPU skins it the way it
## skins him. The bake it replaced cost ~27 ms a ghost. See "Frozen skeletons, not baked meshes".

const FILL_SHADER := preload("res://shaders/cel/vfx/afterimage.gdshader")
const LINE_SHADER := preload("res://shaders/cel/vfx/afterimage_outline.gdshader")
const FILL_DEPTH_SHADER := preload("res://shaders/cel/vfx/afterimage_depth.gdshader")
const LINE_DEPTH_SHADER := preload("res://shaders/cel/vfx/afterimage_outline_depth.gdshader")
const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")

## The pilot whose "Afterimage" exports this reads. Untyped - the pilot has no class_name.
var pilot: Node

## The pool: `afterimage_max_count` ghosts built once and hidden, each holding one copy per mesh
## in `_sources`. A dash shows them in order; a clear hides them again. Nothing is created or
## freed while he dashes.
var _pool: Array[Skeleton3D] = []
## Per pool ghost, its copies - parallel to `_sources`.
var _copies: Array = []
## Every MeshInstance3D under `character` when the pool was built.
var _sources: Array[MeshInstance3D] = []
## His skeleton - the one the skinned sources point at.
var _skeleton: Skeleton3D = null
## The live ghosts, oldest first - always a prefix of `_pool`.
var _ghosts: Array[Skeleton3D] = []
## His final pose (modifiers applied) as local bone transforms, from the last snapshot.
var _pose: Array[Transform3D] = []
## Bumped by every snapshot; the launch ghost waits for one newer than begin()'s.
var _snapshot_serial: int = 0
var _launch_serial: int = 0
## Metres travelled since begin(), along the ticks advance() was handed.
var _travelled: float = 0.0
## Whether the current dash is dropping ghosts at all - false when begin() found MOVEMENT
## EFFECTS off or nothing visible to copy, so advance() is a no-op for the rest of the window.
var _active: bool = false
## Seconds since end(); negative while the dash is still running and nothing is clearing.
var _clear_elapsed: float = -1.0
## Whether the launch ghost is still owed, and where he launched from - see begin().
var _launch_owed: bool = false
var _launch_position: Vector3 = Vector3.ZERO
var _material: ShaderMaterial = null

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = FILL_SHADER
	var line := ShaderMaterial.new()
	line.shader = LINE_SHADER
	_material.next_pass = line
	# The depth passes, at priority -1 so every ghost's depth is down before any ghost's
	# see-through colour: each ghost shows only its front surface, never its limbs or the ghost
	# behind it through itself.
	var fill_depth := ShaderMaterial.new()
	fill_depth.shader = FILL_DEPTH_SHADER
	fill_depth.render_priority = -1
	line.next_pass = fill_depth
	var line_depth := ShaderMaterial.new()
	line_depth.shader = LINE_DEPTH_SHADER
	line_depth.render_priority = -1
	fill_depth.next_pass = line_depth
	# Deferred: the held item is attached later in the pilot's own _ready(). begin() re-checks.
	_build_if_stale.call_deferred()

## A new dash. The launch ghost is OWED, not dropped: pilot9.gd has just hard-cut the tree onto
## the sprint cycle, but his skeleton has not emitted skeleton_updated since, so the snapshot
## still holds whatever he was doing. It is dropped by the first advance() after a newer
## snapshot, placed back where he stood.
func begin(source: Node3D, enabled: bool) -> void:
	clear()
	_travelled = 0.0
	_active = enabled and source != null and source.is_visible_in_tree()
	_launch_owed = _active
	if not _active:
		return
	_build_if_stale()
	_launch_position = source.global_position
	# A fallback pose, so a crossing that beats the first real snapshot still has one.
	_snapshot()
	_launch_serial = _snapshot_serial

## One physics tick of the dash, from `from` to `to` (his global_position either side of
## move_and_slide()). Drops a ghost at every spacing crossing inside the segment, placed at the
## exact crossing rather than at `to`.
func advance(source: Node3D, from: Vector3, to: Vector3) -> void:
	if not _active or source == null:
		return
	if _launch_owed and _snapshot_serial > _launch_serial:
		_launch_owed = false
		_drop(source, _launch_position - source.global_position)
	var step := to - from
	var length := step.length()
	for at in crossings(_travelled, length, pilot.afterimage_spacing):
		if _ghosts.size() >= mini(pilot.afterimage_max_count, _pool.size()):
			break
		# The pose is the last snapshot's; only the position is pulled back along the segment.
		_drop(source, step / length * at - step)
	_travelled += length

## He reappears: the trail starts clearing, oldest first.
func end() -> void:
	_active = false
	_launch_owed = false
	if not _ghosts.is_empty():
		_clear_elapsed = 0.0

## Gone now, no fade - boarding, or a fresh dash over a trail still clearing. The ghosts go back
## to the pool hidden.
func clear() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.visible = false
	_ghosts.clear()
	_clear_elapsed = -1.0

func ghost_count() -> int:
	return _ghosts.size()

func _process(delta: float) -> void:
	if _clear_elapsed < 0.0:
		return
	_clear_elapsed += delta
	var clear_time: float = pilot.afterimage_clear_time
	if _clear_elapsed >= clear_time:
		clear()
		return
	var n := _ghosts.size()
	for i in n:
		_set_param(_ghosts[i], &"ghost_fade",
			fade_at(i, n, _clear_elapsed, clear_time, pilot.afterimage_fade_time))

## -- the pool --------------------------------------------------------------------------------

## Rebuilds the pool if the meshes under `character` changed (a different held item) or
## `afterimage_max_count` was retuned. Only called at load and at a launch, never mid-dash.
func _build_if_stale() -> void:
	if pilot == null or pilot.character == null:
		return
	var meshes: Array[MeshInstance3D] = []
	_ApplyStylized.collect_meshes(pilot.character, meshes)
	if meshes == _sources and _pool.size() == pilot.afterimage_max_count:
		return
	_build(meshes)

func _build(meshes: Array[MeshInstance3D]) -> void:
	clear()
	for g in _pool:
		remove_child(g)
		g.queue_free()
	_pool.clear()
	_copies.clear()
	_sources = meshes
	var skeleton: Skeleton3D = null
	for mi in meshes:
		if mi.skin != null and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
			skeleton = mi.get_node(mi.skeleton)
			break
	if skeleton != _skeleton:
		if _skeleton != null and is_instance_valid(_skeleton) \
				and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
			_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
		_skeleton = skeleton
		if _skeleton != null:
			_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	for g in pilot.afterimage_max_count:
		var ghost := Skeleton3D.new()
		ghost.name = "Afterimage%d" % g
		ghost.top_level = true
		ghost.visible = false
		if _skeleton != null:
			for b in _skeleton.get_bone_count():
				ghost.add_bone(_skeleton.get_bone_name(b))
			for b in _skeleton.get_bone_count():
				ghost.set_bone_parent(b, _skeleton.get_bone_parent(b))
				ghost.set_bone_rest(b, _skeleton.get_bone_rest(b))
		add_child(ghost)
		var copies: Array[MeshInstance3D] = []
		for mi in meshes:
			var copy := MeshInstance3D.new()
			copy.name = mi.name
			copy.material_override = _material
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if _skinned(mi):
				# His mesh and skin, skinned off the ghost's own frozen skeleton (its parent).
				copy.skin = mi.skin
				copy.skeleton = NodePath("..")
			else:
				# No skeleton at all, or the engine would hand it an auto-skin off the rest pose.
				copy.skeleton = NodePath()
			ghost.add_child(copy)
			copies.append(copy)
		_pool.append(ghost)
		_copies.append(copies)

func _skinned(mi: MeshInstance3D) -> bool:
	return _skeleton != null and mi.skin != null and mi.get_node_or_null(mi.skeleton) == _skeleton

## -- the pose --------------------------------------------------------------------------------

## His final pose is only whole here, after the staff-hold and wall-hand modifiers have run.
## Snapshotted only while a dash is live - the rest of the time nobody needs it.
func _on_skeleton_updated() -> void:
	if _active:
		_snapshot()

## Local bone transforms rebuilt from the global poses, so whatever the modifiers wrote comes
## along whichever of the two they left it in.
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
	_snapshot_serial += 1

## Shows the next pool ghost in the snapshot's pose, where he is now, shifted by `offset`.
func _drop(source: Node3D, offset: Vector3) -> void:
	var i := _ghosts.size()
	if i >= _pool.size():
		return
	var ghost := _pool[i]
	if _pose.size() == ghost.get_bone_count():
		for b in _pose.size():
			ghost.set_bone_pose(b, _pose[b])
	var base: Transform3D = _skeleton.global_transform if _skeleton != null \
		else source.global_transform
	ghost.global_transform = base.translated(offset)
	# Each copy sits where its source sits relative to his skeleton; the staff included.
	var to_base := base.affine_inverse()
	var copies: Array = _copies[i]
	for k in _sources.size():
		var mi := _sources[k]
		var copy: MeshInstance3D = copies[k]
		copy.visible = is_instance_valid(mi) and mi.is_visible_in_tree() and mi.mesh != null
		if copy.visible:
			copy.mesh = mi.mesh
			copy.transform = to_base * mi.global_transform
	ghost.visible = true
	# Placed inside a physics tick with interpolation on: without this the ghost would lerp in
	# from wherever it last stood over its first drawn frame.
	ghost.reset_physics_interpolation()
	_ghosts.append(ghost)
	_recolor()

## Newest cyan, then toward green the further back - by rank from the newest, so a dash cut
## short at two ghosts still has the head colour next to him.
func _recolor() -> void:
	var n := _ghosts.size()
	for i in n:
		var c := rank_color(n - 1 - i, pilot.afterimage_max_count,
			pilot.afterimage_head_color, pilot.afterimage_tail_color)
		var line := Color(c.r * pilot.afterimage_line_darken, c.g * pilot.afterimage_line_darken,
			c.b * pilot.afterimage_line_darken, 1.0)
		_set_param(_ghosts[i], &"ghost_color", c)
		_set_param(_ghosts[i], &"ghost_line_color", line)
		_set_param(_ghosts[i], &"ghost_opacity", pilot.afterimage_opacity)
		_set_param(_ghosts[i], &"ghost_fade", 1.0)

static func _set_param(ghost: Node3D, param: StringName, value: Variant) -> void:
	for child in ghost.get_children():
		(child as GeometryInstance3D).set_instance_shader_parameter(param, value)

## -- pure, so tests/test_pilot9_dash.gd can pin them with no tree ----------------------------

## Distances along a segment of `length`, starting `travelled` metres into the dash, at which the
## running total crosses a multiple of `spacing`. The launch ghost (at 0) is begin()'s, not this.
static func crossings(travelled: float, length: float, spacing: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if spacing <= 0.0 or length <= 0.0:
		return out
	var k := floorf(travelled / spacing) + 1.0
	while k * spacing <= travelled + length:
		out.append(k * spacing - travelled)
		k += 1.0
	return out

## Rank 0 is the newest ghost (head colour); rank max_count - 1 is the tail colour.
static func rank_color(rank: int, max_count: int, head: Color, tail: Color) -> Color:
	if max_count <= 1:
		return head
	return head.lerp(tail, clampf(float(rank) / float(max_count - 1), 0.0, 1.0))

## 1.0 solid to 0.0 gone, for ghost `index` (0 = oldest) of `count`, `elapsed` seconds after the
## dash ended. The oldest starts first; the newest finishes exactly at `clear_time`.
static func fade_at(index: int, count: int, elapsed: float, clear_time: float,
		fade_time: float) -> float:
	var fade := minf(maxf(fade_time, 0.001), clear_time)
	var stagger := 0.0
	if count > 1:
		stagger = maxf(clear_time - fade, 0.0) / float(count - 1)
	return 1.0 - clampf((elapsed - float(index) * stagger) / fade, 0.0, 1.0)
