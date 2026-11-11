class_name KnightBody
extends Node3D

# The knight boss's body (docs/specs/knight-boss.md): an armoured, robed knight built in code on
# pilot9's skeleton. pilot9's own meshes are removed; every part here is a skinned ArrayMesh bound
# to his bones, modelled in the skeleton's rest space (T-pose, 1.81 m, facing +Z, his left = +X).
# Rigid parts carry one bone at 1.0; the torso blends up the spine and the long pleated robe blends
# from the hips into the legs.
#
# Round 2 (look pass): he has his own key light (KeyLight, on LIGHT_LAYER only) so the player sees
# the drawing's mint light / mauve-brown shadow split whatever the map's sun does; the map's sun
# leaves that layer out (`exclude_from`).
#
# The pose layer (docs/specs/knight-moveset.md): any pose table (KnightPoses) is solved once into
# local bone rotations, and the body shows a blend of two solved poses plus an optional additive
# table. KnightBrain picks the poses; the body starts in the drawing's pose. He answers take_hit()
# (a white flash and red sparks) so a perfect-reflected missile lands on him.

const PILOT_GLB := "res://assets/pilot9.glb"
const CEL := "res://resources/pilot_cel_character.tres"

## The render layer his parts sit on, and the only one his key light lights. The map's sun must
## leave it out (`exclude_from`) or he is lit twice.
const LIGHT_LAYER := 19
const LIGHT_MASK := 1 << (LIGHT_LAYER - 1)

## Uniform scale on pilot9's skeleton (1.5 = ~2.7 m).
@export var body_scale := 1.5
## Metres (world) between the root (the floor) and his lowest point in the frozen pose.
@export var hover := 1.0
## Where a perfect-reflected missile steers onto him: metres over his root (the floor reference).
## His chest in the hover pose.
var homing_height: float:
	get: return hover + 2.3

@export_group("Key light")
## Where his key light comes FROM, in his own frame (+X his left, +Y up, +Z his front): the
## drawing's upper front, on his right (image left).
@export var key_from := Vector3(-0.45, 0.55, 1.0)
@export var key_energy := 1.0
@export var key_color := Color(1.0, 0.97, 0.93)

@export_group("Colours")
@export var armor_color := Color(0.6, 0.71, 0.63)
@export var robe_color := Color(0.62, 0.73, 0.64)
@export var robe_inner_color := Color(0.45, 0.38, 0.36)
@export var cloth_color := Color(0.52, 0.46, 0.43)
@export var mask_color := Color(0.86, 0.82, 0.66)
@export var sash_color := Color(0.09, 0.085, 0.09)
@export var decal_color := Color(0.1, 0.09, 0.09)
## The cel shadow tone leans toward this (alpha = how far): the drawing's mauve-brown shadows.
@export var shade_tint := Color(0.82, 0.52, 0.6, 1.0)
## How dark the cel shadow is (pilot9 0.45).
@export var shadow_tone := 0.46
## The robe's inside and the under-cloth: a softer lean, or their brown goes red.
@export var cloth_shade_tint := Color(0.74, 0.52, 0.6, 0.35)
## The mask keeps more of its cream in shadow.
@export var mask_shade_tint := Color(0.75, 0.6, 0.5, 0.5)

@export_group("Ink")
## His outline width next to everyone else's (RETRO's ink_width, CEL's 2 px).
@export var ink_scale := 1.5
## Full line width up to this distance (m); past it the line thins with him (ref / distance).
@export var ink_far_ref := 15.0
## The thinnest his line gets far away, as a share of its full width.
@export_range(0.05, 1.0, 0.05) var ink_far_min := 0.3

@export_group("Coat")
## The coat's lower segments' natural frequency (Hz); the upper segments run 1.3x, the sash tails 1.7x.
@export var coat_freq := 1.1
## Damping ratio: under 1 overshoots (0.3 = a swing or two, then still).
@export var coat_damping := 0.3
## Idle billow at the hem (deg) and the seconds its wave takes to run round the coat.
@export var coat_idle_deg := 1.0
@export var coat_idle_period := 3.0
## Trail (deg at the lower segment) per m/s of his motion, sideways and up/down (up/down flares).
@export var coat_drag := 8.5
@export var coat_drag_vertical := 4.0
## Kick (deg) per m/s^2 of his acceleration.
@export var coat_kick := 1.0
## Lag (deg) per rad/s of his turning.
@export var coat_swirl := 6.0
## How much of his pitch/roll the coat hangs back toward world down (0 rigid .. 1 a free pendulum).
@export_range(0.0, 1.0, 0.05) var coat_gravity := 0.3
## The most the motion may swing a segment (deg), and in toward his legs.
@export var coat_cap_deg := 40.0
@export var coat_inward_deg := 5.0
## Seconds the drawing's sweep takes to let go when he wakes.
@export var coat_sweep_time := 1.5

## The drawing's pose (dormant): per bone, model-space rotations [axis, degrees] applied relative to the parent.
## Axes are the rest frame: +X his left, +Y up, +Z forward. Matches the drawing, which faces the
## viewer: his body leans to his right (image left) so his left shoulder rides high, his RIGHT arm
## is flung out wide and low, his LEFT hand sits in front of his belly, his head dips toward the
## reaching hand. With the robe swept to his left that makes the drawing's diagonal.
const POSE := {
	&"Hips": [[Vector3.RIGHT, 2.0], [Vector3.BACK, 6.0]],
	&"Spine": [[Vector3.UP, -6.0], [Vector3.RIGHT, 3.0], [Vector3.BACK, 5.0]],
	&"Chest": [[Vector3.RIGHT, 2.0], [Vector3.BACK, 4.0]],
	&"Head": [[Vector3.RIGHT, 8.0], [Vector3.UP, -10.0], [Vector3.BACK, -6.0]],
	&"RightUpperArm": [[Vector3.BACK, -8.0], [Vector3.UP, 24.0]],
	&"RightLowerArm": [[Vector3.UP, 8.0]],
	&"RightHand": [[Vector3.BACK, 18.0]],
	&"LeftUpperArm": [[Vector3.BACK, -72.0], [Vector3.UP, -16.0]],
	&"LeftLowerArm": [[Vector3.UP, -68.0]],
	&"LeftHand": [[Vector3.BACK, -18.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -10.0], [Vector3.BACK, -4.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 22.0]],
	&"LeftFoot": [[Vector3.RIGHT, 55.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 4.0], [Vector3.BACK, -6.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 12.0]],
	&"RightFoot": [[Vector3.RIGHT, 62.0]],
}

## The sabaton tip in the rest space (left side; x mirrors), the lowest point once posed.
const SABATON_TIP := Vector3(0.136, -0.02, 0.33)

var skeleton: Skeleton3D
## The pilot9 instance (scaled, lifted) holding the skeleton.
var model: Node3D
## His own key light.
var key_light: DirectionalLight3D
## The rig's own placement (scale + hover lift), which the lean pivots about.
var model_rest := Transform3D.IDENTITY
## Material key -> MeshInstance3D, once built.
var parts := {}

var _skin: Skin
var _acc := {}
var _rng := RandomNumberGenerator.new()
## Per bone: rest rotation, global rest basis (for additive tables).
var _rest_q: Array[Quaternion] = []
var _rest_g: Array[Basis] = []
var _flash: StandardMaterial3D
var _flash_age := INF

## The first coat bone: bones from here on are the coat's and the pose layer leaves them alone.
var coat_first := 1 << 30
## How much of the drawing's sweep the coat rests in (1 dormant, 0 awake), and where it's headed.
var coat_sweep := 1.0
var coat_sweep_target := 1.0
var _coat_up := PackedInt32Array()
var _coat_lo := PackedInt32Array()
var _tail := PackedInt32Array()


