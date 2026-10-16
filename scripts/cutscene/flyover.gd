class_name FlyoverShot
extends Node3D

# Cutscene shot 4: the ship flying over Ichi about 1000 ft up in the blizzard, seen from a chase
# camera tight behind its main engine. The building crawls left and down below; near the end the
# ship starts to bank left and the shot cuts mid-bank. See docs/specs/cutscene-flyover.md.
#
# Everything is a function of the shot time (flight line, float, bank, camera sway, trails), so
# seeking shows the same frame. Plays once on load and holds the last frame. R restarts, Esc quits.

## Emitted when the shot reaches its last frame. Later shots chain off this.
signal finished

const SHOT := &"shot"
const LIP_COLUMNS := 128
const SOLID_CELL := 4.0
const EDGE_SORT_DEPTH := 100.0
const EDGE_SHADER := preload("res://shaders/cutscene/flyover_edge.gdshader")
const SHIMMER_SHADER := preload("res://shaders/cutscene/heat_shimmer.gdshader")
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
## OP_1 ends ~270 m out; from this high its edges would show. Past them the ground is painted, not
## built: the sky draws a flat snow plane at `ground_y` below the horizon (shaders/cutscene/
## flyover_sky.gdshader), and the map's outer `edge_band` metres fade into the same paint, fully
## within `edge_solid` metres of its edge (deeper than the ragged edge's notches), so no edge is
## ever seen. The edge is the outer rectangle on west, east and south; on the north it is the
## canyon's lip (the canyon falls away out of sight), found from the mesh at load. `ground_color` is the snow before fog; `mottle` lightens/darkens soft
## patches about `mottle_size` metres across.
@export var ground_y := 0.0
@export var ground_color := Color(0.325, 0.35, 0.415)
@export_range(0.0, 0.3, 0.005) var mottle := 0.04
@export var mottle_size := 120.0
@export var edge_band := 80.0
@export var edge_solid := 25.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var ship: Node3D = $Ship
@onready var trail: IntroSpaceTrail = $EngineTrails
@onready var storm: Storm = $Storm
@onready var embers: FlyoverEmbers = $EngineEmbers

var _done := false
var _edge: MeshInstance3D
var _shimmers: Array[ShaderMaterial] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.fov = fov
	_place_glows()
	_build_shimmer()
	embers.nozzles = trail.nozzles
	embers.air = Vector3(storm.wind_direction.x, 0.0, storm.wind_direction.y).normalized() * storm.wind_speed
	_build_ground()
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


## Shows shot time `t`: ship, camera, trails, embers, shimmer.
func apply(t: float) -> void:
	ship.global_transform = ship_at(t)
	camera.global_transform = camera_at(t)
	if _edge != null:
		_edge.global_position = camera.global_position - camera.global_basis.z * EDGE_SORT_DEPTH
	# From a full trail life before the shot: it opens with the trails already streaming.
	trail.update_trail(t, t - trail.life, ship_at, func(_tau: float) -> float: return 0.0,
			camera.global_position)
	embers.update_embers(t, ship_at, camera.global_position, flight_at(t).basis.z * speed)
	for m in _shimmers:
		m.set_shader_parameter(&"shot_time", t)


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


# The painted ground past the map: the sky's ground plane and the edge fade quad. See the Ground
# exports.
func _build_ground() -> void:
	var terrain: MeshInstance3D = $OP_1.find_children("Plane", "MeshInstance3D", true, false)[0]
	var box := terrain.global_transform * terrain.get_aabb()
	var sky_mat := ($WorldEnvironment as WorldEnvironment).environment.sky.sky_material as ShaderMaterial
	var edge_mat := ShaderMaterial.new()
	edge_mat.shader = EDGE_SHADER
	edge_mat.set_shader_parameter(&"map_rect", Vector4(box.position.x, box.position.z, box.end.x, box.end.z))
	edge_mat.set_shader_parameter(&"lip_tex", _lip_texture(terrain, box))
	edge_mat.set_shader_parameter(&"building_tex", _building_texture(box))
	edge_mat.set_shader_parameter(&"edge_solid", edge_solid)
	edge_mat.set_shader_parameter(&"edge_band", edge_band)
	for m: ShaderMaterial in [sky_mat, edge_mat]:
		m.set_shader_parameter(&"ground_y", ground_y)
		m.set_shader_parameter(&"ground_color", ground_color)
		m.set_shader_parameter(&"mottle", mottle)
		m.set_shader_parameter(&"mottle_size", mottle_size)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	# Full-screen quad: never culled wherever the camera is.
	quad.custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	var mi := MeshInstance3D.new()
	mi.name = "GroundEdge"
	mi.mesh = quad
	mi.material_override = edge_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Draw order (transparent): heat shimmer (-101), storm fog (-100), crease ink and this quad (0),
	# snow (1), trails (2), nozzle glows (3), embers (4; those three set in the scene). Within 0 it sorts by its origin, which
	# apply() keeps EDGE_SORT_DEPTH ahead of the camera: after the map's crease ink (sorted at the
	# map's far-off centre), so it covers it.
	mi.sorting_use_aabb_center = false
	add_child(mi)
	_edge = mi
	for n in storm.get_children():
		var snow := n as GeometryInstance3D
		if snow != null and snow.material_override != storm.fog_material:
			snow.material_override.render_priority = 1


