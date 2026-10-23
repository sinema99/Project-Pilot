class_name FlyoverShot
extends Node3D

# Cutscene shot 4: the ship flying about 1500 ft up over the dead city in the storm, under the
# cloud deck it just broke out of, seen from a chase camera tight behind its main engine. A gutted
# skeleton high-rise crawls left and down below, lightning rims it once; near the end the ship
# starts to bank left and the shot cuts mid-bank. See docs/specs/cutscene-flyover.md.
#
# Everything is a function of the shot time (flight line, float, bank, camera sway, trails), so
# seeking shows the same frame. Plays once on load and holds the last frame. R restarts, Esc quits.

## Emitted when the shot reaches its last frame. Later shots chain off this.
signal finished

const SHOT := &"shot"
const SHIMMER_SHADER := preload("res://shaders/cutscene/heat_shimmer.gdshader")
const MIST_SHADER := preload("res://shaders/cutscene/ground_mist.gdshader")
const HALO_SHADER := preload("res://shaders/cutscene/nozzle_halo.gdshader")
const DOT_SHADER := preload("res://shaders/cutscene/dot_sparks.gdshader")
## The mist pass is kept this far ahead of the camera, so within priority 0 it sorts after the
## crease ink (sorted at the city's far-off centre) and covers it.
const MIST_SORT_DEPTH := 100.0
const SHIMMER_SIDES := 20
const SHIMMER_RINGS := 10

@export var autoplay := true

@export_group("Flight")
## Where the flight line is at 0 s (world), and its heading: degrees the nose is turned from
## world +Z toward +X.
@export var flight_start := Vector3(-300.0, 450.0, -250.0)
@export var heading_degrees := 0.0
## m/s along the flight line.
@export var speed := 70.0

@export_group("Camera")
## Chase camera in the flight line's frame (+Z = nose, +X = the ship's LEFT, +Y = up): where it
## sits and the point it looks at.
@export var camera_offset := Vector3(-1.5, 6.5, -11.5)
@export var camera_look := Vector3(14.3, -12.0, 9.0)
## Vertical field of view, degrees.
@export var fov := 50.0
## Slow wander: peak degrees (pitch / yaw; roll gets half) and metres, and its base rate.
@export var sway_degrees := 0.4
@export var sway_metres := 0.05
@export var sway_hz := 0.4
## Fast buzz on top: peak degrees and base rate.
@export var buzz_degrees := 0.03
@export var buzz_hz := 13.0

@export_group("Float")
@export var bob_metres := 0.15
@export var bob_hz := 0.5
@export var roll_degrees := 1.5
@export var roll_hz := 0.35
@export var pitch_degrees := 0.7
@export var pitch_hz := 0.6
@export var yaw_degrees := 0.4
@export var yaw_hz := 0.23

@export_group("Bank")
## Shot time the bank starts. It eases in and is still speeding up at the cut.
@export var bank_start := 2.1
## Where it has got to at the cut: roll (left wing down), nose turn left, slide left.
@export var bank_roll_degrees := 20.0
@export var bank_yaw_degrees := 4.0
@export var bank_slide := 0.6

@export_group("Engines")
## Glow disc size (m across) for the main engine and the pods.
@export var main_glow_size := 1.7
@export var pod_glow_size := 1.1
## Bloom halo on the main engine (docs/specs/cutscene-flyover.md, "Nozzle propulsion"): size
## (m across), centre brightness (HDR) and flicker (fraction of size + brightness). The dot
## sparks' own knobs are on the DotSparks node (FlyoverDotSparks).
@export var halo_size := 5.0
@export var halo_energy := 1.2
@export_range(0.0, 0.5, 0.01) var halo_flicker := 0.08
## Heat shimmer cone behind each nozzle (docs/specs/cutscene-flyover.md, "Speed lines + engine
## heat"): length (m) behind the main engine and the pods, how much wider than the nozzle it ends,
## and its peak nudge as a fraction of the screen (the pods get `pod_shimmer` of it). Off since
## 2026-10-14 (user call); `shimmer_on` brings it back as tuned.
@export var shimmer_on := false
@export var main_shimmer_length := 6.0
@export var pod_shimmer_length := 3.0
@export var shimmer_flare := 3.0
@export var shimmer_strength := 0.025
@export_range(0.0, 1.0, 0.05) var pod_shimmer := 0.5

