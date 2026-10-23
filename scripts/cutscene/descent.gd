class_name DescentShot
extends Node3D

# Cutscene shot 3: the long shot of the snowy surface under the storm. The ship is never shown;
# a blue trail drops out of the cloud deck top right and arcs down to the middle of the frame.
# See docs/specs/cutscene-descent.md.
#
# Everything is placed FROM THE USER'S SKETCH (1906 x 847 px): a sketch pixel is the same fraction
# of a 16:9 frame, and a ray through it is pushed out to a chosen distance. The sketch tables and
# the sketch_* helpers live here and are static, so DescentLand (which builds before the Storm
# bakes its roof map) and the tests use them without a scene.
#
# Every effect is a function of the shot time (trail head, trail, lightning, flash light), so
# seeking shows the same frame. Plays once on load and holds the last frame. R restarts, Esc quits.

## Emitted when the shot reaches its last frame. Later shots chain off this.
signal finished

const SHOT := &"shot"

const SKETCH_SIZE := Vector2(1906.0, 847.0)
const ASPECT := 16.0 / 9.0
## Vertical field of view, degrees.
const FOV := 40.0
const CAMERA_POSITION := Vector3(0.0, 1.7, 0.0)
## Sketch y of the horizon line: the camera pitches up until the y = 0 horizon sits there.
const HORIZON_PX := 545.0
## Height of the cloud deck's base (m).
const DECK_BASE := 500.0

## The sketch's cloud line, left to right: the deck's front edge.
const CLOUD_LINE := [
	Vector2(-660, 90), Vector2(0, 85), Vector2(10, 98), Vector2(40, 105), Vector2(90, 97),
	Vector2(160, 108), Vector2(240, 113), Vector2(275, 118), Vector2(290, 135), Vector2(330, 138),
	Vector2(480, 145), Vector2(600, 138), Vector2(730, 142), Vector2(850, 132), Vector2(870, 128),
	Vector2(980, 133), Vector2(1000, 128), Vector2(1100, 130), Vector2(1200, 133), Vector2(1340, 125),
	Vector2(1360, 128), Vector2(1480, 132), Vector2(1500, 143), Vector2(1560, 145), Vector2(1660, 140),
	Vector2(1700, 145), Vector2(1750, 140), Vector2(1800, 145), Vector2(1860, 145), Vector2(1906, 137),
	Vector2(2560, 140),
]

## The blue line, as ONE cubic Bezier: [sketch px, horizontal distance (m)] for the start (inside
## the deck, 60 m above its base), its two handles, and Finish. Fitted to the sketch's hand-drawn
## line (4.7 px RMS) with a convex control polygon, so it bends one way only: no squiggles. It
## breaks out where it crosses the deck base (breach_point), on the sketch's breach.
const TRAIL_ARC := [
	[Vector2(1735.0, 85.0), 1563.1],
	[Vector2(1599.8, 275.1), 1621.3],
	[Vector2(1438.3, 343.0), 1646.6],
	[Vector2(910.0, 388.0), 1800.0],
]
## Where the sketch's line leaves the cloud line.
const SKETCH_BREACH := Vector2(1690.0, 142.0)

## The near mountain range's ridge, read off the sketch, left to right (extended past the frame).
const NEAR_RIDGE := [
	Vector2(-660, 520), Vector2(0, 520), Vector2(60, 505), Vector2(130, 530), Vector2(240, 495),
	Vector2(300, 498), Vector2(355, 488), Vector2(395, 515), Vector2(470, 522), Vector2(530, 530),
	Vector2(570, 520), Vector2(680, 495), Vector2(700, 478), Vector2(790, 466), Vector2(850, 468),
	Vector2(870, 458), Vector2(905, 490), Vector2(1000, 500), Vector2(1045, 535), Vector2(1110, 540),
	Vector2(1140, 527), Vector2(1215, 525), Vector2(1240, 500), Vector2(1290, 465), Vector2(1360, 445),
	Vector2(1425, 440), Vector2(1490, 490), Vector2(1525, 498), Vector2(1560, 478), Vector2(1600, 458),
	Vector2(1700, 480), Vector2(1760, 488), Vector2(1835, 515), Vector2(1906, 522), Vector2(2560, 515),
]
## The far range: not in the sketch. Taller, so it peeks over the near range's low points.
const FAR_RIDGE := [
	Vector2(-660, 470), Vector2(0, 470), Vector2(150, 455), Vector2(330, 468), Vector2(520, 450),
	Vector2(640, 425), Vector2(760, 440), Vector2(980, 455), Vector2(1080, 430), Vector2(1180, 445),
	Vector2(1300, 420), Vector2(1450, 415), Vector2(1620, 440), Vector2(1760, 430), Vector2(1906, 460),
	Vector2(2560, 465),
]
const NEAR_RANGE_DISTANCE := 7500.0
const FAR_RANGE_DISTANCE := 12500.0

