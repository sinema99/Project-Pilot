class_name CockpitStormDriver
extends Node

# Drives the cockpit storm shot from the shot time: the snow on the screen, the light it throws (the
# descent's pale calm dimming to slate as he flies into the storm), the seat's buzz ramping with the
# storm (and him with it), the route panel and his two taps on it, his
# three presses on the button strip and the slots lighting, his head turning to the panel. The
# timing is StormBeats and the buzz CockpitShake (both pure); this node only applies them. The
# camera is never touched: the shot is locked off. See docs/specs/cutscene-cockpit-storm.md.

@export var animation_player: AnimationPlayer
@export var seat: CockpitSeat
@export var pose: SeatedPose
@export var holo: CockpitHolo
@export var snow: CockpitSnow
## The overhead key: dims with the rest as the storm closes in.
@export var key_light: DirectionalLight3D
## The screen's light on him: pale lavender in the calm, dim slate in the storm.
@export var fill_light: DirectionalLight3D
## The holo panels' green spill.
@export var holo_light: OmniLight3D
@export var world_environment: WorldEnvironment
## Strip slots he presses, in order (ButtonSlots0 is the back end, 6 the front).
@export var pressed_slots := PackedInt32Array([2, 0, 1])

@export_group("Buzz")
## The seat's buzz in the calm: millimetres and degrees...
@export var buzz_mm := 1.0
@export var buzz_degrees := 0.08
## ...growing by this many times its calm size over the ramp.
@export var buzz_growth := 2.5
## His head's nod in the full storm, degrees.
@export var head_nod_degrees := 0.35
## His torso turns with his head this share of the way.
@export_range(0.0, 1.0) var torso_share := 0.25

@export_group("Light")
## Calm is a dim overcast; the storm darker again, cool slate.
@export var calm_key := Color(0.9, 0.88, 0.96)
@export var storm_key := Color(0.7, 0.75, 0.84)
@export var calm_key_energy := 0.4
@export var storm_key_energy := 0.24
@export var calm_fill := Color(0.9, 0.88, 0.96)
@export var storm_fill := Color(0.68, 0.75, 0.8)
@export var calm_fill_energy := 0.45
@export var storm_fill_energy := 0.3
## The gusts pump the fill this much at full storm.
@export var gust_flicker := 0.3
@export var calm_ambient := Color(0.82, 0.8, 0.9)
@export var storm_ambient := Color(0.55, 0.6, 0.68)
@export var calm_ambient_energy := 0.35
@export var storm_ambient_energy := 0.22
@export var lightning_energy := 2.2

@export_group("Composite")
## The composite look (docs/specs/shots-composite.md row 5): the light sits on the vanishing point
## behind his head and the storm swallows it; the near tint heads for descent's slate-violet.
@export var calm_light_energy := 0.15
@export var storm_light_energy := 0.06
@export var calm_light_radius := 0.15
@export var storm_light_radius := 0.12
@export var calm_wrap := 0.25
@export var storm_wrap := 0.06
@export var calm_tint := Color(0.92, 0.92, 1.0)
@export var storm_tint := Color(0.72, 0.75, 0.92)
@export_range(0.0, 1.0) var calm_near_value := 0.95
@export_range(0.0, 1.0) var storm_near_value := 0.8
## A full lightning flash adds this much wrap.
@export var flash_wrap := 0.6

const SHOT := &"shot"
const SLOT_OFF := Color(0.03, 0.08, 0.1)
const SLOT_LIT := Color(0.35, 0.95, 1.0)

var beats := StormBeats.new()
var shake := CockpitShake.new()
var time := 0.0

var _seat_rest := Transform3D()
var _holo_rest := Transform3D()
var _slot_lamps: Array[StandardMaterial3D] = []


func _ready() -> void:
	shake.buzz_move = buzz_mm / 1000.0
	shake.buzz_tilt = deg_to_rad(buzz_degrees)
	# CockpitShake's surge is the ship answering the sticks in the fire shot; here it is the storm,
	# ramping in step with StormBeats.storm().
	shake.surge_time = beats.ramp_start
	shake.surge_ramp = beats.ramp_end - beats.ramp_start
	shake.surge_buzz = buzz_growth
	if seat != null:
		_seat_rest = seat.transform
		beats.left_rest = seat.left_wrist_target
		beats.right_rest = seat.right_wrist_target
	if holo != null:
		_holo_rest = holo.transform
		beats.head_point = holo.head_point
		beats.panel_point = CockpitHolo.ROUTE.pos
		beats.buttons = _route_buttons()
	_take_slots()
	apply(0.0)


func _process(delta: float) -> void:
	if animation_player != null and animation_player.is_playing() \
			and animation_player.current_animation == String(SHOT):
		time = animation_player.current_animation_position
	else:
		time += delta
	apply(time)


