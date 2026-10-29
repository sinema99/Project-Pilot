class_name ArrivalShot
extends Node3D

# Cutscene shot 5, the intro's last: out of the storm on a clear cold day, a locked high 3/4 view
# of the base the pilot is flying to, a megastructure of chamfered decks and mushroom towers built
# into an alpine ridge (docs/specs/cutscene-arrival.md, reference docs/specs/cutscene-arrival-ref.png).
# This pass is shape and silhouette only; the ship landing comes later.
#
# The camera never moves, so everything is placed THROUGH it: the tables below are read off the
# reference in percent of the frame (u across, v down) and turned into world points by casting a
# ray through the camera to a plane height or a level distance. Retune by editing the tables.
#
# Everything that moves is a function of the shot time, so seeking shows the same frame. Plays once
# on load: 10 s, a 2 s fade to black, then holds black. R restarts, Esc quits.

## Emitted when the shot reaches its last frame.
signal finished

const SHOT := &"shot"
const BEACON_SHADER := preload("res://shaders/cutscene/arrival_beacon.gdshader")
## The frame the tables were read for (the reference is 16:9).
const ASPECT := 16.0 / 9.0

## The decks, top plane first: outline in frame percent on the plane y = `top` (m), slab
## `thick`ness, then the recessed underside band (`band` m deep, `inset` m in from the edge).
## Under that, `legs`: a dark ribbed `plinth` wall down into the land, or short `pillars` (the
## right extension, the only supports that show). `sink` (m): the land is pulled up under the deck
## to this far below the band, so the base reads as built into the mountain; 0 leaves it alone.
## `roof`: what the roof is for (spec R2-3): `pads` (the landing apron, PADS), `ops` (equipment
## housings on the building's grid), `utilities` (a vent run and a radiator strip), `crown` (the
## centre tier's two steps). Points past 100 run off the frame edge. Lowest first.
const DECKS := [
	{name = "Lower", top = 0.0, thick = 26.0, band = 18.0, inset = 22.0, legs = &"plinth", sink = 14.0, roof = &"pads", outline = [
		Vector2(14.8, 52.8), Vector2(15.6, 56.6), Vector2(19.4, 62.2), Vector2(21.2, 64.6),
		Vector2(56.0, 64.6), Vector2(64.5, 61.0), Vector2(64.5, 56.0), Vector2(50.0, 50.0),
		Vector2(36.0, 47.6), Vector2(22.0, 48.6)]},
	{name = "Right", top = -6.0, thick = 22.0, band = 16.0, inset = 18.0, legs = &"pillars", sink = 34.0, roof = &"utilities", outline = [
		Vector2(62.0, 51.0), Vector2(63.5, 55.0), Vector2(80.0, 56.6), Vector2(96.5, 54.2),
		Vector2(106.0, 53.0), Vector2(106.0, 50.2), Vector2(95.0, 49.6), Vector2(80.0, 49.2)]},
	{name = "Mid", top = 22.0, thick = 20.0, band = 10.0, inset = 14.0, legs = &"plinth", sink = 0.0, roof = &"ops", outline = [
		Vector2(35.5, 49.0), Vector2(38.5, 51.6), Vector2(63.5, 55.6), Vector2(68.0, 53.6),
		Vector2(78.5, 49.6), Vector2(78.0, 46.6), Vector2(66.0, 45.4), Vector2(46.0, 45.4),
		Vector2(38.0, 46.6)]},
	{name = "Tier1", top = 40.0, thick = 18.0, band = 0.0, inset = 0.0, legs = &"", sink = 0.0, roof = &"ops", outline = [
		Vector2(44.0, 46.2), Vector2(46.0, 48.6), Vector2(58.0, 49.6), Vector2(61.0, 48.0),
		Vector2(59.0, 45.4), Vector2(48.0, 44.6)]},
	{name = "Tier2", top = 55.0, thick = 15.0, band = 0.0, inset = 0.0, legs = &"", sink = 0.0, roof = &"crown", outline = [
		Vector2(47.5, 44.4), Vector2(49.0, 45.9), Vector2(56.0, 46.4), Vector2(57.6, 45.3),
		Vector2(56.0, 43.8), Vector2(49.5, 43.6)]},
]

