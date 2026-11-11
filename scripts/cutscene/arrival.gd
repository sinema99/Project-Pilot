class_name ArrivalShot
extends Node3D

# Cutscene shot 5, the intro's last: out of the storm on a clear cold day, a locked high 3/4 view
# of the base the pilot is flying to, a megastructure of chamfered decks and mushroom towers built
# into an alpine ridge (docs/specs/cutscene-arrival.md, reference docs/specs/cutscene-arrival-ref.png).
# Since revision 5 it has been abandoned for 200 years: overgrown and falling apart, no lights, no
# craft, nothing moving but the weather. The ship landing comes later.
#
# The camera never moves, so everything is placed THROUGH it: the tables below are read off the
# reference in percent of the frame (u across, v down) and turned into world points by casting a
# ray through the camera to a plane height or a level distance. Retune by editing the tables.
#
# Everything that moves is a function of the shot time, so seeking shows the same frame. Plays once
# on load: 10 s, a 2 s fade to black, then holds black. R restarts, Esc quits.
#
# With `cutscene` off it is only the world: the builders under it place the base off the same
# tables, but there is no camera, fade, clock or keys (the boss arena, docs/specs/boss-arena.md).

## Emitted when the shot reaches its last frame.
signal finished

const SHOT := &"shot"
## The frame the tables were read for (the reference is 16:9).
const ASPECT := 16.0 / 9.0

## The decks, top plane first: outline in frame percent on the plane y = `top` (m), slab
## `thick`ness, then the recessed underside band (`band` m deep, `inset` m in from the edge).
## Under that, `legs`: a dark ribbed `plinth` wall down into the land, or short `pillars` (the
## right extension, the only supports that show). `sink` (m): the land is pulled up under the deck
## to this far below the band, so the base reads as built into the mountain; 0 leaves it alone.
## `roof`: what the roof was for (spec R2-3): `apron` (the landing apron, its pads gone since R5), `ops` (equipment
## housings on the building's grid), `utilities` (a vent run and a radiator strip), `crown` (the
## centre tier's two steps). `glazing` (spec R3-3): glass only where people work - `band` (a
## recessed glazed band under an overhang lip, mullions on the bay grid: the ops floors and base
## command), `corner` (the crew room's strip beside the hangar), `louvres` (the plant deck: louvre
## panels where the radiators vent, no glass). Points past 100 run off the frame edge. Lowest first.
const DECKS := [
	{name = "Lower", top = 0.0, thick = 26.0, band = 18.0, inset = 22.0, legs = &"plinth", sink = 14.0, roof = &"apron", glazing = &"corner", outline = [
		Vector2(14.8, 52.8), Vector2(15.6, 56.6), Vector2(19.4, 62.2), Vector2(21.2, 64.6),
		Vector2(56.0, 64.6), Vector2(64.5, 61.0), Vector2(64.5, 56.0), Vector2(50.0, 50.0),
		Vector2(36.0, 47.6), Vector2(22.0, 48.6)]},
	{name = "Right", top = -6.0, thick = 22.0, band = 16.0, inset = 18.0, legs = &"pillars", sink = 34.0, roof = &"utilities", glazing = &"louvres", outline = [
		Vector2(62.0, 51.0), Vector2(63.5, 55.0), Vector2(80.0, 56.6), Vector2(96.5, 54.2),
		Vector2(106.0, 53.0), Vector2(106.0, 50.2), Vector2(95.0, 49.6), Vector2(80.0, 49.2)]},
	{name = "Mid", top = 22.0, thick = 20.0, band = 10.0, inset = 14.0, legs = &"plinth", sink = 0.0, roof = &"ops", glazing = &"band", outline = [
		Vector2(35.5, 49.0), Vector2(38.5, 51.6), Vector2(63.5, 55.6), Vector2(68.0, 53.6),
		Vector2(78.5, 49.6), Vector2(78.0, 46.6), Vector2(66.0, 45.4), Vector2(46.0, 45.4),
		Vector2(38.0, 46.6)]},
	{name = "Tier1", top = 40.0, thick = 18.0, band = 0.0, inset = 0.0, legs = &"", sink = 0.0, roof = &"ops", glazing = &"band", outline = [
		Vector2(44.0, 46.2), Vector2(46.0, 48.6), Vector2(58.0, 49.6), Vector2(61.0, 48.0),
		Vector2(59.0, 45.4), Vector2(48.0, 44.6)]},
	{name = "Tier2", top = 55.0, thick = 15.0, band = 0.0, inset = 0.0, legs = &"", sink = 0.0, roof = &"crown", glazing = &"band", outline = [
		Vector2(47.5, 44.4), Vector2(49.0, 45.9), Vector2(56.0, 46.4), Vector2(57.6, 45.3),
		Vector2(56.0, 43.8), Vector2(49.5, 43.6)]},
]