func _ready() -> void:
	model = (load(PILOT_GLB) as PackedScene).instantiate() as Node3D
	model.name = &"Rig"
	model.scale = Vector3.ONE * body_scale
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		n.get_parent().remove_child(n)
		n.free()
	for n in model.find_children("*", "AnimationPlayer", true, false):
		n.get_parent().remove_child(n)
		n.free()
	_add_coat_bones()
	_build()
	for b in skeleton.get_bone_count():
		_rest_q.append(skeleton.get_bone_rest(b).basis.orthonormalized().get_rotation_quaternion())
		_rest_g.append(skeleton.get_bone_global_rest(b).basis.orthonormalized())
	apply_pose()
	model.position.y = hover - lowest_point() * body_scale
	model_rest = model.transform
	_build_key_light()
	_build_flash()
	_coat_init()


func _build_key_light() -> void:
	key_light = DirectionalLight3D.new()
	key_light.name = &"KeyLight"
	key_light.light_cull_mask = LIGHT_MASK
	key_light.shadow_caster_mask = LIGHT_MASK
	key_light.light_energy = key_energy
	key_light.light_color = key_color
	# A second sun in the sky shader would draw a second disc.
	key_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 80.0
	add_child(key_light)
	key_light.basis = Basis.looking_at(-key_from.normalized())


## Keeps another light (the map's sun) off him: his key light alone draws his light and shadow.
static func exclude_from(light: Light3D) -> void:
	if light != null:
		light.light_cull_mask &= ~LIGHT_MASK


func _physics_process(delta: float) -> void:
	tick_coat(delta)


func _process(delta: float) -> void:
	if _flash_age < INF:
		_flash_age += delta
		var a := clampf(1.0 - _flash_age / FLASH_TIME, 0.0, 1.0)
		_flash.albedo_color = Color(1.0, 1.0, 1.0, 0.85 * a)
		if a <= 0.0:
			_flash_age = INF
			_set_overlay(null)


## The drawing's pose (dormant).
func apply_pose() -> void:
	show_pose(solve_pose(POSE))


## A pose table (bone name -> [[axis, degrees], ...], model-space rotations relative to the parent,
## rest-frame axes) as one local rotation per bone. Bones the table leaves out keep their rest.
func solve_pose(table: Dictionary) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for b in skeleton.get_bone_count():
		var steps: Array = table.get(StringName(skeleton.get_bone_name(b)), [])
		if steps.is_empty():
			out.append(_rest_q[b])
			continue
		var q := _table_rotation(steps)
		var g := _rest_g[b]
		out.append(_rest_q[b] * (g.inverse() * q * g).get_rotation_quaternion())
	return out


static func _table_rotation(steps: Array) -> Basis:
	var q := Basis.IDENTITY
	for s: Array in steps:
		q = Basis((s[0] as Vector3).normalized(), deg_to_rad(s[1])) * q
	return q


func show_pose(pose: Array[Quaternion]) -> void:
	for b in mini(pose.size(), coat_first):
		skeleton.set_bone_pose_rotation(b, pose[b])


## `a` blended `t` (0..1) of the way to `b`, then `extra` (a pose table, small rotations such as
## the hover sway) added on top in model space.
func show_blend(a: Array[Quaternion], b: Array[Quaternion], t: float, extra := {}) -> void:
	for i in mini(a.size(), coat_first):
		var q := a[i].slerp(b[i], clampf(t, 0.0, 1.0))
		var steps: Array = extra.get(StringName(skeleton.get_bone_name(i)), [])
		if not steps.is_empty():
			# rest * G^-1 (e q) G = (rest G^-1 e G rest^-1) * (rest G^-1 q G)
			var g := _rest_g[i]
			var e := (g.inverse() * _table_rotation(steps) * g).get_rotation_quaternion()
			q = _rest_q[i] * e * _rest_q[i].inverse() * q
		skeleton.set_bone_pose_rotation(i, q)


## Leans the whole body (degrees: pitch forward +, roll to his right +) about his hips, keeping
## the root (facing) where it is.
func set_lean(pitch_deg: float, roll_deg: float) -> void:
	var pivot := Vector3(0.0, model_rest.origin.y + 1.06 * body_scale, 0.0)
	var r := Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)) * Basis(Vector3.BACK, deg_to_rad(roll_deg))
	model.transform = Transform3D(r, pivot - r * pivot) * model_rest


## A bone's world position, `offset` in the bone's rest-space frame (unscaled).
func bone_world(bone_name: String, offset := Vector3.ZERO) -> Vector3:
	var b := skeleton.find_bone(bone_name)
	var posed := skeleton.get_bone_global_pose(b) * skeleton.get_bone_global_rest(b).affine_inverse()
	return skeleton.global_transform * (posed * (skeleton.get_bone_global_rest(b).origin + offset))


const FLASH_TIME := 0.18
const HIT_RED := Color(1.0, 0.12, 0.08)

## Something landed on him (a perfect-reflected missile). Feedback only: he has no health yet.
signal hit_taken(amount: float, kind: StringName, point: Vector3)

func take_hit(amount: float, kind: StringName, point: Vector3) -> void:
	_flash_age = 0.0
	_flash.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	_set_overlay(_flash)
	if is_inside_tree():
		KnightFx.burst(get_parent() if get_parent() != null else self, point, 24, 7.0, HIT_RED, 0.12, 0.45)
	hit_taken.emit(amount, kind, point)


func is_flashing() -> bool:
	return _flash_age < INF


func _build_flash() -> void:
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1.0, 1.0, 1.0, 0.0)


func _set_overlay(mat: Material) -> void:
	for key: StringName in parts:
		(parts[key] as MeshInstance3D).material_overlay = mat


## The lowest posed sabaton tip, in the skeleton's (unscaled) space.
func lowest_point() -> float:
	var low := INF
	for side in [1.0, -1.0]:
		var foot := skeleton.find_bone("LeftFoot" if side > 0.0 else "RightFoot")
		var tip := Vector3(SABATON_TIP.x * side, SABATON_TIP.y, SABATON_TIP.z)
		var posed := skeleton.get_bone_global_pose(foot) * skeleton.get_bone_global_rest(foot).affine_inverse()
		low = minf(low, (posed * tip).y)
	return low


## -- building --------------------------------------------------------------------------------

func _build() -> void:
	_rng.seed = 7
	_skin = Skin.new()
	for b in skeleton.get_bone_count():
		_skin.add_named_bind(skeleton.get_bone_name(b), skeleton.get_bone_global_rest(b).affine_inverse())
	_build_torso()
	_build_head()
	_build_robe()
	for side in [1.0, -1.0]:
		_build_arm(side)
		_build_leg(side)
	_commit()


func _bone(bone_name: String) -> int:
	return skeleton.find_bone(bone_name)


## A Callable giving one bone at 1.0.
func _rigid(bone_name: String) -> Callable:
	var b := _bone(bone_name)
	return func(_p: Vector3) -> Array: return [[b], [1.0]]


## Weights up the spine by height: the two nearest of Hips/Spine/Chest/UpperChest/Neck.
func _spine(p: Vector3) -> Array:
	var names := ["Hips", "Spine", "Chest", "UpperChest", "Neck"]
	var heights: Array[float] = []
	for n: String in names:
		heights.append(skeleton.get_bone_global_rest(_bone(n)).origin.y)
	if p.y <= heights[0]:
		return [[_bone(names[0])], [1.0]]
	for i in range(names.size() - 1):
		if p.y <= heights[i + 1]:
			var f := (p.y - heights[i]) / (heights[i + 1] - heights[i])
			return [[_bone(names[i]), _bone(names[i + 1])], [1.0 - f, f]]
	return [[_bone(names[-1])], [1.0]]


