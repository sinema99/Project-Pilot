class_name BossArena
extends MissionMap

# The first boss arena: the top of the arrival shot's RightWide tower (docs/specs/boss-arena.md).
#
# The 3D is the shot's own world, built live under `world` (an ArrivalShot with `cutscene` off):
# the main base and the land and forest round the cap. Past ~3 km the view is the baked backdrop
# (the sky, tools/bake_boss_backdrop.gd). This node adds what makes it playable, all from the cap
# the base built: a flat floor on its bitten rim, a stop-only wall a few metres inside that rim
# (physics layer 10, which pilot9's movement probes and camera ignore), the spawn, the boss's
# anchor, the kill height, and snow falling round the pilot.
#
# GENERATED at load like the world under it: the children made here have no owner.

## The tower whose cap is the arena (ArrivalShot.TOWERS).
const TOWER := "RightWide"
## The cloud sea round the arena (m across), and the shot time the clouds are frozen at. The bake
## (tools/bake_boss_backdrop.gd) uses the same, so the 3D sea runs on into the baked one.
const SEA_SIZE := 100000.0
const CLOUD_TIME := 5.0
## pilot9.STOP_ONLY_LAYER: the bit the invisible wall sits on.
const STOP_ONLY_LAYER := 1 << 9
## The floor's painted surface (tools/gen_boss_floor.gd), and the metres its image spans, centred on
## the cap. The surface sits this far (m) over the cap's own snow.
const FLOOR_TEXTURE := "res://assets/boss_arena/floor.png"
const FLOOR_SPAN := 340.0
const FLOOR_LIFT := 0.02
const CEL_BASE := "res://resources/cel_ground.tres"
## The arena's weather, overcast and cold where the shot is a clear day. The arena and the backdrop
## bake both take it from here, so the 3D and the baked world meet in one light.
const OVERCAST := {
	sun_energy = 0.42, sun_color = Color(0.86, 0.9, 1.0), ambient = Color(0.27, 0.31, 0.39),
	snow = Color(0.66, 0.71, 0.79), rock = Color(0.2, 0.23, 0.29),
	cloud_lit = Color(0.68, 0.72, 0.79), cloud_mid = Color(0.56, 0.61, 0.69), cloud_shade = Color(0.41, 0.46, 0.55),
	zenith = Color(0.27, 0.32, 0.42), horizon = Color(0.53, 0.58, 0.66), sky_cloud = Color(0.66, 0.7, 0.77),
	sun_glow = Color(0.3, 0.32, 0.36), haze = Color(0.5, 0.55, 0.64), haze_amount = 0.4,
}

## The shot's world, built live (ArrivalShot, cutscene off).
@export var world: ArrivalShot
@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment
## The boss's body (docs/specs/knight-boss.md), put on `BossAnchor` facing the spawn.
@export var knight: Node3D
## The knight's AI (docs/specs/knight-moveset.md), built on him in _place_markers.
var brain: KnightBrain

@export_group("Bounds")
## The wall stands this far (m) inside the visible, bitten rim.
@export var wall_inset := 3.0
@export var wall_height := 60.0
@export var wall_thickness := 2.0
## The kill height sits this far (m) under the cap: below it he is put back on the spawn.
@export var kill_depth := 30.0

@export_group("Spawn")
## How far (m) in from the wall he starts, on the side facing the shot's camera.
@export var spawn_in := 20.0

@export_group("Snow")
@export var snow_amount := 900
## The box (m) the flakes fall through, centred on him: width/depth and height.
@export var snow_box := Vector2(60.0, 24.0)
@export var snow_fall_speed := 1.6
@export var snow_flake_size := 0.07

## The cap: centre (world, on its top), its top height, its bitten rim (world xz) and the wall line.
var centre := Vector3.ZERO
var rim := PackedVector2Array()
var wall_line := PackedVector2Array()

var _snow: GPUParticles3D


# Before the world's builders run (they read these in their _ready).
func _enter_tree() -> void:
	if world != null:
		overcast_world(world)
	if environment != null and sun != null:
		overcast_light(environment.environment, sun)