## The mushroom towers: where the centre of the cap's top sits in the frame (u, v percent), its
## level distance from the camera (m), the cap's radius and the shaft's (m, octagon corner radius).
## `role` (spec R2-4) is the tower's job, read in its cap: `comms` (mast + dish), `control` (a dark
## glazing band), `pad` (flat landing top), `exhaust` (stacks and a steam plume), `sensor` (radome).
## `vary` scales the skirt and collar, so the family is not five copies.
const TOWERS := [
	{name = "LeftTower", u = 10.5, v = 41.6, distance = 1000.0, cap = 64.0, shaft = 34.0, role = &"comms", vary = 0.9},
	{name = "CentreTower", u = 39.5, v = 30.6, distance = 1500.0, cap = 100.0, shaft = 66.0, role = &"control", vary = 1.1},
	{name = "RightWide", u = 65.0, v = 26.4, distance = 2000.0, cap = 160.0, shaft = 78.0, role = &"pad", vary = 0.85},
	{name = "RightTower", u = 67.5, v = 33.2, distance = 1700.0, cap = 110.0, shaft = 84.0, role = &"exhaust", vary = 1.05},
	{name = "FarTower", u = 29.0, v = 11.8, distance = 2600.0, cap = 104.0, shaft = 50.0, role = &"sensor", vary = 1.0},
]

## The landing apron on the Lower deck (spec R2-3): pad centres in frame percent on its top plane and
## their radius (m), and the taxi lane through them to the hangar mouth on the front fascia (frame
## percent; the last point is on the front edge, where the hangar is cut).
const PADS := [
	{u = 24.5, v = 57.0, radius = 40.0},
	{u = 34.0, v = 60.0, radius = 44.0},
]
const LANE := [Vector2(24.5, 57.0), Vector2(34.0, 60.0), Vector2(42.0, 62.0), Vector2(43.0, 64.6)]
const LANE_WIDTH := 26.0
## The hangar mouth: its width (m) along the front fascia, centred on the lane's last point.
const HANGAR_WIDTH := 70.0

## The road (spec R2-8): it leaves the Lower deck's foundation at a portal (`at`, a fraction along
## the front edge of the deck's band line from its left end), runs `out` m straight down the slope,
## then switchbacks `legs` times, each leg `leg` m across the slope and `advance` m on down it.
const ROAD := {at = 0.62, out = 40.0, legs = 4, leg = 220.0, advance = 70.0}
## The power-line cut (spec R2-8): straight from the right extension's front edge (frame percent on
## its top plane) down the forested slope and off the frame's lower right, to a point (frame percent
## at a level distance, m).
const POWER_CUT := {from = Vector2(84.0, 55.0), to = Vector2(112.0, 96.0), distance = 760.0}

## The near ridge the base is built into: crest points as frame percent on the plane y = 0 (which
## sets where the crest runs on the ground) and the crest height there (m). Between points it is
## straight; past the ends it carries on along the end segments.
const CREST := [
	Vector3(-20.0, 60.0, -170.0),
	Vector3(4.0, 58.0, -45.0),
	Vector3(16.0, 57.0, -50.0),
	Vector3(40.0, 58.0, -55.0),
	Vector3(70.0, 57.0, -55.0),
	Vector3(100.0, 56.0, -80.0),
	Vector3(125.0, 56.0, -200.0),
]

## Hills pulled up out of the land: frame percent and level distance (m) of the top, its height (m),
## radius (m) and how far it has fallen at that radius (m). The snow hill behind the deck's left
## half, the knoll the left tower stands on, and the far tower's perch.
## A hill with a `spur` (m) is a ridge, not a cone (spec R2-5): its crest runs that far from the top
## toward a frame point (`toward`, at `toward_distance` m), across the view so its length shows,
## climbing `rise` m into the bank, and its right flank is `steep` times as wide, so that side falls
## away as a rock face.
const HILLS := [
	{u = 28.0, v = 46.0, distance = 1350.0, top = 45.0, radius = 260.0, fall = 260.0},
	{u = 10.5, v = 41.6, distance = 1000.0, top = -15.0, radius = 160.0, fall = 300.0},
	{u = 29.0, v = 12.6, distance = 2650.0, top = 40.0, radius = 330.0, fall = 520.0, spur = 3600.0, rise = 520.0, steep = 0.5,
			toward = Vector2(-25.0, 13.0), toward_distance = 4200.0},
]

## The dominant massif (spec R2-5): the main range's tallest point, back left behind the cloud bank,
## as frame percent across and its level distance (m), plus how much it stands over the range (m)
## and its half-width along it (m).
const MASSIF := {u = 14.0, distance = 15000.0, height = 700.0, width = 5000.0}

## The sister outpost on a far peak, top right: where its deck's centre sits in the frame (u, v
## percent) and its level distance (m). Its deck and towers are laid out around that in metres
## (ArrivalBase.OUTPOST_*), and the peak under it is pulled up by ArrivalLand.
const OUTPOST := {u = 83.0, v = 16.0, distance = 7000.0, peak_radius = 900.0, peak_fall = 1100.0}

@export var autoplay := true

@export_group("Camera")
## The locked camera: height (m) above the deck plane, pitch (degrees, negative = down) and vertical
## field of view (degrees). It sits over the world origin looking down -Z.
@export var camera_height := 300.0
@export var pitch_degrees := -13.5
@export var fov := 32.0

@export_group("Timing")
## The shot holds for `hold` seconds, then fades to black over `fade` seconds.
@export var hold := 10.0
@export var fade := 2.0