## The ruined city, as Rect2(sketch x from, distance from (m), x span, distance span): a dense
## downtown left of centre, and mid-rise sprawl thinning out to the right of it.
const CITY_CORE := Rect2(300.0, 3000.0, 600.0, 2000.0)
const CITY_SPRAWL := Rect2(900.0, 2500.0, 650.0, 3000.0)
## Lone ruins out on the snow at both edges: sketch x, distance (m), height (m).
const CITY_OUTLIERS := [
	Vector3(70.0, 3300.0, 70.0), Vector3(205.0, 5600.0, 190.0),
	Vector3(1640.0, 2900.0, 55.0), Vector3(1830.0, 4800.0, 120.0),
]

## The storm wall on the left: where its lip sits on screen at full strength (sketch px). It joins
## the cloud line by SHELF_END_X; shelf_amount() blends between them.
const SHELF_LINE := [
	Vector2(-660, 455), Vector2(0, 458), Vector2(200, 432), Vector2(400, 378), Vector2(600, 300),
	Vector2(800, 215), Vector2(950, 160), Vector2(2560, 140),
]
const SHELF_FULL_X := 100.0
const SHELF_END_X := 1000.0
## How far out (m) the wall's lip is at full strength, and how many stepped bands it climbs in.
const SHELF_DISTANCE := 3200.0
const SHELF_BANDS := 4

## The snow curtain under the wall: how far out (m), and the sketch x it has thinned out by.
const CURTAIN_DISTANCE := 6000.0
const CURTAIN_END_X := 1050.0

## The background bolts: how far out (m), so tops hide behind the deck and feet behind the ridge.
const BOLT_DISTANCE := 10000.0

## Lone wrecks in the open field: [sketch x, distance (m), length (m), kind, lean (deg), sunk
## fraction, width (m)]. Kinds: snapped, side (tipped nearly over), skeleton, poking (top floors only).
const FIELD_WRECKS := [
	[260.0, 320.0, 40.0, &"snapped", 22.0, 0.45, 16.0],
	[640.0, 650.0, 80.0, &"skeleton", 16.0, 0.40, 30.0],
	[1180.0, 480.0, 45.0, &"snapped", 30.0, 0.50, 20.0],
	[1420.0, 1000.0, 90.0, &"side", 72.0, 0.35, 28.0],
	[840.0, 1400.0, 70.0, &"poking", 35.0, 0.60, 30.0],
	[1680.0, 1900.0, 80.0, &"snapped", 12.0, 0.30, 30.0],
]

## Trees (docs/specs/descent-trees.md). Close lone spruces: [sketch x, distance (m), height (m)].
## Three on the left under the storm wall, one on the right inside the pillar, the middle clear.
const TREE_LONE := [
	[115.0, 120.0, 19.0], [185.0, 175.0, 10.5], [385.0, 95.0, 13.0],
	[1560.0, 140.0, 21.0],
]
## Mid tree lines along creeks: [from sketch x, from distance (m), to sketch x, to distance (m),
## trees deep at the middle]. Each meanders a little and thins out at its ends.
const TREE_RIBBONS := [
	[40.0, 430.0, 560.0, 600.0, 3],
	[640.0, 980.0, 1010.0, 720.0, 2],
	[1260.0, 360.0, 1760.0, 470.0, 3],
	[1520.0, 700.0, 1780.0, 950.0, 2],
	[380.0, 1150.0, 760.0, 1350.0, 2],
	[1050.0, 1250.0, 1330.0, 1080.0, 1],
]
## Far clump lines, 1.5-5 km: the same creek pattern as [from x, from distance, to x, to distance],
## broken into separate mounds. The last rows are patches among the sprawl's outskirts.
const TREE_FAR_LINES := [
	[-120.0, 1700.0, 520.0, 2300.0],
	[560.0, 1900.0, 1100.0, 1600.0],
	[1150.0, 2100.0, 1900.0, 1750.0],
	[1700.0, 2600.0, 2200.0, 3600.0],
	[-200.0, 2900.0, 280.0, 3800.0],
	[620.0, 2500.0, 1000.0, 2800.0],
	[1500.0, 3200.0, 1700.0, 4400.0],
	[180.0, 4300.0, 330.0, 4900.0],
]

