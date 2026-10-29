class_name ArrivalClouds
extends Node3D

# The arrival shot's weather (docs/specs/cutscene-arrival.md, spec R2-6): the storm's tail as a
# backlit cumulus bank pouring over the top-left ridge and around the far tower, a level sea of
# cloud pooled in the valleys behind the base (peaks rise out of it), low mist in the valleys near
# it, spindrift streaming off the ridgelines and the deck edges, and the exhaust tower's steam. All
# cards (shaders/cutscene/arrival_cloud.gdshader) in a few smooth cel tones, moving on the shot clock.
#
# GENERATED like ArrivalLand: no owner, nothing saved into the .tscn. Built after Base (it asks it
# where the stacks are).

const CLOUD_SHADER := preload("res://shaders/cutscene/arrival_cloud.gdshader")

## The camera-facing cards: kind, frame percent (u, v) of the centre, level distance (m), width and
## height (m).
const CARDS := [
	# The bank, back to front: the last one stands round the far tower's lower shaft. Heaps.
	[&"bank", 14.0, 10.0, 5200.0, 2600.0, 1100.0],
	[&"bank", 6.0, 17.0, 3600.0, 1500.0, 700.0],
	[&"bank", 22.0, 20.0, 2900.0, 1000.0, 420.0],
	[&"bank", 29.0, 22.5, 2350.0, 640.0, 240.0],
	[&"bank", 3.0, 30.0, 2300.0, 900.0, 380.0],
	# Valley mist, low soft sheets: round the outpost's foot on the sea: the bright low cloud in the left valley, the long sheet down the right one.
	[&"mist", 83.0, 20.5, 6400.0, 2400.0, 260.0],
	[&"mist", 4.0, 52.0, 1150.0, 520.0, 190.0],
	[&"mist", 90.0, 42.0, 2700.0, 1500.0, 260.0],
	[&"mist", 82.0, 49.0, 2000.0, 900.0, 160.0],
	# Spindrift off the top tier, the right deck, and two far ridgelines.
	[&"drift", 50.0, 43.2, 1450.0, 520.0, 45.0],
	[&"drift", 82.0, 48.4, 1500.0, 520.0, 40.0],
	[&"drift", 72.0, 21.0, 6000.0, 2200.0, 160.0],
	[&"drift", 42.0, 17.0, 7500.0, 2600.0, 200.0],
]

## The cloud sea: its level (m), and the level distances (m) it runs from and to.
const SEA := {y = -470.0, near = 2400.0, far = 42000.0}

## The steam plume over the exhaust stacks: width and height (m), and how far up and downwind its
## centre sits from the stacks (m).
const PLUME := {width = 240.0, height = 240.0, up = 100.0, downwind = 60.0}

## Per kind: mode (0 heap, 1 plume, 2 streak, 3 sea), noise tiles across the card (x, y), drift
## (tiles per second), lobes, wobble, coverage, softness, opacity, soft depth (m).
const KINDS := {
	&"bank": [0, Vector2(1.2, 0.8), Vector2(0.004, 0.0), 11.0, 0.14, 0.0, 0.0, 1.0, 150.0],
	&"mist": [2, Vector2(1.2, 0.6), Vector2(0.006, 0.0), 0.0, 0.0, 0.3, 0.25, 0.65, 200.0],
	&"plume": [1, Vector2(1.0, 1.0), Vector2(0.0, 0.03), 7.0, 0.12, 0.0, 0.0, 0.85, 60.0],
	&"drift": [2, Vector2(0.6, 2.0), Vector2(0.04, 0.0), 0.0, 0.0, 0.45, 0.15, 0.5, 120.0],
	&"sea": [3, Vector2(14.0, 9.0), Vector2(0.0015, 0.0), 0.0, 0.0, 0.22, 0.05, 1.0, 350.0],
}

## Lit, mid and shadow tones; the lit side faces the sun (up left, behind), the belly goes grey-blue.
@export var lit_color := Color(0.97, 0.98, 1.0)
@export var mid_color := Color(0.85, 0.89, 0.95)
@export var shade_color := Color(0.62, 0.68, 0.78)

var materials := {}


func _ready() -> void:
	var shot := get_parent() as ArrivalShot
	var base := get_node(^"../Base") as ArrivalBase
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	noise.frequency = 0.004
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.normalize = true
	tex.generate_mipmaps = true
	tex.noise = noise
	for kind: StringName in KINDS:
		var k: Array = KINDS[kind]
		var m := ShaderMaterial.new()
		m.shader = CLOUD_SHADER
		m.set_shader_parameter(&"noise_tex", tex)
		m.set_shader_parameter(&"mode", k[0])
		m.set_shader_parameter(&"scale", k[1])
		m.set_shader_parameter(&"drift", k[2])
		m.set_shader_parameter(&"lobes", k[3])
		m.set_shader_parameter(&"wobble", k[4])
		m.set_shader_parameter(&"coverage", k[5])
		m.set_shader_parameter(&"softness", k[6])
		m.set_shader_parameter(&"opacity", k[7])
		m.set_shader_parameter(&"soft_depth", k[8])
		m.set_shader_parameter(&"lit_color", lit_color)
		m.set_shader_parameter(&"mid_color", mid_color)
		m.set_shader_parameter(&"shade_color", shade_color)
		materials[kind] = m
	var eye := shot.camera_transform().origin
	var i := 0
	for card: Array in CARDS:
		_card(card[0], shot.at_distance(card[1], card[2], card[3]), Vector2(card[4], card[5]), eye, i)
		i += 1
	if not base.plume_spots.is_empty():
		var at := Vector3.ZERO
		for p in base.plume_spots:
			at += p / base.plume_spots.size()
		_card(&"plume", at + Vector3(PLUME.downwind, PLUME.up, 0.0), Vector2(PLUME.width, PLUME.height), eye, i)
		i += 1
	# The sea: one level quad over the far valleys.
	var quad := QuadMesh.new()
	var depth: float = SEA.far - SEA.near
	quad.size = Vector2(depth * 1.4, depth)
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = quad
	mi.material_override = materials[&"sea"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, SEA.y, -(SEA.near + SEA.far) * 0.5))
	mi.set_instance_shader_parameter(&"seed", 0.0)
	add_child(mi)


func _card(kind: StringName, centre: Vector3, size: Vector2, eye: Vector3, i: int) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.name = "%s%d" % [kind, i]
	mi.mesh = quad
	mi.material_override = materials[kind]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A quad faces +Z: turn it to the camera, kept upright.
	var away := centre - eye
	away.y = 0.0
	mi.transform = Transform3D(Basis.looking_at(away), centre)
	mi.set_instance_shader_parameter(&"seed", float(i) * 1.37)
	mi.set_instance_shader_parameter(&"aspect", size.x / size.y)
	# Blended cards sort back to front by their centres, so the bank's layers stack right.
	add_child(mi)


## Shot time into every card.
func apply(t: float) -> void:
	for m: ShaderMaterial in materials.values():
		m.set_shader_parameter(&"shot_time", t)
