class_name CockpitReentry
extends Node

# Drives the cockpit's atmosphere pass from the shot time: shakes the seat (and the pilot with it),
# trembles the camera, throws his spine and head, trails the hologram panels behind the seat, flares
# the fire, blinks the seat's lamps, drifts a second fire light and fires the sparks on the big jolt.
# The motion itself is CockpitShake (pure); this node only applies it. See
# docs/specs/cutscene-cockpit.md, "Atmosphere pass".
#
# The jolts are method keys (`jolt(strength)`) on the shot animation's track for this node: drag them
# in the editor to retime. They are read once on ready. So are the ending's two keys, `warning()`
# (the WARNING pops up and he flicks it away) and `push()` (both sticks forward); the motion between
# is CockpitBeats, timed by the "Ending" exports. See "Ending: warning swipe and push" in the spec.

@export var animation_player: AnimationPlayer
@export var seat: CockpitSeat
@export var pose: SeatedPose
@export var camera: Camera3D
@export var holo: CockpitHolo
@export var fire: ReentryFire
## The second, softer fire light that drifts across him and the seat.
@export var drift_light: OmniLight3D
## The strongest jolt throws a spark burst from here (seat space: the camera-side console seam)...
@export var spark_point := Vector3(0.45, 0.6, 0.06)
## ...this way, out of the console and up.
@export var spark_direction := Vector3(1.0, 0.7, 0.2)
@export var spark_count := 70

@export_group("Shake")
## Buzz at its peak: millimetres and degrees.
@export var buzz_mm := 5.0
@export var buzz_degrees := 0.4
## A strength-1.0 jolt's kick: centimetres and degrees.
@export var kick_cm := 5.0
@export var kick_degrees := 3.0
## Seconds for a jolt to settle on the seat.
@export var settle := 0.3
## The camera's share of the seat's shake.
@export_range(0.0, 1.0) var camera_share := 0.1
## His head swings this many times the seat's kick, opposite it.
@export var body_throw := 1.5

@export_group("Ending")
## Seconds from the warning to the hand leaving the stick.
@export var react := 1.0
@export var reach := 0.22
## The flick across, contact to gone.
@export var flick := 0.25
@export var hang := 0.15
## Hand back to the stick.
@export var hand_back := 0.45
## The flinch guard on the warning: the left wrist (seat space, in front of his left shoulder), snapped up
## with the head over guard_in with this share of overshoot, held until the swipe leaves from it.
@export var guard_point := Vector3(0.26, 1.0, 0.2)
@export var guard_in := 0.12
@export var guard_overshoot := 0.1
@export var push_duration := 0.25
@export var stick_degrees := 20.0
## The push lean: wind-up over `windup` before the key to windup_lean, push_lean with the sticks,
## pressed back to pushback_lean over `pushback` when the ship answers. Head tucked during it.
@export var windup := 0.3
@export var windup_lean_degrees := 18.0
@export var push_lean_degrees := 22.0
@export var pushback := 0.3
@export var pushback_lean_degrees := 12.0
@export var head_tuck_degrees := 8.0
@export var torso_turn_degrees := 5.0
## The ship answers the push this long after it starts...
@export var answer_delay := 0.2
## ...with the fire's flow this many times faster...
@export var answer_flow := 1.5
## ...and this much extra heat on the screen, held.
@export var answer_heat := 0.45
## The cartoon "!" he gets when the warning pops: in with the head snap, overshoots, hard-cuts out.
@export var startle_pop := 0.1
@export var startle_hold := 0.55
@export var startle_overshoot := 1.3
## The "!"'s height, metres.
@export var startle_height := 0.2
## Seat space off the Head bone: up and out to his right, away from the warning.
@export var startle_offset := Vector3(-0.3, 0.16, 0.05)
## Its hop up during the pop, metres.
@export var startle_bounce := 0.04
## Its top leans this far away from his head, on screen.
@export var startle_tilt_degrees := 12.0

