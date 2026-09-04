extends Node

# Drives the screens built into Setsuna's suit. See docs/specs/setsuna-screens.md.
#
# The black `Highlights` geometry marks where a screen goes; it is not the
# screen. Each region has a QuadMesh floating 2mm proud of it running
# shaders/screen.gdshader, hung off a BoneAttachment3D. This node is the only
# thing that knows those quads exist - player.gd owns the state and never learns
# that materials are involved.
#
# Read every frame rather than driven by signals: dash cooldown is continuous, so
# a uniform gets written each frame regardless, and four set_shader_parameter
# calls are free. _process rather than _physics_process because this is purely
# presentation, so it should run at display rate against whatever state physics
# last committed.

# The band table. Setsuna's controller never accelerates - it assigns
# velocity.x/z directly - so horizontal speed is only ever 0, CROUCH_SPEED,
# SPEED, SPRINT_SPEED (shared with SLIDE_SPEED) or DASH_SPEED. That makes a
# speed-driven colour and a state-driven colour identical in output, and the
# speed-driven one cannot fall out of sync when a movement state is added.
const BAND_IDLE := Color(0.15, 0.42, 0.95)    # standing still
const BAND_CROUCH := Color(0.16, 0.80, 0.35)  # crouch-walk
const BAND_RUN := Color(0.96, 0.80, 0.16)     # run
const BAND_SPRINT := Color(0.95, 0.20, 0.15)  # sprint, slide, dash

# Midpoints between the exact speeds above, so each real value lands
# unambiguously inside its band rather than on an edge.
const BAND_CROUCH_MIN := 1.5
const BAND_RUN_MIN := 4.5
const BAND_SPRINT_MIN := 7.5

const HEALTH_COLOR := Color(0.90, 0.15, 0.15)
const STAMINA_COLOR := Color(0.20, 0.85, 0.30)
const DASH_COLOR := Color(1.00, 0.50, 0.10)

@export var player: NodePath
@export var health_screen: NodePath
@export var stamina_screen: NodePath
@export var dash_screen: NodePath
## Both thighs always show the same thing, so they share one material instance
## and one write per frame.
@export var thigh_screens: Array[NodePath] = []

var _player: Node
var _health_mat: ShaderMaterial
var _stamina_mat: ShaderMaterial
var _dash_mat: ShaderMaterial
var _thigh_mats: Array[ShaderMaterial] = []

# --- the rule set ---------------------------------------------------------
# Pure, per the pattern ui_manager.gd sets out: no nodes, no tree, no side
# effects, so tests/test_setsuna_screens.gd can assert the whole table without
# standing up a scene.

## Thigh screen colour for a horizontal speed in m/s.
static func speed_band(speed: float) -> Color:
	if speed < BAND_CROUCH_MIN:
		return BAND_IDLE
	if speed < BAND_RUN_MIN:
		return BAND_CROUCH
	if speed < BAND_SPRINT_MIN:
		return BAND_RUN
	return BAND_SPRINT

## The dash screen is a ready light, not a gauge: lit when the dash is
## available, dim for the whole lockout. It deliberately shows no progress.
static func dash_fill(cooldown_left: float) -> float:
	return 1.0 if cooldown_left <= 0.0 else 0.0

## Gauge fill for a 0..1 meter, clamped so a stub value out of range cannot
## drive the bar past the end of the panel.
static func meter_fill(value: float) -> float:
	return clampf(value, 0.0, 1.0)

# --- wiring ---------------------------------------------------------------

func _ready() -> void:
	_player = get_node_or_null(player)
	if _player == null:
		push_warning("setsuna_screens: player '%s' not found; screens will not update." % player)
		set_process(false)
		return

	_health_mat = _material_for(health_screen, HEALTH_COLOR)
	_stamina_mat = _material_for(stamina_screen, STAMINA_COLOR)
	_dash_mat = _material_for(dash_screen, DASH_COLOR)
	# One material across both thighs: they are never told different things, and
	# sharing it means the per-frame write stays a single call.
	var shared: ShaderMaterial = null
	for path in thigh_screens:
		var mat := _material_for(path, BAND_IDLE, shared)
		if mat != null and shared == null:
			shared = mat
		if mat != null and not _thigh_mats.has(mat):
			_thigh_mats.append(mat)

# Resolves a screen path to its ShaderMaterial and stamps its resting colour.
# Passing `reuse` shares one material across several quads.
func _material_for(path: NodePath, colour: Color, reuse: ShaderMaterial = null) -> ShaderMaterial:
	var mi := get_node_or_null(path) as MeshInstance3D
	if mi == null:
		push_warning("setsuna_screens: screen '%s' not found." % path)
		return null
	if reuse != null:
		mi.set_surface_override_material(0, reuse)
		return reuse
	var mat := mi.get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		mat = mi.mesh.surface_get_material(0) as ShaderMaterial
	if mat == null:
		push_warning("setsuna_screens: screen '%s' has no ShaderMaterial." % path)
		return null
	mat.set_shader_parameter("fill_color", colour)
	return mat

func _process(_delta: float) -> void:
	if _health_mat != null:
		_health_mat.set_shader_parameter("fill", meter_fill(_player.health))
	if _stamina_mat != null:
		_stamina_mat.set_shader_parameter("fill", meter_fill(_player.stamina))
	if _dash_mat != null:
		_dash_mat.set_shader_parameter("fill", dash_fill(_player.dash_cooldown_left))
	if not _thigh_mats.is_empty():
		var v: Vector3 = _player.velocity
		var colour := speed_band(Vector2(v.x, v.z).length())
		for mat in _thigh_mats:
			# Solid state light: fill stays at 1.0, only the colour moves.
			mat.set_shader_parameter("fill_color", colour)