## Light shafts from the cloud break (docs/specs/descent-composite.md row 4): [top sketch x (on the
## deck's front edge), foot sketch x, foot distance (m), top width (m), foot width (m), strength,
## phase]. Tops lean right of their feet, falling away from the light behind the ridge.
const SHAFTS := [
	[1030.0, 950.0, 3200.0, 70.0, 170.0, 0.7, 0.0],
	[1160.0, 1100.0, 4200.0, 120.0, 280.0, 1.0, 1.7],
	[1270.0, 1240.0, 3600.0, 50.0, 130.0, 0.6, 3.1],
	[1390.0, 1400.0, 4800.0, 140.0, 320.0, 0.9, 4.4],
	[1530.0, 1580.0, 3000.0, 80.0, 180.0, 0.6, 2.2],
]

@export var autoplay := true

@export_group("Composite")
## The light the composite organises around (docs/specs/descent-composite.md row 1): the pale gap
## in the storm behind the mountains, in sketch px.
@export var light_px := Vector2(1240.0, 340.0)
## The shafts' brightness (their shader's `energy`; flyover keeps the 0.5 default). Low on purpose:
## a dark storm with a hint of the gap, so the trail reads against it.
@export var shaft_energy := 0.2

@export_group("Trail")
## Shot time the trail punches out of the deck.
@export var breach_time := 0.6
## Speed profile along the arc: start speed is 1 + speed_ease, cut speed 1 - speed_ease (times the average).
@export_range(0.0, 1.0, 0.01) var speed_ease := 0.6
## The head star's size (m across) and how far its rays reach (glint 0..1).
@export var head_star_size := 45.0
@export_range(0.0, 1.0, 0.01) var head_star_rays := 0.55

@export_group("Clouds")
## How fast the deck's front edge moves (m/s) as the billows turn around the eye over the camera.
@export var cloud_edge_speed := 1.0
## How fast the billows reshape in place: 0.033 is one full reshape about every 30 s.
@export var cloud_churn := 0.033