## Robe weights (docs/specs/knight-coat.md): the two nearest coat chains by angle round the robe's
## axis, upper segment giving way to the lower across the knee row; Hips holds the band under the
## sash so the waist never opens. The legs reach the robe through the chains' targets, not here.
func _robe(p: Vector3) -> Array:
	var f := fposmod(rad_to_deg(atan2(p.x, p.z + 0.02)), 360.0) / COAT_STEP
	var i := int(floorf(f)) % COAT_CHAINS
	var j := (i + 1) % COAT_CHAINS
	var u := f - floorf(f)
	var hips := smoothstep(ROBE[1][0], ROBE_TOP, p.y)
	if hips > 0.0:
		return [[_bone("Hips"), _coat_up[i], _coat_up[j]], [hips, (1.0 - hips) * (1.0 - u), (1.0 - hips) * u]]
	var lo := smoothstep(COAT_JOINT_Y + COAT_JOINT_BLEND, COAT_JOINT_Y - COAT_JOINT_BLEND, p.y)
	return [[_coat_up[i], _coat_lo[i], _coat_up[j], _coat_lo[j]],
		[(1.0 - u) * (1.0 - lo), (1.0 - u) * lo, u * (1.0 - lo), u * lo]]


## A sash tail: Hips at the knot, its own spring bone down its length.
func _sash_tail(i: int) -> Callable:
	var hips := _bone("Hips")
	var tail := _tail[i]
	return func(p: Vector3) -> Array:
		var w := smoothstep(SASH_TAILS[i][0].y - 0.01, SASH_TAILS[i][0].y - 0.08, p.y)
		return [[hips, tail], [1.0 - w, w]]


