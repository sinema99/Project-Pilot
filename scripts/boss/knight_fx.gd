class_name KnightFx
extends RefCounted

# Shared bits for the Knight's attack visuals (docs/specs/knight-moveset.md): the hostile colours,
# glow materials, and one-shot particle bursts. Bursts are cosmetic, so MOVEMENT EFFECTS gates
# them; telegraphs, beams and missiles never ask.

## The range bolt's hostile red, and the white-hot core / lock flash.
const RED := Color(1.0, 0.18, 0.12)
const WHITE := Color(1.0, 0.96, 0.92)
const DUST := Color(0.82, 0.85, 0.9)
const SMOKE := Color(0.3, 0.28, 0.3)


## MOVEMENT EFFECTS (on outside the game, e.g. a bare test tree).
static func effects_on() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null(^"/root/Settings") if tree != null else null
	return s == null or bool(s.get(&"movement_effects"))


## An unshaded glow material, optionally see-through (`color.a` < 1 needs `alpha`).
static func glow(color: Color, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
	return m


## A low-poly ball for particles: round in the cel look where a quad reads as a square chip.
## Vertex colour (the particles' ramp) is its colour and alpha.
static func puff(size: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = size * 0.5
	m.height = size
	m.radial_segments = 8
	m.rings = 4
	var mat := glow(Color.WHITE, true)
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	return m


## A one-shot burst of `count` quads at `point`, thrown out at up to `speed` (m/s, mostly up),
## each `size` m, living `life` s. Frees itself. Nothing when MOVEMENT EFFECTS is off.
static func burst(parent: Node, point: Vector3, count: int, speed: float, color: Color, size: float,
		life: float, flat := false) -> CPUParticles3D:
	if not effects_on() or parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.name = &"KnightBurst"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(count, 1)
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 85.0 if flat else 70.0
	p.flatness = 0.85 if flat else 0.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	p.mesh = puff(size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p
