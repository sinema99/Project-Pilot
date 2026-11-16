extends SceneTree

# Throwaway probe, WINDOWED: EXIA's weathered paint in trial.tscn, standing, three views, one sheet
# per paint scheme. See docs/specs/mech-weathering.md.
#   godot --path . --script tests/_probe_mech_paint_shot.gd -- <out_dir> [look] [clip] [secs]
# look: airframe (default) | retro.   clip: MECH_standing (default) | MECH_run | MECH_idle ...

# [yaw off its facing (deg, 0 = in front), distance, camera height, look-at height]
const VIEWS := [[35.0, 24.0, 5.5, 4.2], [180.0, 24.0, 5.5, 4.2], [-90.0, 26.0, 4.5, 4.2]]
const CROP := Vector2i(720, 900)
const SETTLE := 40

var _out := ""
var _look := "airframe"
var _clip := "MECH_standing"
var _secs := 0.0
var _mech: Node3D
var _paint: MechPaint
var _cam: Camera3D
var _frames := 0
var _scheme := -1
var _sheet: Image

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_look = args[1] if args.size() > 1 else "airframe"
	_clip = args[2] if args.size() > 2 else "MECH_standing"
	_secs = float(args[3]) if args.size() > 3 else 0.0
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _mech == null:
		if current_scene == null or _frames < 120:
			return _frames > 900
		_mech = current_scene.get_node(^"EXIA")
		_paint = _mech.get_node(^"MechPaint")
		var airframe := current_scene.get_node_or_null(^"AirframeLook")
		var retro := current_scene.get_node_or_null(^"RetroLook")
		if _look == "retro":
			airframe.set_active(false)
			retro.apply_look(true)
		else:
			retro.apply_look(false)
			airframe.set_active(true)
		_mech.set_physics_process(false)
		_cam = Camera3D.new()
		_cam.fov = 40.0
		_cam.far = 2000.0
		current_scene.add_child(_cam)
		_cam.current = true
		_next_scheme()
		return false
	if _scheme >= MechPaint.Scheme.size():
		return true
	_hold_clip()
	var local := _frames
	if local >= SETTLE:
		var v := (local - SETTLE) / 4
		if (local - SETTLE) % 4 == 0:
			_aim(v)
		elif (local - SETTLE) % 4 == 3:
			_grab(v)
			if v == VIEWS.size() - 1:
				var path := "%s/paint_%s_%s_%d.png" % [_out, _look, _clip, _scheme]
				print("saved ", path, " ", _sheet.save_png(path))
				_next_scheme()
	return false

func _next_scheme() -> void:
	_scheme += 1
	_frames = 0
	if _scheme < MechPaint.Scheme.size():
		_paint.scheme = _scheme
	_sheet = Image.create(CROP.x * VIEWS.size(), CROP.y, false, Image.FORMAT_RGBA8)

func _hold_clip() -> void:
	var player: AnimationPlayer = _mech.anim_player
	player.play(_clip)
	player.seek(minf(_secs, player.get_animation(_clip).length), true)
	player.pause()

func _aim(v: int) -> void:
	var view: Array = VIEWS[v]
	var p: Vector3 = _mech.global_position
	var facing := _mech.global_transform.basis.z
	facing.y = 0.0
	var f := facing.normalized().rotated(Vector3.UP, deg_to_rad(view[0]))
	_cam.global_position = p + f * float(view[1]) + Vector3.UP * float(view[2])
	_cam.look_at(p + Vector3.UP * float(view[3]), Vector3.UP)
	_cam.reset_physics_interpolation()

func _grab(v: int) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var size := img.get_size()
	var at := Vector2i(maxi((size.x - CROP.x) / 2, 0), maxi((size.y - CROP.y) / 2, 0))
	_sheet.blit_rect(img, Rect2i(at, Vector2i(mini(CROP.x, size.x), mini(CROP.y, size.y))), Vector2i(CROP.x * v, 0))
