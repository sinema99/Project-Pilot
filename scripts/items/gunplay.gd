## The gun framework: aim, fire, reload, ammo and the HUD that shows them. Built at runtime by
## pilot9.gd::_setup_gunplay() and ticked from its physics step; pilot9 only asks it four things
## (aim_blend, wants_camera_facing, limits_speed, look_scale) and hands it the fire / reload
## presses. Knows no particular gun: everything is in the drawn HeldItem's GunDef.
## Hitscan: aimed, one ray from the muzzle along the barrel (the aim IK points it at what the camera
## sees) and the crosshair is drawn where that ray lands; at the hip, a camera-centre ray.
## See docs/specs/pilot9-gunplay.md.
extends Node

## Fired a shot. `hit` is whether it landed on something that answers take_hit().
signal fired(gun: GunDef, hit: bool)
signal reloaded(gun: GunDef)

## The layers a bullet stops on: the world (1) and the range dummy's hitbox (9).
const BULLET_MASK := 1 | 256
const AIM_EASE_TIME := 0.15
## How long he keeps facing the camera after a hip-fired shot, seconds.
const FACE_HOLD := 0.5
## Shoulder offset and arm length while aiming (arm is a fraction of the normal one).
const AIM_SHOULDER_OFFSET := 1.0
## The aim camera's arm, metres behind the pivot (never longer than the hip arm).
const AIM_ARM_LENGTH := 1.25
const AIM_LOOK_SCALE := 0.7
const AIM_SWAY_SCALE := 0.5
const HIT_FLICKER := 0.15
## How quickly a shot's kick lands on the camera, and the shake's fade rate.
const KICK_LAND_TIME := 0.03
const SHAKE_DECAY := 14.0
## The aim pose eases in and out over this long (also around a reload).
const POSE_EASE_TIME := 0.2

const CROSS_BLOCK := 3.0
const CROSS_AIM_RADIUS := 9.0
## The T crosshair: the empty centre, pixels, and the length of each of its three arms in blocks.
const CROSS_GAP := 6.0
const CROSS_ARM_BLOCKS := 4
## The crosshair follows the barrel, never further than this many pixels from screen centre.
const CROSS_MAX_DRIFT := 60.0
## The furthest down the barrel the crosshair reads, metres (the IK's own convergence limit).
const BARREL_FAR := 25.0
## The aim pose must be this settled before the barrel rules the shot; while the arms are still
## easing in, the camera ray does and the crosshair stays at centre.
const BARREL_READY := 0.97
const HOT := Color(1.0, 0.2, 0.15)

const _Fx := preload("res://scripts/items/gun_fx.gd")
const _Reload := preload("res://scripts/items/gun_reload.gd")

var _pilot: Node = null
var _holder: Node = null

## 0 (hip) .. 1 (full aim), eased.
var aim_blend: float = 0.0
var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _face_hold: float = 0.0
var _hit_flash: float = 0.0
var _dry_flash: float = 0.0
## The arm's aim-pose weight: aim_blend, dropped to 0 across a reload and back after it.
var aim_pose: float = 0.0
## An empty magazine + a fire press starts a reload by itself.
var auto_reload: bool = true
var _reload_total: float = 0.0
var _reload_empty: bool = false
## Recoil: radians still to land on the camera, and radians owed back. Bloom in degrees.
var _kick_p: float = 0.0
var _kick_y: float = 0.0
var _recover_p: float = 0.0
var bloom_deg: float = 0.0
var _shake: float = 0.0
var _shake_t: float = 0.0
var fx: Node = null
var reload_fx: Node = null
## GunDef -> rounds left. A gun keeps its count across swaps.
var _rounds: Dictionary = {}
var _last_gun: GunDef = null
var _query: PhysicsRayQueryParameters3D = null
var _rng := RandomNumberGenerator.new()

var _layer: CanvasLayer = null
var _cross: Control = null
var _cross_origin := Vector2.ZERO
var _name_label: Label = null
var _ammo_label: Label = null
## Where the barrel points on screen, pixels off the centre (zero at the hip).
var _barrel_offset: Vector2 = Vector2.ZERO


