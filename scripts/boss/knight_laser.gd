class_name KnightLaser
extends Node3D

# The Knight's laser visuals (docs/specs/knight-moveset.md, decision 6): a thin red aim line that
# tracks pilot, the same line white and thicker once locked, then the beam - a white-hot core in a
# red glow - with a flash at the claw. Placed in world space (top_level); KnightBrain drives it and
# does the hit test.

## Aim line radius while tracking / once locked (m).
@export var aim_radius := 0.03
@export var lock_radius := 0.07
## The beam: white core and red glow radii (m). The glow is the hit width (0.8 m across).
@export var core_radius := 0.16
@export var glow_radius := 0.4

var _aim: MeshInstance3D
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _muzzle: MeshInstance3D
var _aim_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D


func _init() -> void:
	top_level = true
	name = &"KnightLaser"
	_aim_mat = KnightFx.glow(KnightFx.RED)
	_aim = _cylinder(&"Aim", _aim_mat)
	_core_mat = KnightFx.glow(KnightFx.WHITE, true)
	_core = _cylinder(&"Core", _core_mat)
	_glow_mat = KnightFx.glow(Color(KnightFx.RED.r, KnightFx.RED.g, KnightFx.RED.b, 0.55), true)
	_glow = _cylinder(&"Glow", _glow_mat)
	_muzzle = MeshInstance3D.new()
	_muzzle.name = &"Muzzle"
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 12
	s.rings = 6
	s.material = _core_mat
	_muzzle.mesh = s
	_muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_muzzle)
	hide_all()


func _cylinder(n: StringName, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var c := CylinderMesh.new()
	c.top_radius = 1.0
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 10
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	c.material = mat
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Stretches a unit cylinder (Y axis, centred) from `a` to `b` at radius `r`.
static func span(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var len := maxf(d.length(), 0.001)
	var y := d / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x * r, y * len, z * r), (a + b) * 0.5)


func hide_all() -> void:
	for mi in [_aim, _core, _glow, _muzzle]:
		mi.visible = false


func is_aiming() -> bool:
	return _aim.visible


func is_firing() -> bool:
	return _core.visible


## The aim line from the claw to `to`. `locked` turns it white and thick; `flash` (0..1) pulses it.
func show_aim(from: Vector3, to: Vector3, locked: bool, flash := 0.0) -> void:
	_core.visible = false
	_glow.visible = false
	_muzzle.visible = false
	_aim.visible = true
	_aim_mat.albedo_color = KnightFx.WHITE if locked else KnightFx.RED
	var r := lock_radius * (1.0 + 0.5 * flash) if locked else aim_radius
	span(_aim, from, to, r)


## The beam from the claw to `to`; `fade` (1 -> 0) thins it out at the end.
func show_beam(from: Vector3, to: Vector3, fade: float) -> void:
	_aim.visible = false
	_core.visible = true
	_glow.visible = true
	_muzzle.visible = true
	var k := clampf(fade, 0.0, 1.0)
	span(_core, from, to, core_radius * (0.4 + 0.6 * k))
	span(_glow, from, to, glow_radius * (0.5 + 0.5 * k))
	_glow_mat.albedo_color.a = 0.55 * k
	_core_mat.albedo_color.a = k
	_muzzle.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.6 + 0.6 * k)), from)
