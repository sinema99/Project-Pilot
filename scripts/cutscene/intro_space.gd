extends Node3D

# Cutscene shot 1: the snowy planet and the Vanguard flying in. See
# docs/specs/cutscene-intro-space.md. Every key lives in the AnimationPlayer's `shot` animation,
# so timing and paths are tuned in the editor; this script plays it and adds the camera rumble as
# the ship flies by (a function of the shot time, so seeking shows the same shake).
#
# Effects pass (spec "Effects pass"): engine trails, storm turn + lightning, re-entry heat, hull
# glint. Every one is a function of the shot time too, so seeking shows the same frame.
#
# Plays once on load and holds the last frame. R restarts, Esc quits.

## Emitted when the shot reaches its last frame. Later shots chain off this.
signal finished

const SHOT := &"shot"

@export var autoplay := true

@export_group("Flyby rumble")
## Peak camera shake, degrees of rotation (pitch / yaw; roll gets half).
@export var shake_degrees := 0.4
## Shot times: the rumble rises from start to peak (closest pass), then dies out by end.
@export var shake_start := 7.0
@export var shake_peak := 7.2
@export var shake_end := 7.8
## Base rumble frequency. Low enough to read as a rumble, not a buzz.
@export var shake_hz := 9.0

@export_group("Planet")
## Degrees the clouds drift east over the whole shot, on top of the planet's own turn.
@export var cloud_drift_degrees := 0.35
## The outer bands stay still; the eyewall and the inner rain bands turn counter-clockwise from
## above at these degrees per second (spec "Storm eye rebuild"). Very subtle on purpose.
@export var wall_spin_rate := 1.5
@export var band_spin_rate := 0.75
## The storm's eye and size (degrees). Pushed to the surface and cloud shaders on load, so the
## lightning and the clouds agree on where the storm is.
@export var storm_lat_lon := Vector2(27.8, -81.7)
@export var storm_radius_degrees := 7.5

@export_group("Lightning")
@export var lightning_seed := 7
## Flashes per second before the ramp, and at its end.
@export var lightning_rate_early := 2.5
@export var lightning_rate_late := 6.0
## Shot times the rate climbs between.
@export var lightning_ramp_start := 7.0
@export var lightning_ramp_end := 11.0
## Chance a flash sets off a neighbour a moment later.
@export_range(0.0, 1.0) var lightning_chain_chance := 0.3
## Ordinary flashes stop here so the sting stands alone.
@export var lightning_last := 11.5
## The final sting: start time, radius (degrees) and brightness. It peaks just after the start
## and is dark again before the shot's last frame.
@export var sting_time := 11.75
@export var sting_radius_degrees := 2.6
@export var sting_brightness := 1.5

@export_group("Re-entry heat")
## Shot times the heat starts building and is full.
@export var heat_start := 9.0
@export var heat_full := 12.0

@export_group("Hull glint")
## Shot time of the glint's middle, and how long its sweep across the hull takes.
@export var glint_time := 7.2
@export var glint_duration := 0.15
## Re-entry flare on the nose (m across at full heat), so the heat reads once the ship is a speck.
@export var heat_glow_size := 40.0
## Star flare size (m) at the glint's peak.
@export var glint_star_size := 7.0
## The overlay (heat + glint) put on every ship mesh.
@export var ship_fx_material: ShaderMaterial

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var _surface: ShaderMaterial = ($PlanetTilt/Planet as MeshInstance3D).mesh.surface_get_material(0)
@onready var _clouds: ShaderMaterial = ($PlanetTilt/Planet/Clouds as MeshInstance3D).mesh.surface_get_material(0)
@onready var _halo: ShaderMaterial = ($PlanetTilt/Halo as MeshInstance3D).mesh.surface_get_material(0)
@onready var _planet: MeshInstance3D = $PlanetTilt/Planet
@onready var _ship_path: Path3D = $CameraRig/ShipPath
@onready var _ship_follow: PathFollow3D = $CameraRig/ShipPath/ShipFollow
@onready var _ship: Node3D = $CameraRig/ShipPath/ShipFollow/Ship
@onready var _trail: IntroSpaceTrail = $EngineTrails
@onready var _bow_shock: MeshInstance3D = $CameraRig/ShipPath/ShipFollow/BowShock
@onready var _glint_star: MeshInstance3D = $GlintStar
@onready var _heat_glow: MeshInstance3D = $CameraRig/ShipPath/ShipFollow/HeatGlow
@onready var _title_card: IntroTitleCard = $TitleCard

