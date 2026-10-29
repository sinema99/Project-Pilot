class_name ArrivalForest
extends Node3D

# Spruce on the arrival shot's forest floor (docs/specs/cutscene-arrival.md): one slender spruce
# mesh in the descent's look (DescentTrees: dark spruce, snow on top) tinted toward the reference's
# blue air, scattered as a MultiMesh out to `reach` wherever ArrivalLand.forest_score beats its
# break-up noise (the terrain's rule, spec R2-2), thinning out over `edge` of score past that, so
# the forest's edge is ragged at tree scale. Past `reach` the forest is only the land's dark floor
# colour. No ink: at these distances the hull would turn the forest into noise.
#
# Sized to the reference's read (a fine speckle against an 800 m deck), not to real spruce.
# GENERATED like ArrivalLand; sits below it in the tree.

const CEL_BASE := "res://resources/cel_ground.tres"
## The descent's spruce green pushed toward the reference's blue air (the composite's haze barely
## reaches 1 km), and snow on the top tier only, a shade down: white tips everywhere read as speckle.
const C_SPRUCE := Color(0.08, 0.16, 0.17)
const C_TIER_SNOW := Color(0.58, 0.64, 0.72)
const SIDES := 6
## Default reach (m); the land fades its bare forest floor from here.
const REACH := 3200.0

@export var forest_seed := 31
## Trees per square metre of forest floor, how far out they stand (m from the camera), and the cap.
## They thin out over `edge` of forest score past the floor's edge, so the forest has no hard rim.
@export var density := 0.012
@export var reach := REACH
@export var max_trees := 120000
@export_range(0.0, 0.5, 0.01) var edge := 0.1
## Tree height range (m) and width as a fraction of height.
@export var height_min := 9.0
@export var height_max := 16.0
@export var girth := 0.3

## Trees actually placed.
var count := 0


func _ready() -> void:
	var land := get_node(^"../Land") as ArrivalLand
	var rng := RandomNumberGenerator.new()
	rng.seed = forest_seed
	var xforms: Array[Transform3D] = []
	var v := land.vertices
	for t in land.triangles.size() / 3:
		var ia := land.triangles[t * 3]
		var a := v[ia]
		if Vector2(a.x, a.z).length() > reach or a.y > land.treeline:
			continue
		var b := v[land.triangles[t * 3 + 1]]
		var c := v[land.triangles[t * 3 + 2]]
		var cross := (c - a).cross(b - a)
		var mid := (a + b + c) / 3.0
		var score := land.forest_score(mid.y, absf(cross.normalized().y), land.ridges[ia],
				land.clear_at(mid.x, mid.z).x)
		var f := smoothstep(0.0, edge, score - land.forest_bar(mid.x, mid.z))
		if f <= 0.0:
			continue
		var area := cross.length() * 0.5
		var want := area * density * f * f
		var n := int(want) + (1 if rng.randf() < want - int(want) else 0)
		for k in n:
			var r1 := sqrt(rng.randf())
			var r2 := rng.randf()
			var p := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
			var h := rng.randf_range(height_min, height_max)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h, h, h))
			xforms.append(Transform3D(basis, p - Vector3.UP * 0.5))
			if xforms.size() >= max_trees:
				break
		if xforms.size() >= max_trees:
			break
	count = xforms.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _spruce_mesh()
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Spruce"
	mmi.multimesh = mm
	add_child(mmi)


# One spruce, 1 m tall: three stacked green tiers, each with a snow cap on its upper half.
func _spruce_mesh() -> ArrayMesh:
	var green := SurfaceTool.new()
	green.begin(Mesh.PRIMITIVE_TRIANGLES)
	var snow := SurfaceTool.new()
	snow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := girth * 0.5
	var tiers := [[0.08, 0.55, w], [0.35, 0.8, w * 0.75], [0.6, 1.0, w * 0.5]]
	for tier: Array in tiers:
		var y0: float = tier[0]
		var y1: float = tier[1]
		var r: float = tier[2]
		if y1 < 1.0:
			_cone(green, y0, r, y1, 0.0)
		else:
			_cone(green, y0, r, lerpf(y0, y1, 0.45), r * 0.55)
			_cone(snow, lerpf(y0, y1, 0.45), r * 0.55, y1, 0.0)
	var mesh := ArrayMesh.new()
	green.generate_normals()
	green.commit(mesh)
	mesh.surface_set_material(0, _cel(C_SPRUCE))
	snow.generate_normals()
	snow.commit(mesh)
	mesh.surface_set_material(1, _cel(C_TIER_SNOW))
	return mesh


func _cone(st: SurfaceTool, y0: float, r0: float, y1: float, r1: float) -> void:
	for i in SIDES:
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		# Clockwise seen from outside.
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(q0)
		if r1 > 0.0:
			st.add_vertex(p1)
			st.add_vertex(q1)
			st.add_vertex(q0)


func _cel(col: Color) -> ShaderMaterial:
	var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	m.next_pass = null
	return m