@export_group("Dropouts")
## Panels of the wire grid knocked out on each jolt, picked from those in frame...
@export var jolt_drops_min := 3
@export var jolt_drops_max := 6
## ...each for this many frames (at 60 fps)...
@export var drop_frames_min := 2
@export var drop_frames_max := 4
## ...and the burst on the push.
@export var push_drops := 8
@export var push_drop_frames_max := 5
## Only panels whose centre is this far inside the frame (NDC)...
@export var drop_frame_margin := 0.85
## ...and clear of the seat, which fills this NDC x range of the shot.
@export var seat_ndc_x := Vector2(-0.5, 0.55)

@export_group("Composite")
## The composite look (docs/specs/shots-composite.md row 4): the light sits where the fire enters the
## frame (its source on the screen sphere, kept just inside the frame edge), dims on the jolts and
## grows as the fire swallows the wake on the push.
@export var world_environment: WorldEnvironment
@export var light_energy := 0.8
@export var light_radius := 0.25
## The light's radius at full swallow, times light_radius.
@export var swallow_grow := 2.2
## How far a full jolt flash drops the light and the wrap (0..1).
@export_range(0.0, 1.0) var jolt_dim := 0.6
## The light's centre stays this far outside the frame at most (UV).
@export var edge_margin := 0.04

@export_group("Drift light")
@export var drift_center := Vector3(-0.5, 0.9, 1.3)
@export var drift_energy := 0.7

const SHOT := &"shot"
const LAMP_GREEN := Color(0.45, 1.0, 0.72)
const LAMP_OFF := Color(0.04, 0.12, 0.09)
const ALARM_RED := Color(1.0, 0.12, 0.08)
## Seat parts that blink green: the button strip on the camera-side control box and the handset windows.
const BLINK_PARTS := [&"ButtonSlots0", &"ButtonSlots1", &"ButtonSlots2", &"ButtonSlots3", &"ButtonSlots4",
		&"ButtonSlots5", &"ButtonSlots6", &"HandsetWindowL", &"HandsetWindowR"]
## The cyan gauge faces: they pulse.
const GAUGE_PARTS := [&"Gauge", &"Dial0", &"Dial1"]
## The red lamp that flashes on the jolts: the left stick's thumb button.
const ALARM_PARTS := [&"GripButtonL"]

var shake := CockpitShake.new()
var beats := CockpitBeats.new()
var time := 0.0
## The spark burst, built on ready as a child of the seat.
var sparks: GPUParticles3D
## The startle "!", built on ready as a child of the seat.
var startle: Label3D

var _seat_rest := Transform3D()
var _wrap_rest := 1.2
var _camera_rest := Transform3D()
var _holo_rest := Transform3D()
var _lamps: Dictionary[StringName, StandardMaterial3D] = {}
var _gauge_base: Dictionary[StringName, Color] = {}
var _spark_strength := 1.0
## The dropout events, by time: [{time, drops: Array[Vector4]}]. Built on ready from the keys.
var drop_events: Array[Dictionary] = []
## The stick parts that tilt on the push, and their rest transforms.
var _stick_rest: Dictionary[StringName, Transform3D] = {}
## Stick parts per side, pivoting at the boot.
const STICK_PARTS := [&"Grip", &"GripHead", &"GripButton", &"GripTrigger"]


func _ready() -> void:
	_tune()
	_read_jolts()
	if seat != null:
		_seat_rest = seat.transform
	if camera != null:
		_camera_rest = camera.transform
	if holo != null:
		_holo_rest = holo.transform
	_take_lamps()
	_take_sticks()
	if holo != null:
		holo.set_surge(shake.surge_time)
	_build_sparks()
	_build_startle()
	_build_drops()
	var look := DepthComposite.find_in(world_environment)
	if look != null:
		_wrap_rest = look.wrap_strength
	apply(0.0)


