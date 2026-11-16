@tool
class_name Hub2Door
extends Node3D

# An openable hub2 door (docs/specs/hub2-final-pass.md, decision 5). Sits in a gap left by a
# Hub2Piece BULKHEAD / CABIN: origin = bottom centre of the doorway on the wall plane, +Z = the wall's
# front. Press F (the shared InteractionPrompt) within reach to toggle; it stays where it is left.
#
#   SWING    personnel door, 1.1 x 2.25, hinged on its -X edge, swings ~95 deg AWAY from the player
#   SHUTTER  roll-up, `width` x `height`, rattles up into its roll box in 1.5 s
#   BLAST    unpowered sliding blast door, NOT interactive: two leaves jammed `gap` metres apart
#   SLIDE    powered person door 1.8 x 2.6 (leaf 2.1 x 2.7 riding on the +Z face of the wall): slides
#            sideways (+X) into the wall in ~0.8 s with a small jolt at each end. Keypad lamp on both
#            faces: red shut, green open. Used by the hub2 control room (docs/specs/hub2-control-room.md).
#
# The moving part is an AnimatableBody3D so it pushes rather than teleports. Meshes come from
# PropMeshCache (built once, loaded after). Live in the runtime scene: the dressing bake copies it.

enum Type { SWING, SHUTTER, BLAST, SLIDE }

const SLIDE_LEAF := Vector2(2.1, 2.7)
const SLIDE_LAMP_SHUT := Color(0.95, 0.12, 0.08)
const SLIDE_LAMP_OPEN := Color(0.15, 0.95, 0.3)

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const INTERACT_ACTION := &"interact"
const REACH := 2.4

@export var type: Type = Type.SWING:
	set(v):
		type = v
		_queue()
## Doorway size (SHUTTER / BLAST; SWING is fixed 1.1 x 2.25).
@export var width := 4.2:
	set(v):
		width = v
		_queue()
@export var height := 4.4:
	set(v):
		height = v
		_queue()
## BLAST: the jammed gap between the leaves, metres.
@export var gap := 1.0:
	set(v):
		gap = v
		_queue()
## Starts open.
@export var start_open := false
## Keypad beside a SWING door: 0 none, 1 dark, 2 smashed.
@export_range(0, 2) var keypad := 1:
	set(v):
		keypad = v
		_queue()
@export var wear := 0.85

## SLIDE only: the leaf wears this (hub2's world-space wall shader) so it matches the wall it sits in.
var surface_material: Material

var is_open := false
var _built := false
var _body: AnimatableBody3D
var _t := 0.0        # 0 closed .. 1 open
var _dir := 1.0      # swing direction sign
var _prompt: Node
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	_built = true
	_rebuild()
	is_open = start_open
	_t = 1.0 if is_open else 0.0
	_pose()
	_set_lamp()


func _queue() -> void:
	if _built:
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		if c.has_meta(&"prop_part"):
			c.free()
	_body = null
	var key := [type, snappedf(width, 0.05), snappedf(height, 0.05), snappedf(gap, 0.05), keypad, snappedf(wear, 0.05)]
	var made: Dictionary = PropMeshCache.fetch("door", key, func() -> Dictionary: return _build_meshes())
	# made.mesh = the moving part (or both blast leaves), made.boxes = its collision in body space.
	if type == Type.BLAST:
		var sb := StaticBody3D.new()
		sb.set_meta(&"prop_part", true)
		add_child(sb)
		_add_visual(sb, made["mesh"])
		_add_boxes(sb, made["boxes"])
		return
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = false
	_body.set_meta(&"prop_part", true)
	add_child(_body)
	if type == Type.SWING:
		_body.position = Vector3(-0.55, 0, 0)   # hinge
	_add_visual(_body, made["mesh"])
	_add_boxes(_body, made["boxes"])
	if type == Type.SLIDE:
		_add_slide_handle()
		_build_slide_keypads()
	if type == Type.SWING and keypad > 0:
		var kp := Hub2Piece.build_cached(Hub2Piece.Kind.KEYPAD, keypad - 1, 0, 0, wear, Vector3.ONE, "", false)
		var mi := MeshInstance3D.new()
		mi.mesh = kp["mesh"]
		mi.position = Vector3(0.85, 1.3, 0.16)
		mi.set_meta(&"prop_part", true)
		add_child(mi)


## SLIDE: a dark vertical handle bar on each face of the leaf (its own mesh so the leaf can wear the wall shader).
func _add_slide_handle() -> void:
	var made: Dictionary = PropMeshCache.fetch("door", ["slide_handle"], func() -> Dictionary:
		var kit := PropKit.new(0.0, 4803)
		kit.box(Vector3(0.45, 0.9, 0.04), Vector3(0.53, 1.4, 0.1), Hub2PieceBuild.STEEL_DARK)
		kit.box(Vector3(0.45, 0.9, -0.1), Vector3(0.53, 1.4, -0.04), Hub2PieceBuild.STEEL_DARK)
		return {"mesh": kit.commit(), "boxes": []})
	var mi := MeshInstance3D.new()
	mi.name = "Handle"
	mi.mesh = made["mesh"]
	mi.visibility_range_end = 90.0
	_body.add_child(mi)


