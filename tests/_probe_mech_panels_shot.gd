extends SceneTree

# Throwaway probe, WINDOWED: EXIA's back panels in trial.tscn, held in a clip pose, shot from the two
# angles of the user's drawing (side, behind) plus a back three-quarter. One sheet per pose.
# See docs/specs/exia-back-panels.md.
#   godot --path . --script tests/_probe_mech_panels_shot.gd -- <out_dir> [look]
# look: airframe (default) | retro.

# name -> [clip, seconds into it]
# Rev 4: the run and sprint sheets also put the mech in Loco.RUN with a pilot "driving", so the panels
# swing to the run tilt; "kneel" holds MECH_idle's last frame, the parked crouch.
const POSES := {"standing": ["MECH_standing", 0.0], "run": ["MECH_run", 0.6], "sprint": ["MECH_sprint", 0.5],
	"kneel": ["MECH_idle", 1.0], "powerdown_mid": ["MECH_idle", 0.5], "bootup_025": ["MECH_launch", 0.25],
	"bootup_mid": ["MECH_launch", 0.5],
	# Rev 5: the swing held at its caps - [clip, seconds, sway deg].
	"sway_out": ["MECH_standing", 0.0, 6.0], "sway_in": ["MECH_standing", 0.0, -3.0],
	"run_sway_out": ["MECH_run", 0.6, 6.0]}
# [yaw off its facing (deg, 0 = in front), distance, camera height, look-at height]
const VIEWS := [[-90.0, 28.0, 4.0, 4.3], [180.0, 20.0, 6.0, 4.3], [150.0, 22.0, 5.0, 4.3]]
const CROP := Vector2i(720, 900)
const SETTLE := 40

var _out := ""
var _look := "airframe"
var _mech: Node3D
var _cam: Camera3D
var _frames := 0
var _pose := -1
var _names: Array = POSES.keys()
var _sheet: Image

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_look = args[1] if args.size() > 1 else "airframe"
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _mech == null:
		if current_scene == null or _frames < 120:
			return _frames > 900
		_mech = current_scene.get_node(^"EXIA")
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
		_next_pose()
		return false
	if _pose >= _names.size():
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
				var path := "%s/panels_%s_%s.png" % [_out, _look, _names[_pose]]
				print("saved ", path, " ", _sheet.save_png(path))
				_next_pose()
	return false

func _next_pose() -> void:
	_pose += 1
	_frames = 0
	_sheet = Image.create(CROP.x * VIEWS.size(), CROP.y, false, Image.FORMAT_RGBA8)

func _hold_clip() -> void:
	if _pose >= _names.size():
		return
	var p: Array = POSES[_names[_pose]]
	var player: AnimationPlayer = _mech.anim_player
	player.play(p[0])
	player.seek(minf(float(p[1]), player.get_animation(p[0]).length), true)
	player.pause()
	var running: bool = p[0] == "MECH_run" or p[0] == "MECH_sprint"
	_mech._panels_driving = running
	_mech.loco = 2 if running else 0  # Loco.RUN / Loco.STAND
	_mech._panel_sway = Vector2(float(p[2]) if p.size() > 2 else 0.0, 0.0)

func _aim(v: int) -> void:
	var view: Array = VIEWS[v]
	var p: Vector3 = _mech.global_position
	var facing := _mech.global_transform.basis.z
	facing.y = 0.0
	var f := facing.normalized().rotated(Vector3.UP, deg_to_rad(view[0]))
	_cam.global_position = p + f * float(view[1]) + Vector3.UP * float(view[2])
	# Aim a little behind the mech, so the panels sit in frame from the side.
	_cam.global_position -= facing.normalized() * 2.0
	_cam.look_at(p - facing.normalized() * 2.0 + Vector3.UP * float(view[3]), Vector3.UP)
	_cam.reset_physics_interpolation()

func _grab(v: int) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var size := img.get_size()
	var at := Vector2i(maxi((size.x - CROP.x) / 2, 0), maxi((size.y - CROP.y) / 2, 0))
	_sheet.blit_rect(img, Rect2i(at, Vector2i(mini(CROP.x, size.x), mini(CROP.y, size.y))), Vector2i(CROP.x * v, 0))