@export_group("Lightning")
## How strongly the flashes show: the deck's rings mix in at this, and FlashLight scales by it.
@export_range(0.0, 1.0, 0.01) var flash_opacity := 0.5
## Seconds each pulse takes to fade to a third.
@export var flash_decay := 0.05
## FlashLight energy at a flash's full brightness.
@export var flash_light_energy := 0.22
## How much a background bolt rims the ruin around the camera, against a deck flash.
@export var ruin_bolt_rim := 0.6
## Flashes: [start time, sketch x on the cloud line, metres into the deck from its edge, radius (m),
## peak brightness, pulses (seconds after start)]. A sketch x below 0 means "at the breach".
@export var flash_table: Array = [
	[0.52, -1.0, 0.0, 280.0, 1.5, [0.0, 0.07, 0.13, 0.24]],
	[5.60, 420.0, 250.0, 180.0, 0.8, [0.0, 0.07]],
	[5.68, 560.0, 320.0, 150.0, 0.6, [0.0, 0.06, 0.15]],
	[10.40, 1180.0, 200.0, 200.0, 0.7, [0.0, 0.08]],
	[14.00, 150.0, 150.0, 160.0, 0.6, [0.0, 0.06, 0.14]],
	[16.20, 1530.0, 300.0, 220.0, 0.8, [0.0, 0.07]],
]
## Background bolts: [start time, sketch x, pulses (seconds after start), peak, glow in the deck at
## the top (for strikes not under a deck flash), foot drift (sketch px)].
@export var bolt_table: Array = [
	[3.20, 380.0, [0.0, 0.06, 0.14], 1.0, true, -30.0],
	[5.62, 500.0, [0.0, 0.07], 0.9, false, 25.0],
	[7.80, 1300.0, [0.0, 0.05, 0.12], 0.9, true, 40.0],
	[10.42, 1180.0, [0.0, 0.08], 0.8, false, -20.0],
	[12.60, 760.0, [0.0, 0.06], 1.0, true, -35.0],
	[12.68, 880.0, [0.0, 0.07, 0.15], 0.9, true, 30.0],
	[16.22, 1600.0, [0.0, 0.07], 0.8, false, 20.0],
	[18.40, 230.0, [0.0, 0.05, 0.11, 0.2], 1.0, true, -25.0],
]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var land: DescentLand = $Land
@onready var trees: DescentTrees = $Trees
@onready var trail: IntroSpaceTrail = $Trail
@onready var head_star: MeshInstance3D = $HeadStar
@onready var flash_light: DirectionalLight3D = $FlashLight
@onready var bolts: DescentBolts = $Bolts
@onready var ruin: DescentRuin = $Camera3D/Ruin
@onready var shafts: DescentShafts = $Shafts
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var lightning := IntroSpaceLightning.new()
## The arc the head flies, in world space, and where along it the breach is (m).
var curve: Curve3D
var breach_offset := 0.0
## Shot time the head is at the arc's start (inside the deck).
var start_time := 0.0
var _done := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.global_transform = camera_transform()
	camera.fov = FOV
	curve = trail_curve()
	breach_offset = curve.get_closest_offset(breach_point())
	start_time = solve_start_time()
	_build_lightning()
	bolts.build(bolt_table, flash_decay)
	shafts.build(SHAFTS)
	shafts.material.set_shader_parameter(&"energy", shaft_energy)
	var look := composite()
	if look:
		look.light_uv = light_px / SKETCH_SIZE
	land.deck_material.set_shader_parameter(&"flash_opacity", flash_opacity)
	var eye := land.to_global(CAMERA_POSITION)
	land.deck_material.set_shader_parameter(&"eye_center", Vector2(eye.x, eye.z))
	land.deck_material.set_shader_parameter(&"spin_rate", cloud_edge_speed / deck_edge_distance())
	land.deck_material.set_shader_parameter(&"churn_rate", cloud_churn)
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


## Shows shot time `t`: trail, head star, lightning, the light it throws and the cloud motion.
func apply(t: float) -> void:
	# Drawn from the breach on: inside the deck the wide ribbon would poke through the billows.
	trail.update_trail(t, breach_time, ship_at, func(_tau: float) -> float: return 0.0,
			camera.global_position)
	head_star.visible = t >= breach_time
	head_star.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * head_star_size), head_at(t))
	(head_star.material_override as ShaderMaterial).set_shader_parameter(&"glint", head_star_rays)
	var live := lightning.active_at(t, 8)
	land.deck_material.set_shader_parameter(&"flashes", PackedVector4Array(live))
	land.deck_material.set_shader_parameter(&"cloud_time", t)
	trees.apply(t)
	flash_light.light_energy = flash_light_energy * flash_opacity * live[0].w
	flash_light.visible = live[0].w > 0.0
	bolts.apply(t)
	var bolt_peak := 0.0
	for b in bolts.brightness_at(t):
		bolt_peak = maxf(bolt_peak, b)
	var flash := maxf(flash_opacity * live[0].w, ruin_bolt_rim * bolt_peak)
	ruin.apply(t, flash)
	shafts.apply(t, flash)
	var look := composite()
	if look:
		look.flash = clampf(flash, 0.0, 1.0)
	land.curtain_material.set_shader_parameter(&"glows", PackedVector4Array(bolts.curtain_glows(t, 4)))
	land.curtain_material.set_shader_parameter(&"cloud_time", t)