# --- pure helpers (static so the tests need no rig) -------------------------------------------------

## May a click turn into a shot right now?
static func can_fire(is_armed: bool, is_blocked: bool, cooldown: float, reloading: bool, rounds: int) -> bool:
	return is_armed and not is_blocked and cooldown <= 0.0 and not reloading and rounds > 0

## The lens multiplier at `blend` of the way into the aim: 1.0 at hip, 1 - cut at full aim.
static func fov_scale(cut: float, blend: float) -> float:
	return 1.0 - cut * clampf(blend, 0.0, 1.0)

## The ammo readout, `6 / ∞`.
static func ammo_text(rounds: int, reloading: bool) -> String:
	return "RELOADING" if reloading else "%d / ∞" % rounds

## The aim ring's radius in pixels for a cone of `spread_deg` on a `fov_deg` lens `height` px tall.
static func ring_radius(cone_deg: float, fov_deg: float, height: float) -> float:
	var px := height * 0.5 / tan(deg_to_rad(fov_deg) * 0.5) * tan(deg_to_rad(cone_deg))
	return CROSS_AIM_RADIUS + px

## The cone half-angle, degrees: the gun's rest spread (hip..aim) plus the bloom, capped.
static func spread_deg(g: GunDef, blend: float, bloom: float) -> float:
	return minf(lerpf(g.spread_hip_deg, g.spread_aim_deg, clampf(blend, 0.0, 1.0)) + bloom,
		g.bloom_max_deg)

## Seconds a reload takes: the full time from empty, tactical_scale of it with rounds left.
static func reload_seconds(g: GunDef, rounds: int) -> float:
	return g.reload_time * (g.tactical_scale if rounds > 0 else 1.0)

## One shot's camera kick, radians pitch: the aimed kick, hip-fire kicking hip_kick_scale harder.
static func kick_pitch(g: GunDef, blend: float) -> float:
	return deg_to_rad(g.recoil_pitch_deg) * lerpf(g.hip_kick_scale, 1.0, clampf(blend, 0.0, 1.0))

