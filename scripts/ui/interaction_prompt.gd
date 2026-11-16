class_name InteractionPrompt
extends Node3D

# The one interaction prompt in the scene: a PS1 panel floating beside whoever the camera is
# following. See docs/specs/interaction-panel.md (the look and the placement) and
# docs/specs/button-door.md (the bidding).
#
# Shared rather than one per source, because two prompts drawn beside the same pilot overlap -
# a door with a switch on each side, or a door next to a parked EXIA. Every source BIDS with a
# distance each physics frame it is in range, this commits the closest one, and
# `current_source` is the answer to "am I the one being offered" that a source checks before
# acting on a keypress. Buttons, doors and EXIA all bid here; nothing draws its own prompt.
#
# Found by group, and INSTANTIATED BY THE FIRST SOURCE THAT LOOKS FOR ONE - see acquire(). That
# is what lets a door be pasted into a scene that has never heard of this file. It is added
# WITHOUT an `owner`, exactly like the blockout boxes' generated geometry, so nothing reaches
# the .tscn and nothing can accumulate.
#
# Where it goes: the active camera's nearest ancestor with interaction_anchor() says where the
# body is (pilot9: shoulder height, his shoulder side; EXIA: its chest, right). The panel sits
# `offset` metres along the camera's flattened right vector times `side`, yawed `yaw_deg` in
# toward the body, upright, eased after its spot over `follow_time`, and scaled every frame to a
# constant on-screen size. A camera with no such ancestor gets a spot ahead and to the right.

const FACE_SCRIPT := preload("res://scripts/ui/interaction_panel_face.gd")
const PANEL_SHADER := preload("res://shaders/ui/interaction_panel.gdshader")

## Set on the root node in the .tscn as well - both halves have to agree or acquire() builds a
## second prompt every time it is called.
const GROUP := &"interaction_prompt"

const SCENE_PATH := "res://scenes/ui/interaction_prompt.tscn"

## Shown when an action has no key bound at all, which is a misconfigured InputMap rather than
## a state the game can be in.
const NO_KEY := "?"

## The method an anchor provides. Returns {point: Vector3, side: float (+1 camera-right,
## -1 left), offset: float (metres sideways)}.
const ANCHOR_METHOD := &"interaction_anchor"

## The screen-height reference for texel_px.
const REFERENCE_HEIGHT := 1080.0

## On-screen size of one panel texel, in pixels of a 1080-line screen. 3 keeps the panel about
## the height of the old bottom-centre row (16 texels = 48 px).
@export var texel_px := 3.0
## Degrees the panel is turned in toward the body, so its near edge is closer to the camera.
@export var yaw_deg := 20.0
## Seconds the panel takes to catch up to its spot (and to slide across on a shoulder swap).
@export var follow_time := 0.1
## How much of the camera's pitch the panel tilts with (0 = upright, 1 = fully with the camera).
## Eased by follow_time, like the sideways catch-up.
@export_range(0.0, 1.0) var tilt_follow := 1.0
@export var unfold_time := 0.1
@export var fold_time := 0.08
## The flattest the panel gets mid-fold, as a share of its height - a line, not nothing.
@export var fold_floor := 0.08
## Where the panel goes when the camera has no anchor: metres ahead, sideways and down.
@export var fallback_ahead := 2.5
@export var fallback_side := 0.6
@export var fallback_drop := 0.3


## The source the prompt is currently offering, or null. Read by a source before it acts on a
## press: exactly one responds however many are in range.
var current_source: Node = null

# This frame's best bid, cleared on every commit. Sources bid in _physics_process at the
# default priority and this commits at 100, so every bid is in before it is read.
var _best_source: Node = null
var _best_distance := 0.0
var _best_action: StringName = &""
var _best_text := ""
var _best_options := PackedStringArray()
var _best_progress := -1.0

# What the panel shows. Kept through the fold so the word does not blank as it closes.
var _shown := false
var _key := ""
var _word := ""
# The option list being shown (empty = a single word) and its highlighted row, and the progress
# bar (< 0 = none). See docs/specs/mech-stash.md, decisions 5 and 8.
var _options := PackedStringArray()
var _progress := -1.0
## The highlighted row of a multi-option offer. Reset to 0 whenever the panel stops offering it.
var selected_index := 0
# 0 = folded away, 1 = open.
var _open := 0.0

# The panel's eased spot and its eased side (yaw follows it), and the anchor they were eased
# for. A new anchor (pilot <-> EXIA) snaps rather than flying across the scene.
var _pos := Vector3.ZERO
var _side := 1.0
var _tilt := 0.0
var _anchor_node: Node = null
var _placed := false

