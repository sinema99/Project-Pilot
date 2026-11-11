class_name KnightSmash
extends Node3D

# The Knight's smash visuals (docs/specs/knight-moveset.md, decision 8): the red floor ring that
# follows pilot then flashes white when locked, the expanding shockwave, the crack left in the
# floor, and the dust/snow burst. World space (top_level); KnightBrain places it and does the hits.

## Ring radius (the shockwave's reach) and its line width (m).
@export var radius := 6.0
@export var ring_width := 0.22
## Seconds the crack stays before it fades out (over 1 s).
@export var crack_time := 4.0

var _ring: MeshInstance3D
var _fill: MeshInstance3D
var _wave: MeshInstance3D
var _crack: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _wave_mat: StandardMaterial3D
var _crack_mat: StandardMaterial3D
var _crack_age := INF


func _init() -> void:
	top_level = true
	name = &"KnightSmash"
	_ring_mat = KnightFx.glow(KnightFx.RED)
	_ring = _annulus(&"Ring", 1.0 - ring_width / radius, 1.0, _ring_mat)
	_fill_mat = KnightFx.glow(Color(KnightFx.RED.r, KnightFx.RED.g, KnightFx.RED.b, 0.14), true)
	_fill = _annulus(&"Fill", 0.0, 1.0, _fill_mat)
	_wave_mat = KnightFx.glow(Color(1.0, 0.8, 0.75, 0.9), true)
	_wave = _annulus(&"Wave", 0.82, 1.0, _wave_mat)
	_crack_mat = KnightFx.glow(Color(0.05, 0.045, 0.05, 1.0), true)
	_crack = MeshInstance3D.new()
	_crack.name = &"Crack"
	_crack.mesh = _crack_mesh()
	_crack.mesh.surface_set_material(0, _crack_mat)
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	hide_all()


## A flat ring in XZ from `inner` to `outer` (unit radius; scaled by the node).
func _annulus(n: StringName, inner: float, outer: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 64
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		st.add_vertex(o0 * inner)
		st.add_vertex(o1 * outer)
		st.add_vertex(o0 * outer)
		st.add_vertex(o0 * inner)
		st.add_vertex(o1 * inner)
		st.add_vertex(o1 * outer)
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	mi.mesh.surface_set_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Jagged dark cracks radiating from the centre, unit-sized (scaled by `radius`).
static func _crack_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.25, 0.25)
		var p := Vector3.ZERO
		var len := rng.randf_range(0.45, 0.85)
		var steps := 4
		var w := 0.035
		for s in steps:
			a += rng.randf_range(-0.35, 0.35)
			var q := p + Vector3(cos(a), 0.0, sin(a)) * len / steps
			var side := (q - p).cross(Vector3.UP).normalized()
			var w1 := w * (1.0 - float(s + 1) / steps) + 0.004
			st.add_vertex(p + side * w)
			st.add_vertex(q - side * w1)
			st.add_vertex(q + side * w1)
			st.add_vertex(p + side * w)
			st.add_vertex(p - side * w)
			st.add_vertex(q - side * w1)
			p = q
			w = w1
	return st.commit()


func hide_all() -> void:
	for mi in [_ring, _fill, _wave, _crack]:
		mi.visible = false
	_crack_age = INF


func is_marking() -> bool:
	return _ring.visible


## The telegraph at `centre` (on the floor): red while it follows, white when `locked`.
func show_mark(centre: Vector3, locked: bool, flash := 0.0) -> void:
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), centre + Vector3.UP * 0.05)
	_ring.visible = true
	_fill.visible = true
	_ring.global_transform = xf
	_fill.global_transform = xf
	_ring_mat.albedo_color = KnightFx.WHITE.lerp(KnightFx.RED, 0.0 if locked else 1.0)
	_fill_mat.albedo_color.a = 0.14 + (0.18 * flash if locked else 0.0)


func hide_mark() -> void:
	_ring.visible = false
	_fill.visible = false


## The shockwave ring at `r` metres; `fade` 1 -> 0.
func show_wave(centre: Vector3, r: float, fade: float) -> void:
	_wave.visible = fade > 0.0
	_wave.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), centre + Vector3.UP * 0.08)
	_wave_mat.albedo_color.a = 0.9 * clampf(fade, 0.0, 1.0)


func hide_wave() -> void:
	_wave.visible = false


## The crack and the dust burst on impact.
func impact(centre: Vector3) -> void:
	_crack.visible = true
	_crack.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * radius * 0.8),
		centre + Vector3.UP * 0.04)
	_crack_age = 0.0
	_crack_mat.albedo_color.a = 1.0
	var parent := get_parent()
	KnightFx.burst(parent, centre + Vector3.UP * 0.3, 70, 11.0, KnightFx.DUST, 0.7, 1.1, true)
	KnightFx.burst(parent, centre + Vector3.UP * 0.2, 30, 7.0, KnightFx.WHITE, 0.25, 0.6)


func _process(delta: float) -> void:
	if _crack_age < INF:
		_crack_age += delta
		_crack_mat.albedo_color.a = clampf(1.0 - (_crack_age - crack_time), 0.0, 1.0)
		if _crack_age > crack_time + 1.0:
			_crack.visible = false
			_crack_age = INF