func _material(color: Color, ink := true, tint := shade_tint) -> ShaderMaterial:
	var mat := (load(CEL) as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"color", color)
	mat.set_shader_parameter(&"shadow_tint", tint)
	mat.set_shader_parameter(&"shadow_tone", shadow_tone)
	if not ink:
		mat.next_pass = null
	elif mat.next_pass is ShaderMaterial:
		# His heavier line: CEL reads ink_width (visible px at 1080p; CEL's line is 2 px), RETRO
		# scales its own width by the ink_scale meta (RetroLook.ink_chain).
		var outline := (mat.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
		outline.set_shader_parameter(&"ink_width", 2.0 * ink_scale)
		outline.set_meta(&"ink_scale", ink_scale)
		# Thin with distance (RetroLook.ink_chain duplicates this pass, so RETRO keeps it).
		outline.set_shader_parameter(&"ink_far_ref", ink_far_ref)
		outline.set_shader_parameter(&"ink_far_min", ink_far_min)
		mat.next_pass = outline
	return mat


func _commit() -> void:
	var colours := {
		&"Armor": [armor_color, true], &"Robe": [robe_color, true], &"RobeInner": [robe_inner_color, true],
		&"Cloth": [cloth_color, true], &"Mask": [mask_color, true], &"Sash": [sash_color, true],
		&"Decals": [decal_color, false],
	}
	for key: StringName in _acc:
		var acc: Dictionary = _acc[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var normals: PackedVector3Array = acc.normals
		for i in normals.size():
			normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-12 else Vector3.UP
		arrays[Mesh.ARRAY_VERTEX] = acc.verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = acc.bones
		arrays[Mesh.ARRAY_WEIGHTS] = acc.weights
		arrays[Mesh.ARRAY_INDEX] = acc.index
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = mesh
		mi.skin = _skin
		mi.layers = LIGHT_MASK
		var tint := shade_tint
		if key == &"Mask":
			tint = mask_shade_tint
		elif key == &"RobeInner" or key == &"Cloth":
			tint = cloth_shade_tint
		mi.material_override = _material(colours[key][0], colours[key][1], tint)
		# The rest-pose bounds don't hold the posed arms and legs.
		mi.extra_cull_margin = 2.0
		skeleton.add_child(mi)
		mi.skeleton = mi.get_path_to(skeleton)
		parts[key] = mi
	_acc.clear()


## Adds one primitive: `verts`, triangles `tris`, and per vertex the point it bulges away from
## (`inside`), which orients each triangle so its front faces out (Godot culls counter-clockwise).
## `flip` turns it inside out (a robe's inner face).
func _add(key: StringName, verts: PackedVector3Array, tris: PackedInt32Array, inside: PackedVector3Array,
		weigh: Callable, flip := false) -> void:
	if not _acc.has(key):
		_acc[key] = {verts = PackedVector3Array(), normals = PackedVector3Array(),
				bones = PackedInt32Array(), weights = PackedFloat32Array(), index = PackedInt32Array()}
	var acc: Dictionary = _acc[key]
	var base: int = (acc.verts as PackedVector3Array).size()
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var index := PackedInt32Array()
	for k in range(0, tris.size(), 3):
		var a := tris[k]
		var b := tris[k + 1]
		var c := tris[k + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if n.length_squared() < 1e-14:
			continue
		var out := (verts[a] + verts[b] + verts[c]) / 3.0 - (inside[a] + inside[b] + inside[c]) / 3.0
		if flip:
			out = -out
		if n.dot(out) > 0.0:
			var s := b
			b = c
			c = s
			n = -n
		# n now points in; the vertex normals point out.
		normals[a] -= n
		normals[b] -= n
		normals[c] -= n
		index.append_array([base + a, base + b, base + c])
	var bones: PackedInt32Array = acc.bones
	var weights: PackedFloat32Array = acc.weights
	for i in verts.size():
		var w: Array = weigh.call(verts[i])
		var bs: Array = w[0]
		var ws: Array = w[1]
		var total := 0.0
		for x in ws:
			total += maxf(x, 0.0)
		for j in 4:
			bones.append(bs[j] if j < bs.size() else 0)
			weights.append(maxf(ws[j], 0.0) / total if j < ws.size() and total > 0.0 else 0.0)
	# Packed arrays come out of a Dictionary as copies: write each back.
	acc.bones = bones
	acc.weights = weights
	var all_verts: PackedVector3Array = acc.verts
	all_verts.append_array(verts)
	acc.verts = all_verts
	var all_normals: PackedVector3Array = acc.normals
	all_normals.append_array(normals)
	acc.normals = all_normals
	var all_index: PackedInt32Array = acc.index
	all_index.append_array(index)
	acc.index = all_index


## Rings (each the same point count) joined into a surface; `centres` per ring orient it.
func _loft(key: StringName, rings: Array, centres: PackedVector3Array, wrap: bool, weigh: Callable,
		flip := false) -> void:
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var n: int = (rings[0] as PackedVector3Array).size()
	for r in rings.size():
		verts.append_array(rings[r])
		for i in n:
			inside.append(centres[r])
	var tris := PackedInt32Array()
	var cols := n if wrap else n - 1
	for r in rings.size() - 1:
		for i in cols:
			var j := (i + 1) % n
			var a := r * n + i
			var b := r * n + j
			var c := (r + 1) * n + i
			var d := (r + 1) * n + j
			tris.append_array([a, b, c, b, d, c])
	_add(key, verts, tris, inside, weigh, flip)


## A ring of `n` points round `centre` in the u/v plane, radii `r`, from angle a0 to a1 (radians;
## wrap = a full loop without the closing duplicate).
static func _ring(centre: Vector3, u: Vector3, v: Vector3, r: Vector2, n: int, a0 := 0.0, a1 := TAU,
		wrap := true) -> PackedVector3Array:
	var out := PackedVector3Array()
	var steps := n if wrap else n - 1
	for i in n:
		var a := lerpf(a0, a1, float(i) / float(steps))
		out.append(centre + u * cos(a) * r.x + v * sin(a) * r.y)
	return out


## A tube along `path` with elliptical radii per point (x across `hint` x tangent, y the other).
func _tube(key: StringName, path: PackedVector3Array, radii: Array, sides: int, weigh: Callable,
		hint := Vector3.BACK) -> void:
	var rings := []
	var centres := PackedVector3Array()
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var u := t.cross(hint)
		if u.length_squared() < 1e-6:
			u = t.cross(Vector3.UP)
		u = u.normalized()
		var v := u.cross(t).normalized()
		rings.append(_ring(path[i], u, v, radii[i], sides))
		centres.append(path[i])
	_loft(key, rings, centres, true, weigh)


## A cone spike from `base` along `dir`.
func _spike(key: StringName, base: Vector3, dir: Vector3, radius: float, length: float, weigh: Callable) -> void:
	_tube(key, PackedVector3Array([base, base + dir.normalized() * length]),
			[Vector2(radius, radius), Vector2.ZERO], 6, weigh, Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.BACK)


## An ellipsoid cap: centre `c`, axes (x, y = the pole, z) with radii `r`, from the pole down to
## latitude `lat_max` (degrees from the pole).
func _dome(key: StringName, c: Vector3, axes: Basis, r: Vector3, lat_max: float, weigh: Callable,
		rows := 7, cols := 16) -> void:
	var rings := []
	var centres := PackedVector3Array()
	for i in rows + 1:
		var th := deg_to_rad(lat_max) * float(maxi(i, 0)) / float(rows)
		th = maxf(th, 0.001)
		rings.append(_ring(c + axes.y * r.y * cos(th), axes.x, axes.z, Vector2(r.x, r.z) * sin(th), cols))
		centres.append(c)
	_loft(key, rings, centres, true, weigh)


## The point and outward normal on that ellipsoid at latitude/longitude (degrees).
static func _on_dome(c: Vector3, axes: Basis, r: Vector3, lat: float, lon: float) -> Array:
	var th := deg_to_rad(lat)
	var ph := deg_to_rad(lon)
	var p := c + axes.x * r.x * sin(th) * cos(ph) + axes.z * r.z * sin(th) * sin(ph) + axes.y * r.y * cos(th)
	var n := (axes.x * sin(th) * cos(ph) / r.x + axes.z * sin(th) * sin(ph) / r.z + axes.y * cos(th) / r.y).normalized()
	return [p, n]


## A flat teardrop decal (the drawing's punched slots) lying on a surface at `at` facing `normal`,
## its point toward `up`.
func _teardrop(at: Vector3, normal: Vector3, up: Vector3, size: float, weigh: Callable) -> void:
	var nrm := normal.normalized()
	var v := (up - nrm * up.dot(nrm)).normalized()
	var u := nrm.cross(v)
	var centre := at + nrm * 0.004
	var verts := PackedVector3Array([centre])
	var inside := PackedVector3Array([centre - nrm])
	var n := 10
	for i in n:
		var a := TAU * float(i) / float(n)
		# A circle pulled to a point on +v.
		var pull := pow(maxf(sin(a), 0.0), 3.0)
		var p := Vector2(cos(a) * (1.0 - pull * 0.85), sin(a) * (1.0 + pull * 1.3)) * size
		verts.append(centre + u * p.x * 0.6 + v * p.y)
		inside.append(centre - nrm)
	var tris := PackedInt32Array()
	for i in n:
		tris.append_array([0, 1 + i, 1 + (i + 1) % n])
	_add(&"Decals", verts, tris, inside, weigh)


## A thin dark line laid over a surface: the mask's crack, plate edges, robe creases. `points`
## already on the surface, `out_from` the point inside it (one, or one per point).
func _crack(points: PackedVector3Array, out_from: Variant, width: float, weigh: Callable, taper := 0.6) -> void:
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var tris := PackedInt32Array()
	for i in points.size():
		var o: Vector3 = out_from[i] if out_from is PackedVector3Array else out_from
		var nrm := (points[i] - o).normalized()
		var t := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := t.cross(nrm).normalized() * width * (1.0 - taper * float(i) / float(points.size()))
		var p := points[i] + nrm * 0.004
		verts.append_array([p - side, p + side])
		inside.append_array([o, o])
		if i > 0:
			var k := i * 2
			tris.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	_add(&"Decals", verts, tris, inside, weigh)


## -- torso -----------------------------------------------------------------------------------

## Torso cross-sections: height, half-width, half-depth (centre z -0.01).
const TORSO := [
	[0.98, 0.2, 0.16], [1.1, 0.205, 0.155], [1.26, 0.225, 0.165], [1.4, 0.245, 0.175],
	[1.5, 0.23, 0.165], [1.54, 0.14, 0.11], [1.565, 0.075, 0.07],
]

func _torso_at(y: float) -> Vector2:
	for i in TORSO.size() - 1:
		if y <= TORSO[i + 1][0]:
			var f: float = (y - TORSO[i][0]) / (TORSO[i + 1][0] - TORSO[i][0])
			return Vector2(lerpf(TORSO[i][1], TORSO[i + 1][1], f), lerpf(TORSO[i][2], TORSO[i + 1][2], f))
	return Vector2(TORSO[-1][1], TORSO[-1][2])


## A point on the torso at angle (deg from his front, + = his left), height y, pushed out `proud`.
func _torso_point(deg: float, y: float, proud: float) -> Vector3:
	var r := _torso_at(y) + Vector2(proud, proud)
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * r.x, y, -0.01 + cos(a) * r.y)


func _build_torso() -> void:
	var rings := []
	var centres := PackedVector3Array()
	for row: Array in TORSO:
		var c := Vector3(0.0, row[0], -0.01)
		rings.append(_ring(c, Vector3.RIGHT, Vector3.BACK, Vector2(row[1], row[2]), 20))
		centres.append(c)
	_loft(&"Armor", rings, centres, true, _spine)
	_build_scales()
	# The spiked back plate over the shoulder blades.
	var back := Basis(Vector3.RIGHT, Vector3(0.0, 0.25, -1.0).normalized(), Vector3(0.0, 1.0, 0.25).normalized())
	var bc := Vector3(0.0, 1.4, -0.12)
	var br := Vector3(0.2, 0.08, 0.15)
	_dome(&"Armor", bc, back, br, 80.0, _rigid("UpperChest"))
	for lon in [-150.0, -90.0, -30.0, 30.0, 90.0, 150.0]:
		var pn := _on_dome(bc, back, br, 50.0, lon)
		_spike(&"Armor", pn[0] - pn[1] * 0.01, pn[1] + Vector3.UP * 0.4, 0.014, 0.04, _rigid("UpperChest"))
	# The sash: a wide dark band at the waist with two tails hanging at the front left.
	var sc0 := Vector3(0.0, 1.11, -0.015)
	var sc1 := Vector3(0.0, 0.97, -0.015)
	var s0 := _ring(sc0, Vector3.RIGHT, Vector3.BACK, Vector2(0.24, 0.195), 22)
	var s1 := _ring(sc1, Vector3.RIGHT, Vector3.BACK, Vector2(0.255, 0.21), 22)
	_loft(&"Sash", [s0, s1], PackedVector3Array([sc0, sc1]), true, _rigid("Hips"))
	for i in SASH_TAILS.size():
		_tube(&"Sash", PackedVector3Array(SASH_TAILS[i]), SASH_TAIL_RADII[i], 6, _sash_tail(i))


## The sash's two tails at the front left (paths, top first), and their tube radii.
const SASH_TAILS := [
	[Vector3(0.1, 1.0, 0.205), Vector3(0.13, 0.86, 0.24), Vector3(0.15, 0.78, 0.26)],
	[Vector3(0.04, 1.0, 0.212), Vector3(0.05, 0.9, 0.24), Vector3(0.055, 0.84, 0.25)],
]
const SASH_TAIL_RADII := [
	[Vector2(0.045, 0.012), Vector2(0.04, 0.009), Vector2(0.036, 0.007)],
	[Vector2(0.04, 0.011), Vector2(0.036, 0.008), Vector2(0.032, 0.007)],
]


## The chest: rows of overlapping scale plates over the front, each a shallow pointed shield whose
## lower edge sweeps down toward his sides (the drawing's chevron of plates), inked along that edge.
func _build_scales() -> void:
	var rows := [1.47, 1.37, 1.27, 1.17]
	for k in rows.size():
		var y0: float = rows[k]
		var height := 0.13
		var proud := 0.006 + 0.004 * float(k)
		var weigh := func(_p: Vector3) -> Array: return _spine(Vector3(0.0, y0 - height * 0.5, 0.0))
		var off := 0.0 if k % 2 == 0 else 0.5
		var count := 6
		var span := 34.0
		for i in count + (1 if k % 2 == 1 else 0):
			var centre := (float(i) - off - float(count - 1) * 0.5) * span
			if absf(centre) > 115.0:
				continue
			var top := PackedVector3Array()
			var bottom := PackedVector3Array()
			var tc := PackedVector3Array()
			var bc := PackedVector3Array()
			for j in 5:
				var f := float(j) / 4.0
				var deg := centre + (f - 0.5) * span * 1.12
				var sweep := 0.06 * absf(sin(deg_to_rad(deg)))
				top.append(_torso_point(deg, y0 - sweep * 0.5, proud))
				# The lower edge stands off the body and comes to a point at the plate's middle.
				var point := 0.035 * (1.0 - absf(f - 0.5) * 2.0)
				bottom.append(_torso_point(deg, y0 - height - sweep - point, proud + 0.022))
				tc.append(Vector3(0.0, y0, -0.01))
				bc.append(Vector3(0.0, y0 - height, -0.01))
			var verts := PackedVector3Array()
			verts.append_array(top)
			verts.append_array(bottom)
			var inside := PackedVector3Array()
			inside.append_array(tc)
			inside.append_array(bc)
			var tris := PackedInt32Array()
			for j in 4:
				tris.append_array([j, j + 1, 5 + j, j + 1, 6 + j, 5 + j])
			_add(&"Armor", verts, tris, inside, weigh)
			var edge := PackedVector3Array()
			for j in 5:
				edge.append(top[j].lerp(bottom[j], 0.94))
			_crack(edge, bc, 0.0045, weigh, 0.0)


## -- head ------------------------------------------------------------------------------------

## Helm cross-sections: height, half-width, half-depth, centre z. A rounded dome with a short point
## leaning back, low between the pauldrons.
const HOOD := [
	[1.52, 0.09, 0.096, 0.0], [1.58, 0.104, 0.112, 0.0], [1.64, 0.108, 0.116, -0.005],
	[1.7, 0.104, 0.11, -0.012], [1.745, 0.088, 0.094, -0.025], [1.78, 0.062, 0.067, -0.04],
	[1.8, 0.032, 0.036, -0.06], [1.812, 0.0, 0.0, -0.085],
]
## The visor's centre, degrees from his front (+ = his left): it sits toward his right.
const VISOR_YAW := -12.0

func _build_head() -> void:
	var head := _rigid("Head")
	var rings := []
	var centres := PackedVector3Array()
	for row: Array in HOOD:
		var c := Vector3(0.0, row[0], row[3])
		rings.append(_ring(c, Vector3.RIGHT, Vector3.BACK, Vector2(row[1], row[2]), 18))
		centres.append(Vector3(0.0, 1.65, -0.02))
	_loft(&"Armor", rings, centres, true, head)
	# An ink ring round the helm's rim.
	var rim := PackedVector3Array()
	for k in 19:
		var a := TAU * float(k) / 18.0
		var r := _hood_at(1.535)
		rim.append(Vector3(sin(a) * r.x, 1.535, _hood_z(1.535) + cos(a) * r.y))
	_crack(rim, Vector3(0.0, 1.535, 0.0), 0.004, head, 0.0)
	# The visor: a narrow cream plate on the front-right of the face, coming down to a beak that
	# juts forward. Rows: height, half-width (deg), forward pull (m).
	var visor_rows := [[1.55, 3.0, 0.045], [1.58, 13.0, 0.026], [1.615, 22.0, 0.012], [1.655, 25.0, 0.004],
			[1.69, 21.0, 0.0], [1.715, 11.0, 0.0]]
	var mask := []
	var mc := PackedVector3Array()
	var fwd := Vector3(sin(deg_to_rad(VISOR_YAW)), 0.0, cos(deg_to_rad(VISOR_YAW)))
	for row: Array in visor_rows:
		var y: float = row[0]
		var half: float = row[1]
		var ring := PackedVector3Array()
		for i in 7:
			var deg := VISOR_YAW + lerpf(-half, half, float(i) / 6.0)
			var pull: float = row[2] * (1.0 - absf(float(i) - 3.0) / 3.0 * 0.6)
			ring.append(_mask_point(deg, y) + fwd * pull + Vector3.DOWN * pull * 0.5)
		mask.append(ring)
		mc.append(Vector3(0.0, y, _hood_z(y) - 0.05))
	_loft(&"Mask", mask, mc, false, head)
	# The inked crack: down from the brow, one branch.
	var hc := Vector3(0.0, 1.65, -0.01)
	var crack := PackedVector3Array()
	for ay: Vector2 in [Vector2(-14, 1.705), Vector2(-17, 1.685), Vector2(-13, 1.662), Vector2(-16, 1.64)]:
		crack.append(_mask_point(ay.x, ay.y))
	_crack(crack, hc, 0.0045, head)
	var branch := PackedVector3Array([_mask_point(-13, 1.662), _mask_point(-9, 1.656), _mask_point(-5, 1.66)])
	_crack(branch, hc, 0.003, head)
	# A few short spikes round the back and sides of the collar.
	for a in [-135.0, 180.0, 135.0]:
		var rad := deg_to_rad(a)
		var at := Vector3(sin(rad) * 0.14, 1.53, cos(rad) * 0.14)
		_spike(&"Armor", at, Vector3(sin(rad), 0.6, cos(rad)), 0.016, 0.05, _rigid("UpperChest"))


func _hood_at(y: float) -> Vector2:
	for i in HOOD.size() - 1:
		if y <= HOOD[i + 1][0]:
			var f: float = clampf((y - HOOD[i][0]) / (HOOD[i + 1][0] - HOOD[i][0]), 0.0, 1.0)
			return Vector2(lerpf(HOOD[i][1], HOOD[i + 1][1], f), lerpf(HOOD[i][2], HOOD[i + 1][2], f))
	return Vector2.ZERO


func _hood_z(y: float) -> float:
	for i in HOOD.size() - 1:
		if y <= HOOD[i + 1][0]:
			var f: float = clampf((y - HOOD[i][0]) / (HOOD[i + 1][0] - HOOD[i][0]), 0.0, 1.0)
			return lerpf(HOOD[i][3], HOOD[i + 1][3], f)
	return HOOD[-1][3]


## A point on the mask surface at angle (deg from front, + = his left) and height.
func _mask_point(deg: float, y: float) -> Vector3:
	var r := _hood_at(y) + Vector2(0.01, 0.012)
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * r.x, y, _hood_z(y) + cos(a) * r.y)


## -- robe ------------------------------------------------------------------------------------

const ROBE_TOP := 1.05
const ROBE_HEM := -0.06
## Robe cross-sections: height, half-width, half-depth (centre z -0.02).
const ROBE := [[1.05, 0.235, 0.19], [0.84, 0.33, 0.27], [0.56, 0.45, 0.36], [0.26, 0.55, 0.43], [-0.06, 0.62, 0.48]]
## Pleats round the robe; each is two flat faces (a ridge between them, a valley at each side).
const PLEATS := 8
## The drawing's sweep to his left at the hem (x his left, y up, z forward), fading in up the robe.
const SWEEP := Vector3(0.3, 0.0, -0.13)
## His left side of the hem flares out and lifts this much more (x out, y up).
const SWEEP_LEFT := Vector2(0.2, 0.14)
## The hem's big ragged points: angle (deg from his front, + = his left) and drop (m).
const HEM_POINTS := [[-40.0, 0.17], [35.0, 0.12], [110.0, 0.2], [185.0, 0.15], [255.0, 0.18]]

## How far down the robe (0 waist .. 1 hem) a height is.
static func _robe_t(y: float) -> float:
	return clampf((ROBE_TOP - y) / (ROBE_TOP - ROBE_HEM), 0.0, 1.0)


## The robe's axis at row r (its centre; swept by `sweep`, 0..1).
func _robe_axis(r: int, sweep := 0.0) -> Vector3:
	var row: Array = ROBE[r]
	var f := pow(_robe_t(row[0]), 1.7) * sweep
	return Vector3(0.0, row[0], -0.02) + SWEEP * f


## A point on the robe at angle `deg` (+ = his left) on row `r`; `fold` scales the radius (ridges
## out, valleys in). The mesh is built straight (`sweep` 0): the drawing's sweep (1) is the coat
## chains' dormant target (docs/specs/knight-coat.md).
func _robe_point(deg: float, r: int, fold: float, sweep := 0.0) -> Vector3:
	var row: Array = ROBE[r]
	var y: float = row[0]
	var t := _robe_t(y)
	var f := pow(t, 1.7) * sweep
	var a := deg_to_rad(deg)
	var side := maxf(sin(a), 0.0)
	var p := Vector3(sin(a) * row[1] * fold, y, -0.02 + cos(a) * row[2] * fold) + SWEEP * f
	p.x += SWEEP_LEFT.x * f * side
	p.y += SWEEP_LEFT.y * f * side
	if r == ROBE.size() - 1:
		# The hem rides a little higher between its big ragged points.
		var drop := 0.0
		for hp: Array in HEM_POINTS:
			var d := absf(wrapf(deg - float(hp[0]), -180.0, 180.0))
			drop = maxf(drop, float(hp[1]) * maxf(1.0 - d / 19.0, 0.0))
		var jag := fmod(absf(sin(deg * 12.9898) * 43758.5453), 1.0)
		p.y += 0.06 - drop + (jag - 0.5) * 0.03
	return p


func _build_robe() -> void:
	# Each pleat face is its own primitive, so the creases stay sharp and the key light paints them
	# alternately light and shadow. Fold depth grows down the robe (tight at the sash).
	var faces := PLEATS * 2
	var step := 360.0 / float(faces)
	for j in faces:
		var a0 := float(j) * step
		var outer := []
		var inner := []
		var centres := PackedVector3Array()
		for r in ROBE.size():
			var depth := lerpf(0.02, 0.1, sqrt(_robe_t(ROBE[r][0])))
			# Even edges are ridges, odd ones valleys.
			var f0 := 1.0 + (depth if j % 2 == 0 else -depth)
			var f1 := 1.0 + (-depth if j % 2 == 0 else depth)
			var ring := PackedVector3Array()
			for i in 4:
				var f := float(i) / 3.0
				ring.append(_robe_point(a0 + step * f, r, lerpf(f0, f1, f)))
			outer.append(ring)
			var axis := _robe_axis(r)
			var shrunk := PackedVector3Array()
			for p in ring:
				shrunk.append(axis + (p - axis) * Vector3(0.985, 1.0, 0.985))
			inner.append(shrunk)
			centres.append(axis)
		_loft(&"Robe", outer, centres, false, _robe)
		_loft(&"RobeInner", inner, centres, false, _robe, true)
	# Crease ink: long lines down every ridge from below the sash, shorter ones up from the hem in
	# the valleys.
	for j in faces:
		var deg := float(j) * step
		var ridge := j % 2 == 0
		var line := PackedVector3Array()
		var axes := PackedVector3Array()
		for r in range(1 if ridge else 2, ROBE.size()):
			var depth := lerpf(0.02, 0.1, sqrt(_robe_t(ROBE[r][0])))
			line.append(_robe_point(deg, r, 1.0 + (depth if ridge else -depth)))
			axes.append(_robe_axis(r))
		_crack(line, axes, 0.006 if ridge else 0.005, _robe, 0.35)


## -- arms ------------------------------------------------------------------------------------

func _build_arm(side: float) -> void:
	var s := "Left" if side > 0.0 else "Right"
	# The pauldron drapes: the shoulder bone holds its top, the upper arm takes over outward, so it
	# hangs over a lowered arm instead of standing off it like a cap.
	var b_shoulder := _bone(s + "Shoulder")
	var b_upper := _bone(s + "UpperArm")
	var drape := func(p: Vector3) -> Array:
		var w := smoothstep(0.16, 0.5, absf(p.x)) * (1.0 - smoothstep(1.6, 1.72, p.y) * 0.5)
		return [[b_shoulder, b_upper], [1.0 - w, w]]
	var upper := _rigid(s + "UpperArm")
	var lower := _rigid(s + "LowerArm")
	var hand := _rigid(s + "Hand")
	var sh := skeleton.get_bone_global_rest(_bone(s + "UpperArm")).origin
	var el := skeleton.get_bone_global_rest(_bone(s + "LowerArm")).origin
	var wr := skeleton.get_bone_global_rest(_bone(s + "Hand")).origin
	var m := func(v: Vector3) -> Vector3: return Vector3(v.x * side, v.y, v.z)
	# The sleeve under the plates.
	_tube(&"Cloth", PackedVector3Array([sh.lerp(el, -0.1), sh.lerp(el, 0.5), el]),
			[Vector2(0.07, 0.07), Vector2(0.065, 0.065), Vector2(0.058, 0.058)], 10, upper)
	# Pauldron: a big rounded dome on the shoulder, two lames stepping down the arm to the elbow,
	# studded with small rivet spikes and a few punched slots.
	var out: Vector3 = m.call(Vector3(1.0, 0.0, 0.0))
	var pole: Vector3 = m.call(Vector3(0.45, 1.0, 0.0)).normalized()
	var axes := Basis(pole.cross(Vector3.BACK).normalized() * side, pole, Vector3.BACK)
	var domes := [
		[m.call(Vector3(0.29, 1.47, -0.005)), Vector3(0.21, 0.16, 0.225), 100.0, drape],
		[m.call(Vector3(0.36, 1.4, -0.005)), Vector3(0.19, 0.135, 0.205), 96.0, drape],
		[m.call(Vector3(0.43, 1.34, -0.008)), Vector3(0.16, 0.11, 0.175), 92.0, drape],
	]
	for d: Array in domes:
		_dome(&"Armor", d[0], axes, d[1], d[2], d[3])
		# An ink line just above each lame's rim, like the drawing's plate edges.
		var rim := PackedVector3Array()
		for k in 29:
			rim.append(_on_dome(d[0], axes, d[1], d[2] - 5.0, 360.0 * float(k) / 28.0)[0])
		_crack(rim, d[0], 0.005, d[3], 0.0)
	for k in 16:
		var d: Array = domes[mini(int(k / 6.0), 2)]
		var lat := _rng.randf_range(22.0, 82.0)
		var lon := 360.0 * float(k) / 16.0 * 2.3 + _rng.randf_range(-15.0, 15.0)
		var pn := _on_dome(d[0], axes, d[1], lat, lon)
		_spike(&"Armor", pn[0] - pn[1] * 0.006, pn[1], 0.011, _rng.randf_range(0.028, 0.045), d[3])
	for k in 6:
		var d: Array = domes[k % 3]
		var pn := _on_dome(d[0], axes, d[1], _rng.randf_range(30.0, 75.0), _rng.randf_range(0.0, 360.0))
		_teardrop(pn[0], pn[1], pole, 0.0065, d[3])
	# Elbow cop, then the vambrace flaring to a cuff, two small spikes on its outer side.
	_dome(&"Armor", el + Vector3(0.0, 0.0, -0.02), Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0.07, 0.045, 0.07), 90.0, lower, 4, 10)
	_tube(&"Armor", PackedVector3Array([el.lerp(wr, 0.08), el.lerp(wr, 0.55), el.lerp(wr, 0.92), el.lerp(wr, 1.0)]),
			[Vector2(0.068, 0.068), Vector2(0.06, 0.06), Vector2(0.075, 0.08), Vector2(0.08, 0.085)], 12, lower)
	var cuff := PackedVector3Array()
	var dir := (wr - el).normalized()
	var cu := dir.cross(Vector3.BACK).normalized()
	var cv := cu.cross(dir).normalized()
	for k in 17:
		var a := TAU * float(k) / 16.0
		cuff.append(el.lerp(wr, 0.86) + cu * cos(a) * 0.072 + cv * sin(a) * 0.076)
	_crack(cuff, el.lerp(wr, 0.86), 0.004, lower, 0.0)
	for f in [0.35, 0.65]:
		var at: Vector3 = el.lerp(wr, f) + Vector3(0.0, 0.055, -0.02)
		_spike(&"Armor", at, Vector3(0.0, 1.0, -0.4), 0.011, 0.04, lower)
		_teardrop(el.lerp(wr, f + 0.12) + Vector3(0.0, 0.0, 0.061), Vector3.BACK, out, 0.007, lower)
	_build_hand(wr, side, hand)