func _process(delta: float) -> void:
	if animation_player != null and animation_player.is_playing() \
			and animation_player.current_animation == String(SHOT):
		time = animation_player.current_animation_position
	else:
		time += delta
	apply(time)


## Called by the shot's method keys. The strongest jolt throws the sparks.
func jolt(strength: float) -> void:
	if sparks != null and strength >= _spark_strength - 1e-4:
		sparks.restart()
		sparks.emitting = true


## Method keys for the ending. Everything they start is read off the shot time in apply().
func warning() -> void:
	pass


func push() -> void:
	pass


## Poses everything for shot time t. Pure in t: the same t always gives the same frame.
func apply(t: float) -> void:
	time = t
	if seat != null:
		seat.transform = _seat_rest * shake.seat_offset(t)
	if camera != null:
		var m := shake.seat_motion(t)
		var b := Basis.from_euler(m.rot * camera_share)
		camera.transform = Transform3D(b * _camera_rest.basis, _camera_rest.origin + m.move * camera_share)
	var tilt := beats.stick_angle(t)
	_tilt_sticks(tilt)
	if pose != null:
		pose.body_sway = shake.body_sway(t) + beats.body(t)
		pose.head_sway = shake.head_sway(t) + beats.head_look(t)
		pose.left_wrist_shift = _stick_turn(beats.wrist_rest, tilt) 				* Transform3D(Basis(), beats.left_wrist(t) - beats.wrist_rest)
		pose.right_wrist_shift = _stick_turn(seat.right_wrist_target if seat != null else Vector3.ZERO, tilt)
	var fl := shake.flash(t)
	if holo != null:
		holo.transform = _holo_rest * shake.panel_offset(t)
		var rot: Vector3 = shake.seat_motion(t).rot
		holo.set_state(t, fl, shake.glitch(t), rot.z * 6.0, rot.x * 6.0)
		_place_warning(t)
	_place_startle(t)
	if fire != null:
		var surge := shake.surge(t)
		fire.flare = shake.flare(t) + answer_heat * surge
		fire.speed_scale = lerpf(1.0, answer_flow, surge)
		fire.swallow = shake.swallow(t)
		_drop_panels(t)
	if drift_light != null:
		drift_light.position = drift_center + Vector3(sin(t * 0.9) * 0.5, sin(t * 1.3 + 1.0) * 0.25,
				sin(t * 0.6 + 2.0) * 0.3)
		var flicker := ReentryFire.flicker_at(t, 0.15)
		drift_light.light_energy = drift_energy * flicker * (1.0 + shake.flare(t) * 0.8)
	_light_lamps(t, fl)
	_update_composite(t, fl)


## Where the fire comes from as a screen UV, clamped to just past the frame edge.
func fire_entry_uv() -> Vector2:
	var src := fire.global_transform * (fire.source_direction.normalized() * fire.radius)
	var uv := DepthComposite.screen_uv(camera, src)
	var lo := -edge_margin
	return Vector2(clampf(uv.x, lo, 1.0 - lo), clampf(uv.y, lo, 1.0 - lo))


func _update_composite(t: float, fl: float) -> void:
	var look := DepthComposite.find_in(world_environment)
	if look == null or fire == null or camera == null:
		return
	var dim := 1.0 - jolt_dim * fl
	look.light_uv = fire_entry_uv()
	look.light_radius = light_radius * lerpf(1.0, swallow_grow, shake.swallow(t))
	look.light_energy = light_energy * dim
	look.wrap_strength = _wrap_rest * dim