@export_group("Ground")
## The ground is painted, not built: the sky draws a flat snow plane at `ground_y` below the horizon
## (shaders/cutscene/flyover_sky.gdshader), with the city's buried streets on the hero's grid.
## `ground_color` is the snow before fog; `mottle` lightens/darkens soft patches about
## `mottle_size` metres across. Streets (block size and width are the city's, FlyoverCity): how
## much darker, and the radius they die out by (the packed city's).
@export var ground_y := 0.0
@export var ground_color := Color(0.3, 0.31, 0.37)
@export_range(0.0, 0.3, 0.005) var mottle := 0.04
@export var mottle_size := 120.0
@export_range(0.0, 1.0, 0.01) var street_dark := 0.12
@export var street_radius := 1500.0

@export_group("Lightning")
## The main strike: a double flicker starting at `flash_time`, the second hit `flash_gap` later at
## `flash_second` of the first, each dying with time constant `flash_decay`. Then a faint far
## flicker at `far_flash_time`, `far_flash` strong.
@export var flash_time := 1.2
@export var flash_gap := 0.12
@export_range(0.0, 1.0, 0.05) var flash_second := 0.8
@export var flash_decay := 0.09
@export var far_flash_time := 2.6
@export_range(0.0, 1.0, 0.05) var far_flash := 0.25
## FlashLight energy at a full flash, and how far the fog lifts toward `flash_color`.
## Which way the flash light travels (world): from the far side of the hero toward the camera, so
## it catches the edges of the slabs.
@export var flash_direction := Vector3(-0.45, -0.45, -0.77)
@export var flash_light_energy := 1.2
@export_range(0.0, 1.0, 0.05) var flash_fog := 0.12
@export var flash_color := Color(0.55, 0.9, 1.0)

@export_group("Composite")
## The key light (docs/specs/shots-composite.md row 6): a break in the cloud deck far ahead, by its
## heading (degrees from the camera's level look direction, toward screen left) and elevation
## (degrees; the camera looks down, so it sits just above the frame and bleeds in from the top).
@export var light_heading_degrees := 0.0
@export var light_elevation_degrees := -8.0
## Height (m) the shafts fall from, and how much further along the light's heading their tops sit
## than their feet, so they lean back toward the break.
@export var shaft_top_height := 800.0
@export var shaft_lean := 500.0

@export_group("Hull rim")
## The ship's cool-teal fresnel rim (alpha = strength), and its strength at a full flash.
@export var rim_color := Color(0.42, 0.66, 0.7, 0.3)
@export_range(0.0, 1.0, 0.05) var rim_flash_strength := 0.6

@export_group("Ground mist")
## A low layer on the snow hiding where the ruins meet the ground (shaders/cutscene/
## ground_mist.gdshader): `mist_density` at the snow, gone by `mist_height` m (its top wobbling
## `mist_top_wobble` m), in patches `mist_patch_size` m across that thin it by `mist_breakup`,
## drifting `mist_drift` m/s (world xz, downwind).
@export var mist_on := true
@export var mist_height := 25.0
@export_range(0.0, 1.0, 0.05) var mist_density := 0.6
@export var mist_color := Color(0.5, 0.54, 0.6)
@export var mist_patch_size := 180.0
@export_range(0.0, 1.0, 0.05) var mist_breakup := 0.5
@export var mist_top_wobble := 15.0
@export var mist_drift := Vector2(0.0, -6.0)