## A half-open claw: a gauntlet back, four long thin talons curling toward the palm (down at rest),
## a thumb forward.
func _build_hand(wr: Vector3, side: float, hand: Callable) -> void:
	var out := Vector3(side, 0.0, 0.0)
	_tube(&"Armor", PackedVector3Array([wr + out * 0.005, wr + out * 0.05, wr + out * 0.095]),
			[Vector2(0.05, 0.025), Vector2(0.052, 0.027), Vector2(0.05, 0.022)], 10, hand, Vector3.UP)
	for k in 4:
		var z := lerpf(-0.04, 0.04, float(k) / 3.0)
		var spread := lerpf(-14.0, 14.0, float(k) / 3.0)
		var length := 1.0 - absf(float(k) - 1.5) * 0.12
		var p := wr + out * 0.095 + Vector3(0.0, 0.0, z)
		var path := PackedVector3Array([p])
		var bend := 10.0
		for seg in [0.085, 0.075, 0.09]:
			var d := out.rotated(Vector3.BACK, deg_to_rad(-bend * side)).rotated(Vector3.UP, deg_to_rad(-spread * side))
			p += d * seg * length
			path.append(p)
			bend += 24.0
		_tube(&"Armor", path, [Vector2(0.01, 0.01), Vector2(0.008, 0.008), Vector2(0.006, 0.006), Vector2.ZERO], 6, hand)
	var thumb := wr + out * 0.035 + Vector3(0.0, -0.01, 0.045)
	_tube(&"Armor", PackedVector3Array([thumb, thumb + Vector3(0.035 * side, -0.03, 0.07), thumb + Vector3(0.07 * side, -0.07, 0.11)]),
			[Vector2(0.011, 0.011), Vector2(0.008, 0.008), Vector2.ZERO], 6, hand)


