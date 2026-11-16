## The gun's visual feedback, built from hand-drawn-in-code pixel art: a layered muzzle flash (jet
## + star + embers + a stepped light), a fast tracer with a colour-banded trail, barrel smoke (smooth
## soft billowing puffs, shaders/gun_ink.gdshader, not pixel art) that builds with sustained fire, impacts (burst, dust, bouncing sparks, a fading hole), rifle casings
## and reload brass. Sprites are nearest-filtered, unshaded and alpha-cut so they stay crisp under
## every look. Built by gunplay.gd, which only ever calls the verbs below.
## See docs/specs/pilot9-gunplay-pass3.md.
extends Node

const TRACER_SPEED := 900.0
const TRACER_HEAD_LEN := 3.0
const TRACER_FADE := 0.08
const TRACER_TAIL_LEN := 12.0
const HOLE_LIFE := 20.0
const MAX_HOLES := 24

const FRAME_DT := 0.018
const FLASH_FRAMES := 5
const FLASH_TIME := FRAME_DT * FLASH_FRAMES

const JET_W := 28
const JET_H := 14
const JET_PX := 0.02
const STAR_PX := 0.018
const MAX_SPRITES := 60
const MAX_INKS := 24

const HEAT_ON := 2.4
const HEAT_OFF := 1.2
const HEAT_MAX := 6.0

## Hot to cold: white, yellow, orange, red, dark.
const RAMP: Array[Color] = [
	Color(1.0, 1.0, 0.9), Color(1.0, 0.88, 0.35), Color(1.0, 0.56, 0.14),
	Color(0.82, 0.22, 0.1), Color(0.3, 0.09, 0.14)]

## Live debris: {node, vel, life, gravity, floor, bounce, spin}.
var _bits: Array[Dictionary] = []
var _tracers: Array[Dictionary] = []
var _holes: Array[Node3D] = []
var _flash_nodes: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _anims: Array[Dictionary] = []

var _jets: Array = []
var _stars: Array = []
var _smoke: Array = []
var _bursts: Array = []
var _inks: Array[Dictionary] = []
var _ink_mesh: QuadMesh
var _ink_mat: ShaderMaterial
var _art_ready := false

var heat := 0.0
var _heat_decay := 1.0 / 1.5
var _smoking := false
var _smoke_timer := 0.0
var _muzzle: Node3D


static func flat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	return m


static func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	mesh.material_override = flat(colour)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


