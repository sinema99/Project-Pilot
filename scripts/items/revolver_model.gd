## The revolver's visual: assets/revolver.glb as modelled in Blender (about 4.3 m long, muzzle down
## its -X, top up +Y), brought to its in-hand size and turned into the item frame pilot9's hand
## expects. See docs/specs/pilot9-revolver.md.
##
## The item frame: the origin is the middle of the grip (where his fist closes), -Z is down the
## barrel, +Y is the top of the gun. Everything is worked out from the GLB at _ready(), so a
## re-export straight over assets/revolver.glb lands without touching this scene - only
## `grip_point` and `muzzle_point` are in the GLB's own units.
extends Node3D

const _CEL := preload("res://resources/pilot_cel_character.tres")
const _Texture := preload("res://scripts/items/revolver_texture.gd")

## Muzzle to the back of the grip, metres. A handcannon on purpose (user, 2026-11-12: 0.35 -> 0.6): a
## real 0.28 m gun is a few pixels at the DayZ camera's distance.
@export_range(0.05, 1.0, 0.01) var length: float = 0.6:
	set(value):
		length = value
		if is_inside_tree():
			_fit()
## The middle of the grip in the GLB's own space (Blender units): his fist goes here.
@export var grip_point: Vector3 = Vector3(-0.30, 0.62, 0.0)
## The end of the barrel in the GLB's own space.
@export var muzzle_point: Vector3 = Vector3(-3.991, 1.433, 0.0)
@export var metal_color: Color = Color(0.18, 0.19, 0.21)
## For a mesh whose node name has "grip" in it - once the grip is its own object in Blender.
@export var wood_color: Color = Color(0.30, 0.17, 0.09)

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


## pilot9's cel material with the generated PS1 texture as albedo (RevolverTexture). Mesh 0 is the
## body (the grip is zoned out of it by position), the unit-cube one is the cylinder, the small one the hammer.
@export_range(0.0, 1.0, 0.05) var wear: float = 0.5
@export var texture_seed: int = 7


func _paint() -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var kind := &"body"
		# The GLB's node names: Cube is the body, Cube.001 the cylinder, Cube.002 the hammer.
		match String(mi.name):
			"Cube.001": kind = &"cylinder"
			"Cube.002": kind = &"hammer"
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != model and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var mat := _CEL.duplicate() as ShaderMaterial
		mat.set_shader_parameter(&"color", Color.WHITE)
		# paint() swaps in a mesh with usable UVs, so it runs before the material takes the texture.
		var tex := _Texture.paint(mi, xf, kind, texture_seed, wear)
		mat.set_shader_parameter(&"base_texture", tex)
		mi.material_override = mat