## -- legs ------------------------------------------------------------------------------------

func _build_leg(side: float) -> void:
	var s := "Left" if side > 0.0 else "Right"
	var hip := skeleton.get_bone_global_rest(_bone(s + "UpperLeg")).origin
	var knee := skeleton.get_bone_global_rest(_bone(s + "LowerLeg")).origin
	var ankle := skeleton.get_bone_global_rest(_bone(s + "Foot")).origin
	_tube(&"Cloth", PackedVector3Array([hip + Vector3(0, 0.04, 0), hip.lerp(knee, 0.5), knee]),
			[Vector2(0.085, 0.085), Vector2(0.075, 0.075), Vector2(0.062, 0.062)], 10, _rigid(s + "UpperLeg"))
	var shin := _rigid(s + "LowerLeg")
	_dome(&"Armor", knee + Vector3(0.0, 0.0, 0.03), Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(0.065, 0.045, 0.07), 85.0, shin, 4, 10)
	_tube(&"Armor", PackedVector3Array([knee, knee.lerp(ankle, 0.5), ankle.lerp(knee, 0.08), ankle + Vector3(0, 0.02, 0)]),
			[Vector2(0.064, 0.07), Vector2(0.056, 0.064), Vector2(0.047, 0.055), Vector2(0.05, 0.058)], 10, shin)
	# The sabaton: a long point running past the toe.
	var x := ankle.x
	var tip := Vector3(SABATON_TIP.x * side, SABATON_TIP.y, SABATON_TIP.z)
	_tube(&"Armor", PackedVector3Array([Vector3(x, 0.06, -0.06), Vector3(x, 0.045, 0.04), Vector3(x, 0.02, 0.16), tip]),
			[Vector2(0.052, 0.055), Vector2(0.05, 0.045), Vector2(0.032, 0.026), Vector2.ZERO], 10, _rigid(s + "Foot"), Vector3.UP)


