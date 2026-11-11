class_name ArrivalClouds
extends Node3D

# The arrival shot's weather (docs/specs/cutscene-arrival.md, spec R2-6): the storm's tail as a
# backlit cumulus bank pouring over the top-left ridge and around the far tower, a level sea of
# cloud pooled in the valleys behind the base (peaks rise out of it), low mist in the valleys near
# it, spindrift streaming off the ridgelines, the deck edges and the broken tower caps (the exhaust
# tower's steam went with revision 5: the base is cold). All cards (shaders/cutscene/arrival_cloud.gdshader) in a few smooth cel tones, moving on the shot clock.
#
# GENERATED like ArrivalLand: no owner, nothing saved into the .tscn. Built after Base (it asks it
# where the caps are broken).

const CLOUD_SHADER := preload("res://shaders/cutscene/arrival_cloud.gdshader")
## The banks' variant (spec R6-2): translucent as one sheet.
const BANK_SHADER := preload("res://shaders/cutscene/arrival_cloud_bank.gdshader")

## The camera-facing cards: kind, frame percent (u, v) of the centre, level distance (m), width and
## height (m).
const CARDS := [
	# The bank, back to front: the last one stands round the far tower's lower shaft. Heaps. Since
	# R6 (spec R6-3) it sits as low as the right bank: its top under the left range, the far tower's
	# cap clear.
	[&"bank", 14.0, 22.0, 5200.0, 2600.0, 1100.0],
	[&"bank", 6.0, 29.0, 3600.0, 1500.0, 700.0],
	[&"bank", 22.0, 32.0, 2900.0, 1000.0, 420.0],
	[&"bank", 29.0, 34.5, 2350.0, 640.0, 240.0],
	[&"bank", 3.0, 42.0, 2300.0, 900.0, 380.0],
	# Valley mist, low sheets: round the outpost's foot on the sea, the long sheet down the right
	# valley. (The left valley's went with R6: the lowered bank covers it.)
	[&"mist", 83.0, 20.5, 6400.0, 2400.0, 260.0],
	[&"mist", 90.0, 42.0, 2700.0, 1500.0, 260.0],
	[&"mist", 82.0, 49.0, 2000.0, 900.0, 160.0],
	# Spindrift off the top tier, the right deck, and two far ridgelines.
	[&"drift", 50.0, 43.2, 1450.0, 520.0, 45.0],
	[&"drift", 82.0, 48.4, 1500.0, 520.0, 40.0],
	[&"drift", 72.0, 21.0, 6000.0, 2200.0, 160.0],
	[&"drift", 42.0, 17.0, 7500.0, 2600.0, 200.0],
	# The bank's sibling on the right (spec R4-5), not a mirror: the back heap wraps the outpost
	# peak's foot as the left one wraps the far tower, the rest step forward to just behind the plant
	# deck, all deeper than RightTower, which stands in front of them.
	[&"bank", 88.0, 23.0, 6400.0, 3000.0, 950.0],
	[&"bank", 97.0, 31.0, 4600.0, 1800.0, 650.0],
	[&"bank", 84.0, 36.0, 3700.0, 1300.0, 420.0],
	[&"bank", 95.0, 42.0, 2900.0, 1100.0, 330.0],
	[&"bank", 80.0, 44.5, 2500.0, 620.0, 200.0],
]

## The cloud sea: its level (m), and the level distances (m) it runs from and to.
const SEA := {y = -470.0, near = 2400.0, far = 42000.0}

## Spindrift off a broken cap (spec R5-6): the card's width and height (m), streaming downwind.
const BREAK_DRIFT := Vector2(360.0, 34.0)

## The spire's spindrift card off each ledge: width and height (m), sized to read at 11 km.
const SPIRE_DRIFT := Vector2(1300.0, 90.0)

## Per kind: mode (0 heap, 1 plume (none since R5), 2 streak, 3 sea), noise tiles across the card (x, y), drift
## (tiles per second), lobes, wobble, coverage, softness, opacity, soft depth (m).
const KINDS := {
	&"bank": [0, Vector2(1.2, 0.8), Vector2(0.004, 0.0), 11.0, 0.14, 0.0, 0.0, 0.5, 60.0],
	&"mist": [2, Vector2(1.2, 0.6), Vector2(0.006, 0.0), 0.0, 0.0, 0.3, 0.04, 0.65, 200.0],
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
		m.shader = BANK_SHADER if kind == &"bank" else CLOUD_SHADER
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
	# The banks draw nearest first (spec R6-2): each one's sort depth mirrored inside the banks' range.
	var near := INF
	var far := 0.0
	for card: Array in CARDS:
		if card[0] == &"bank":
			near = minf(near, card[3])
			far = maxf(far, card[3])
	var i := 0
	for card: Array in CARDS:
		var mi := _card(card[0], shot.at_distance(card[1], card[2], card[3]), Vector2(card[4], card[5]), eye, i)
		if card[0] == &"bank":
			mi.sorting_offset = 2.0 * card[3] - (near + far)
		i += 1
	for p in base.break_spots:
		_card(&"drift", p + Vector3(BREAK_DRIFT.x * 0.5 - 30.0, 6.0, 0.0), BREAK_DRIFT, eye, i)
		i += 1
	# The spire (spec R4-8): spindrift streaming downwind off its ledges in the frame. The sea laps
	# its snowfield as it is (R4b-3), no heaps.
	var spire := get_node_or_null(^"../Spire") as ArrivalSpire
	if spire != null:
		for p in spire.ledges:
			_card(&"drift", p + Vector3(SPIRE_DRIFT.x * 0.5 - 40.0, 0.0, 0.0), SPIRE_DRIFT, eye, i)
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


func _card(kind: StringName, centre: Vector3, size: Vector2, eye: Vector3, i: int) -> MeshInstance3D:
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
	return mi


## Shot time into every card.
func apply(t: float) -> void:
	for m: ShaderMaterial in materials.values():
		m.set_shader_parameter(&"shot_time", t)
