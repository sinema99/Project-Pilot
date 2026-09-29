class_name Pilot9Vfx
extends Node3D

## pilot9's movement effects: grind sparks and their light, the ground-jump dust, the
## double-jump air burst and the landing dust; and pass 2's speed lasers, slide sparks, wall-run
## scuffs, wall-jump kick, hand taps and sprint kicks. See docs/specs/pilot9-movement-vfx.md.
##
## The pilot decides WHEN (the jump branches, the landing hand-off, the rail catch) and calls
## one of the five verbs below; this node decides what it looks like. Every dial is read off
## the pilot at the moment of use, so they tune live in the Inspector like the dash streak's.
##
## Built in code by the pilot's _ready(), so a rebuild of pilot9.tscn cannot lose it. No image
## files: every texture is a gradient made here.

## The pilot whose "Movement Effects" exports this reads. Untyped - the pilot has no class_name.
var pilot: Node

## Bursts are thrown clear of the pilot (top_level) and freed this long after their lifetime,
## by timer rather than `finished`: the dummy renderer never finishes a particle system.
const FREE_MARGIN := 0.5
## Stations along a laser bolt - enough for its spindle to read as a curve, not a diamond.
const LASER_STATIONS := 7
## Re-rolls a bolt gets to find an angle clear of the camera before that one is skipped.
const LASER_TRIES := 8
## How flat the cone is: its vertical reach as a fraction of its sideways one, so the low
## bolts stay out of the floor and the high ones out of the sky over his head.
const LASER_SQUASH := 0.7
## The fraction of a bolt's life it stretches over, and the fraction it fades in over.
const LASER_GROW := 0.4
const LASER_FADE_IN := 0.1
## Every system is culled against this box, not a computed one. Bursts are small and short;
## a box too big costs nothing, one too small pops sparks out at the screen edge.
const VISIBILITY := AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))

var _grind: GPUParticles3D = null
var _grind_mat: ParticleProcessMaterial = null
var _light: OmniLight3D = null
var _flicker := 1.0

var _slide: GPUParticles3D = null
var _slide_mat: ParticleProcessMaterial = null
var _slide_light: OmniLight3D = null
var _slide_flicker := 1.0
var _lasers: MeshInstance3D = null
var _lasers_mesh: ImmediateMesh = null
var _lasers_mat: StandardMaterial3D = null
var _lasers_active := false
## Bolts owed but not yet fired - the rate is a fraction of a bolt a tick.
var _laser_owed := 0.0
## Each live bolt: {from, dir, age, life, speed, length, width, alpha}. World space - fired,
## a bolt stays on its line whatever he does next.
var _bolts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _wall: GPUParticles3D = null
var _wall_mat: ParticleProcessMaterial = null

var _puff_tex: Texture2D = null
var _spark_tex: Texture2D = null
var _ring_tex: Texture2D = null