func _tune() -> void:
	shake.buzz_move = buzz_mm / 1000.0
	shake.buzz_tilt = deg_to_rad(buzz_degrees)
	shake.kick_move = kick_cm / 100.0
	shake.kick_tilt = deg_to_rad(kick_degrees)
	shake.settle = settle
	shake.body_throw = body_throw
	beats.react = react
	beats.reach = reach
	beats.flick = flick
	beats.hang = hang
	beats.back = hand_back
	beats.guard_point = guard_point
	beats.guard_in = guard_in
	beats.guard_overshoot = guard_overshoot
	beats.push_duration = push_duration
	beats.stick_tilt = deg_to_rad(stick_degrees)
	beats.windup = windup
	beats.windup_lean = deg_to_rad(windup_lean_degrees)
	beats.push_lean = deg_to_rad(push_lean_degrees)
	beats.pushback = pushback
	beats.pushback_lean = deg_to_rad(pushback_lean_degrees)
	beats.head_tuck = deg_to_rad(head_tuck_degrees)
	beats.torso_turn = deg_to_rad(torso_turn_degrees)
	beats.startle_pop = startle_pop
	beats.startle_hold = startle_hold
	beats.startle_overshoot = startle_overshoot
	if seat != null:
		beats.wrist_rest = seat.left_wrist_target
	if holo != null:
		beats.panel_point = CockpitHolo.WARNING.pos
		beats.panel_half_width = CockpitHolo.WARNING.size.x * 0.5
		beats.head_point = holo.head_point


# The jolts are the `jolt` method keys on the shot's track for this node.
func _read_jolts() -> void:
	var times := PackedFloat32Array()
	var strengths := PackedFloat32Array()
	if animation_player != null and animation_player.has_animation(SHOT):
		var anim := animation_player.get_animation(SHOT)
		for track in anim.get_track_count():
			if anim.track_get_type(track) != Animation.TYPE_METHOD:
				continue
			for k in anim.track_get_key_count(track):
				var method := anim.method_track_get_name(track, k)
				if method == &"warning":
					beats.warning_time = anim.track_get_key_time(track, k)
				elif method == &"push":
					beats.push_time = anim.track_get_key_time(track, k)
					shake.surge_time = beats.push_time + answer_delay
					beats.answer_time = shake.surge_time
				if method != &"jolt":
					continue
				var args := anim.method_track_get_params(track, k)
				times.append(anim.track_get_key_time(track, k))
				strengths.append(float(args[0]) if args.size() > 0 else 1.0)
	shake.set_jolts(times, strengths)
	_spark_strength = 0.0
	for s in strengths:
		_spark_strength = maxf(_spark_strength, s)


# One dropout event per jolt (3-6 panels, 2-4 frames each) and a burst on the push, all picked from the
# panels in frame, seeded by the event so R replays the same ones.
func _build_drops() -> void:
	drop_events.clear()
	if fire == null or camera == null:
		return
	var in_frame := _panels_in_frame()
	if in_frame.is_empty():
		return
	var times: Array[float] = []
	for j: Dictionary in shake.jolts:
		times.append(j.time)
	if beats.push_time < INF:
		times.append(beats.push_time)
	for i in times.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (i + 1)
		var on_push := i == times.size() - 1 and beats.push_time < INF
		var count := push_drops if on_push else rng.randi_range(jolt_drops_min, jolt_drops_max)
		var pool := in_frame.duplicate()
		var drops: Array[Vector4] = []
		for d in mini(count, ReentryFire.MAX_DROPS):
			if pool.is_empty():
				break
			var cell: Vector2i = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			var frames := rng.randi_range(drop_frames_min, push_drop_frames_max if on_push else drop_frames_max)
			drops.append(Vector4(cell.x, cell.y, rng.randi_range(0, 2), frames / 60.0))
		drop_events.append({time = times[i], drops = drops})
	drop_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)


