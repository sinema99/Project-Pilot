extends SceneTree

# Bakes the boss arena's 2D backdrop (docs/specs/boss-arena.md): the arrival world past ~3 km, seen
# from the arena's centre (the RightWide cap), as six 90 deg views into assets/boss_arena/. The
# arena's sky (shaders/boss_arena_backdrop.gdshader) samples them by view direction.
#
# WINDOWED (it renders). Run from the project root whenever the arrival shot changes:
#   godot --path . --script tools/bake_boss_backdrop.gd
#
# What goes in: the land as a full circle from 3 km out (the arena's 3D land runs to 3.5 km, so they
# overlap), the sister outpost, the spire, the clouds farther than CARD_CLEAR turned to face the
# arena, the cloud sea moved under the arena, the sky, the haze. What stays out: the main base, the
# forest and the growth (the arena builds those in 3D). No cinema post, no screen-space sun glow.

const SCENE := "res://scenes/cutscene_arrival.tscn"
const OUT := "res://assets/boss_arena"
const TOWER := "RightWide"
## Face name, look direction F, up U. The sky shader repeats these.
const FACES := [
	["px", Vector3(1, 0, 0), Vector3(0, 1, 0)],
	["nx", Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	["py", Vector3(0, 1, 0), Vector3(0, 0, 1)],
	["ny", Vector3(0, -1, 0), Vector3(0, 0, -1)],
	["pz", Vector3(0, 0, 1), Vector3(0, 1, 0)],
	["nz", Vector3(0, 0, -1), Vector3(0, 1, 0)],
]
const SIZE := 2048
## The eye this far over the cap's top (m).
const EYE_HEIGHT := 2.0
## The land's first ring (m from the arena).
const LAND_NEAR := 3000.0
const LAND_COLUMNS := 720
## Cloud cards nearer the arena than this (m, level) are left out.
const CARD_CLEAR := 1200.0
## The shot time the clouds are frozen at, and the sea round the arena: BossArena's.
const CLOUD_TIME := BossArena.CLOUD_TIME
const SEA_SIZE := BossArena.SEA_SIZE
## How much taller the ranges stand on screen than in the shot.
const RANGE_LIFT := 2.0
## The spire as the space elevator it is: the shot's cone drawn out taller, its point above where it has faded out.
const ELEVATOR_TAPER := 9000.0
const ELEVATOR_BUILT_TO := 0.9
## The elevations (degrees) it fades out between, into the sky behind it.
const ELEVATOR_FADE := Vector2(14.0, 38.0)

var _shot: ArrivalShot
var _viewport: SubViewport
var _camera: Camera3D
var _eye := Vector3.ZERO
var _frames := 0
var _face := 0
var _wait := 0
## The face as rendered with the spire, while the same view renders without it.
var _with_spire: Image


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_shot = load(SCENE).instantiate() as ArrivalShot
	_shot.cutscene = false
	var land := _shot.get_node(^"Land") as ArrivalLand
	land.view_on_tower = TOWER
	land.near = LAND_NEAR
	land.half_angle_degrees = 180.0
	land.columns = LAND_COLUMNS
	land.range_lift = RANGE_LIFT
	var spire := _shot.get_node(^"Spire") as ArrivalSpire
	spire.taper_height = ELEVATOR_TAPER
	spire.built_to = ELEVATOR_BUILT_TO
	BossArena.overcast_world(_shot)
	for t: Dictionary in ArrivalShot.TOWERS:
		if t.name == TOWER:
			_eye = _shot.at_distance(t.u, t.v, t.distance) + Vector3.UP * EYE_HEIGHT
	root.add_child(_shot)


# The world's _ready has run by the first frame (not inside _initialize).
func _setup() -> void:
	_shot.clouds.apply(CLOUD_TIME)
	_overcast()
	for n: Node in [_shot.get_node(^"Forest"), _shot.get_node(^"Growth")]:
		(n as Node3D).visible = false
	for child in _shot.base.get_children():
		(child as Node3D).visible = String(child.name).begins_with("Outpost")
	_place_clouds()
	_strip_post()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 90.0
	_camera.near = 1.0
	_camera.far = 90000.0
	_viewport.add_child(_camera)
	_camera.current = true
	print("eye ", _eye, " land verts ", _shot.land.vertices.size())


## The arena's weather on the shot's light and sky.
func _overcast() -> void:
	var env := _shot.world_environment.environment as Environment
	BossArena.overcast_light(env, _shot.get_node(^"Sun") as DirectionalLight3D)
	var sky := env.sky.sky_material as ShaderMaterial
	sky.set_shader_parameter(&"zenith", BossArena.OVERCAST.zenith)
	sky.set_shader_parameter(&"horizon", BossArena.OVERCAST.horizon)
	sky.set_shader_parameter(&"cloud", BossArena.OVERCAST.sky_cloud)
	sky.set_shader_parameter(&"sun_glow", BossArena.OVERCAST.sun_glow)


## Cards near the arena out; the rest turned to face it, upright. The sea centred under it.
func _place_clouds() -> void:
	for card in _shot.clouds.get_children():
		var mi := card as MeshInstance3D
		if mi == null:
			continue
		if mi.name == &"Sea":
			(mi.mesh as QuadMesh).size = Vector2(SEA_SIZE, SEA_SIZE)
			mi.position = Vector3(_eye.x, mi.position.y, _eye.z)
			continue
		var away := mi.position - _eye
		away.y = 0.0
		if away.length() < CARD_CLEAR:
			mi.visible = false
			continue
		mi.basis = Basis.looking_at(away)


## The haze stays, its screen-space parts off; the cinema post goes.
func _strip_post() -> void:
	var env := _shot.world_environment
	var look := DepthComposite.find_in(env)
	look.light_energy = 0.0
	look.haze_color = BossArena.OVERCAST.haze
	look.haze_amount = BossArena.OVERCAST.haze_amount
	# The haze's wide lobe, its tint toward the light's core, the light wrap and the glow are
	# screen-space: per face they would not meet at the
	# seams. The lobe made as wide as the world (the shot's floor of it everywhere would be thinner).
	look.haze_radius = 1000.0
	look.wrap_strength = 0.0
	look.haze_light_mix = 0.0
	(_shot.world_environment.environment as Environment).glow_enabled = false
	var compositor := Compositor.new()
	compositor.compositor_effects = [look]
	env.compositor = compositor


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_setup()
	if _frames < 30:
		return false
	var face: Array = FACES[_face]
	if _wait == 0:
		var f: Vector3 = face[1]
		var u: Vector3 = face[2]
		_camera.global_transform = Transform3D(Basis(f.cross(u), u, -f), _eye)
		(_shot.get_node(^"Spire") as Node3D).visible = _with_spire == null
	_wait += 1
	if _wait < 12:
		return false
	_wait = 0
	var img := _viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if _with_spire == null:
		_with_spire = img
		return false
	img = _fade_spire(_with_spire, img, face[1], face[2])
	_with_spire = null
	var path := ProjectSettings.globalize_path("%s/backdrop_%s.png" % [OUT, face[0]])
	img.save_png(path)
	print("saved ", path)
	_face += 1
	return _face >= FACES.size()


## The view with the spire, going over to the view without it as the elevation climbs. Only the
## pixels the spire touches differ, so nothing else in the face changes.
func _fade_spire(with_spire: Image, without: Image, f: Vector3, u: Vector3) -> Image:
	var a := with_spire.get_data()
	var b := without.get_data()
	var r := f.cross(u)
	for i in range(0, a.size(), 3):
		if a[i] == b[i] and a[i + 1] == b[i + 1] and a[i + 2] == b[i + 2]:
			continue
		var pixel := i / 3
		var x := (float(pixel % SIZE) + 0.5) / SIZE * 2.0 - 1.0
		var y := 1.0 - (float(pixel / SIZE) + 0.5) / SIZE * 2.0
		var up := rad_to_deg(asin((f + r * x + u * y).normalized().y))
		var k := smoothstep(ELEVATOR_FADE.x, ELEVATOR_FADE.y, up)
		for c in 3:
			b[i + c] = int(round(lerpf(a[i + c], b[i + c], k)))
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, b)