## -- coat ------------------------------------------------------------------------------------
## The moving coat (docs/specs/knight-coat.md): a two-bone chain down each pleat ridge and a bone
## per sash tail, sprung in code. Each segment's rotation is (motion tilt) * (target), the target
## being the drawing's sweep (dormant) and the legs; the motion tilt is a 2D spring (x his left,
## y his front, radians) pulled toward a shifted rest by his drag, kicks, turning, a share of world
## gravity and the idle billow.

const COAT_CHAINS := PLEATS
const COAT_STEP := 360.0 / float(COAT_CHAINS)
## The knee row the upper and lower segments meet at, and the height over which they blend.
const COAT_JOINT_Y := 0.56
const COAT_JOINT_BLEND := 0.1
## Per kind (upper, lower, tail): share of the motion, of the idle billow, and of the frequency.
const COAT_GAIN := [0.5, 1.0, 1.3]
const COAT_IDLE := [0.4, 1.0, 1.6]
const COAT_FREQ := [1.3, 1.0, 1.7]

## Per segment (uppers, then lowers, then the tails): bone, kind, outward direction, idle phase,
## frequency scale, motion tilt and its rate.
var _seg_bone := PackedInt32Array()
var _seg_kind := PackedInt32Array()
var _seg_out := PackedVector2Array()
var _seg_phase := PackedFloat32Array()
var _seg_freq := PackedFloat32Array()
var _seg_d := PackedVector2Array()
var _seg_w := PackedVector2Array()
## Per chain: the drawing's sweep for the upper and lower segment, and how far it sits on his left.
var _sweep_up: Array[Quaternion] = []
var _sweep_lo: Array[Quaternion] = []
var _chain_left := PackedFloat32Array()
var _coat_clock := 0.0
var _coat_seeded := false
var _coat_p := Vector3.ZERO
var _coat_v := Vector3.ZERO
var _coat_a := Vector3.ZERO
var _coat_yaw := 0.0
var _coat_yaw_rate := 0.0


func _coat_depth(r: int) -> float:
	return lerpf(0.02, 0.1, sqrt(_robe_t(ROBE[r][0])))


## Adds the coat and sash-tail bones (before the Skin is built, so it binds them). Their global
## rest bases are identity: a pose is a model-space rotation about the bone's head.
func _add_coat_bones() -> void:
	var hips := _bone("Hips")
	coat_first = skeleton.get_bone_count()
	for i in COAT_CHAINS:
		var deg := float(i) * COAT_STEP
		_coat_up.append(_add_coat_bone("CoatU%d" % i, hips, _robe_point(deg, 0, 1.0 + _coat_depth(0))))
	for i in COAT_CHAINS:
		var deg := float(i) * COAT_STEP
		_coat_lo.append(_add_coat_bone("CoatL%d" % i, _coat_up[i], _robe_point(deg, 2, 1.0 + _coat_depth(2))))
	for i in SASH_TAILS.size():
		_tail.append(_add_coat_bone("SashTail%d" % i, hips, SASH_TAILS[i][0]))


func _add_coat_bone(bone_name: String, parent: int, at: Vector3) -> int:
	var b := skeleton.get_bone_count()
	skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(b, parent)
	skeleton.set_bone_rest(b, skeleton.get_bone_global_rest(parent).affine_inverse() * Transform3D(Basis.IDENTITY, at))
	skeleton.reset_bone_pose(b)
	return b