## SLIDE: a small keypad on each face of the wall beside the doorway, its lamp red / green.
func _build_slide_keypads() -> void:
	if keypad <= 0:
		return
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var made: Dictionary = PropMeshCache.fetch("door", ["keypad_slide"], func() -> Dictionary:
		var kit := PropKit.new(0.0, 4799)
		kit.box(Vector3(-0.09, -0.14, -0.03), Vector3(0.09, 0.14, 0.03), Hub2PieceBuild.STEEL_DARK, Transform3D.IDENTITY, false)
		for i in 3:
			for j in 2:
				kit.box(Vector3(-0.06 + j * 0.065, -0.1 + i * 0.045, 0.03), Vector3(-0.015 + j * 0.065, -0.06 + i * 0.045, 0.036), Color(0.5, 0.52, 0.5), Transform3D.IDENTITY, false)
		return {"mesh": kit.commit(), "boxes": []})
	for side in [1.0, -1.0]:
		var pad := Node3D.new()
		pad.set_meta(&"prop_part", true)
		pad.position = Vector3(-1.4, 1.3, 0.15 * side)
		pad.rotation.y = 0.0 if side > 0.0 else PI
		add_child(pad)
		var body := MeshInstance3D.new()
		body.mesh = made["mesh"]
		pad.add_child(body)
		var lamp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.035, 0.012)
		lamp.mesh = bm
		lamp.material_override = _lamp_mat
		lamp.position = Vector3(0, 0.1, 0.036)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.add_child(lamp)
	_set_lamp()


func _set_lamp() -> void:
	if _lamp_mat != null:
		_lamp_mat.albedo_color = SLIDE_LAMP_OPEN if is_open else SLIDE_LAMP_SHUT