static func _h(a: int, b: int, c: int = 0) -> float:
	return float(((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) & 0xFFFF) / 65535.0


## Palette step for a heat value 0..1 (transparent when cold).
static func ramp(h: float) -> Color:
	if h > 0.8:
		return RAMP[0]
	if h > 0.6:
		return RAMP[1]
	if h > 0.42:
		return RAMP[2]
	if h > 0.25:
		return RAMP[3]
	if h > 0.1:
		return RAMP[4]
	return Color(0, 0, 0, 0)


# --- pixel art ------------------------------------------------------------------------------------

func _ensure_art() -> void:
	if _art_ready:
		return
	_art_ready = true
	for v in 3:
		var frames: Array = []
		for t in FLASH_FRAMES:
			frames.append(_jet_tex(v, t))
		_jets.append(frames)
	for t in 2:
		_stars.append(_star_tex(t))
	for t in 4:
		_smoke.append(_smoke_tex(t))
	for t in 3:
		_bursts.append(_burst_tex(t))


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## One frame of the forward flame: grows to its longest on frame 1, then shrinks and cools.
static func _jet_tex(variant: int, t: int) -> ImageTexture:
	var img := Image.create(JET_W, JET_H, false, Image.FORMAT_RGBA8)
	var length: float = [0.45, 1.0, 0.88, 0.62, 0.38][t] * [1.0, 0.84, 1.14][variant]
	length = minf(length, 1.0)
	var wmax: float = [0.5, 0.85, 0.7, 0.5, 0.3][t]
	var half := JET_H * 0.5
	for x in JET_W:
		var u := (x + 0.5) / JET_W
		if u >= length:
			continue
		var base := wmax * half * pow(1.0 - u / length, 0.65)
		for y in JET_H:
			var dy := y + 0.5 - half
			var side := 1.0 + (0.28 if (dy < 0.0) == (variant == 1) else -0.18) * (1 if variant > 0 else 0)
			var jag := (_h(x >> 1, y >> 1, variant * 7 + t) - 0.5) * 2.4 * u
			var edge := base * side + jag
			if absf(dy) > edge:
				continue
			var hot := (1.0 - absf(dy) / maxf(edge, 0.5)) * 0.5 + (1.0 - u / length) * 0.5 - t * 0.1
			var c := ramp(hot)
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	return _tex(img)


static func _star_tex(t: int) -> ImageTexture:
	var img := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	var reach := 6 if t == 0 else 3
	for y in 13:
		for x in 13:
			var dx := absi(x - 6)
			var dy := absi(y - 6)
			var d := maxi(dx, dy)
			var on := ((dx == 0 or dy == 0) and d <= reach) \
				or (dx == dy and dx <= int(reach * 0.55)) or (dx * dx + dy * dy <= 3)
			if on:
				var c := ramp(1.0 - float(d) / (reach + 1.0) - t * 0.12)
				if c.a > 0.0:
					img.set_pixel(x, y, c)
	return _tex(img)


static func _smoke_tex(t: int) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	var tones := [Color(0.82, 0.84, 0.88), Color(0.62, 0.64, 0.72), Color(0.42, 0.44, 0.54)]
	for y in 14:
		for x in 14:
			var dx := x - 6.5
			var dy := y - 6.5
			var r := sqrt(dx * dx + dy * dy)
			var rad := 5.2 + (_h(x, y, 3) - 0.5) * 2.6
			if r > rad:
				continue
			if _h(x, y, 11 + t) < t * 0.22:
				continue
			var shade := clampi(int((dx + dy + 9.0) / 6.5), 0, 2)
			img.set_pixel(x, y, tones[shade])
	return _tex(img)


static func _burst_tex(t: int) -> ImageTexture:
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	for y in 11:
		for x in 11:
			var d := sqrt((x - 5.0) * (x - 5.0) + (y - 5.0) * (y - 5.0))
			var on := false
			if t == 0:
				on = d <= 2.3
			elif t == 1:
				on = d <= 4.2 and (d >= 2.0 or _h(x, y, 5) > 0.5)
			else:
				on = d <= 5.2 and d >= 3.6 and _h(x, y, 6) > 0.45
			if on:
				var c := ramp(0.95 - t * 0.3 - d * 0.04)
				if c.a > 0.0:
					img.set_pixel(x, y, c)
	return _tex(img)


func _sprite(tex: Texture2D, px: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


func _jet_quad(tex: Texture2D, s: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(JET_W, JET_H) * JET_PX * s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad's x runs down the barrel, its y stays up.
	mi.basis = Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	mi.position = Vector3(0, 0, -JET_W * JET_PX * s * 0.5)
	return mi


# --- muzzle ---------------------------------------------------------------------------------------

## Set true to bring back the flash sprites + light (embers and smoke are unaffected).
const SHOW_FLASH := true

## The flash on the muzzle marker (so it rides the gun's kick), its stepped light, forward embers,
## and a bit of heat. `heavy` is the revolver: bigger, hotter, a longer tail, slower smoke build.
func muzzle_flash(muzzle: Node3D, heavy: bool = false) -> void:
	if muzzle == null:
		return
	_ensure_art()
	var s := 1.6 if heavy else 1.0
	if not SHOW_FLASH:
		_muzzle_embers(muzzle, s)
		_register_shot(muzzle, heavy)
		return
	var root := Node3D.new()
	root.name = &"MuzzleFlash"
	muzzle.add_child(root)
	root.transform = Transform3D.IDENTITY
	var variant := randi() % 3
	var mats: Array[StandardMaterial3D] = []
	var jets: Array = _jets[variant]
	var pivot := Node3D.new()
	root.add_child(pivot)
	pivot.rotate_z(randf() * TAU)
	for k in 2:
		var arm := Node3D.new()
		pivot.add_child(arm)
		arm.rotate_z(k * PI * 0.5)
		var jq := _jet_quad(jets[0], s)
		arm.add_child(jq)
		mats.append(jq.material_override)
	var star := _sprite(_stars[0], STAR_PX * s)
	star.position = Vector3(0, 0, -0.03)
	root.add_child(star)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.92, 0.72)
	light.light_energy = 2.6 * (1.5 if heavy else 1.0) * randf_range(0.75, 1.25)
	light.omni_range = 5.5
	light.shadow_enabled = false
	root.add_child(light)
	_flash_nodes.append({"node": root, "light": light, "age": 0.0, "mats": mats, "jets": jets,
		"star": star, "energy": light.light_energy, "life": FLASH_TIME + (FRAME_DT if heavy else 0.0),
		"frame": -1, "light_step": -1})
	_step_flash(_flash_nodes[-1], 0.0)
	_muzzle_embers(muzzle, s)
	_register_shot(muzzle, heavy)


func _muzzle_embers(muzzle: Node3D, s: float) -> void:
	var fwd := -muzzle.global_basis.z
	for i in 5:
		var d := (fwd + Vector3(randf_range(-0.35, 0.35), randf_range(-0.2, 0.4),
			randf_range(-0.35, 0.35))).normalized()
		_ember(muzzle.global_position + fwd * 0.05, d * randf_range(3.0, 7.0) * s,
			randf_range(0.18, 0.3), 7.0, 0.028 * s)


func _step_flash(f: Dictionary, delta: float) -> void:
	f.age = float(f.age) + delta
	var age: float = f.age
	var frame := mini(int(age / FRAME_DT), FLASH_FRAMES - 1)
	if frame != f.frame:
		f.frame = frame
		var jets: Array = f.jets
		for m in f.mats:
			(m as StandardMaterial3D).albedo_texture = jets[frame]
		var star: Sprite3D = f.star
		if is_instance_valid(star):
			star.visible = frame < 2
			if frame < 2:
				star.texture = _stars[frame]
	var step := 0 if age < 0.025 else (1 if age < 0.055 else 2)
	if step != f.light_step and is_instance_valid(f.light):
		f.light_step = step
		var l: OmniLight3D = f.light
		l.light_color = [Color(1.0, 0.92, 0.72), Color(1.0, 0.6, 0.22), Color(0.8, 0.22, 0.1)][step]
		l.light_energy = float(f.energy) * [1.0, 0.7, 0.4][step]


func _step_flashes(delta: float) -> void:
	var i := _flash_nodes.size() - 1
	while i >= 0:
		var f: Dictionary = _flash_nodes[i]
		var n: Node3D = f.node
		if not is_instance_valid(n):
			_flash_nodes.remove_at(i)
			i -= 1
			continue
		_step_flash(f, delta)
		if float(f.age) >= float(f.life):
			n.queue_free()
			_flash_nodes.remove_at(i)
		i -= 1


# --- smoke ----------------------------------------------------------------------------------------

## Heat builds per shot and bleeds off; three quick shots light the barrel and it keeps smoking
## until the heat drains. The revolver's window is twice the rifle's (its shots are slower).
func _register_shot(muzzle: Node3D, heavy: bool) -> void:
	_muzzle = muzzle
	_heat_decay = 1.0 / (3.0 if heavy else 1.5)
	heat = minf(heat + 1.0, HEAT_MAX)
	if heat < HEAT_ON:
		_wisp(muzzle, 0.55, 0.55, 0.7, 1.0)
		if heavy:
			_wisp(muzzle, 0.7, 0.5, 0.8, 1.0)


func is_smoking() -> bool:
	return _smoking


## One soft smoke puff off the muzzle: starts small and dense, rolls forward and up, grows and
## thins to nothing. `size` is its final diameter scale, `up` and `fwd` weight its drift.
func _wisp(muzzle: Node3D, size: float, up: float, life: float, fwd: float) -> void:
	if not is_instance_valid(muzzle) or _inks.size() >= MAX_INKS:
		return
	if _ink_mesh == null:
		_ink_mesh = QuadMesh.new()
		_ink_mesh.size = Vector2(1.0, 1.0)
		_ink_mat = ShaderMaterial.new()
		_ink_mat.shader = load("res://shaders/gun_ink.gdshader")
	var f := -muzzle.global_basis.z
	var mi := MeshInstance3D.new()
	mi.mesh = _ink_mesh
	mi.material_override = _ink_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	# About half the puffs are tail puffs: smaller, longer-lived, lifted off the top of the muzzle so
	# they string into a thin trailing tail above the billow.
	var tail := randf() < 0.5
	if tail:
		size *= 0.55
		life *= 2.2
		up *= 2.2
		fwd *= 0.3
	var final := size * 0.5 * randf_range(0.8, 1.2)
	mi.scale = Vector3.ONE * final * 0.25
	add_child(mi)
	mi.global_position = muzzle.global_position + f * 0.04 + (Vector3.UP * 0.03 if tail else Vector3.ZERO)
	mi.set_instance_shader_parameter("seed", randf())
	mi.set_instance_shader_parameter("tint", Color(0.72, 0.75, 0.82).lerp(Color(0.92, 0.93, 0.97), randf()))
	mi.set_instance_shader_parameter("age", 0.0)
	var vel := f * 0.5 * fwd + Vector3.UP * up * 0.3 		+ Vector3(randf_range(-0.12, 0.12), randf_range(0.0, 0.08), randf_range(-0.12, 0.12))
	_inks.append({"node": mi, "vel": vel, "life": life * randf_range(0.9, 1.4), "age": 0.0,
		"final": final, "tail": tail})


func _step_inks(delta: float) -> void:
	var i := _inks.size() - 1
	while i >= 0:
		var a: Dictionary = _inks[i]
		var n: MeshInstance3D = a.node
		if not is_instance_valid(n):
			_inks.remove_at(i)
			i -= 1
			continue
		a.age = float(a.age) + delta
		var k := float(a.age) / float(a.life)
		if k >= 1.0:
			n.queue_free()
			_inks.remove_at(i)
			i -= 1
			continue
		n.set_instance_shader_parameter("age", k)
		# Grows fast then eases out (a puff expanding into the air).
		n.scale = Vector3.ONE * float(a.final) * (0.25 + 0.75 * (1.0 - pow(1.0 - k, 2.0)))
		# Drag bleeds the muzzle push off; a gentle lift keeps it rising.
		a.vel = (a.vel as Vector3) * pow(0.35 if not a.get("tail", false) else 0.8, delta) 			+ Vector3.UP * (0.25 if not a.get("tail", false) else 0.5) * delta
		n.global_position += (a.vel as Vector3) * delta
		i -= 1


func _step_smoke(delta: float) -> void:
	# Once the barrel is smoking, the heat drains twice as fast: the smoke lasts half as long.
	heat = maxf(0.0, heat - _heat_decay * (2.0 if _smoking else 1.0) * delta)
	if _smoking and (heat < HEAT_OFF or not is_instance_valid(_muzzle)):
		_smoking = false
	elif not _smoking and heat >= HEAT_ON and is_instance_valid(_muzzle):
		_smoking = true
	if not _smoking:
		return
	_smoke_timer -= delta
	if _smoke_timer <= 0.0:
		var rate := clampf((heat - 1.0) * 4.0, 3.0, 14.0)
		_smoke_timer = 1.0 / rate
		_wisp(_muzzle, 0.9 + heat * 0.08, 0.6, 1.5, 0.5)


# --- generic pixel sprites ------------------------------------------------------------------------

## A billboard that plays `frames` over `life`, drifting, growing and cooling its tint.
func _anim(frames: Array, at: Vector3, vel: Vector3, life: float, px_from: float, px_to: float,
		tint_from: Color, tint_to: Color, wobble: float) -> void:
	if _anims.size() >= MAX_SPRITES:
		return
	var s := _sprite(frames[0], px_from)
	s.top_level = true
	add_child(s)
	s.global_position = at
	s.modulate = tint_from
	_anims.append({"node": s, "frames": frames, "vel": vel, "life": life, "age": 0.0,
		"from": px_from, "to": px_to, "a": tint_from, "b": tint_to, "wobble": wobble,
		"phase": randf() * TAU})


func _step_anims(delta: float) -> void:
	var i := _anims.size() - 1
	while i >= 0:
		var a: Dictionary = _anims[i]
		var n: Sprite3D = a.node
		if not is_instance_valid(n):
			_anims.remove_at(i)
			i -= 1
			continue
		a.age = float(a.age) + delta
		var k := float(a.age) / float(a.life)
		if k >= 1.0:
			n.queue_free()
			_anims.remove_at(i)
			i -= 1
			continue
		var frames: Array = a.frames
		n.texture = frames[mini(int(k * frames.size()), frames.size() - 1)]
		n.pixel_size = lerpf(float(a.from), float(a.to), sqrt(k))
		n.modulate = (a.a as Color).lerp(a.b, k)
		var w := float(a.wobble)
		var ph := float(a.age) * 3.4 + float(a.phase)
		n.global_position += (a.vel as Vector3) * delta + Vector3(sin(ph), 0, cos(ph)) * w * delta
		a.vel = (a.vel as Vector3) * pow(0.35, delta)
		i -= 1


# --- embers ---------------------------------------------------------------------------------------

## A tiny cube that cools through the palette as it flies. `floor_y` makes it bounce once.
func _ember(at: Vector3, vel: Vector3, life: float, gravity: float, size: float,
		floor_y: float = -INF) -> void:
	if _embers.size() >= 80:
		return
	var m := _box(Vector3.ONE * size, RAMP[0])
	m.top_level = true
	add_child(m)
	m.global_position = at
	_embers.append({"node": m, "vel": vel, "life": life, "age": 0.0, "gravity": gravity,
		"size": size, "floor": floor_y, "bounced": false})


func _step_embers(delta: float) -> void:
	var i := _embers.size() - 1
	while i >= 0:
		var e: Dictionary = _embers[i]
		var n: MeshInstance3D = e.node
		if not is_instance_valid(n):
			_embers.remove_at(i)
			i -= 1
			continue
		e.age = float(e.age) + delta
		var k := float(e.age) / float(e.life)
		if k >= 1.0:
			n.queue_free()
			_embers.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = e.vel
		v.y -= float(e.gravity) * delta
		n.global_position += v * delta
		if n.global_position.y <= float(e.floor):
			n.global_position.y = float(e.floor)
			v = Vector3(v.x * 0.5, absf(v.y) * 0.4 if not e.bounced else 0.0, v.z * 0.5)
			e.bounced = true
		e.vel = v
		var step := mini(int(k * 4.0), 3)
		(n.material_override as StandardMaterial3D).albedo_color = RAMP[step]
		n.scale = Vector3.ONE * (0.5 if k > 0.85 else 1.0)
		i -= 1


# --- tracer ---------------------------------------------------------------------------------------

## A fast bright head with a colour-banded trail that cools behind it. `thick` scales both.
func tracer(from: Vector3, to: Vector3, thick: float = 1.0) -> void:
	var total := from.distance_to(to)
	if total < 0.3:
		return
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	var head := _box(Vector3(0.03, 0.03, 1.0) * Vector3(thick, thick, 1.0), RAMP[0])
	root.add_child(head)
	var bands: Array[MeshInstance3D] = []
	for b in 3:
		var band := _box(Vector3(0.012, 0.012, 1.0) * Vector3(thick, thick, 1.0), RAMP[1])
		root.add_child(band)
		bands.append(band)
	_tracers.append({"node": root, "head": head, "bands": bands, "from": from, "to": to,
		"dir": (to - from) / total, "total": total, "age": 0.0})
	_step_tracer(_tracers[-1], 0.0)


static func _place(n: Node3D, from: Vector3, dir: Vector3, a: float, b: float) -> void:
	var length := maxf(b - a, 0.001)
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	n.top_level = true
	n.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, length)),
		from + dir * (a + length * 0.5))