func _coat_init() -> void:
	for kind in 3:
		var bones: PackedInt32Array = [_coat_up, _coat_lo, _tail][kind]
		for i in bones.size():
			var a := deg_to_rad(float(i) * COAT_STEP)
			_seg_bone.append(bones[i])
			_seg_kind.append(kind)
			_seg_out.append(Vector2(0.0, 1.0) if kind == 2 else Vector2(sin(a), cos(a)))
			# The billow runs round the coat (+ angle); the tails ride it a little behind.
			_seg_phase.append(-a if kind < 2 else 0.6 + float(i) * 1.3)
			_seg_freq.append(float(COAT_FREQ[kind]) * (1.0 + 0.12 * sin(float(i) * 2.4 + float(kind))))
	_seg_d.resize(_seg_bone.size())
	_seg_w.resize(_seg_bone.size())
	var hem := ROBE.size() - 1
	for i in COAT_CHAINS:
		var deg := float(i) * COAT_STEP
		var pts := []
		for sweep: float in [0.0, 1.0]:
			pts.append([_robe_point(deg, 0, 1.0 + _coat_depth(0), sweep), _robe_point(deg, 2, 1.0 + _coat_depth(2), sweep),
				_robe_point(deg, hem, 1.0 + _coat_depth(hem), sweep)])
		_sweep_up.append(Quaternion((pts[0][1] - pts[0][0]).normalized(), (pts[1][1] - pts[1][0]).normalized()))
		_sweep_lo.append(Quaternion((pts[0][2] - pts[0][1]).normalized(), (pts[1][2] - pts[1][1]).normalized()))
		_chain_left.append(smoothstep(-0.16, 0.16, sin(deg_to_rad(deg)) * float(ROBE[hem][1])))
	reset_coat()


## Drops the coat's motion (a reset or a teleport): still, in the sweep it's headed for.
func reset_coat() -> void:
	coat_sweep = coat_sweep_target
	_coat_seeded = false
	for k in _seg_d.size():
		_seg_d[k] = Vector2.ZERO
		_seg_w[k] = Vector2.ZERO
	_apply_coat(_hips_frame())


## Hips-rest model frame -> posed model frame (the frame the coat's tilts and targets live in).
func _hips_frame() -> Quaternion:
	var h := _bone("Hips")
	return skeleton.get_bone_global_pose(h).basis.orthonormalized().get_rotation_quaternion() \
		* Quaternion(_rest_g[h]).inverse()


## One step of the coat. Runs in _physics_process; probes and tests that step the brain by hand
## call it themselves.
func tick_coat(delta: float) -> void:
	if delta <= 0.0 or _seg_bone.is_empty():
		return
	coat_sweep = move_toward(coat_sweep, coat_sweep_target, delta / maxf(coat_sweep_time, 0.001))
	_coat_clock += delta
	var frame := _hips_frame()
	var to_world := skeleton.global_basis.orthonormalized().get_rotation_quaternion() * frame
	var from_world := to_world.inverse()
	var p := skeleton.global_transform * skeleton.get_bone_global_pose(_bone("Hips")).origin
	var fwd := to_world * Vector3.BACK
	var yaw := atan2(fwd.x, fwd.z)
	if not _coat_seeded or p.distance_to(_coat_p) > 5.0:
		_coat_seeded = true
		_coat_p = p
		_coat_v = Vector3.ZERO
		_coat_a = Vector3.ZERO
		_coat_yaw = yaw
		_coat_yaw_rate = 0.0
	var v_prev := _coat_v
	_coat_v = _coat_v.lerp((p - _coat_p) / delta, 1.0 - exp(-delta / 0.04))
	_coat_a = _coat_a.lerp((_coat_v - v_prev) / delta, 1.0 - exp(-delta / 0.06))
	_coat_p = p
	_coat_yaw_rate = lerpf(_coat_yaw_rate, wrapf(yaw - _coat_yaw, -PI, PI) / delta, 1.0 - exp(-delta / 0.08))
	_coat_yaw = yaw
	# His motion in the hips frame.
	var v := from_world * _coat_v
	var a := from_world * _coat_a
	var g := from_world * Vector3.DOWN
	var g_flat := Vector2(g.x, g.z)
	var g_tilt := Vector2.ZERO
	if g_flat.length_squared() > 1e-10:
		g_tilt = g_flat.normalized() * acos(clampf(-g.y, -1.0, 1.0)) * coat_gravity
	var push := -Vector2(v.x, v.z) * deg_to_rad(coat_drag) - Vector2(a.x, a.z) * deg_to_rad(coat_kick)
	var flare := -v.y * deg_to_rad(coat_drag_vertical) - a.y * deg_to_rad(coat_kick)
	var swirl := -_coat_yaw_rate * deg_to_rad(coat_swirl)
	var cap := deg_to_rad(coat_cap_deg)
	var inward := deg_to_rad(coat_inward_deg)
	var idle := deg_to_rad(coat_idle_deg)
	var ph := TAU * _coat_clock / maxf(coat_idle_period, 0.1)
	var steps := maxi(1, ceili(delta * 120.0))
	var h := delta / float(steps)
	for k in _seg_bone.size():
		var kind := _seg_kind[k]
		var out := _seg_out[k]
		var side := Vector2(out.y, -out.x)
		var phase := _seg_phase[k]
		var rest := (push + out * flare + side * swirl) * float(COAT_GAIN[kind]) + g_tilt
		rest = _soft_cap(rest, cap)
		rest += (out * sin(ph + phase) + out * 0.35 * sin(ph * 2.3 + phase * 2.9)
			+ side * 0.4 * sin(ph * 1.6 + phase * 1.7)) * idle * float(COAT_IDLE[kind])
		var om := TAU * coat_freq * _seg_freq[k]
		var d := _seg_d[k]
		var w := _seg_w[k]
		for s in steps:
			w += ((rest - d) * om * om - w * 2.0 * coat_damping * om) * h
			d += w * h
		# Only a few degrees in toward his legs, and never past the cap.
		var r := d.dot(out)
		if r < -inward:
			d -= out * (r + inward)
			w -= out * minf(w.dot(out), 0.0)
		if d.length() > cap:
			var n := d.normalized()
			d = n * cap
			w -= n * maxf(w.dot(n), 0.0)
		_seg_d[k] = d
		_seg_w[k] = w
	_apply_coat(frame)


static func _soft_cap(v: Vector2, cap: float) -> Vector2:
	var l := v.length()
	return v if l < 1e-9 else v / l * cap * tanh(l / cap)


## A model-space tilt that swings a hanging segment's tip toward `d` (radians, x his left, y his
## front).
static func _tilt(d: Vector2) -> Quaternion:
	var l := d.length()
	if l < 1e-7:
		return Quaternion.IDENTITY
	return Quaternion(Vector3(-d.y, 0.0, d.x) / l, l)


## A limb's rotation off its rest, in the hips-rest frame.
func _limb(bone_name: String, frame: Quaternion) -> Quaternion:
	var b := _bone(bone_name)
	var posed := skeleton.get_bone_global_pose(b).basis.orthonormalized().get_rotation_quaternion()
	return frame.inverse() * posed * Quaternion(_rest_g[b]).inverse()


func _apply_coat(frame: Quaternion) -> void:
	if _seg_bone.is_empty():
		return
	var hips_rest := Quaternion(_rest_g[_bone("Hips")])
	var thigh_l := _limb("LeftUpperLeg", frame)
	var thigh_r := _limb("RightUpperLeg", frame)
	var shin_l := _limb("LeftLowerLeg", frame)
	var shin_r := _limb("RightLowerLeg", frame)
	for i in COAT_CHAINS:
		var left := _chain_left[i]
		var thigh := thigh_r.slerp(thigh_l, left)
		var shin := shin_l if left >= 0.5 else shin_r
		# The old weighting's leg shares: a third at the knee row, half at the hem (the near shin 0.4).
		var leg_up := Quaternion.IDENTITY.slerp(thigh, 0.34)
		var leg_lo := Quaternion.IDENTITY.slerp(thigh.slerp(shin, 0.4), 0.5)
		var up := _tilt(_seg_d[i]) * leg_up * Quaternion.IDENTITY.slerp(_sweep_up[i], coat_sweep)
		var lo := _tilt(_seg_d[COAT_CHAINS + i]) * leg_lo * Quaternion.IDENTITY.slerp(_sweep_lo[i], coat_sweep)
		skeleton.set_bone_pose_rotation(_coat_up[i], hips_rest.inverse() * up)
		skeleton.set_bone_pose_rotation(_coat_lo[i], up.inverse() * lo)
	for i in _tail.size():
		skeleton.set_bone_pose_rotation(_tail[i], hips_rest.inverse() * _tilt(_seg_d[2 * COAT_CHAINS + i]))