## The shot's DepthComposite (the first effect on the WorldEnvironment's compositor), or null.
func composite() -> DepthComposite:
	var c := world_environment.compositor
	if c == null:
		return null
	for e in c.compositor_effects:
		if e is DepthComposite:
			return e
	return null


# --- the sketch ------------------------------------------------------------------------------

## The camera: at CAMERA_POSITION looking down -Z, pitched up so the horizon lands on HORIZON_PX.
static func camera_transform() -> Transform3D:
	var horizon_ndc := 1.0 - 2.0 * HORIZON_PX / SKETCH_SIZE.y
	var pitch := -atan(horizon_ndc * tan(deg_to_rad(FOV) * 0.5))
	return Transform3D(Basis(Vector3.RIGHT, pitch), CAMERA_POSITION)


## World direction of the ray through sketch pixel `px`.
static func sketch_dir(px: Vector2) -> Vector3:
	return camera_transform().basis * sketch_local(px).normalized()


## The camera-space ray through sketch pixel `px`, scaled to one metre deep (z = -1).
static func sketch_local(px: Vector2) -> Vector3:
	var tan_v := tan(deg_to_rad(FOV) * 0.5)
	var ndc := Vector2(2.0 * px.x / SKETCH_SIZE.x - 1.0, 1.0 - 2.0 * px.y / SKETCH_SIZE.y)
	return Vector3(ndc.x * tan_v * ASPECT, ndc.y * tan_v, -1.0)


## The point on the ray through `px` at `distance` metres horizontally from the camera.
static func sketch_point(px: Vector2, distance: float) -> Vector3:
	var d := sketch_dir(px)
	return CAMERA_POSITION + d * (distance / Vector2(d.x, d.z).length())


## The point on the ray through `px` at world height `y`.
static func sketch_at_height(px: Vector2, y: float) -> Vector3:
	var d := sketch_dir(px)
	return CAMERA_POSITION + d * ((y - CAMERA_POSITION.y) / d.y)


## Where world point `p` lands in sketch pixels (the inverse of sketch_dir).
static func to_sketch(p: Vector3) -> Vector2:
	var local := camera_transform().affine_inverse() * p
	var tan_v := tan(deg_to_rad(FOV) * 0.5)
	var ndc := Vector2(local.x / -local.z / (tan_v * ASPECT), local.y / -local.z / tan_v)
	return Vector2((ndc.x + 1.0) * 0.5 * SKETCH_SIZE.x, (1.0 - ndc.y) * 0.5 * SKETCH_SIZE.y)


## A polyline's y at sketch x, linearly between its points (clamped at the ends).
static func polyline_y(line: Array, x: float) -> float:
	if x <= line[0].x:
		return line[0].y
	for i in range(1, line.size()):
		if x <= line[i].x:
			var a: Vector2 = line[i - 1]
			var b: Vector2 = line[i]
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return line[line.size() - 1].y


## Mean horizontal distance (m) from the camera to the deck's front edge across the frame.
static func deck_edge_distance() -> float:
	var sum := 0.0
	var n := 0
	for x in range(0, int(SKETCH_SIZE.x) + 1, 50):
		var edge := sketch_at_height(Vector2(x, polyline_y(CLOUD_LINE, x)), DECK_BASE)
		sum += Vector2(edge.x - CAMERA_POSITION.x, edge.z - CAMERA_POSITION.z).length()
		n += 1
	return sum / n


## How much of the storm wall column `x` (sketch px) has: 1 on the left, 0 from SHELF_END_X on.
static func shelf_amount(x: float) -> float:
	return 1.0 - smoothstep(SHELF_FULL_X, SHELF_END_X, x)


## The deck's front edge at sketch x as a world point: the cloud line on the deck base, or on the
## left the storm wall's lip, pushed out toward SHELF_DISTANCE and brought down toward SHELF_LINE
## (never above the deck base).
static func deck_edge_point(x: float) -> Vector3:
	var flat := sketch_at_height(Vector2(x, polyline_y(CLOUD_LINE, x)), DECK_BASE)
	var k := shelf_amount(x)
	if k <= 0.0:
		return flat
	var dist := lerpf(Vector2(flat.x - CAMERA_POSITION.x, flat.z - CAMERA_POSITION.z).length(), SHELF_DISTANCE, k)
	var lip := sketch_point(Vector2(x, polyline_y(SHELF_LINE, x)), dist)
	if lip.y <= DECK_BASE:
		return lip
	var d := sketch_dir(Vector2(x, polyline_y(SHELF_LINE, x))) * Vector3(1, 0, 1)
	return CAMERA_POSITION * Vector3(1, 0, 1) + d.normalized() * dist + Vector3(0.0, DECK_BASE, 0.0)