func _step_tracer(t: Dictionary, delta: float) -> bool:
	t.age = float(t.age) + delta
	var age: float = t.age
	var total: float = t.total
	var arrive := total / TRACER_SPEED
	var fade := maxf(age - arrive, 0.0)
	if fade >= TRACER_FADE:
		return false
	var pos := minf(age * TRACER_SPEED, total)
	var from: Vector3 = t.from
	var dir: Vector3 = t.dir
	var head: MeshInstance3D = t.head
	head.visible = age < arrive
	if head.visible:
		_place(head, from, dir, maxf(pos - TRACER_HEAD_LEN, 0.0), pos)
	var bands: Array = t.bands
	for i in bands.size():
		var band: MeshInstance3D = bands[i]
		# Oldest band (nearest the muzzle, i = 0) is the coolest; each step of fade cools them all.
		var idx := (2 - i) + int(fade / (TRACER_FADE / 3.0))
		band.visible = idx < 4
		if band.visible:
			(band.material_override as StandardMaterial3D).albedo_color = RAMP[clampi(idx, 1, 4)]
			# A short tail travelling with the head, not the whole muzzle-to-hit line.
			var tail_a := maxf(pos - TRACER_TAIL_LEN, 0.0)
			var seg := (pos - tail_a) / 3.0
			_place(band, from, dir, tail_a + seg * i, tail_a + seg * (i + 1))
	return true


