## The rifle's visual: assets/rifle.glb as modelled in Blender (about 52 units long, muzzle down
## its -X, stock at +X, top up +Y), brought to its in-hand size and turned into the item frame
## pilot9's hand expects. See docs/specs/pilot9-rifle.md.
##
## The item frame (same as the revolver): the origin is the middle of the pistol grip (where his
## fist closes), -Z is down the barrel, +Y is the top of the gun, +X is the gun's left. Everything is
## worked out from the GLB at _ready(), so a re-export straight over assets/rifle.glb lands without
## touching this scene - only `grip_point` and `muzzle_point` are in the GLB's own units.
extends Node3D

const _CEL := preload("res://resources/pilot_cel_character.tres")

## Muzzle to the back of the stock, metres.
@export_range(0.3, 3.0, 0.01) var length: float = 1.5:
	set(value):
		length = value
		if is_inside_tree():
			_fit()
## The middle of the pistol grip in the GLB's own space (Blender units): his fist goes here.
@export var grip_point: Vector3 = Vector3(15.5, 15.4, 0.0)
## The end of the barrel in the GLB's own space.
@export var muzzle_point: Vector3 = Vector3(-24.2, 20.1, 0.0)

@onready var model: Node3D = $Model
@onready var muzzle: Marker3D = $Muzzle


func _ready() -> void:
	_paint()
	_fit()


## Scale from the GLB's whole extent along its barrel axis, then turn -X onto -Z and put the grip
## on the origin.
func _fit() -> void:
	var box := model_bounds()
	var s := length / maxf(box.size.x, 0.0001)
	# -90 degrees about Y takes the GLB's +X to +Z, so its muzzle (-X) points down -Z.
	var turn := Basis(Vector3.UP, -PI * 0.5)
	model.transform = Transform3D(turn.scaled(Vector3.ONE * s), -(turn * grip_point) * s)
	muzzle.position = turn * (muzzle_point - grip_point) * s


## Every mesh's box in the Model node's own frame (before it is placed).
func model_bounds() -> AABB:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.has_meta(&"materialize_shell"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != model and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		# Real vertices, not the mesh box: a rotated part's box overstates the length.
		for surf in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
				var w := xf * v
				box = AABB(w, Vector3.ZERO) if first else box.expand(w)
				first = false
	return box


## pilot9's cel material (so the ink outline) on every surface, in that surface's own Blender colour.
func _paint() -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var mat := _CEL.duplicate() as ShaderMaterial
			mat.set_shader_parameter(&"color", src.albedo_color if src != null else Color(0.2, 0.2, 0.2))
			mi.set_surface_override_material(s, mat)