## Where the deck's front edge lands on screen at sketch x (sketch px y).
static func lip_y(x: float) -> float:
	return to_sketch(deck_edge_point(x)).y


# --- the trail -------------------------------------------------------------------------------

## World position of TRAIL_ARC point `i`.
static func trail_point(i: int) -> Vector3:
	return sketch_point(TRAIL_ARC[i][0], TRAIL_ARC[i][1])


## The arc: one Bezier segment from the start to Finish, baked every 2 m.
static func trail_curve() -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 2.0
	var p0 := trail_point(0)
	var p3 := trail_point(3)
	c.add_point(p0, Vector3.ZERO, trail_point(1) - p0)
	c.add_point(p3, trail_point(2) - p3, Vector3.ZERO)
	return c


## Where the arc crosses the deck base: the breach.
static func breach_point() -> Vector3:
	var p := [trail_point(0), trail_point(1), trail_point(2), trail_point(3)]
	var lo := 0.0
	var hi := 1.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _bezier(p, mid).y > DECK_BASE:
			lo = mid
		else:
			hi = mid
	return _bezier(p, (lo + hi) * 0.5)


static func _bezier(p: Array, t: float) -> Vector3:
	return (p[0] as Vector3).bezier_interpolate(p[1], p[2], p[3], t)


## How far along the arc (0..1 of `u`, the time fraction from start_time to the cut) the head is.
func progress(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u + speed_ease * (u - u * u)


## Solves start_time so the head is exactly at the breach at breach_time.
func solve_start_time() -> float:
	var fb := breach_offset / curve.get_baked_length()
	var u := fb
	if speed_ease > 0.0:
		var k := speed_ease
		u = ((1.0 + k) - sqrt((1.0 + k) * (1.0 + k) - 4.0 * k * fb)) / (2.0 * k)
	var end := shot_length()
	return (breach_time - u * end) / (1.0 - u)


## The trail head (the unseen ship) at shot time `t`.
func head_at(t: float) -> Vector3:
	var u := (t - start_time) / (shot_length() - start_time)
	return curve.sample_baked(progress(u) * curve.get_baked_length(), true)


## For the trail: the "ship" at shot time `tau`. One nozzle at its origin.
func ship_at(tau: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, head_at(tau))


# --- lightning -------------------------------------------------------------------------------

func _build_lightning() -> void:
	lightning.flashes.clear()
	lightning.decay = flash_decay
	for row: Array in flash_table:
		var f := IntroSpaceLightning.Flash.new()
		f.start = row[0]
		var at: Vector3
		if row[1] < 0.0:
			at = breach_point()
		else:
			at = deck_point(row[1], row[2])
		f.pos = Vector2(at.x, at.z)
		f.radius = row[3]
		f.peak = row[4]
		f.pulses = PackedFloat32Array(row[5])
		lightning.flashes.append(f)
	# A small glow in the deck over each standalone bolt, where it leaves the cloud.
	for row: Array in bolt_table:
		if not row[4]:
			continue
		var g := IntroSpaceLightning.Flash.new()
		g.start = row[0]
		var top := deck_point(row[1], 120.0)
		g.pos = Vector2(top.x, top.z)
		g.radius = 110.0
		g.peak = 0.5 * float(row[3])
		g.pulses = PackedFloat32Array(row[2])
		lightning.flashes.append(g)


## A point `inward` metres into the deck from its front edge at sketch x, toward the camera.
static func deck_point(x: float, inward: float) -> Vector3:
	var edge := deck_edge_point(x)
	var toward_cam := (CAMERA_POSITION - edge) * Vector3(1, 0, 1)
	return edge + toward_cam.normalized() * inward


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