var _viewport: SubViewport
var _face: Control
var _mesh: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	# Higher runs later. The bids come in at the default 0, so this has to be above it or the
	# prompt commits a frame-old winner and lags a metre behind the player.
	process_physics_priority = 100
	# After every camera rig has placed its camera for the frame.
	process_priority = 1000
	# Runs while paused only to hide: a panel drawn over everything would sit on top of the
	# hologram pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The AIRFRAME look leaves this alone (it only takes cel / grid / standard materials anyway).
	set_meta(&"airframe_skip", true)
	_build()
	set_physics_process(true)
	set_process(true)


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Face"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.size = Vector2i(64, FACE_SCRIPT.HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_face = FACE_SCRIPT.new()
	_face.name = "Draw"
	_face.size = Vector2(_viewport.size)
	_viewport.add_child(_face)
	add_child(_viewport)

	_material = ShaderMaterial.new()
	_material.shader = PANEL_SHADER
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	_material.set_shader_parameter(&"face", _viewport.get_texture())

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mesh = MeshInstance3D.new()
	_mesh.name = "Panel"
	_mesh.mesh = quad
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Placed in world space every frame; the prompt's own transform is irrelevant.
	_mesh.top_level = true
	_mesh.visible = false
	add_child(_mesh)


## The prompt for `context`'s scene, building one if there is none. Returns null only when
## there is no tree to build into, which is a headless caller outside the scene tree.
##
## Static, and reached through a preload rather than by class name - see button-door.md on why
## nothing in this project references a global class across files.
static func acquire(context: Node) -> Node:
	var tree := context.get_tree() if context != null else null
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found != null:
		return found
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_warning("InteractionPrompt: %s is missing - no prompt will be drawn." % SCENE_PATH)
		return null
	var made := packed.instantiate()
	# The current scene rather than the viewport root, so reloading the scene takes the prompt
	# with it. No owner is set: this is generated, and generated things stay out of the .tscn.
	var host: Node = tree.current_scene
	if host == null:
		host = tree.root
	host.add_child(made)
	return made


## A source's bid to be the one shown, `distance` metres from the player. Closest wins.
## `progress` >= 0 draws a fill bar under the word (0..1). `options` (two or more) turns the panel
## into a list the wheel scrolls; `text` is then ignored and the source reads selected_option()
## when its key is pressed.
func offer(source: Node, distance: float, action: StringName, text: String,
		progress: float = -1.0, options: PackedStringArray = PackedStringArray()) -> void:
	if _best_source != null and distance >= _best_distance:
		return
	_best_source = source
	_best_distance = distance
	_best_action = action
	_best_text = text
	_best_progress = progress
	_best_options = options if options.size() > 1 else PackedStringArray()


## The highlighted option of a list offer, or the word of a plain one.
func selected_option() -> String:
	if _options.size() > 1:
		return _options[clampi(selected_index, 0, _options.size() - 1)]
	return _word


## True while a list offer is up and visible - the only time the wheel is the panel's.
func is_offering_list() -> bool:
	if not _shown or _options.size() <= 1 or get_tree() == null or get_tree().paused:
		return false
	var ui := get_node_or_null(^"/root/UI")
	return ui == null or not ui.hides_world_prompts()


## Moves the highlight `step` rows (+1 down), clamped at the ends. Snaps: a content swap, no tween.
func scroll_selection(step: int) -> void:
	if _options.size() <= 1:
		return
	var next := clampi(selected_index + step, 0, _options.size() - 1)
	if next != selected_index:
		selected_index = next
		_refresh_face()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not is_offering_list():
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_selection(1)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_selection(-1)
		get_viewport().set_input_as_handled()


## Drops the offer this instant rather than waiting for the next commit - what a button calls
## as it goes spent. The panel folds away rather than cutting, so the press reads as taken.
func clear_now() -> void:
	_best_source = null
	current_source = null
	_shown = false


## True while a source is being offered (the panel is open or opening).
func is_showing() -> bool:
	return _shown


## The word the panel shows (or last showed, while it folds). For a list, the highlighted one.
func shown_text() -> String:
	return selected_option()


## The list being shown (empty for a single word).
func shown_options() -> PackedStringArray:
	return _options


## The bar's fill, < 0 when there is none.
func shown_progress() -> float:
	return _progress


func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	commit()


## Takes this frame's winner and resets the bidding. Separated from _physics_process so a test
## can step it without a physics server.
func commit() -> void:
	var previous := current_source
	current_source = _best_source
	_best_source = null
	if current_source == null:
		_shown = false
		selected_index = 0
		return
	var key := key_label_for(_best_action)
	if not _shown or current_source != previous or _best_options != _options:
		# A different offer (or the panel reopening) starts back on the first option.
		selected_index = 0
	if not _shown:
		# Opening: start from the spot, not from wherever it was last seen.
		_placed = false
	_shown = true
	# A new word while open swaps on the spot - no replayed unfold.
	if key != _key or _best_text != _word or _best_options != _options 			or not is_equal_approx(_best_progress, _progress):
		_set_content(key, _best_text, _best_options, _best_progress)