func _add_visual(parent: Node, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	mi.mesh = mesh
	mi.visibility_range_end = 90.0
	if surface_material != null and type == Type.SLIDE:
		mi.material_override = surface_material
	parent.add_child(mi)


func _add_boxes(parent: Node, boxes: Array) -> void:
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		parent.add_child(cs)


func _build_meshes() -> Dictionary:
	var kit := PropKit.new(wear, 4721 + int(type))
	var boxes: Array = []
	match type:
		Type.SWING:
			# leaf in hinge space: x 0..1.1, y 0..2.25, z -0.03..0.03
			var c := Color(0.36, 0.40, 0.42)
			kit.box(Vector3(0.0, 0.0, -0.03), Vector3(1.1, 2.25, 0.03), c)
			kit.box(Vector3(0.15, 1.5, 0.03), Vector3(0.95, 2.0, 0.04), Color(0.08, 0.1, 0.11))   # wired window
			for i in 4:
				kit.box(Vector3(0.15 + i * 0.27, 1.5, 0.04), Vector3(0.17 + i * 0.27, 2.0, 0.045), Hub2PieceBuild.STEEL_DARK)
			for side in [-1.0, 1.0]:
				kit.box(Vector3(0.88, 0.98, 0.03 * side), Vector3(1.0, 1.04, 0.09 * side if side > 0.0 else -0.03), Hub2PieceBuild.STEEL_DARK)
			kit.box(Vector3(0.0, 0.0, 0.03), Vector3(1.1, 0.25, 0.035), Color(0.25, 0.26, 0.27))   # kick plate
			boxes = [[Vector3(0.55, 1.125, 0), Vector3(1.1, 2.25, 0.08)]]
		Type.SHUTTER:
			var c2 := Color(0.48, 0.50, 0.50)
			var n := int(height / 0.25)
			for i in n:
				var y := i * 0.25
				kit.box(Vector3(-width * 0.5, y, -0.04), Vector3(width * 0.5, y + 0.23, 0.04), c2 if i % 2 == 0 else c2.darkened(0.08))
			kit.box(Vector3(-width * 0.5, 0.0, 0.04), Vector3(width * 0.5, 0.12, 0.1), Hub2PieceBuild.SAFETY_YELLOW.darkened(0.2))
			Hub2PieceBuild.paint_text(kit, "PULL", Vector3(-0.3, 0.3, 0.045), Vector3.RIGHT, Vector3.UP, 0.04, Color(0.1, 0.1, 0.1))
			boxes = [[Vector3(0, height * 0.5, 0), Vector3(width, height, 0.1)]]
		Type.SLIDE:
			# leaf in body space: x -1.05..1.05, y 0..2.7, z -0.04..0.04
			var cs := Color(0.38, 0.41, 0.43)
			kit.box(Vector3(-1.05, 0.0, -0.04), Vector3(1.05, 2.7, 0.04), cs)
			# A plain wall panel: no window, stripes, plate or text. The handle is its own mesh (_add_slide_handle).
			boxes = [[Vector3(0, 1.35, 0), Vector3(2.1, 2.7, 0.1)]]
		Type.BLAST:
			var c3 := Color(0.38, 0.38, 0.36)
			var leaf := (width - gap) * 0.5
			for side in [-1.0, 1.0]:
				var x0: float = width * 0.5 - leaf if side > 0.0 else -width * 0.5
				var x1: float = width * 0.5 if side > 0.0 else -width * 0.5 + leaf
				kit.box(Vector3(x0, 0, -0.35), Vector3(x1, height, 0.35), c3)
				# hex panels
				var cx := (x0 + x1) * 0.5
				for row in int(height / 1.6):
					for col in int(leaf / 1.4):
						var p := Vector3(x0 + 0.7 + col * 1.4, 0.9 + row * 1.6, 0.36)
						Hub2PieceBuild.paint_logo(kit, p, Vector3.RIGHT, Vector3.UP, 1.1, c3.darkened(0.25))
				# hazard edge on the meeting stile
				var ex: float = x1 if side < 0.0 else x0
				for i in int(height / 0.5):
					var y := i * 0.5
					kit.box(Vector3(ex - 0.12, y, 0.36), Vector3(ex + 0.12, y + 0.25, 0.4), Hub2PieceBuild.SAFETY_YELLOW.darkened(0.2) if i % 2 == 0 else Hub2PieceBuild.BLACK)
				boxes.append([Vector3(cx, height * 0.5, 0), Vector3(x1 - x0, height, 0.7)])
			Hub2PieceBuild.paint_text(kit, "NO POWER", Vector3(-width * 0.5 + 0.4, height - 0.8, 0.37), Vector3.RIGHT, Vector3.UP, 0.08, Color(0.75, 0.2, 0.1))
	return {"mesh": kit.commit(), "boxes": boxes}


func _pose() -> void:
	if _body == null:
		return
	match type:
		Type.SWING:
			var e := _t * _t * (3.0 - 2.0 * _t)
			_body.rotation = Vector3(0, -_dir * deg_to_rad(95.0) * e, 0)
		Type.SHUTTER:
			_body.position = Vector3(0, height * _t * 0.95, 0)
			_body.scale = Vector3.ONE
		Type.SLIDE:
			var e2 := _t * _t * (3.0 - 2.0 * _t)
			var jolt := 0.025 * sin(_t * 40.0) * (1.0 - 4.0 * _t * (1.0 - _t))
			# z 0 = the middle of the wall: the leaf sits recessed, a reveal on both faces.
			_body.position = Vector3(SLIDE_LEAF.x * 0.98 * e2 + jolt, 0.0, 0.0)
			# The wall shader paints from world position: cancel the slide so the texture rides the leaf.
			if surface_material is ShaderMaterial and is_inside_tree():
				(surface_material as ShaderMaterial).set_shader_parameter(&"pos_offset", global_transform.basis * _body.position)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or type == Type.BLAST:
		return
	var target := 1.0 if is_open else 0.0
	if not is_equal_approx(_t, target):
		var speed := 1.0 / (0.5 if type == Type.SWING else (0.8 if type == Type.SLIDE else 1.5))
		_t = move_toward(_t, target, speed * delta)
		_pose()
	var pilot := _player()
	if pilot == null or pilot.get("frozen") == true:
		return
	var ui := get_node_or_null(^"/root/UI")
	if ui != null and not ui.stack.is_empty():
		return
	var handle := global_transform * Vector3(0, 1.1, 0)
	var d := pilot.global_position + Vector3(0, 1.0, 0)
	if d.distance_to(handle) > REACH:
		return
	if _prompt == null:
		_prompt = PROMPT_SCRIPT.acquire(self)
	if _prompt != null:
		_prompt.offer(self, d.distance_to(handle), INTERACT_ACTION, "CLOSE" if is_open else "OPEN")


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or type == Type.BLAST:
		return
	if not event.is_action_pressed(INTERACT_ACTION):
		return
	if _prompt == null or _prompt.current_source != self:
		return
	get_viewport().set_input_as_handled()
	toggle()


## Opens (swinging away from the player for SWING) or closes.
func toggle() -> void:
	if not is_open and type == Type.SWING:
		var pilot := _player()
		if pilot != null:
			var local := global_transform.affine_inverse() * pilot.global_position
			# player in front (+Z) -> swing to -Z (rotation +), behind -> swing toward +Z
			_dir = -1.0 if local.z > 0.0 else 1.0
	is_open = not is_open
	_set_lamp()


## The player body, through the Inventory autoload looked up at runtime (never by name: headless
## --script tools load this script without autoloads).
func _player() -> Node3D:
	var inv := get_node_or_null(^"/root/Inventory")
	if inv == null or not inv.has_method(&"player"):
		return null
	return inv.call(&"player") as Node3D