## Shaft cards from the break (docs/specs/shots-composite.md row 6): [heading offset (degrees from
## light_heading_degrees, toward screen left), foot distance from the flight start (m), top width (m), foot width (m),
## strength, phase].
const SHAFTS := [
	[-10.0, 1300.0, 60.0, 150.0, 0.7, 0.0],
	[-1.0, 1600.0, 100.0, 220.0, 1.0, 1.7],
	[7.0, 1350.0, 50.0, 120.0, 0.6, 3.1],
	[15.0, 1750.0, 90.0, 200.0, 0.8, 4.4],
]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var ship: Node3D = $Ship
@onready var trail: IntroSpaceTrail = $EngineTrails
@onready var storm: Storm = $Storm
@onready var embers: FlyoverEmbers = $EngineEmbers
@onready var city: FlyoverCity = $City
@onready var flash_light: DirectionalLight3D = $FlashLight
@onready var shafts: DescentShafts = $Shafts
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var _done := false
var _shimmers: Array[ShaderMaterial] = []
var _sky: ShaderMaterial
## The ship's cel materials (the applier's per-slot copies), for the rim.
var _hull: Array[ShaderMaterial] = []
var _mist: MeshInstance3D
var _mist_material: ShaderMaterial
var _halo_material: ShaderMaterial
## Dot sparks around the engines, built in _ready.
var dots: FlyoverDotSparks


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.fov = fov
	_place_glows()
	_build_shimmer()
	embers.nozzles = trail.nozzles
	embers.air = Vector3(storm.wind_direction.x, 0.0, storm.wind_direction.y).normalized() * storm.wind_speed
	_build_dots()
	_build_ground()
	_collect_hull()
	_build_mist()
	flash_light.basis = Basis.looking_at(flash_direction)
	shafts.build_cards(shaft_cards(), camera_at(shot_length() * 0.5).origin)
	animation_player.animation_finished.connect(_on_animation_finished)
	if autoplay:
		restart()
	else:
		apply(0.0)


## Plays the shot from its first frame.
func restart() -> void:
	_done = false
	animation_player.stop()
	animation_player.play(SHOT)
	animation_player.seek(0.0, true)


func shot_length() -> float:
	return animation_player.get_animation(SHOT).length


func _process(_delta: float) -> void:
	var t := shot_length() if _done else animation_player.current_animation_position
	apply(t)


## Shows shot time `t`: ship, camera, trails, embers, dot sparks, halo flicker, shimmer.
func apply(t: float) -> void:
	ship.global_transform = ship_at(t)
	camera.global_transform = camera_at(t)
	if _mist != null:
		_mist.global_position = camera.global_position - camera.global_basis.z * MIST_SORT_DEPTH
		_mist_material.set_shader_parameter(&"shot_time", t)
	var f := flash_at(t)
	_apply_flash(f)
	_apply_composite(t, f)
	# From a full trail life before the shot: it opens with the trails already streaming.
	trail.update_trail(t, t - trail.life, ship_at, func(_tau: float) -> float: return 0.0,
			camera.global_position)
	embers.update_embers(t, ship_at, camera.global_position, flight_at(t).basis.z * speed)
	dots.update_dots(t, ship.global_transform, camera.global_basis)
	_halo_material.set_shader_parameter(&"shot_time", t)
	for m in _shimmers:
		m.set_shader_parameter(&"shot_time", t)


## Level (horizontal) world direction `offset_degrees` from the camera's first-frame look, toward
## screen left.
func level_direction(offset_degrees: float) -> Vector3:
	var fwd := -camera_at(0.0).basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	return fwd.rotated(Vector3.UP, deg_to_rad(offset_degrees))


## The light's direction (world).
func light_direction() -> Vector3:
	var e := deg_to_rad(light_elevation_degrees)
	return (level_direction(light_heading_degrees) * cos(e) + Vector3.UP * sin(e)).normalized()


## The shaft cards in world space: feet on the ground along the light's heading from the flight start,
## tops up at shaft_top_height and shaft_lean further on.
func shaft_cards() -> Array:
	var flight := flight_at(0.0)
	var start := Vector3(flight.origin.x, 0.0, flight.origin.z)
	var cards := []
	for row: Array in SHAFTS:
		var level := level_direction(light_heading_degrees + row[0])
		var foot := start + level * float(row[1])
		var top := foot + level * shaft_lean + Vector3.UP * shaft_top_height
		cards.append([top, foot, row[2], row[3], row[4], row[5]])
	return cards