# The wire grid's panels whose centre the shot camera sees, as (segment, ring).
func _panels_in_frame() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var size := camera.get_viewport().get_visible_rect().size if camera.is_inside_tree() else Vector2(16, 9)
	var aspect := size.x / maxf(size.y, 1.0)
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	var to_cam := _camera_rest_global().affine_inverse()
	for seg in ReentryFire.GRID_SEGMENTS:
		for ring in ReentryFire.GRID_RINGS:
			var lon := TAU * (seg + 0.5) / ReentryFire.GRID_SEGMENTS
			var lat := PI * 0.5 - PI * (ring + 0.5) / ReentryFire.GRID_RINGS
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var local := to_cam * (fire.global_transform * (dir * fire.radius))
			if local.z >= 0.0:
				continue
			var ndc := Vector2(local.x / -local.z / (tan_v * aspect), local.y / -local.z / tan_v)
			var behind_seat := ndc.x > seat_ndc_x.x and ndc.x < seat_ndc_x.y
			if absf(ndc.x) < drop_frame_margin and absf(ndc.y) < drop_frame_margin and not behind_seat:
				cells.append(Vector2i(seg, ring))
	return cells


func _camera_rest_global() -> Transform3D:
	var parent := camera.get_parent() as Node3D
	return parent.global_transform * _camera_rest if parent != null else _camera_rest


# Hands the fire the latest dropout event's panels and their age; none before the first.
func _drop_panels(t: float) -> void:
	var current := {}
	for e: Dictionary in drop_events:
		if e.time <= t:
			current = e
	if current.is_empty():
		fire.set_drops([] as Array[Vector4], -1.0)
	else:
		fire.set_drops(current.drops, t - current.time)


# Gives the blinking seat parts their own unshaded material, so they glow in the fire's dark.
func _take_lamps() -> void:
	if seat == null:
		return
	for part: StringName in BLINK_PARTS + ALARM_PARTS:
		var mi := seat.get_node_or_null(NodePath(part)) as MeshInstance3D
		if mi == null:
			continue
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		_lamps[part] = m
	for part: StringName in GAUGE_PARTS:
		var mi := seat.get_node_or_null(NodePath(part)) as MeshInstance3D
		if mi != null and mi.mesh != null and mi.mesh.surface_get_material(0) is StandardMaterial3D:
			var m := (mi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			mi.material_override = m
			_lamps[part] = m
			_gauge_base[part] = m.albedo_color


func _take_sticks() -> void:
	if seat == null:
		return
	for s in ["L", "R"]:
		for part: StringName in STICK_PARTS:
			var node := seat.get_node_or_null(String(part) + s) as Node3D
			if node != null:
				_stick_rest[StringName(String(part) + s)] = node.transform


# The pivot each stick tilts round: its boot, seat space.
func _stick_pivot(grip: Vector3) -> Vector3:
	return grip + Vector3(0.0, -0.075, -0.015)


# The push's turn of a stick, as a seat-space transform: round X, the top toward his facing.
func _stick_turn(near: Vector3, angle: float) -> Transform3D:
	if seat == null or is_zero_approx(angle):
		return Transform3D()
	var grip := seat.left_grip if near.x > 0.0 else seat.right_grip
	var pivot := _stick_pivot(grip)
	var b := Basis(Vector3.RIGHT, angle)
	return Transform3D(b, pivot - b * pivot)


func _tilt_sticks(angle: float) -> void:
	if seat == null:
		return
	for part: StringName in _stick_rest:
		var node := seat.get_node(NodePath(part)) as Node3D
		var side := seat.left_grip if String(part).ends_with("L") else seat.right_grip
		node.transform = _stick_turn(side, angle) * _stick_rest[part]


# The WARNING: hidden until its key, pops open, rides out with the flick, gone.
func _place_warning(t: float) -> void:
	var w := holo.warning
	if w == null:
		return
	w.visible = beats.warning_visible(t)
	if not w.visible:
		return
	var gone := beats.warning_gone(t)
	var spec: Dictionary = CockpitHolo.WARNING
	var rest_pos: Vector3 = spec.pos
	w.position = rest_pos + beats.warning_offset(t)
	w.open_amount = beats.warning_open(t)
	w.fade = 1.0 - gone
	w.stretch = 1.0 + 0.6 * gone
	w.extra_glitch = 1.0 if (gone > 0.0 or beats.warning_open(t) < 1.0) else 0.0


# The startle "!": next to his head on the side away from the warning, square to the camera, its
# top leaning away from his head. Rides the seat's shake and his head's snap.
func _place_startle(t: float) -> void:
	if startle == null:
		return
	startle.visible = beats.startle_visible(t)
	if not startle.visible:
		return
	var head := beats.head_point
	if pose != null and pose.head_position.is_finite():
		head = pose.head_position
	var at := seat.global_transform * (head + startle_offset + Vector3.UP * startle_bounce * beats.startle_bounce(t))
	var b := camera.global_basis.orthonormalized() if camera != null else Basis()
	var out := seat.global_basis * Vector3(startle_offset.x, 0.0, startle_offset.z)
	var side := signf(b.x.dot(out))
	b = b * Basis(Vector3.BACK, -side * deg_to_rad(startle_tilt_degrees))
	startle.global_transform = Transform3D(b.scaled(Vector3.ONE * maxf(beats.startle_scale(t), 0.001)), at)


func _build_startle() -> void:
	if seat == null:
		return
	startle = Label3D.new()
	startle.name = "Startle"
	startle.text = "!"
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.2
	startle.font = font
	startle.font_size = 96
	# A "!" stands about 0.72 em tall.
	startle.pixel_size = startle_height / (96.0 * 0.72)
	startle.modulate = Color.WHITE
	startle.outline_size = 20
	startle.outline_modulate = Color.BLACK
	startle.shaded = false
	startle.double_sided = true
	startle.no_depth_test = true
	startle.render_priority = 10
	startle.outline_render_priority = 9
	startle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	startle.visible = false
	seat.add_child(startle)


func _build_sparks() -> void:
	if seat == null:
		return
	sparks = GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.one_shot = true
	sparks.emitting = false
	sparks.amount = spark_count
	sparks.lifetime = 0.55
	sparks.explosiveness = 0.95
	sparks.local_coords = false
	sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	sparks.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	sparks.position = spark_point
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.02
	m.direction = spark_direction.normalized()
	m.spread = 35.0
	m.initial_velocity_min = 1.5
	m.initial_velocity_max = 3.5
	m.gravity = Vector3(0.0, -7.0, 0.0)
	m.damping_min = 1.0
	m.damping_max = 2.5
	m.scale_min = 0.6
	m.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1.6, 1.4, 0.9, 1.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.8, 0.2, 0.05, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	m.color_ramp = ramp_tex
	sparks.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.1)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(1.0, 0.85, 0.5)
	q.material = qm
	sparks.draw_pass_1 = q
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seat.add_child(sparks)