func _step_tracers(delta: float) -> void:
	var i := _tracers.size() - 1
	while i >= 0:
		var t: Dictionary = _tracers[i]
		var n: Node3D = t.node
		if not is_instance_valid(n):
			_tracers.remove_at(i)
		elif not _step_tracer(t, delta):
			n.queue_free()
			_tracers.remove_at(i)
		i -= 1


# --- impacts --------------------------------------------------------------------------------------

## What a bullet leaves on the world: a flash burst, dust, bouncing sparks, a hole that fades.
func impact(point: Vector3, normal: Vector3, on_target: bool) -> void:
	_ensure_art()
	var at := point + normal * 0.06
	_anim(_bursts, at, Vector3.ZERO, 0.12, 0.016, 0.024, Color.WHITE, Color.WHITE, 0.0)
	var dust_a := Color(0.85, 0.75, 0.58) if normal.y > 0.7 else Color(0.76, 0.77, 0.82)
	var dust_b := Color(0.5, 0.48, 0.5)
	if on_target:
		dust_a = Color(1.0, 0.35, 0.25)
		dust_b = Color(0.5, 0.1, 0.15)
	for i in 2:
		var d := (normal + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.7),
			randf_range(-0.6, 0.6))).normalized()
		_anim(_smoke, at, d * randf_range(0.5, 1.4), randf_range(0.35, 0.55), 0.008, 0.02,
			dust_a, dust_b, 0.0)
	var floor_y := _floor_y(point)
	for i in 7:
		var d := (normal + Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0),
			randf_range(-1, 1))).normalized()
		_ember(at, d * randf_range(3.0, 6.5), randf_range(0.35, 0.55), 9.0, 0.03, floor_y)
	if not on_target:
		_hole(point, normal)