func _ready() -> void:
	_puff_tex = _radial([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	# A hard white core and a short glow - stretched along its velocity, a streak.
	_spark_tex = _radial([0.0, 0.35, 1.0],
		[Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	# Clear middle, a bright band near the edge, soft on both sides of it.
	_ring_tex = _radial([0.0, 0.62, 0.82, 1.0],
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_build_grind()
	_build_slide()
	_build_lasers()
	_build_wall()

# --- the five verbs --------------------------------------------------------------

## A floor jump: the low dust ring spreading flat from his feet.
func ground_jump(feet: Vector3) -> void:
	var p := _dust_burst("GroundJumpDust", pilot.vfx_jump_dust_count, pilot.vfx_dust_speed,
		pilot.vfx_dust_lifetime, Vector3.ZERO, 0.0)
	_fire(p, Transform3D(Basis.IDENTITY, feet))

## The double jump: a flat air ring expanding under him plus wind streaks shooting down.
func double_jump(feet: Vector3) -> void:
	_fire(_air_ring(), Transform3D(Basis.IDENTITY, feet))
	_fire(_air_streaks(), Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.1))

## A landing. `strength` is the dust curve's 0..1 (0.5 = a full jump); `facing` is flat, his
## side puffs go out either side of it. A non-zero `skew` (flat, metres per second) is the
## slide's backward trail, added to every puff.
func land(feet: Vector3, strength: float, facing: Vector3, skew: Vector3) -> void:
	if strength <= 0.0:
		return
	var side := facing.cross(Vector3.UP).normalized()
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	# Up to 0.5 the side puffs grow to full; the ring only exists above it.
	var sides := clampf(strength / 0.5, 0.0, 1.0)
	var count := maxi(int(round(pilot.vfx_land_side_count * sides)), 1)
	var spd: float = pilot.vfx_dust_speed * lerpf(0.6, 1.0, sides)
	for s in [side, -side]:
		var p := _dust_burst("LandingDust", count, spd, pilot.vfx_dust_lifetime, s, 20.0, skew)
		_fire(p, Transform3D(Basis.IDENTITY, feet))
	var ring := clampf((strength - 0.5) / 0.5, 0.0, 1.0)
	if ring > 0.0:
		var p := _dust_burst("LandingDust", maxi(int(round(pilot.vfx_land_ring_count * ring)), 2),
			pilot.vfx_dust_speed * lerpf(1.0, 1.8, ring),
			pilot.vfx_dust_lifetime * lerpf(1.2, 2.0, ring), Vector3.ZERO, 0.0, skew)
		_fire(p, Transform3D(Basis.IDENTITY, feet))

## A rail contact: the heavy catch shower, or the smaller switch landing burst. `backward` is
## against his travel.
func rail_contact(feet: Vector3, backward: Vector3, heavy: bool) -> void:
	var count: int = pilot.vfx_spark_catch_count if heavy else pilot.vfx_spark_switch_count
	if count <= 0:
		return
	var p := _spark_particles("RailSparkBurst", count, pilot.vfx_spark_lifetime * 1.3, 1.0)
	var mat := _spark_process(pilot.vfx_spark_speed * 1.2)
	# Wider and more upward than the stream - the hit throws them everywhere.
	mat.direction = Vector3(0.0, 0.8, 1.0).normalized()
	mat.spread = 60.0
	p.process_material = mat
	_fire(p, Transform3D(_basis_facing(backward), feet))

## Every physics frame. `gear` is 0 at the grind gear and 1 at the sprint gear; the stream is
## denser and sprays harder up it. Inactive, the stream stops emitting (sparks in flight
## finish) and the light goes out.
func grind(active: bool, feet: Vector3, backward: Vector3, gear: float) -> void:
	if _grind == null:
		return
	_grind.emitting = active
	_light.visible = active
	if not active:
		return
	gear = clampf(gear, 0.0, 1.0)
	_grind.global_transform = Transform3D(_basis_facing(backward), feet)
	_grind.amount_ratio = lerpf(pilot.vfx_spark_grind_density, 1.0, gear)
	var spd: float = pilot.vfx_spark_speed * lerpf(pilot.vfx_spark_grind_speed, 1.0, gear)
	_grind_mat.initial_velocity_min = spd * 0.6
	_grind_mat.initial_velocity_max = spd
	_grind_mat.color = pilot.vfx_spark_color
	# Eased toward a fresh random target every frame: a flicker, not a strobe.
	_flicker = lerpf(_flicker, randf_range(0.55, 1.25), 0.35)
	_light.light_color = pilot.vfx_spark_color
	_light.light_energy = pilot.vfx_spark_light_energy * _flicker
	_light.omni_range = pilot.vfx_spark_light_range
	_light.global_position = feet + Vector3.UP * 0.25

## Whether the grind stream is running - for the tests.
func is_grinding() -> bool:
	return _grind != null and _grind.emitting

## The light, for the tests.
func grind_light() -> OmniLight3D:
	return _light

# --- pass 2 -----------------------------------------------------------------------

## Every physics frame. The speed lasers: bolts fired backward out of a ring round his `chest`,
## flaring outward. `backward` is his travel reversed, `strength` 0 at the lasers' on-speed and
## 1 at full, `ease` the 0..1 ease-in (it thins the rate), `travel` his velocity and `eye` the
## camera, so no bolt is fired down the lens. The pilot has already applied the on/off
## hysteresis and the dash exception. Inactive, nothing new fires; live bolts run out.
func lasers(active: bool, chest: Vector3, backward: Vector3, strength: float, ease: float,
		travel: Vector3, eye: Vector3, delta: float) -> void:
	if _lasers == null:
		return
	_lasers_active = active
	if not active or backward.length() < 0.001:
		_laser_owed = 0.0
		return
	strength = clampf(strength, 0.0, 1.0)
	var rate: float = lerpf(pilot.vfx_laser_rate_min, pilot.vfx_laser_rate_max, strength)
	_laser_owed += rate * clampf(ease, 0.0, 1.0) * delta
	while _laser_owed >= 1.0:
		_laser_owed -= 1.0
		_fire_bolt(chest, backward.normalized(), strength, travel, eye)

## One bolt at a random angle round the ring - re-rolled while its flight would come within
## vfx_laser_camera_clear of the lens, and skipped if every roll does.
func _fire_bolt(chest: Vector3, back: Vector3, strength: float, travel: Vector3,
		eye: Vector3) -> void:
	var basis := _basis_facing(back)
	var flare := deg_to_rad(lerpf(pilot.vfx_laser_flare_min, pilot.vfx_laser_flare_max, strength))
	var centre: Vector3 = chest + back * pilot.vfx_laser_behind
	var life: float = pilot.vfx_laser_lifetime * _rng.randf_range(0.85, 1.15)
	var length: float = lerpf(pilot.vfx_laser_length_min, pilot.vfx_laser_length_max, strength) \
		* _rng.randf_range(0.7, 1.15)
	var speed: float = pilot.vfx_laser_speed * _rng.randf_range(0.85, 1.15)
	for _try in LASER_TRIES:
		var a := _rng.randf() * TAU
		var out: Vector3 = basis * Vector3(cos(a), sin(a) * LASER_SQUASH, 0.0)
		var bolt := {
			from = centre + out * pilot.vfx_laser_ring_radius,
			dir = (back + out * tan(flare)).normalized(),
			age = 0.0, life = life, speed = speed, length = length,
			width = pilot.vfx_laser_width * _rng.randf_range(0.6, 1.2),
			alpha = _rng.randf_range(0.6, 1.0) * lerpf(pilot.vfx_laser_min_opacity, 1.0, strength),
		}
		if _bolt_clears(bolt, travel, eye, pilot.vfx_laser_camera_clear):
			_bolts.append(bolt)
			return

## Whether `bolt`, over its whole life, keeps `clear` metres off a camera that starts at `eye`
## and rides along at `travel`. Sampled; static and pure.
static func _bolt_clears(bolt: Dictionary, travel: Vector3, eye: Vector3, clear: float) -> bool:
	if not eye.is_finite():
		return true
	for s in 9:
		var age: float = bolt.life * s / 8.0
		var cam := eye + travel * age
		var span := _bolt_span(bolt, age)
		var near := Geometry3D.get_closest_point_to_segment(cam, span[0], span[1])
		if near.distance_to(cam) < clear:
			return false
	return true

## Tail and head of `bolt` at `age`: the head flies out from where it was fired, and the bolt
## stretches to full length over the first LASER_GROW of its life, its tail never behind the
## firing point. Static and pure.
static func _bolt_span(bolt: Dictionary, age: float) -> PackedVector3Array:
	var run: float = bolt.speed * age
	var grow := clampf(age / maxf(bolt.life * LASER_GROW, 0.001), 0.0, 1.0)
	var length := minf(bolt.length * grow, run)
	var head: Vector3 = bolt.from + bolt.dir * run
	return PackedVector3Array([head - bolt.dir * length, head])

## Whether new bolts are firing - for the tests.
func is_firing() -> bool:
	return _lasers != null and _lasers_active

## Every live bolt's tail and head, world space - for the tests.
func bolt_spans() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for b in _bolts:
		out.append(_bolt_span(b, b.age))
	return out

func _process(delta: float) -> void:
	if _lasers == null:
		return
	for b in _bolts:
		b.age += delta
	_bolts = _bolts.filter(func(b: Dictionary) -> bool: return b.age < b.life)
	_draw_lasers()

## Each bolt as a camera-facing spindle: pointed at both ends, widest and brightest in the
## middle, fading in fast and out over the back half of its life. One surface for them all.
func _draw_lasers() -> void:
	_lasers_mesh.clear_surfaces()
	if _bolts.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var col: Color = pilot.vfx_laser_color
	var drawn := 0
	for b in _bolts:
		var span := _bolt_span(b, b.age)
		if span[0].distance_to(span[1]) < 0.01:
			continue
		if drawn == 0:
			_lasers_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _lasers_mat)
		drawn += 1
		var k: float = b.age / b.life
		var fade: float = minf(k / LASER_FADE_IN, 1.0) * (1.0 - smoothstep(0.5, 1.0, k))
		var eye: Vector3 = (cam.global_position - span[1]) if cam else Vector3.UP
		var side: Vector3 = (b.dir as Vector3).cross(eye).normalized() * b.width * 0.5
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_c := Color()
		for j in LASER_STATIONS:
			var t := float(j) / (LASER_STATIONS - 1)
			var bulge := pow(sin(PI * t), 0.8)
			var p := span[0].lerp(span[1], t)
			var c := Color(col.r, col.g, col.b, col.a * b.alpha * fade * (0.5 + 0.5 * bulge))
			var l := p + side * bulge
			var r := p - side * bulge
			if j > 0:
				_bolt_quad(prev_l, prev_r, l, r, prev_c, c)
			prev_l = l
			prev_r = r
			prev_c = c
	if drawn > 0:
		_lasers_mesh.surface_end()

## Two triangles from one station pair to the next, UV across the strip for the soft edge.
func _bolt_quad(al: Vector3, ar: Vector3, bl: Vector3, br: Vector3, ca: Color,
		cb: Color) -> void:
	for v in [[al, 0.0, ca], [ar, 1.0, ca], [bl, 0.0, cb], [ar, 1.0, ca], [br, 1.0, cb],
			[bl, 0.0, cb]]:
		_lasers_mesh.surface_set_color(v[2])
		_lasers_mesh.surface_set_uv(Vector2(v[1], 0.5))
		_lasers_mesh.surface_add_vertex(v[0])

## Every physics frame. The grind stream's twin: `strength` 0 is the thin end, 1 the heavy.
func slide(active: bool, foot: Vector3, backward: Vector3, strength: float) -> void:
	if _slide == null:
		return
	_slide.emitting = active
	_slide_light.visible = active
	if not active:
		return
	strength = clampf(strength, 0.0, 1.0)
	_slide.global_transform = Transform3D(_basis_facing(backward), foot)
	_slide.amount_ratio = lerpf(pilot.vfx_spark_grind_density * 0.6, 1.0, strength)
	var spd: float = pilot.vfx_spark_speed \
		* lerpf(pilot.vfx_spark_grind_speed * 0.8, 1.0, strength)
	_slide_mat.initial_velocity_min = spd * 0.6
	_slide_mat.initial_velocity_max = spd
	_slide_mat.color = pilot.vfx_spark_color
	_slide_flicker = lerpf(_slide_flicker, randf_range(0.55, 1.25), 0.35)
	_slide_light.light_color = pilot.vfx_spark_color
	_slide_light.light_energy = pilot.vfx_spark_light_energy * pilot.vfx_slide_light_scale \
		* _slide_flicker
	_slide_light.omni_range = pilot.vfx_spark_light_range
	_slide_light.global_position = foot + Vector3.UP * 0.25

## Whether the slide stream is running - for the tests.
func is_slide_sparking() -> bool:
	return _slide != null and _slide.emitting

## The slide's light, for the tests.
func slide_light() -> OmniLight3D:
	return _slide_light

## A slide's first frame: a light shower off the leading foot.
func slide_start(foot: Vector3, backward: Vector3) -> void:
	var count: int = pilot.vfx_slide_entry_count
	if count <= 0:
		return
	var p := _spark_particles("SlideSparkBurst", count, pilot.vfx_spark_lifetime, 1.0)
	var mat := _spark_process(pilot.vfx_spark_speed)
	mat.direction = Vector3(0.0, 0.5, 1.0).normalized()
	mat.spread = 40.0
	p.process_material = mat
	_fire(p, Transform3D(_basis_facing(backward), foot))

## Every physics frame. `foot` is on the wall face at his foot height, `normal` points off it,
## `fade` is 1 through the run and falls to 0 across the droop.
func wall_run(active: bool, foot: Vector3, normal: Vector3, fade: float) -> void:
	if _wall == null:
		return
	fade = clampf(fade, 0.0, 1.0)
	_wall.emitting = active and fade > 0.0
	if not _wall.emitting:
		return
	_wall.global_transform = Transform3D(Basis.IDENTITY, foot + normal * 0.05)
	_wall.amount_ratio = fade
	_wall_mat.direction = (normal + Vector3.UP * 0.2).normalized()
	_wall_mat.color = pilot.vfx_dust_color

## Whether the wall trail is running - for the tests.
func is_scuffing() -> bool:
	return _wall != null and _wall.emitting

## Attaching to a wall: a small puff on the face where he lands on it.
func wall_attach(foot: Vector3, normal: Vector3) -> void:
	var p := _dust_burst("WallAttachDust", maxi(pilot.vfx_wall_kick_count / 2, 1),
		pilot.vfx_dust_speed * 0.7, pilot.vfx_dust_lifetime, Vector3.ZERO, 0.0, Vector3.ZERO,
		normal)
	_fire(p, Transform3D(Basis.IDENTITY, foot + normal * 0.05))

## A wall jump: the jump ring laid flat on the face, and a puff out along the normal.
func wall_jump(foot: Vector3, normal: Vector3) -> void:
	var count: int = pilot.vfx_wall_kick_count
	var ring := _dust_burst("WallKickDust", count, pilot.vfx_dust_speed,
		pilot.vfx_dust_lifetime, Vector3.ZERO, 0.0, Vector3.ZERO, normal)
	_fire(ring, Transform3D(Basis.IDENTITY, foot + normal * 0.05))
	var out := _dust_burst("WallKickDust", maxi(count / 2, 1), pilot.vfx_dust_speed * 1.2,
		pilot.vfx_dust_lifetime, normal, 25.0)
	_fire(out, Transform3D(Basis.IDENTITY, foot + normal * 0.05))

## Hands going down on a lip or a top: one tiny tap under each point.
func hand_taps(points: Array) -> void:
	for pt: Vector3 in points:
		var p := _dust_burst("HandTap", pilot.vfx_hand_tap_count, pilot.vfx_dust_speed * 0.5,
			pilot.vfx_hand_tap_lifetime, Vector3.ZERO, 0.0, Vector3.ZERO, Vector3.UP, 0.25)
		_fire(p, Transform3D(Basis.IDENTITY, pt + Vector3.UP * 0.03))

## Breaking into a sprint: a short dust kick thrown back from his feet. `dir` is backward.
func sprint_kick(feet: Vector3, dir: Vector3) -> void:
	var p := _dust_burst("SprintKick", pilot.vfx_sprint_kick_count, pilot.vfx_dust_speed,
		pilot.vfx_dust_lifetime, dir, 35.0)
	_fire(p, Transform3D(Basis.IDENTITY, feet))

## A hard cut at speed: a skid thrown along `dir`, the way he WAS going.
func skid(feet: Vector3, dir: Vector3) -> void:
	var p := _dust_burst("SkidDust", pilot.vfx_skid_count, pilot.vfx_dust_speed * 1.4,
		pilot.vfx_dust_lifetime * 1.3, dir, 30.0)
	_fire(p, Transform3D(Basis.IDENTITY, feet))

# --- the systems ------------------------------------------------------------------

## The persistent grind stream. World-space particles, so what he leaves behind stays put and
## a fast ride draws a trail.
func _build_grind() -> void:
	var rate: float = pilot.vfx_spark_rate
	var life: float = pilot.vfx_spark_lifetime
	_grind = _spark_particles("GrindSparks", maxi(int(ceil(rate * life)), 1), life, 0.0)
	_grind.one_shot = false
	_grind.emitting = false
	_grind_mat = _spark_process(pilot.vfx_spark_speed)
	_grind.process_material = _grind_mat
	_grind.top_level = true
	_grind.set_meta(&"persistent", true)
	add_child(_grind)

	_light = OmniLight3D.new()
	_light.name = "GrindLight"
	_light.top_level = true
	_light.shadow_enabled = false
	_light.visible = false
	_light.light_color = pilot.vfx_spark_color
	_light.omni_range = pilot.vfx_spark_light_range
	_light.set_meta(&"persistent", true)
	add_child(_light)

## The slide's stream: the grind stream's twin, with its own dimmer light.
func _build_slide() -> void:
	var rate: float = pilot.vfx_spark_rate
	var life: float = pilot.vfx_spark_lifetime
	_slide = _spark_particles("SlideSparks", maxi(int(ceil(rate * life)), 1), life, 0.0)
	_slide.one_shot = false
	_slide.emitting = false
	_slide_mat = _spark_process(pilot.vfx_spark_speed)
	_slide.process_material = _slide_mat
	_slide.top_level = true
	_slide.set_meta(&"persistent", true)
	add_child(_slide)

	_slide_light = OmniLight3D.new()
	_slide_light.name = "SlideLight"
	_slide_light.top_level = true
	_slide_light.shadow_enabled = false
	_slide_light.visible = false
	_slide_light.set_meta(&"persistent", true)
	add_child(_slide_light)

## The speed lasers: every live bolt drawn fresh each frame into one ImmediateMesh in world
## space. Soft across its width (the texture), added on so it glows.
func _build_lasers() -> void:
	_lasers_mesh = ImmediateMesh.new()
	_lasers = MeshInstance3D.new()
	_lasers.name = "SpeedLasers"
	_lasers.mesh = _lasers_mesh
	_lasers.top_level = true
	_lasers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var across := GradientTexture2D.new()
	across.width = 32
	across.height = 1
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	across.gradient = g
	_lasers_mat = _material(across, true, BaseMaterial3D.BILLBOARD_DISABLED)
	_lasers.set_meta(&"persistent", true)
	add_child(_lasers)

## The wall-run trail: soft dust puffs left on the face, drifting out off it.
func _build_wall() -> void:
	var rate: float = pilot.vfx_wall_dust_rate
	var life: float = pilot.vfx_dust_lifetime * 1.5
	_wall = _particles("WallDust", maxi(int(ceil(rate * life)), 1), life, 0.0)
	_wall.one_shot = false
	_wall.emitting = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.06
	m.direction = Vector3.RIGHT
	m.spread = 30.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.1
	m.gravity = Vector3.ZERO
	m.damping_min = 1.5
	m.damping_max = 2.5
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.6
	m.scale_max = 0.9
	m.scale_curve = _curve([Vector2(0.0, 0.4), Vector2(0.3, 1.0), Vector2(1.0, 1.3)])
	m.color = pilot.vfx_dust_color
	m.color_ramp = _fade([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	_wall_mat = m
	_wall.process_material = m
	_wall.draw_pass_1 = _quad(Vector2(0.3, 0.3), _material(_puff_tex, false,
		BaseMaterial3D.BILLBOARD_PARTICLES))
	_wall.top_level = true
	_wall.set_meta(&"persistent", true)
	add_child(_wall)

## A spark's process material: sprayed along the emitter's +Z (backward) and a little up,
## fanned, falling, shrinking to nothing.
func _spark_process(speed: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.08
	m.direction = Vector3(0.0, 0.35, 1.0).normalized()
	m.spread = 25.0
	m.initial_velocity_min = speed * 0.6
	m.initial_velocity_max = speed
	m.gravity = Vector3(0.0, -14.0, 0.0)
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = 0.6
	m.scale_max = 1.0
	m.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	m.color = pilot.vfx_spark_color
	m.color_ramp = _fade([Color(1.6, 1.4, 1.0, 1.0), Color(1, 1, 1, 1), Color(0.8, 0.4, 0.2, 0.0)])
	return m

## A one-shot ring of dust puffs spreading flat from the feet. `dir` non-zero aims them into a
## cone `spread` degrees wide instead (the landing's side puffs); `skew` is added to every puff.
## `axis` is the ring's: up lies it on the floor, a wall normal lays it on the face. `size` is a
## puff's metres across, and the ring scales with it.
func _dust_burst(name_: String, count: int, speed: float, life: float, dir: Vector3,
		spread: float, skew: Vector3 = Vector3.ZERO, axis: Vector3 = Vector3.UP,
		size: float = 0.45) -> GPUParticles3D:
	var p := _particles(name_, maxi(count, 1), life, 1.0)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = axis.normalized() if axis != Vector3.ZERO else Vector3.UP
	m.emission_ring_radius = 0.25 * size / 0.45
	m.emission_ring_inner_radius = 0.15 * size / 0.45
	m.emission_ring_height = 0.0
	m.gravity = Vector3.ZERO
	if dir == Vector3.ZERO:
		# Straight out from the ring's centre.
		m.radial_velocity_min = speed * 0.7
		m.radial_velocity_max = speed
		m.direction = m.emission_ring_axis
		m.spread = 0.0
		m.initial_velocity_min = 0.2
		m.initial_velocity_max = 0.5
	else:
		m.direction = (dir + Vector3.UP * 0.15).normalized()
		m.spread = spread
		m.initial_velocity_min = speed * 0.7
		m.initial_velocity_max = speed
	if skew != Vector3.ZERO:
		# The trail: a constant pull the damping cannot eat, so the puffs drift back after they
		# stop spreading.
		m.gravity = skew * 2.0
	m.damping_min = speed * 1.5
	m.damping_max = speed * 2.5
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.8
	m.scale_max = 1.2
	m.scale_curve = _curve([Vector2(0.0, 0.4), Vector2(0.3, 1.0), Vector2(1.0, 1.4)])
	m.color = pilot.vfx_dust_color
	m.color_ramp = _fade([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	p.process_material = m
	p.draw_pass_1 = _quad(Vector2(size, size), _material(_puff_tex, false,
		BaseMaterial3D.BILLBOARD_PARTICLES))
	return p

## The double jump's flat ring: one particle, lying in the ground plane, growing to
## `vfx_air_ring_size` metres across and fading.
func _air_ring() -> GPUParticles3D:
	var life: float = pilot.vfx_air_lifetime
	var p := _particles("DoubleJumpRing", 1, life, 1.0)
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 0.0
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.0
	m.gravity = Vector3.ZERO
	m.scale_curve = _curve([Vector2(0.0, 0.25), Vector2(0.4, 0.85), Vector2(1.0, 1.0)])
	m.color = pilot.vfx_air_color
	m.color_ramp = _fade([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.process_material = m
	var size: float = pilot.vfx_air_ring_size
	var quad := _quad(Vector2(size, size), _material(_ring_tex, true,
		BaseMaterial3D.BILLBOARD_DISABLED))
	quad.orientation = PlaneMesh.FACE_Y
	p.draw_pass_1 = quad
	return p

## The double jump's wind: short streaks shot downward and out, drawn along their velocity.
func _air_streaks() -> GPUParticles3D:
	var life: float = pilot.vfx_air_lifetime * 0.8
	var p := _particles("DoubleJumpWind", maxi(pilot.vfx_air_streaks, 1), life, 1.0)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = 0.3
	m.emission_ring_inner_radius = 0.1
	m.emission_ring_height = 0.0
	m.direction = Vector3.DOWN
	m.spread = 30.0
	m.initial_velocity_min = 6.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3.ZERO
	m.damping_min = 10.0
	m.damping_max = 14.0
	m.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.3)])
	m.color = pilot.vfx_air_color
	m.color_ramp = _fade([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.process_material = m
	p.draw_pass_1 = _quad(Vector2(0.06, 0.7), _material(_spark_tex, true,
		BaseMaterial3D.BILLBOARD_DISABLED))
	return p

## The bones of every system here. `explosiveness` 1 is a burst, 0 a stream.
func _particles(name_: String, amount: int, life: float, explosiveness: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name_
	p.amount = amount
	p.lifetime = maxf(life, 0.01)
	p.one_shot = true
	p.explosiveness = explosiveness
	p.local_coords = false
	p.visibility_aabb = VISIBILITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## A spark system: thin streaks drawn along their velocity, facing the camera, added on.
func _spark_particles(name_: String, amount: int, life: float,
		explosiveness: float) -> GPUParticles3D:
	var p := _particles(name_, amount, life, explosiveness)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.draw_pass_1 = _quad(Vector2(0.035, 0.28), _material(_spark_tex, true,
		BaseMaterial3D.BILLBOARD_DISABLED))
	return p

## Puts a one-shot burst into the world where it happened and schedules its end.
func _fire(p: GPUParticles3D, xform: Transform3D) -> void:
	p.top_level = true
	# Readable names: two bursts alive at once are LandingDust and LandingDust2, not an @-name.
	add_child(p, true)
	p.global_transform = xform
	p.emitting = true
	if is_inside_tree():
		get_tree().create_timer(p.lifetime + FREE_MARGIN).timeout.connect(p.queue_free)

# --- small builders ---------------------------------------------------------------

## A basis whose +Z is `backward`, slope and all - a sloped rail sprays along its slope. Y
## stays as close to up as that allows.
static func _basis_facing(backward: Vector3) -> Basis:
	var z := backward.normalized()
	if z == Vector3.ZERO or absf(z.dot(Vector3.UP)) > 0.999:
		return Basis.IDENTITY
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, z.cross(x), z)

static func _radial(offsets: Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t

static func _fade(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / maxf(colors.size() - 1, 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t

static func _quad(size: Vector2, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	return q

## Unlit, textured, tinted by the particle colour. Additive is the glow - sparks and air;
## dust is plain alpha so it can darken what is behind it.
static func _material(tex: Texture2D, additive: bool, billboard: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