## The mushroom towers: where the centre of the cap's top sits in the frame (u, v percent), its
## level distance from the camera (m), the cap's radius and the shaft's (m, octagon corner radius).
## `role` (spec R2-4) is the tower's job, read in its cap: `comms` (mast + dish), `control` (flight
## control, spec R3-7: the raked glazed cab under the cap, looking down on the pads), `pad` (flat
## landing top), `exhaust` (stacks, cold since R5), `sensor` (radome).
## `vary` scales the skirt and collar, so the family is not five copies. A tower down the slope
## stands on a `bastion` (spec R4-2): a dark stepped retaining plinth this many shaft radii out, cut
## into the slope, in place of the flared footing.
## `wear` (spec R5-2), 200 years on: `broken` (a third of the cap's rim gone in one stepped wedge),
## `snapped` (the comms mast snapped, its dish down, a bite or two out of the rim), `bitten` (a few
## bites out of the rim, a fallen bracket, the glazing empty).
const TOWERS := [
	{name = "LeftTower", u = 10.5, v = 41.6, distance = 1000.0, cap = 64.0, shaft = 34.0, role = &"comms", vary = 0.9, bastion = 2.6, wear = &"snapped"},
	{name = "CentreTower", u = 39.5, v = 30.6, distance = 1500.0, cap = 100.0, shaft = 66.0, role = &"control", vary = 1.1, wear = &"bitten"},
	{name = "RightWide", u = 65.0, v = 26.4, distance = 2000.0, cap = 160.0, shaft = 78.0, role = &"pad", vary = 0.85, wear = &"bitten"},
	{name = "RightTower", u = 67.5, v = 33.2, distance = 1700.0, cap = 110.0, shaft = 84.0, role = &"exhaust", vary = 1.05, wear = &"broken"},
	{name = "FarTower", u = 29.0, v = 11.8, distance = 2600.0, cap = 104.0, shaft = 50.0, role = &"sensor", vary = 1.0, wear = &"bitten"},
]

## What is left of the landing apron on the Lower deck (spec R2-3; its pads, lane and craft went in
## R5): the hangar mouth on the front fascia (frame percent of its centre on the front edge, width m),
## the lift head's site where the first pad was, and the collapse hole where the second pad was
## (spec R5-3: frame percent of its centre on the roof, radius m).
const HANGAR := {u = 43.0, v = 64.6, width = 70.0}
const LIFT_SITE := Vector2(24.5, 57.0)
const HOLE := {u = 34.0, v = 60.0, radius = 25.0}

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
	Vector3(4.0, 53.0, -45.0),
	Vector3(16.0, 53.0, -50.0),
	Vector3(40.0, 58.0, -55.0),
	Vector3(70.0, 57.0, -55.0),
	Vector3(100.0, 56.0, -80.0),
	Vector3(125.0, 56.0, -200.0),
]

## Hills pulled up out of the land: frame percent and level distance (m) of the top, its height (m),
## radius (m) and how far it has fallen at that radius (m). The snow hill behind the deck's left
## half (spec R4-1: set back and tightened so none of it comes up through the Lower deck's roof) and
## the far tower's perch. The left tower has no knoll (spec R3-1): the crest at the base's
## left end sits back (CREST v 53), so the tower stands down the front slope, its shaft rising out of
## the forest.
## A hill with a `spur` (m) is a ridge, not a cone (spec R2-5): its crest runs that far from the top
## toward a frame point (`toward`, at `toward_distance` m), across the view so its length shows,
## climbing `rise` m into the bank, and its right flank is `steep` times as wide, so that side falls
## away as a rock face.
const HILLS := [
	{u = 28.0, v = 44.0, distance = 1600.0, top = 45.0, radius = 240.0, fall = 220.0},
	{u = 29.0, v = 12.6, distance = 2650.0, top = 40.0, radius = 330.0, fall = 520.0, spur = 3600.0, rise = 520.0, steep = 0.5,
			toward = Vector2(-25.0, 13.0), toward_distance = 4200.0},
]