func _apply_composite(t: float, f: float) -> void:
	shafts.apply(t, f)
	var look := DepthComposite.find_in(world_environment)
	if look == null:
		return
	# The break is effectively at infinity: placed off the camera, it holds still as the ship flies.
	look.light_uv = DepthComposite.screen_uv(camera, camera.global_position + light_direction() * 10000.0)
	look.flash = clampf(f, 0.0, 1.0)


## Lightning at shot time `t`, 0..1: the main double flicker, then the far one.
func flash_at(t: float) -> float:
	var f := _pulse(t, flash_time, 1.0)
	f = maxf(f, _pulse(t, flash_time + flash_gap, flash_second))
	return maxf(f, _pulse(t, far_flash_time, far_flash))


# A hit at `at`: up in 0.02 s, then dying away.
func _pulse(t: float, at: float, peak: float) -> float:
	var u := t - at
	if u < 0.0:
		return 0.0
	return peak * minf(u / 0.02, 1.0) * exp(-maxf(u - 0.02, 0.0) / flash_decay)


func _apply_flash(f: float) -> void:
	flash_light.visible = f > 0.001
	flash_light.light_energy = flash_light_energy * f
	if _sky != null:
		_sky.set_shader_parameter(&"flash", f)
	if _mist_material != null:
		_mist_material.set_shader_parameter(&"flash", f)
	# The storm fog is globals (Storm.apply): lift them toward the flash colour, and back.
	RenderingServer.global_shader_parameter_set(&"storm_near_color", storm.near_color.lerp(flash_color, flash_fog * f))
	RenderingServer.global_shader_parameter_set(&"storm_far_color", storm.far_color.lerp(flash_color, flash_fog * f))
	var rim := rim_color.lerp(flash_color, f)
	rim.a = lerpf(rim_color.a, rim_flash_strength, f)
	for m in _hull:
		m.set_shader_parameter(&"fresnel", rim)


## The straight, level flight line at shot time `t` (negative t too). +Z is the nose.
func flight_at(t: float) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(heading_degrees))
	return Transform3D(b, flight_start + b.z * speed * t)


## 0 before bank_start, 1 at the cut: squared, so it is still speeding up when the shot ends.
func bank_amount(t: float) -> float:
	var u := clampf((t - bank_start) / (shot_length() - bank_start), 0.0, 1.0)
	return u * u


## The ship at shot time `t`: flight line, then the bank, then the float.
func ship_at(t: float) -> Transform3D:
	var k := bank_amount(t)
	# Model +X is the ship's left: the slide and the nose turn go that way, and a negative roll
	# about the nose drops the left wing.
	var bank := Transform3D(
		Basis(Vector3.UP, deg_to_rad(bank_yaw_degrees) * k) * Basis(Vector3.BACK, -deg_to_rad(bank_roll_degrees) * k),
		Vector3(bank_slide * k, 0.0, 0.0))
	return flight_at(t) * bank * float_at(t)


## The float wobble at shot time `t`: slow sines at unrelated rates, so it never reads as a loop.
func float_at(t: float) -> Transform3D:
	var w := TAU * t
	var pitch := deg_to_rad(pitch_degrees) * sin(w * pitch_hz + 0.7)
	var yaw := deg_to_rad(yaw_degrees) * sin(w * yaw_hz + 2.3)
	var roll := deg_to_rad(roll_degrees) * sin(w * roll_hz + 1.1)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	return Transform3D(b, Vector3(0.0, bob_metres * sin(w * bob_hz), 0.0))