## `forward` turned by a random angle inside a cone of `cone_deg` half-angle.
static func spread_dir(forward: Vector3, cone_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if cone_deg <= 0.0:
		return forward
	var up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var true_up := right.cross(forward).normalized()
	var ang := deg_to_rad(cone_deg) * sqrt(rng.randf())
	var az := rng.randf() * TAU
	return (forward * cos(ang) + (right * cos(az) + true_up * sin(az)) * sin(ang)).normalized()


# --- setup ------------------------------------------------------------------------------------------

func setup(pilot: Node, holder: Node) -> void:
	_pilot = pilot
	_holder = holder
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = BULLET_MASK
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	_rng.randomize()
	fx = _Fx.new()
	fx.name = &"GunFx"
	add_child(fx)
	reload_fx = _Reload.new()
	reload_fx.name = &"GunReload"
	add_child(reload_fx)
	reload_fx.setup(_pilot, _holder, fx)
	_build_hud()


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.name = &"GunHud"
	_layer.layer = 11
	_layer.visible = false
	add_child(_layer)
	_cross = Control.new()
	_cross.name = &"Crosshair"
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.draw.connect(_draw_crosshair)
	_layer.add_child(_cross)
	_name_label = Ps1Plate.make_label(14, Color(0.45, 0.62, 0.62))
	_ammo_label = Ps1Plate.make_label(30)
	for label in [_name_label, _ammo_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_layer.add_child(label)
	_ammo_label.offset_left = -300.0
	_ammo_label.offset_right = -32.0
	_ammo_label.offset_top = -78.0
	_ammo_label.offset_bottom = -36.0
	_name_label.offset_left = -300.0
	_name_label.offset_right = -32.0
	_name_label.offset_top = -98.0
	_name_label.offset_bottom = -78.0


# --- state ------------------------------------------------------------------------------------------

## The GunDef in his hand, or null: needs a drawn gun, and not mid draw / holster animation.
func gun() -> GunDef:
	if _holder == null or _holder.held_item == null or not _holder.is_drawn \
			or _holder.item_instance == null:
		return null
	var anim: Node = _pilot.equip_anim
	if anim != null and anim.is_playing():
		return null
	return _holder.held_item.gun


func armed() -> bool:
	return gun() != null


## States and modes where the gun stays drawn but neither aims nor fires.
func blocked() -> bool:
	return _pilot.frozen or _pilot.is_tredging or _pilot.is_carrying or _pilot.is_sliding \
		or _pilot.is_dashing or _pilot.is_wall_running or _pilot.is_wall_climbing \
		or _pilot.is_climbing or _pilot.is_vaulting or _pilot.is_rail_grinding \
		or _pilot.is_rail_switching or _pilot.riding != null


## Right mouse held, with a gun out, on his feet, in a state that allows it.
func aim_active() -> bool:
	return armed() and not blocked() and _pilot.is_on_floor() \
		and InputMap.has_action(&"aim") and Input.is_action_pressed(&"aim")


func rounds_left() -> int:
	var g := gun()
	if g == null:
		return 0
	return int(_rounds.get(g, g.magazine))


func is_reloading() -> bool:
	return _reload_left > 0.0


## Aimed, his body holds the standing-aim pose whatever the stick does: no legs, no lean.
func body_locked() -> bool:
	return aim_active()


## Body follows the camera while aiming, and for FACE_HOLD after a shot.
func wants_camera_facing() -> bool:
	return aim_active() or (_face_hold > 0.0 and armed() and not blocked())


## Aim holds him to a walk, no sprint.
func limits_speed() -> bool:
	return aim_active()


func look_scale() -> float:
	return lerpf(1.0, AIM_LOOK_SCALE, aim_blend)


func sway_scale() -> float:
	return lerpf(1.0, AIM_SWAY_SCALE, aim_blend)


## The lens multiplier for this frame.
func fov_multiplier() -> float:
	var g := gun()
	return fov_scale(g.aim_fov_cut if g != null else 0.0, aim_blend)


## The shoulder offset the camera wants: `normal` at hip, AIM_SHOULDER_OFFSET at full aim.
## (Drawing a gun alone changes nothing: aim_blend is 0 until right mouse is held.)
func shoulder_offset(normal: float) -> float:
	return lerpf(normal, maxf(normal, AIM_SHOULDER_OFFSET), aim_blend)


## The arm length: `normal` at hip, AIM_ARM_FRACTION of it at full aim.
func arm_length(normal: float) -> float:
	return lerpf(normal, minf(normal, AIM_ARM_LENGTH), aim_blend)


## The running reload's progress 0..1, or -1 with none.
func reload_progress() -> float:
	if _reload_left <= 0.0 or _reload_total <= 0.0:
		return -1.0
	return clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0)


## The camera roll the last shots' shake adds, radians.
func shake_roll() -> float:
	return sin(_shake_t * 85.0) * _shake


# --- per frame --------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	var g := gun()
	if g != _last_gun:
		# A swap (or a holster) ends a reload; the old gun keeps its rounds.
		_reload_left = 0.0
		_cooldown = 0.0
		_last_gun = g
		bloom_deg = 0.0
		_recover_p = 0.0
		_kick_p = 0.0
		_kick_y = 0.0
	_cooldown = maxf(_cooldown - delta, 0.0)
	_face_hold = maxf(_face_hold - delta, 0.0)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_dry_flash = maxf(_dry_flash - delta, 0.0)
	if g != null and _reload_left > 0.0:
		if blocked():
			_reload_left = 0.0
		else:
			_reload_left -= delta
			if _reload_left <= 0.0:
				_reload_left = 0.0
				_rounds[g] = g.magazine
				reloaded.emit(g)
	var target := 1.0 if aim_active() else 0.0
	aim_blend = move_toward(aim_blend, target, delta / AIM_EASE_TIME)
	# The arm's aim pose follows aim_blend, but lets go for the length of a reload.
	var pose_target := 0.0 if _reload_left > 0.0 or g == null else aim_blend
	aim_pose = move_toward(aim_pose, pose_target, delta / POSE_EASE_TIME)
	_step_recoil(g, delta)
	if reload_fx != null:
		reload_fx.step(g, reload_progress(), _reload_empty, delta)
	_update_barrel_offset(g)
	_update_hud(g)


## The kick lands on the camera fast, then the recoverable part of it comes back; bloom and the
## shake fade. The camera pivot is the view, so the kick moves the real aim.
func _step_recoil(g: GunDef, delta: float) -> void:
	var piv: Node3D = _pilot.camera_pivot
	var land := 1.0 - exp(-delta / KICK_LAND_TIME)
	var dp := _kick_p * land
	var dy := _kick_y * land
	_kick_p -= dp
	_kick_y -= dy
	if g != null:
		var back := _recover_p * (1.0 - exp(-delta * 4.0 / maxf(g.recoil_recover_time, 0.05)))
		_recover_p -= back
		dp -= back
		bloom_deg = maxf(bloom_deg - g.bloom_decay * delta, 0.0)
	if (absf(dp) > 1e-7 or absf(dy) > 1e-7) and _free_looking():
		_pilot.free_look_kick(dp, dy)
	elif (absf(dp) > 1e-7 or absf(dy) > 1e-7) and piv != null:
		piv.rotation.x = _pilot._clamp_look_pitch(piv.rotation.x + dp)
		piv.rotation.y += dy
	_shake = _shake * exp(-SHAKE_DECAY * delta)
	_shake_t += delta


## The fire press (left mouse). Returns whether a round went out.
func try_fire() -> bool:
	var g := gun()
	if g == null or blocked():
		return false
	var rounds := int(_rounds.get(g, g.magazine))
	if _cooldown > 0.0 or is_reloading():
		return false
	if rounds <= 0:
		# Dry fire: no shot, the count blinks; an empty gun then reloads by itself.
		_dry_flash = 0.25
		_cooldown = g.fire_interval
		if auto_reload:
			press_reload()
		return false
	_rounds[g] = rounds - 1
	_cooldown = g.fire_interval
	_face_hold = FACE_HOLD
	var hit := _shoot(g)
	_recoil(g)
	fired.emit(g, hit)
	return true


## The reload press (R with a gun out). Returns whether one started.
func press_reload() -> bool:
	var g := gun()
	if g == null or blocked() or is_reloading():
		return false
	var rounds := int(_rounds.get(g, g.magazine))
	if rounds >= g.magazine:
		return false
	_reload_empty = rounds <= 0
	_reload_total = reload_seconds(g, rounds)
	_reload_left = _reload_total
	return true


## Refill one gun's magazine now (tests, and whatever later hands out ammo).
func refill(g: GunDef) -> void:
	_rounds[g] = g.magazine


## Free-look (Alt) is swinging the camera: the aim stays on the frame frozen at the press.
func _free_looking() -> bool:
	return _pilot.has_method(&"aim_view_transform") and _pilot._free_look_active()


## The view the gun aims down - the camera, or the frozen frame under free-look.
func _aim_view() -> Transform3D:
	if _pilot.has_method(&"aim_view_transform"):
		return _pilot.aim_view_transform()
	return _pilot.camera_3d.global_transform


func _shoot(g: GunDef) -> bool:
	var view := _aim_view()
	var muzzle := _muzzle_node()
	# Aimed, the round leaves the barrel along the barrel (the IK points it at what the camera
	# sees); at the hip the barrel is only carried, so the camera ray still decides.
	var from := view.origin
	var fwd := -view.basis.z
	var barrel := muzzle != null and aim_pose >= BARREL_READY
	if barrel:
		from = muzzle.global_position
		fwd = -muzzle.global_basis.z.normalized()
	var dir := spread_dir(fwd, spread_deg(g, aim_blend, bloom_deg), _rng)
	var space: PhysicsDirectSpaceState3D = _pilot.get_world_3d().direct_space_state
	_query.exclude = [_pilot.get_rid()]
	var result := {}
	if barrel:
		# One ray from the camera to the muzzle: a barrel poked past a corner or into a wall is a
		# point-blank hit on that surface, never a round that starts on the far side of it.
		_query.from = view.origin
		_query.to = from
		result = space.intersect_ray(_query)
	var point_blank := not result.is_empty()
	var end: Vector3 = result.position if point_blank else from + dir * g.range_m
	if not point_blank:
		_query.from = from
		_query.to = end
		result = space.intersect_ray(_query)
		if not result.is_empty():
			end = result.position
	var landed := false
	if not result.is_empty():
		var target := _owner_with(result.collider, &"take_hit")
		if target != null:
			target.take_hit(g.damage, &"bullet", end)
			landed = true
			_hit_flash = HIT_FLICKER
		fx.impact(end, result.normal, landed)
	# The revolver (no ejected brass) is the heavy gun: bigger flash, thicker trail.
	var heavy := not g.ejects_casings
	fx.muzzle_flash(muzzle, heavy)
	# Aimed: the trail leaves the barrel. Hip: the carried gun points anywhere, so the trail starts
	# just ahead of the camera (low and to the right, like a gun hand) and runs down the crosshair ray.
	var trail_from := from
	if barrel:
		trail_from = muzzle.global_position
	else:
		trail_from = view.origin + fwd * 1.5 + view.basis.x * 0.15 \
			- view.basis.y * 0.12
	fx.tracer(trail_from, end, 1.5 if heavy else 1.0)
	if g.ejects_casings:
		_eject_casing()
	return landed


## Per shot: the camera kick (queued, lands over KICK_LAND_TIME), a sideways nudge, the bloom
## and the shake. Hip-fire kicks harder; aimed shake is lighter.
func _recoil(g: GunDef) -> void:
	var kick := kick_pitch(g, aim_blend)
	_kick_p += kick
	_recover_p += kick * (1.0 - g.recoil_keep)
	_kick_y += deg_to_rad(_rng.randfn(0.0, g.recoil_yaw_deg * 0.6))
	bloom_deg = minf(bloom_deg + g.bloom_per_shot, g.bloom_max_deg)
	var shake := deg_to_rad(g.shake_deg) * lerpf(1.0, 0.6, aim_blend)
	_shake = minf(_shake + shake, deg_to_rad(3.0))


func _muzzle_node() -> Node3D:
	if _holder != null and _holder.item_instance != null:
		return _holder.item_instance.find_child("Muzzle", true, false) as Node3D
	return null


## The rifle's casing: out of the right of the receiver, up and back.
func _eject_casing() -> void:
	if _holder == null or _holder.item_instance == null:
		return
	var xf: Transform3D = _holder.item_instance.global_transform
	# The item's local +X is the shooter's right (the old -X threw brass out of the left).
	var port := xf * Vector3(0.03, 0.06, -0.15)
	var dir := (xf.basis.x + xf.basis.y * 0.6 + xf.basis.z * 0.4).normalized()
	fx.casing(port, dir)


func _muzzle_position() -> Vector3:
	if _holder != null and _holder.item_instance != null:
		var m := _holder.item_instance.find_child("Muzzle", true, false) as Node3D
		if m != null:
			return m.global_position
		return _holder.item_instance.global_position
	return _pilot.global_position + Vector3.UP * 1.4


## The nearest ancestor of `node` (or itself) that answers `method`.
static func _owner_with(node: Node, method: StringName) -> Node:
	var n := node
	while n != null:
		if n.has_method(method):
			return n
		n = n.get_parent()
	return null


# --- HUD --------------------------------------------------------------------------------------------

func _update_hud(g: GunDef) -> void:
	var show: bool = g != null and not _pilot.frozen
	_layer.visible = show
	if not show:
		return
	_name_label.text = g.display_name
	var rounds := int(_rounds.get(g, g.magazine))
	_ammo_label.text = ammo_text(rounds, is_reloading())
	var empty := rounds <= 0 and not is_reloading()
	var blink := _dry_flash > 0.0 and int(_dry_flash * 24.0) % 2 == 0
	_ammo_label.add_theme_color_override(&"font_color",
		HOT if (empty or blink) else Ps1Plate.TEXT)
	_cross.queue_redraw()


func _draw_crosshair() -> void:
	var g := gun()
	if g == null:
		return
	# The centre is NOT snapped: the block grid is laid out relative to it, so the T keeps its chunky
	# pixel shape but slides smoothly with the barrel.
	_cross_origin = _cross.size * 0.5 + _barrel_offset
	var centre := Vector2.ZERO
	var hit_on := _hit_flash > 0.0 and int(_hit_flash * 60.0) % 2 == 0
	var col := HOT if hit_on else Color(1, 1, 1, 0.95)
	var prog := reload_progress()
	# A T with an empty centre: left, right and bottom arms (no top). The arms ride out with the
	# spread; a reload dims them and refills them in turn, right, bottom, left.
	var cam: Camera3D = _pilot.camera_3d
	var cone := spread_deg(g, aim_blend, bloom_deg)
	var gap := CROSS_GAP + ring_radius(cone, cam.fov, _cross.size.y) - CROSS_AIM_RADIUS
	var arms := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var total := arms.size() * CROSS_ARM_BLOCKS
	var i := 0
	for d: Vector2 in arms:
		for k in CROSS_ARM_BLOCKS:
			var lit := prog < 0.0 or float(i) / float(total) <= prog
			_pixel(centre + d * (gap + CROSS_BLOCK * float(k)),
				col if lit else Color(col.r, col.g, col.b, 0.28), 1.0)
			i += 1
	if _hit_flash > 0.0:
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			for k in 2:
				_pixel(centre + d * CROSS_BLOCK * float(k + 2) * 1.4, HOT, 0.85)


## Where the barrel points, on screen: a point BARREL_FAR down its line projected through the camera,
## as pixels off the centre, clamped, and blended in with the aim pose.
func _update_barrel_offset(g: GunDef) -> void:
	var muzzle := _muzzle_node() if g != null and aim_pose > 0.01 else null
	# Free-look: the crosshair stays where it was on screen while the camera looks around.
	if muzzle != null and _free_looking():
		return
	if muzzle == null:
		_barrel_offset = Vector2.ZERO
		return
	var cam: Camera3D = _pilot.camera_3d
	var from := muzzle.global_position
	var fwd := -muzzle.global_basis.z.normalized()
	# The direction, not the hit: a barrel aimed at the horizon over open ground still reads centre.
	# Read where the IK converges it (6..25 m), so the shoulder's parallax cancels there and only a
	# real miss of the camera's line (recoil, a turn the body lags) shows.
	var reach := BARREL_FAR
	if _holder != null and _holder.arm_modifier != null:
		reach = from.distance_to(_holder.arm_modifier.ik_aim_point)
	var point := from + fwd * clampf(reach, 3.0, BARREL_FAR)
	if cam.is_position_behind(point):
		_barrel_offset = Vector2.ZERO
		return
	var vp := cam.get_viewport().get_visible_rect().size
	var off := (cam.unproject_position(point) - vp * 0.5) * (_cross.size / vp)
	_barrel_offset = off.limit_length(CROSS_MAX_DRIFT) * clampf((aim_pose - 0.9) / (BARREL_READY - 0.9), 0.0, 1.0)


## One crosshair pixel: a plain block (no outline), snapped to the block grid.
func _pixel(at: Vector2, colour: Color, scale_px: float) -> void:
	var b := CROSS_BLOCK * scale_px
	# Snap the offset from the (smoothly moving) origin, not the screen position.
	var snap_at := (at / CROSS_BLOCK).round() * CROSS_BLOCK + _cross_origin
	_cross.draw_rect(Rect2(snap_at - Vector2.ONE * b * 0.5, Vector2.ONE * b), colour)