## The near slope's landform (spec R4-4): spurs running down from the base toward the camera and the
## gully between them, so the forest has a shape. Each runs from a frame point on the plane y = -60
## (the deck's foot) to one on y = -160 (the frame's bottom edge), `height` m over the slope at its
## crest (negative: a gully), `width` m to its flank.
const SPURS := [
	{from = Vector2(22.0, 70.0), to = Vector2(16.0, 104.0), height = 36.0, width = 70.0},
	{from = Vector2(40.0, 70.0), to = Vector2(42.0, 104.0), height = -24.0, width = 55.0},
	{from = Vector2(60.0, 70.0), to = Vector2(68.0, 104.0), height = 34.0, width = 80.0},
]
## Rock bands (spec R4-4) where the slope is steepest: the ground in front of each line (frame
## points on the plane y = -60) drops `drop` m over `width` m, so the step shows as a rock face. The
## one under the deck foundation; the bastion makes its own (ArrivalLand).
const ROCK_BANDS := [
	{line = [Vector2(17.0, 73.5), Vector2(30.0, 74.5), Vector2(45.0, 75.0), Vector2(62.0, 74.0)], drop = 16.0, width = 6.0},
]

## The spire (spec R4-6, R4b): an ancient built shaft far out past the base, centre back between
## CentreTower and RightWide. Its foot's centre in frame percent at a level distance (m), its radius
## there (m), and the radius it has narrowed to where it leaves the top of the frame (m). It stands
## on a low snowfield just above the cloud sea, no rock: level out to `field` m from the foot, then
## a shoulder `shoulder` m wide falling at `grade` (gentle enough to stay open snow) down into the
## cloud, then `fall` m over `field_radius` m under it; the whole outline pushed in and out by up to
## `lobes` (fraction) round it so the shore the sea laps is not a circle.
const SPIRE := {u = 52.0, v = 20.4, distance = 11000.0, radius = 175.0, frame_top_radius = 125.0,
		field = 400.0, shoulder = 500.0, grade = 0.07, fall = 800.0, field_radius = 900.0, lobes = 0.25}

## The dominant massif (spec R2-5): the main range's tallest point, back left behind the cloud bank,
## as frame percent across and its level distance (m), plus how much it stands over the range (m)
## and its half-width along it (m).
const MASSIF := {u = 14.0, distance = 15000.0, height = 700.0, width = 5000.0}

## The sister outpost on a far peak, top right: where its deck's centre sits in the frame (u, v
## percent) and its level distance (m). Its deck and towers are laid out around that in metres
## (ArrivalBase.OUTPOST_*), and the peak under it is pulled up by ArrivalLand.
const OUTPOST := {u = 83.0, v = 16.0, distance = 7000.0, peak_radius = 900.0, peak_fall = 1100.0}

@export var autoplay := true
## Off: only the world (the builders' tables and the sun). The camera, fade, clock and keys are
## not used and need not exist.
@export var cutscene := true

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

@onready var animation_player: AnimationPlayer = get_node_or_null(^"AnimationPlayer")
@onready var camera: Camera3D = get_node_or_null(^"Camera3D")
@onready var sun: DirectionalLight3D = get_node_or_null(^"Sun")
@onready var world_environment: WorldEnvironment = get_node_or_null(^"WorldEnvironment")
@onready var land: ArrivalLand = get_node_or_null(^"Land")
@onready var base: ArrivalBase = get_node_or_null(^"Base")
@onready var clouds: ArrivalClouds = get_node_or_null(^"Clouds")
@onready var fade_rect: ColorRect = get_node_or_null(^"Fade/Black")

var _done := false


func _ready() -> void:
	# The storm's fog globals are shared: this shot is out of it.
	RenderingServer.global_shader_parameter_set(&"storm_fog", 0.0)
	if sun != null:
		sun.basis = Basis.looking_at(-sun_direction())
	if not cutscene:
		set_process(false)
		set_process_input(false)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.global_transform = camera_transform()
	camera.fov = fov
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


## Shows shot time `t`: clouds, spindrift, the fade.
func apply(t: float) -> void:
	clouds.apply(t)
	fade_rect.color.a = fade_at(t)
	var look := DepthComposite.find_in(world_environment)
	if look != null:
		look.light_uv = key_light_uv()


## How black the frame is at `t`: 0 until `hold`, then easing to 1 at the end.
func fade_at(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf((t - hold) / fade, 0.0, 1.0))


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