## The builders' colours for the overcast: call before `shot` is in the tree.
static func overcast_world(shot: Node) -> void:
	var land := shot.get_node(^"Land") as ArrivalLand
	land.snow_color = OVERCAST.snow
	land.rock_color = OVERCAST.rock
	var clouds := shot.get_node(^"Clouds") as ArrivalClouds
	clouds.lit_color = OVERCAST.cloud_lit
	clouds.mid_color = OVERCAST.cloud_mid
	clouds.shade_color = OVERCAST.cloud_shade


static func overcast_light(env: Environment, light: DirectionalLight3D) -> void:
	env.ambient_light_color = OVERCAST.ambient
	light.light_energy = OVERCAST.sun_energy
	light.light_color = OVERCAST.sun_color


func _ready() -> void:
	if world != null and sun != null:
		sun.basis = Basis.looking_at(-world.sun_direction())
	_build_arena()
	super()


func _process(_delta: float) -> void:
	if _snow != null and pilot != null:
		_snow.global_position = pilot.global_position + Vector3.UP * snow_box.y * 0.35


func _build_arena() -> void:
	var i := -1
	for k in ArrivalShot.TOWERS.size():
		if ArrivalShot.TOWERS[k].name == TOWER:
			i = k
	var cap: Dictionary = world.base.caps[i]
	var top: Vector3 = world.base.cap_tops[i]
	rim = cap.poly
	centre = Vector3(top.x, cap.y, top.z)
	kill_height = centre.y - kill_depth
	var arena := Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	map = arena
	_build_floor(arena)
	_build_surface(arena)
	if world.clouds != null:
		place_sea(world.clouds, centre)
	wall_line = Geometry2D.offset_polygon(rim, -wall_inset, Geometry2D.JOIN_MITER)[0]
	_build_wall(arena)
	_place_markers(arena)
	_build_snow()


## One flat body on the bitten rim, its top on the cap's top.
func _build_floor(arena: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	arena.add_child(body)
	var shape := CollisionPolygon3D.new()
	var depth := 4.0
	# The polygon lies in the node's local XY and is extruded along its local Z. Turned +90 deg
	# about X, local (x, y, z) is world (x, -z, y): the polygon's y is world z, the depth runs down.
	var flat := PackedVector2Array()
	for p in rim:
		flat.append(p)
	shape.polygon = flat
	shape.depth = depth
	shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, centre.y - depth * 0.5, 0.0))
	body.add_child(shape)


## The painted surface: the rim as one flat mesh just over the cap's snow, on the cel material so
## every look takes it. Visual only, the collision is the polygon above.
func _build_surface(arena: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in Geometry2D.triangulate_polygon(rim):
		var p := rim[k]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x - centre.x, p.y - centre.z) / FLOOR_SPAN + Vector2(0.5, 0.5))
		st.add_vertex(Vector3(p.x, centre.y + FLOOR_LIFT, p.y))
	var material := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	material.set_shader_parameter(&"color", Color.WHITE)
	material.set_shader_parameter(&"base_texture", load(FLOOR_TEXTURE))
	material.next_pass = null
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = st.commit()
	surface.material_override = material
	arena.add_child(surface)