func _light_lamps(t: float, fl: float) -> void:
	var i := 0
	for part: StringName in BLINK_PARTS:
		if _lamps.has(part):
			# Each its own rate and duty, so the strip twinkles instead of chasing.
			var rate := 0.9 + fmod(i * 0.73, 1.6)
			var duty := 0.35 + fmod(i * 0.29, 0.4)
			var on := fmod(t * rate + i * 0.37, 1.0) < duty
			if String(part).begins_with("Handset"):
				_lamps[part].albedo_color = LAMP_GREEN * (0.55 + 0.25 * sin(t * 2.1 + i))
			else:
				_lamps[part].albedo_color = LAMP_GREEN if on else LAMP_OFF
		i += 1
	for part: StringName in GAUGE_PARTS:
		if _lamps.has(part):
			var pulse := 0.8 + 0.2 * sin(t * (2.3 + i * 0.7) + i)
			_lamps[part].albedo_color = _gauge_base[part] * pulse
		i += 1
	for part: StringName in ALARM_PARTS:
		if _lamps.has(part):
			var blink := 1.0 if fmod(t * 9.0, 1.0) < 0.6 else 0.35
			var lit := clampf(fl * 1.4, 0.0, 1.0) * blink
			_lamps[part].albedo_color = Color(0.22, 0.03, 0.02).lerp(ALARM_RED, lit)