func _hole(point: Vector3, normal: Vector3) -> void:
	var m := _box(Vector3(0.09, 0.09, 0.012), Color(0.05, 0.05, 0.06))
	m.top_level = true
	add_child(m)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	m.global_transform = Transform3D(Basis.looking_at(-normal, up), point + normal * 0.012)
	_holes.append(m)
	while _holes.size() > MAX_HOLES:
		var old: Node3D = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	get_tree().create_timer(HOLE_LIFE).timeout.connect(func() -> void:
		if is_instance_valid(m):
			_holes.erase(m)
			m.queue_free())


# --- casings and brass ----------------------------------------------------------------------------

## A spent brass casing kicked out of `at` along `dir` (world), lands and rests.
func casing(at: Vector3, dir: Vector3, size: float = 1.0) -> void:
	var m := _box(Vector3(0.018, 0.018, 0.055) * size, Color(0.85, 0.62, 0.22))
	var vel := dir * randf_range(1.6, 2.6) + Vector3(0, randf_range(1.6, 2.4), 0)
	_spawn_bit(m, at, vel, 2.2, 14.0, true)


## A prop node that falls from `at` and rests on the floor (the dropped magazine).
func debris(node: Node3D, at: Vector3, vel: Vector3, life: float) -> void:
	_spawn_bit(node, at, vel, life, 14.0, true)