var lightning := IntroSpaceLightning.new()
# A second follower on the ship path, moved to past times to find where the nozzles were.
var _probe_follow := PathFollow3D.new()
var _ship_start := 7.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	animation_player.animation_finished.connect(_on_animation_finished)
	# The halo's day side: toward the sun, which shines along the light's -z.
	_halo.set_shader_parameter(&"sun_dir", ($Sun as Node3D).global_transform.basis.z.normalized())
	for m: ShaderMaterial in [_surface, _clouds]:
		m.set_shader_parameter(&"storm_lat_lon", storm_lat_lon)
		m.set_shader_parameter(&"storm_radius_deg", storm_radius_degrees)
	_probe_follow.rotation_mode = _ship_follow.rotation_mode
	_probe_follow.loop = _ship_follow.loop
	_probe_follow.visible = false
	_ship_path.add_child(_probe_follow)
	_ship_start = _ship_appears_at()
	lightning.build(lightning_seed, lightning_rate_early, lightning_rate_late, lightning_ramp_start,
			lightning_ramp_end, lightning_last, storm_radius_degrees,
			lightning_chain_chance, band_spin_rate)
	lightning.add_sting(sting_time, Vector2.ZERO, sting_radius_degrees, sting_brightness)
	if ship_fx_material:
		for mi in _ship.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = ship_fx_material
	if autoplay:
		restart()


## Plays the shot from its first frame.
func restart() -> void:
	animation_player.stop()
	animation_player.play(SHOT)
	animation_player.seek(0.0, true)


func _process(_delta: float) -> void:
	var t := animation_player.current_animation_position
	camera.rotation = shake_at(t)
	_title_card.update_card(t, shake_on_screen(camera.rotation))
	var drift := cloud_drift_at(t)
	var spin := storm_spin_at(t)
	for m: ShaderMaterial in [_surface, _clouds]:
		m.set_shader_parameter(&"cloud_drift", drift)
		m.set_shader_parameter(&"storm_spin_wall", spin.x)
		m.set_shader_parameter(&"storm_spin_band", spin.y)
	_update_lightning(t)
	_trail.update_trail(t, _ship_start, ship_model_at, heat_at, camera.global_position)
	_update_ship_fx(t)


## Cloud drift (degrees east) at shot time `t`: steady over the shot, so seeking shows the same sky.
func cloud_drift_at(t: float) -> float:
	var length := animation_player.get_animation(SHOT).length
	return cloud_drift_degrees * clampf(t / length, 0.0, 1.0)


## Storm turn (degrees, counter-clockwise from above) at shot time `t`: x = eyewall, y = inner
## rain bands. Steady, so seeking shows the same storm.
func storm_spin_at(t: float) -> Vector2:
	return Vector2(wall_spin_rate, band_spin_rate) * maxf(t, 0.0)


## Re-entry heat 0..1 at shot time `t`.
func heat_at(t: float) -> float:
	return smoothstep(heat_start, heat_full, t)


## Glint 0..1 at shot time `t`: one rise and fall over glint_duration around glint_time.
func glint_at(t: float) -> float:
	var p := (t - glint_time) / glint_duration + 0.5
	if p <= 0.0 or p >= 1.0:
		return 0.0
	return sin(PI * p)


## The ship model's global transform at shot time `tau`, read off the animation rather than the
## live nodes, so the trail can ask about the past.
func ship_model_at(tau: float) -> Transform3D:
	var anim := animation_player.get_animation(SHOT)
	var rig_track := anim.find_track(^"CameraRig:position", Animation.TYPE_VALUE)
	var progress_track := anim.find_track(^"CameraRig/ShipPath/ShipFollow:progress_ratio", Animation.TYPE_VALUE)
	var rig := Transform3D(Basis.IDENTITY, anim.value_track_interpolate(rig_track, tau))
	_probe_follow.progress_ratio = anim.value_track_interpolate(progress_track, tau)
	return rig * _ship_path.transform * _probe_follow.transform * _ship.transform