## A box per edge of the wall line, its inner face on the line, on the stop-only layer only.
func _build_wall(arena: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = STOP_ONLY_LAYER
	body.collision_mask = 0
	arena.add_child(body)
	var inward := 1.0 if _signed_area(wall_line) > 0.0 else -1.0
	for k in wall_line.size():
		var a := wall_line[k]
		var b := wall_line[(k + 1) % wall_line.size()]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var along := (b - a) / length
		# Left of a->b is inside for a counter-clockwise (positive area) ring in (x, z).
		var into := Vector2(-along.y, along.x) * inward
		var mid := (a + b) * 0.5 - into * wall_thickness * 0.5
		var box := BoxShape3D.new()
		box.size = Vector3(length + wall_thickness, wall_height, wall_thickness)
		var col := CollisionShape3D.new()
		col.shape = box
		# A turn about Y that puts the box's local X along the edge (world x, z = along.x, along.y).
		var turn := Basis(Vector3.UP, atan2(-along.y, along.x))
		col.transform = Transform3D(turn, Vector3(mid.x, centre.y + wall_height * 0.5 - 2.0, mid.y))
		body.add_child(col)


## The spawn ("spawn", -Z = facing): toward the shot's camera, `spawn_in` from the nearest wall, looking
## at the spire. The boss's anchor at the centre.
func _place_markers(arena: Node3D) -> void:
	var c := Vector2(centre.x, centre.z)
	var toward := -c.normalized()
	# Out toward the camera side until the nearest wall (a bite's side, often) is `spawn_in` away.
	var reach := _ray_to_line(c, toward)
	var along := maxf(reach - spawn_in, 0.0)
	while along > 0.0 and _to_line(c + toward * along) < spawn_in:
		along -= 1.0
	var at := c + toward * maxf(along, 0.0)
	var spire := world.at_distance(ArrivalShot.SPIRE.u, ArrivalShot.SPIRE.v, ArrivalShot.SPIRE.distance)
	var look := (Vector2(spire.x, spire.z) - at).normalized()
	var spawn := Marker3D.new()
	spawn.name = "spawn"
	spawn.transform = Transform3D(Basis.looking_at(Vector3(look.x, 0.0, look.y)), Vector3(at.x, centre.y, at.y))
	arena.add_child(spawn)
	var anchor := Marker3D.new()
	anchor.name = "BossAnchor"
	anchor.position = centre
	arena.add_child(anchor)
	if knight != null:
		var to_spawn := Vector3(at.x - centre.x, 0.0, at.y - centre.z).normalized()
		knight.global_transform = Transform3D(Basis.looking_at(to_spawn, Vector3.UP, true), centre)
		# He has his own key light (docs/specs/knight-boss.md round 2); the sun stays off him.
		if knight is KnightBody:
			KnightBody.exclude_from(sun)
			# His AI and moveset (docs/specs/knight-moveset.md), with the arena's debug keys.
			brain = KnightBrain.new()
			brain.name = &"Brain"
			brain.debug_keys = true
			knight.add_child(brain)
			brain.setup(knight as KnightBody, pilot, centre)


## The clouds round a viewer at `eye`: only the level sea, centred under it and SEA_SIZE across,
## frozen at CLOUD_TIME. The camera-facing cards are the shot's, placed for its camera.
static func place_sea(clouds: ArrivalClouds, eye: Vector3) -> void:
	clouds.apply(CLOUD_TIME)
	for card in clouds.get_children():
		var mi := card as MeshInstance3D
		if mi == null:
			continue
		if mi.name != &"Sea":
			mi.visible = false
			continue
		(mi.mesh as QuadMesh).size = Vector2(SEA_SIZE, SEA_SIZE)
		mi.position = Vector3(eye.x, mi.position.y, eye.z)


## Distance from `p` to the nearest point of the wall line.
func _to_line(p: Vector2) -> float:
	var best := INF
	for k in wall_line.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, wall_line[k], wall_line[(k + 1) % wall_line.size()])))
	return best


## Distance from `from` along `dir` to the wall line.
func _ray_to_line(from: Vector2, dir: Vector2) -> float:
	var best := INF
	for k in wall_line.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(from, from + dir * 10000.0,
				wall_line[k], wall_line[(k + 1) % wall_line.size()])
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best if best != INF else 0.0


static func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Light snow round him: flakes in world space, the emitter box riding along with him.
func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = snow_amount
	_snow.lifetime = snow_box.y / snow_fall_speed
	_snow.preprocess = _snow.lifetime
	_snow.local_coords = false
	_snow.visibility_aabb = AABB(Vector3(-snow_box.x, -snow_box.y * 1.5, -snow_box.x), Vector3(snow_box.x * 2.0, snow_box.y * 2.5, snow_box.x * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(snow_box.x * 0.5, snow_box.y * 0.5, snow_box.x * 0.5)
	pm.direction = Vector3(0.25, -1.0, 0.1)
	pm.spread = 12.0
	pm.initial_velocity_min = snow_fall_speed * 0.7
	pm.initial_velocity_max = snow_fall_speed * 1.3
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	_snow.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(snow_flake_size, snow_flake_size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.78, 0.81, 0.87)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	quad.material = mat
	_snow.draw_pass_1 = quad
	add_child(_snow)