@export_group("Sun")
## Where the sun is: heading (degrees from the camera's look toward screen left; above 90 is behind
## the camera, below 90 is beyond the scene) and elevation (degrees).
@export var sun_heading_degrees := 35.0
@export var sun_elevation_degrees := 48.0

@export_group("Beacons")
## Blink period (s), how long each blink is lit (s), and its HDR brightness.
@export var beacon_period := 1.6
@export var beacon_on := 0.25
@export var beacon_energy := 14.0
@export var beacon_size := 12.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var land: ArrivalLand = $Land
@onready var base: ArrivalBase = $Base
@onready var clouds: ArrivalClouds = $Clouds
@onready var fade_rect: ColorRect = $Fade/Black

var _done := false
## Per beacon: {mesh, phase}.
var _beacons: Array[Dictionary] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The storm's fog globals are shared: this shot is out of it.
	RenderingServer.global_shader_parameter_set(&"storm_fog", 0.0)
	camera.global_transform = camera_transform()
	camera.fov = fov
	sun.basis = Basis.looking_at(-sun_direction())
	_build_beacons()
	animation_player.get_animation(SHOT).length = hold + fade
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
	return hold + fade


func _process(_delta: float) -> void:
	var t := shot_length() if _done else animation_player.current_animation_position
	apply(t)


## Shows shot time `t`: clouds, spindrift, beacons, the fade.
func apply(t: float) -> void:
	clouds.apply(t)
	for b in _beacons:
		(b.mesh as GeometryInstance3D).set_instance_shader_parameter(&"energy", beacon_energy * beacon_at(t, b.phase))
	fade_rect.color.a = fade_at(t)
	var look := DepthComposite.find_in(world_environment)
	if look != null:
		look.light_uv = key_light_uv()


## How black the frame is at `t`: 0 until `hold`, then easing to 1 at the end.
func fade_at(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf((t - hold) / fade, 0.0, 1.0))


## A beacon's brightness at `t`, 0..1: a short hard blink each period, offset by `phase` (s).
func beacon_at(t: float, phase: float) -> float:
	var u := fposmod(t + phase, beacon_period)
	return 1.0 if u < beacon_on else 0.0


# --- the locked camera and the frame tables ----------------------------------------------------

## The camera's world transform, from the exports alone (the children build from it before this
## node's _ready).
func camera_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(pitch_degrees)), Vector3(0.0, camera_height, 0.0))


## The world direction through frame point (`u`, `v`), percent across and down.
func screen_ray(u: float, v: float) -> Vector3:
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var local := Vector3((u / 50.0 - 1.0) * tan_v * ASPECT, (1.0 - v / 50.0) * tan_v, -1.0)
	return (camera_transform().basis * local).normalized()


## Where the ray through (`u`, `v`) meets the level plane at height `y`.
func on_plane(u: float, v: float, y: float) -> Vector3:
	var o := camera_transform().origin
	var d := screen_ray(u, v)
	return o + d * ((y - o.y) / d.y)


## The point on the ray through (`u`, `v`) a level `distance` (m) from the camera.
func at_distance(u: float, v: float, distance: float) -> Vector3:
	var d := screen_ray(u, v)
	return camera_transform().origin + d * (distance / Vector2(d.x, d.z).length())


## Frame percent (u across, v down) of world point `p`; for tests and the probes.
func frame_point(p: Vector3) -> Vector2:
	var local := camera_transform().affine_inverse() * p
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	return Vector2((local.x / -local.z / (tan_v * ASPECT) + 1.0) * 50.0, (1.0 - local.y / -local.z / tan_v) * 50.0)


## Unit vector toward the sun.
func sun_direction() -> Vector3:
	var level := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(sun_heading_degrees))
	var e := deg_to_rad(sun_elevation_degrees)
	return (level * cos(e) + Vector3.UP * sin(e)).normalized()


## The composite's key light: the sun's spot on screen, held just off the frame's top edge so its
## glow bleeds in from the top left the way the sun lights the scene.
func key_light_uv() -> Vector2:
	var uv := DepthComposite.screen_uv(camera, camera.global_position + sun_direction() * 10000.0)
	return Vector2(clampf(uv.x, 0.02, 0.98), clampf(uv.y, -0.15, -0.05))


# --- beacons -----------------------------------------------------------------------------------

func _build_beacons() -> void:
	var material := ShaderMaterial.new()
	material.shader = BEACON_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(beacon_size, beacon_size)
	var i := 0
	for spot: Vector3 in base.beacon_spots:
		var mi := MeshInstance3D.new()
		mi.name = "Beacon%d" % i
		mi.mesh = quad
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = spot
		add_child(mi)
		# Neighbours out of step, so the base twinkles rather than pulsing as one.
		_beacons.append({mesh = mi, phase = fposmod(i * 0.61, beacon_period)})
		i += 1


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