## Position in the storm's frame (storm-local degrees) of a planet-space direction at shot time
## `t`. Must match planet_earth.gdshaderinc::earth_storm_local (after the drift).
func storm_local(earth_dir: Vector3, t: float) -> Vector2:
	var e := earth_dir.normalized()
	var lat := rad_to_deg(asin(clampf(e.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(-e.z, e.x)) - cloud_drift_at(t)
	var c := storm_lat_lon
	return Vector2((lon - c.y) * cos(deg_to_rad(c.x)), lat - c.x)


## Where the ship is heading at shot time `t`, as a planet-space (Earth-space) point: its nose ray
## onto the planet, else the ground under it.
func ship_aim_on_planet(t: float) -> Vector3:
	var x := ship_model_at(t)
	var centre := _planet.global_position
	var radius := (_planet.mesh as SphereMesh).radius * _planet.global_basis.get_scale().x
	var o := x.origin - centre
	var d := x.basis.z.normalized()
	var b := o.dot(d)
	var disc := b * b - (o.length_squared() - radius * radius)
	var hit := x.origin
	if disc > 0.0 and -b - sqrt(disc) > 0.0:
		hit = x.origin + d * (-b - sqrt(disc))
	return _planet.global_transform.affine_inverse() * hit


func _update_lightning(t: float) -> void:
	lightning.sting.pos = storm_local(ship_aim_on_planet(sting_time), t)
	_clouds.set_shader_parameter(&"flashes", PackedVector4Array(lightning.active_at(t, 8)))


func _update_ship_fx(t: float) -> void:
	var heat := heat_at(t)
	var x := _ship.global_transform
	if ship_fx_material:
		ship_fx_material.set_shader_parameter(&"heat", heat)
		ship_fx_material.set_shader_parameter(&"lead_dir", x.basis.z.normalized())
		ship_fx_material.set_shader_parameter(&"sun_toward", ($Sun as Node3D).global_transform.basis.z.normalized())
	(_bow_shock.material_override as ShaderMaterial).set_shader_parameter(&"heat", heat)
	_bow_shock.visible = heat > 0.0
	_heat_glow.visible = heat > 0.0
	_heat_glow.scale = Vector3.ONE * heat_glow_size * maxf(heat, 0.05)
	(_heat_glow.material_override as ShaderMaterial).set_shader_parameter(&"glint", heat)
	var g := glint_at(t) if _ship_follow.visible else 0.0
	# The faces that catch the sun at the flyby are the back ones (the sun is behind the camera and
	# the ship flies away from it), so the band sweeps across the back, one side to the other.
	var p := clampf((t - glint_time) / glint_duration + 0.5, 0.0, 1.0)
	var band := x * Vector3(lerpf(-7.6, 7.6, p), 1.47, -2.0)  # pod tip to pod tip, sinestro_1.glb
	if ship_fx_material:
		ship_fx_material.set_shader_parameter(&"glint", g)
		ship_fx_material.set_shader_parameter(&"glint_point", band)
		ship_fx_material.set_shader_parameter(&"glint_axis", x.basis.x.normalized())
	_glint_star.visible = g > 0.0
	_glint_star.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * glint_star_size), band)
	(_glint_star.material_override as ShaderMaterial).set_shader_parameter(&"glint", g)


# First key where the ship turns visible: the trail starts there.
func _ship_appears_at() -> float:
	var anim := animation_player.get_animation(SHOT)
	var track := anim.find_track(^"CameraRig/ShipPath/ShipFollow:visible", Animation.TYPE_VALUE)
	for k in anim.track_get_key_count(track):
		if anim.track_get_key_value(track, k):
			return anim.track_get_key_time(track, k)
	return 0.0


## Camera rotation offset (radians, pitch / yaw / roll) at shot time `t`: smooth layered sines,
## so the same time always gives the same shake.
func shake_at(t: float) -> Vector3:
	var env := 0.0
	if t > shake_start and t < shake_end:
		env = smoothstep(shake_start, shake_peak, t) if t < shake_peak 				else 1.0 - smoothstep(shake_peak, shake_end, t)
	if env <= 0.0:
		return Vector3.ZERO
	var w := TAU * shake_hz * t
	var pitch := sin(w * 1.0) * 0.6 + sin(w * 1.53 + 1.3) * 0.4
	var yaw := sin(w * 0.87 + 2.1) * 0.6 + sin(w * 1.71 + 0.4) * 0.4
	var roll := sin(w * 1.19 + 3.7) * 0.5
	return Vector3(pitch, yaw, roll) * deg_to_rad(shake_degrees) * env


## The camera rumble as a screen offset in canvas pixels, so the title card shakes with the
## picture: turning the camera left (yaw +) slides the image right, tilting up slides it down.
func shake_on_screen(shake: Vector3) -> Vector2:
	var h := get_viewport().get_visible_rect().size.y
	var focal := h * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	return Vector2(shake.y, shake.x) * focal


func _on_animation_finished(anim: StringName) -> void:
	if anim == SHOT:
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