## The camera at shot time `t`: the fixed chase offset on the flight line, plus the sway. Never
## sees the float or the bank.
func camera_at(t: float) -> Transform3D:
	var flight := flight_at(t)
	var rest := Transform3D(Basis.IDENTITY, camera_offset).looking_at(camera_look, Vector3.UP)
	return flight * rest * sway_at(t)


## Camera sway at shot time `t`, in camera space: a slow wander plus a faint buzz.
func sway_at(t: float) -> Transform3D:
	var s := TAU * sway_hz * t
	var b := TAU * buzz_hz * t
	var pitch := deg_to_rad(sway_degrees) * (0.6 * sin(s + 0.4) + 0.4 * sin(s * 1.73 + 2.0)) \
			+ deg_to_rad(buzz_degrees) * (0.6 * sin(b) + 0.4 * sin(b * 1.61 + 1.2))
	var yaw := deg_to_rad(sway_degrees) * (0.6 * sin(s * 0.83 + 1.9) + 0.4 * sin(s * 1.37 + 0.3)) \
			+ deg_to_rad(buzz_degrees) * (0.6 * sin(b * 1.13 + 2.2) + 0.4 * sin(b * 1.87 + 0.5))
	var roll := deg_to_rad(sway_degrees) * 0.5 * sin(s * 0.67 + 3.1)
	var pos := Vector3(sin(s * 0.91 + 0.8), sin(s * 1.21 + 2.6), 0.0) * sway_metres
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), pos)


# The glow discs sit on the trail's nozzle centres, facing back out of the nozzles.
func _place_glows() -> void:
	var glows := [$Ship/MainGlow, $Ship/PodGlowL, $Ship/PodGlowR]
	for i in glows.size():
		var g: Node3D = glows[i]
		var size := main_glow_size if i == 0 else pod_glow_size
		# QuadMesh faces +Z; turn it to face -Z (out of the nozzle, toward the camera).
		g.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * size), trail.nozzles[i])
	($Ship/EngineLight as Node3D).position = trail.nozzles[0] + Vector3(0.0, 0.0, -1.5)
	# The halo: a unit quad scaled to its size; the shader turns it to the camera and flickers it.
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = HALO_SHADER
	_halo_material.render_priority = 3
	_halo_material.set_shader_parameter(&"energy", halo_energy)
	_halo_material.set_shader_parameter(&"flicker", halo_flicker)
	var halo := MeshInstance3D.new()
	halo.name = "MainHalo"
	halo.mesh = QuadMesh.new()
	halo.material_override = _halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * halo_size), trail.nozzles[0])
	ship.add_child(halo)


# The dot sparks: world-space mesh rebuilt each frame (FlyoverDotSparks), drawn last.
func _build_dots() -> void:
	dots = FlyoverDotSparks.new()
	dots.name = "DotSparks"
	var mat := ShaderMaterial.new()
	mat.shader = DOT_SHADER
	mat.render_priority = 6
	dots.material_override = mat
	dots.nozzles = trail.nozzles
	add_child(dots)


# A heat shimmer cone behind each nozzle, on the ship so it banks and floats with it. Main first.
func _build_shimmer() -> void:
	if not shimmer_on:
		return
	for i in trail.nozzles.size():
		var main := i == 0
		var mat := ShaderMaterial.new()
		mat.shader = SHIMMER_SHADER
		# Before the storm fog (-100): see heat_shimmer.gdshader.
		mat.render_priority = -101
		mat.set_shader_parameter(&"strength", shimmer_strength * (1.0 if main else pod_shimmer))
		_shimmers.append(mat)
		# Starts at the glow disc's rim, which fills the nozzle mouth.
		var r0 := 0.5 * (main_glow_size if main else pod_glow_size)
		var mi := MeshInstance3D.new()
		mi.name = "Shimmer%d" % i
		mi.mesh = _shimmer_cone(r0, r0 * shimmer_flare, main_shimmer_length if main else pod_shimmer_length)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = trail.nozzles[i]
		ship.add_child(mi)