# The canyon lip's world z across the map's x range, one texel per `LIP_COLUMNS`th: the furthest
# north the terrain stays within 4 m of `ground_y` in each column. An empty column takes its
# neighbour's.
func _lip_texture(terrain: MeshInstance3D, box: AABB) -> ImageTexture:
	var lip := PackedFloat32Array()
	lip.resize(LIP_COLUMNS)
	lip.fill(-INF)
	var xf := terrain.global_transform
	for si in terrain.mesh.get_surface_count():
		for v: Vector3 in terrain.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var p := xf * v
			if p.y < ground_y - 4.0:
				continue
			var c := clampi(int((p.x - box.position.x) / box.size.x * LIP_COLUMNS), 0, LIP_COLUMNS - 1)
			lip[c] = maxf(lip[c], p.z)
	for c in range(1, LIP_COLUMNS):
		if lip[c] == -INF:
			lip[c] = lip[c - 1]
	for c in range(LIP_COLUMNS - 2, -1, -1):
		if lip[c] == -INF:
			lip[c] = lip[c + 1]
	var img := Image.create(LIP_COLUMNS, 1, false, Image.FORMAT_RF)
	for c in LIP_COLUMNS:
		img.set_pixel(c, 0, Color(lip[c], 0.0, 0.0))
	return ImageTexture.create_from_image(img)


# The building's height span per SOLID_CELL-metre cell over the map's box (r = lowest, g = highest
# point of any of its triangles whose x/z bounds touch the cell, grown one cell each way), so the
# edge pass leaves it alone. Cells it does not touch hold an empty span.
func _building_texture(box: AABB) -> ImageTexture:
	var w := int(ceil(box.size.x / SOLID_CELL))
	var h := int(ceil(box.size.z / SOLID_CELL))
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(w * h)
	hi.resize(w * h)
	lo.fill(INF)
	hi.fill(-INF)
	var cell := func(v: float, origin: float, n: int) -> int:
		return clampi(int((v - origin) / SOLID_CELL), 0, n - 1)
	for mi: MeshInstance3D in $OP_1.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Plane":
			continue
		var xf := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			for t in range(0, idx.size(), 3):
				var a := xf * verts[idx[t]]
				var b := xf * verts[idx[t + 1]]
				var c := xf * verts[idx[t + 2]]
				var x0: int = cell.call(minf(a.x, minf(b.x, c.x)), box.position.x, w) - 1
				var x1: int = cell.call(maxf(a.x, maxf(b.x, c.x)), box.position.x, w) + 1
				var z0: int = cell.call(minf(a.z, minf(b.z, c.z)), box.position.z, h) - 1
				var z1: int = cell.call(maxf(a.z, maxf(b.z, c.z)), box.position.z, h) + 1
				for cz in range(maxi(z0, 0), mini(z1, h - 1) + 1):
					for cx in range(maxi(x0, 0), mini(x1, w - 1) + 1):
						var i := cz * w + cx
						lo[i] = minf(lo[i], minf(a.y, minf(b.y, c.y)))
						hi[i] = maxf(hi[i], maxf(a.y, maxf(b.y, c.y)))
	var img := Image.create(w, h, false, Image.FORMAT_RGF)
	for i in w * h:
		@warning_ignore("integer_division")
		img.set_pixel(i % w, i / w, Color(1e9, -1e9, 0.0) if lo[i] == INF else Color(lo[i], hi[i], 0.0))
	return ImageTexture.create_from_image(img)


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