func _floor_y(at: Vector3) -> float:
	var floor_y := at.y - 1.6
	var space := get_viewport().world_3d.direct_space_state if get_viewport() != null else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * 4.0, 1)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			floor_y = r.position.y + 0.01
	return floor_y


func _spawn_bit(node: Node3D, at: Vector3, vel: Vector3, life: float, gravity: float,
		rests: bool = false) -> void:
	node.top_level = true
	add_child(node)
	node.global_position = at
	_bits.append({"node": node, "vel": vel, "life": life, "gravity": gravity,
		"floor": _floor_y(at), "rests": rests, "spin": Vector3(randf_range(-9, 9),
		randf_range(-9, 9), randf_range(-9, 9))})


func _process(delta: float) -> void:
	_step_bits(delta)
	_step_tracers(delta)
	_step_flashes(delta)
	_step_embers(delta)
	_step_anims(delta)
	_step_inks(delta)
	_step_smoke(delta)


func _step_bits(delta: float) -> void:
	var i := _bits.size() - 1
	while i >= 0:
		var b: Dictionary = _bits[i]
		var n: Node3D = b.node
		if not is_instance_valid(n):
			_bits.remove_at(i)
			i -= 1
			continue
		b.life -= delta
		if b.life <= 0.0:
			n.queue_free()
			_bits.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = b.vel
		var resting: bool = b.get("resting", false)
		if not resting:
			v.y -= float(b.gravity) * delta
			n.global_position += v * delta
			n.rotate_x(b.spin.x * delta)
			n.rotate_y(b.spin.y * delta)
			if n.global_position.y <= float(b.floor):
				n.global_position.y = float(b.floor)
				if bool(b.rests):
					if absf(v.y) > 0.8:
						v = Vector3(v.x * 0.4, -v.y * 0.35, v.z * 0.4)
					else:
						b.resting = true
						v = Vector3.ZERO
				else:
					v = Vector3(v.x * 0.3, 0.0, v.z * 0.3)
			b.vel = v
		i -= 1