# An open cone from radius r0 at z = 0 back to r1 at z = -length. UV.y runs 0 -> 1 along it.
func _shimmer_cone(r0: float, r1: float, length: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var slope := (r1 - r0) / length
	for ring in SHIMMER_RINGS + 1:
		var v := float(ring) / SHIMMER_RINGS
		var r := lerpf(r0, r1, v)
		for side in SHIMMER_SIDES + 1:
			var u := float(side) / SHIMMER_SIDES
			var a := TAU * u
			verts.append(Vector3(cos(a) * r, sin(a) * r, -length * v))
			normals.append(Vector3(cos(a), sin(a), slope).normalized())
			uvs.append(Vector2(u, v))
	var row := SHIMMER_SIDES + 1
	for ring in SHIMMER_RINGS:
		for side in SHIMMER_SIDES:
			var a := ring * row + side
			idx.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# The painted ground: the sky's snow plane, with the streets on the hero's grid. See the Ground
# exports.
func _build_ground() -> void:
	_sky = ($WorldEnvironment as WorldEnvironment).environment.sky.sky_material as ShaderMaterial
	_sky.set_shader_parameter(&"ground_y", ground_y)
	_sky.set_shader_parameter(&"ground_color", ground_color)
	_sky.set_shader_parameter(&"mottle", mottle)
	_sky.set_shader_parameter(&"mottle_size", mottle_size)
	_sky.set_shader_parameter(&"street_origin", Vector2(city.hero_at.x, city.hero_at.z))
	_sky.set_shader_parameter(&"street_angle", deg_to_rad(city.grid_degrees))
	_sky.set_shader_parameter(&"street_block", city.street_block)
	_sky.set_shader_parameter(&"street_width", city.street_width)
	_sky.set_shader_parameter(&"street_dark", street_dark)
	_sky.set_shader_parameter(&"street_radius", street_radius)
	_sky.set_shader_parameter(&"flash_color", flash_color)
	# Draw order (transparent): heat shimmer (-101), storm fog (-100), crease ink then ground mist
	# (0), snow (1), trails (2), main halo (3), nozzle glows (4), embers (5; trails, glows and
	# embers set in the scene), dot sparks (6).
	for n in storm.get_children():
		var snow := n as GeometryInstance3D
		if snow != null and snow.material_override != storm.fog_material:
			snow.material_override.render_priority = 1


# The ground mist: a full-screen pass. See the Ground mist exports.
func _build_mist() -> void:
	if not mist_on:
		return
	_mist_material = ShaderMaterial.new()
	_mist_material.shader = MIST_SHADER
	_mist_material.set_shader_parameter(&"ground_y", ground_y)
	_mist_material.set_shader_parameter(&"height", mist_height)
	_mist_material.set_shader_parameter(&"density", mist_density)
	_mist_material.set_shader_parameter(&"color", mist_color)
	_mist_material.set_shader_parameter(&"patch_size", mist_patch_size)
	_mist_material.set_shader_parameter(&"breakup", mist_breakup)
	_mist_material.set_shader_parameter(&"top_wobble", mist_top_wobble)
	_mist_material.set_shader_parameter(&"drift", mist_drift)
	_mist_material.set_shader_parameter(&"flash_color", flash_color)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	# Full-screen quad: never culled wherever the camera is.
	quad.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	_mist = MeshInstance3D.new()
	_mist.name = "GroundMist"
	_mist.mesh = quad
	_mist.material_override = _mist_material
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.sorting_use_aabb_center = false
	add_child(_mist)


# The ship's cel materials as ApplyCelShip left them (it is ready first: an earlier child).
func _collect_hull() -> void:
	for mi: MeshInstance3D in $Ship/Model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null and not _hull.has(m):
				_hull.append(m)


func _on_animation_finished(anim: StringName) -> void:
	if anim == SHOT:
		_done = true
		finished.emit()


# _input, not _unhandled_input: the UI autoload reads Esc in its own _input to open the pause
# menu. The current scene sits after the autoloads, so it sees the key first and consumes it.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		get_viewport().set_input_as_handled()
		restart()
	elif key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		get_tree().quit()