## Poses everything for shot time t. Pure in t: the same t always gives the same frame.
func apply(t: float) -> void:
	time = t
	var storm := beats.storm(t)
	var gust := beats.gust(t)
	var fl := beats.flash(t)
	if seat != null:
		seat.transform = _seat_rest * shake.seat_offset(t)
	if pose != null and seat != null:
		shake.head_wobble = deg_to_rad(head_nod_degrees) * storm
		var look := beats.head_look(t)
		pose.body_sway = Vector3(0.0, look.y * torso_share, 0.0)
		pose.head_sway = shake.head_sway(t) + look
		pose.left_wrist_shift = Transform3D(Basis(), beats.left_wrist(t) - seat.left_wrist_target)
		pose.right_wrist_shift = Transform3D(Basis(), beats.right_wrist(t) - seat.right_wrist_target)
	if holo != null:
		holo.transform = _holo_rest * shake.panel_offset(t)
		holo.set_state(t, 0.0, 0.0, 0.0, 0.0)
		_place_route(t)
	if snow != null:
		snow.set_state(t, storm, beats.travel(t), beats.source_dir(t), gust, fl)
		snow.set_ramp(beats.ramp_start, beats.ramp_end)
	if key_light != null:
		key_light.light_color = calm_key.lerp(storm_key, storm)
		key_light.light_energy = lerpf(calm_key_energy, storm_key_energy, storm)
	if fill_light != null:
		fill_light.light_color = calm_fill.lerp(storm_fill, storm).lerp(Color.WHITE, fl)
		fill_light.light_energy = lerpf(calm_fill_energy, storm_fill_energy, storm) \
				* (1.0 + gust_flicker * (gust - 0.5) * storm) + lightning_energy * fl
	if world_environment != null and world_environment.environment != null:
		var env := world_environment.environment
		env.ambient_light_color = calm_ambient.lerp(storm_ambient, storm).lerp(Color.WHITE, fl * 0.6)
		env.ambient_light_energy = lerpf(calm_ambient_energy, storm_ambient_energy, storm) + fl * 0.6
	for i in _slot_lamps.size():
		if _slot_lamps[i] != null:
			_slot_lamps[i].albedo_color = SLOT_LIT if beats.slot_lit(t, i) else SLOT_OFF
	_update_composite(storm, fl)


## The vanishing point, world: the snow's antipode of `ahead`, on the screen sphere.
func vanishing_point() -> Vector3:
	var r := snow.radius if snow != null else 4.05
	var centre := snow.global_transform if snow != null else Transform3D()
	return centre * (-beats.source_dir(time) * r)


func _update_composite(storm: float, fl: float) -> void:
	var look := DepthComposite.find_in(world_environment)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if look == null or camera == null:
		return
	look.light_uv = DepthComposite.screen_uv(camera, vanishing_point())
	look.light_energy = lerpf(calm_light_energy, storm_light_energy, storm)
	look.light_radius = lerpf(calm_light_radius, storm_light_radius, storm)
	look.wrap_strength = lerpf(calm_wrap, storm_wrap, storm) + flash_wrap * fl
	look.dark_tint = calm_tint.lerp(storm_tint, storm)
	look.near_value = lerpf(calm_near_value, storm_near_value, storm)
	look.flash = clampf(fl, 0.0, 1.0)


# The route panel: hidden until it pops, the taps lighting its buttons, folding away.
func _place_route(t: float) -> void:
	var r := holo.route
	if r == null:
		return
	r.visible = beats.route_visible(t)
	if not r.visible:
		return
	var amount := beats.route_amount(t)
	r.open_amount = amount
	r.extra_glitch = 1.0 if amount < 1.0 else 0.0
	r.display.route_taps = beats.route_taps(t)
	r.display.route_confirm = beats.route_confirm(t)


# The route panel's two buttons, seat space: the drawing's fractions onto the glass.
func _route_buttons() -> Array[Vector3]:
	var spec: Dictionary = CockpitHolo.ROUTE
	var pos: Vector3 = spec.pos
	var sz: Vector2 = spec.size
	var facing := (holo.head_point - pos).normalized()
	var frame := Transform3D(Basis.looking_at(facing, Vector3.UP, true), pos)
	var out: Array[Vector3] = []
	for f in HoloDisplay.ROUTE_BUTTONS:
		out.append(frame * Vector3((f.x - 0.5) * sz.x, (0.5 - f.y) * sz.y, 0.0))
	return out


# The pressed slots get their own unshaded lamp material, dark until pressed; their positions go to
# the beats.
func _take_slots() -> void:
	if seat == null:
		return
	var points: Array[Vector3] = []
	for i in pressed_slots:
		var mi := seat.get_node_or_null("ButtonSlots%d" % i) as MeshInstance3D
		if mi == null:
			_slot_lamps.append(null)
			points.append(beats.left_rest)
			continue
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = SLOT_OFF
		mi.material_override = m
		_slot_lamps.append(m)
		points.append(mi.position)
	beats.slots = points