func _set_content(key: String, word: String, options: PackedStringArray = PackedStringArray(),
		progress: float = -1.0) -> void:
	_key = key
	_word = word
	_options = options
	_progress = progress
	_refresh_face()


func _refresh_face() -> void:
	if _viewport == null:
		return
	var list := _options if _options.size() > 1 else PackedStringArray([_word])
	_viewport.size = FACE_SCRIPT.size_for(list, _progress >= 0.0)
	_face.size = Vector2(_viewport.size)
	_face.set_list(_key, list, selected_index, _progress)
	_material.set_shader_parameter(&"face_texels", Vector2(_viewport.size))


func _process(delta: float) -> void:
	if _mesh == null:
		return
	# Paused, or a screen (the inventory) is open over a running world.
	var ui := get_node_or_null(^"/root/UI")
	if get_tree().paused or (ui != null and ui.hides_world_prompts()):
		_mesh.visible = false
		return
	var rate := delta / maxf(unfold_time if _shown else fold_time, 0.001)
	_open = clampf(_open + (rate if _shown else -rate), 0.0, 1.0)
	if _open <= 0.0:
		_mesh.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_mesh.visible = false
		return
	_place(cam, delta)
	_mesh.visible = true


func _place(cam: Camera3D, delta: float) -> void:
	var cam_pos := cam.global_position
	var right := cam.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT

	var anchor_node := _anchor_for(cam)
	var point: Vector3
	var side := 1.0
	var offset := fallback_side
	if anchor_node != null:
		var a: Dictionary = anchor_node.call(ANCHOR_METHOD)
		point = a.get("point", anchor_node.global_position)
		side = signf(a.get("side", 1.0))
		if side == 0.0:
			side = 1.0
		offset = a.get("offset", fallback_side)
	else:
		var fwd := -cam.global_basis.z
		point = cam_pos + fwd * fallback_ahead + Vector3.DOWN * fallback_drop
	var target := point + right * side * offset
	var tilt_target := asin(clampf((-cam.global_basis.z).y, -1.0, 1.0)) * tilt_follow

	if not _placed or anchor_node != _anchor_node:
		_pos = target
		_side = side
		_tilt = tilt_target
		_anchor_node = anchor_node
		_placed = true
	else:
		var k := 1.0 - exp(-delta * 4.0 / maxf(follow_time, 0.001))
		_pos = _pos.lerp(target, k)
		_side = lerpf(_side, side, k)
		_tilt = lerpf(_tilt, tilt_target, k)

	# Upright, facing the camera, then turned in toward the body: on the right of him the near
	# (left) edge comes toward the camera.
	var to_cam := cam_pos - _pos
	to_cam.y = 0.0
	if to_cam.length_squared() < 1e-6:
		to_cam = cam.global_basis.z
		to_cam.y = 0.0
	var face := Basis.looking_at(-to_cam.normalized(), Vector3.UP)
	face = Basis(Vector3.UP, deg_to_rad(yaw_deg) * _side) * face
	# Tilt with the camera's pitch about the panel's own horizontal axis: looking down tips the
	# face up toward the camera.
	face = face * Basis(Vector3.RIGHT, _tilt)

	# Constant on-screen size: world height of one texel at this depth.
	var depth := maxf((_pos - cam_pos).dot(-cam.global_basis.z), cam.near)
	var texel_world := (texel_px / REFERENCE_HEIGHT) * 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5)
	var texels := Vector2(_viewport.size)
	var fold := lerpf(fold_floor, 1.0, _ease(_open))
	_mesh.global_transform = Transform3D(
		face.scaled_local(Vector3(texels.x * texel_world, texels.y * texel_world * fold, 1.0)),
		_pos)


# The active camera's nearest ancestor that says where its body is, or null.
func _anchor_for(cam: Node) -> Node:
	var n: Node = cam
	while n != null:
		if n.has_method(ANCHOR_METHOD):
			return n
		n = n.get_parent()
	return null


static func _ease(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


## The keycap's text for an action, read off the InputMap rather than hardcoded, so rebinding
## `interact` cannot leave the cap lying. First key event wins; pad events have no cap.
static func key_label_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return NO_KEY
	for ev in InputMap.action_get_events(action):
		var key := ev as InputEventKey
		if key == null:
			continue
		# Physical first: that is how `interact` is bound, and it is the one that survives a
		# non-QWERTY layout.
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code != KEY_NONE:
			return OS.get_keycode_string(code)
	return NO_KEY
