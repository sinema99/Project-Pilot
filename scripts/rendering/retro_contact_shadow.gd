class_name RetroContactShadow
extends MeshInstance3D

# RETRO's contact shadow (docs/specs/retro-look-pass-2.md): a soft cool ellipse on the ground under
# one body, the way a cel animator paints the shadow under a character's feet. RetroLook adds one
# per CharacterBody3D / AnimatableBody3D while RETRO is on and frees them when it goes off.
#
# Top level, so it never tilts with the body: each physics frame a ray from the body finds the
# ground and the quad lies on it. Lifting off shrinks and fades it, so it also says how high you are.

const SHADER := preload("res://shaders/cel/retro_contact_shadow.gdshader")

## Ellipse radius as a multiple of the body's collision footprint radius.
@export var footprint_scale := 1.5
## Opacity on the ground.
@export_range(0.0, 1.0, 0.01) var strength := 0.6
## Height above its resting gap where it reaches its smallest and faintest.
@export var fade_height := 6.0
@export_range(0.0, 1.0, 0.01) var min_size := 0.5
@export_range(0.0, 1.0, 0.01) var min_strength := 0.25
## How far down the ray looks.
@export var reach := 40.0

var body: CollisionObject3D
var _material: ShaderMaterial
var _radius := 0.5
## The smallest body-origin-to-ground gap seen: the body standing. Bodies whose origin sits at the
## feet rest at ~0, capsule-centred ones higher.
var _rest := INF


static func for_body(b: CollisionObject3D, tint: Color) -> RetroContactShadow:
	var s := RetroContactShadow.new()
	s.body = b
	s.name = &"RetroContactShadow"
	s._material = ShaderMaterial.new()
	s._material.shader = SHADER
	s._material.set_shader_parameter(&"tint", tint)
	s.material_override = s._material
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	s.mesh = plane
	s._radius = footprint_radius(b) * s.footprint_scale
	return s


## Half the widest horizontal extent of the body's collision shapes, in world metres.
static func footprint_radius(b: CollisionObject3D) -> float:
	var r := 0.0
	for child in b.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var aabb: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		r = maxf(r, maxf(aabb.size.x, aabb.size.z) * 0.5)
	return r if r > 0.0 else 0.4


func _ready() -> void:
	top_level = true
	visible = false


func _physics_process(_delta: float) -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		visible = false
		return
	var from := body.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * reach,
			body.collision_mask, [body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		visible = false
		return
	var gap: float = body.global_position.y - hit.position.y
	_rest = minf(_rest, maxf(gap, 0.0))
	var t := clampf((gap - _rest) / maxf(fade_height, 1e-3), 0.0, 1.0)
	var size := _radius * 2.0 * lerpf(1.0, min_size, t)
	var n: Vector3 = hit.normal
	var x := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(n).normalized()
	global_transform = Transform3D(Basis(x * size, n, z * size), hit.position + n * 0.03)
	_material.set_shader_parameter(&"strength", strength * lerpf(1.0, min_strength, t))
	visible = true
