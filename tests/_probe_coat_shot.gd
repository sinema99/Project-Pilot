extends SceneTree

# Throwaway probe, WINDOWED: pilot9 in his trench coat in trial.tscn, held in a clip pose with the
# coat fed a speed, shot from three sides. One sheet (back three-quarter | side | front) per pose.
#   godot --path . --script tests/_probe_coat_shot.gd -- <out_dir> [look] [pilot_index] [pose ...]
# look: airframe (default) | retro. Poses default to all of POSES.

# name -> [clip, seconds into it, speed along his facing (m/s), vertical speed (m/s), extras]
const POSES := {
	"idle": ["idle", 0.0, 0.0, 0.0, ""],
	"off": ["idle", 0.0, 0.0, 0.0, "off"],
	"run": ["run_forward", 0.2, 5.0, 0.0, ""],
	"sprint": ["sprint_forward", 0.2, 7.5, 0.0, ""],
	"back": ["run_backward", 0.2, -5.0, 0.0, ""],
	"left": ["run_left", 0.2, 0.0, 0.0, "side5"],
	"left2": ["run_left", 0.45, 0.0, 0.0, "side5"],
	"left3": ["run_left", 0.7, 0.0, 0.0, "side5"],
	"left4": ["run_left", 0.95, 0.0, 0.0, "side5"],
	"right3": ["run_right", 0.7, 0.0, 0.0, "side-5"],
	"right4": ["run_right", 0.95, 0.0, 0.0, "side-5"],
	"right": ["run_right", 0.2, 0.0, 0.0, "side-5"],
	"right2": ["run_right", 0.45, 0.0, 0.0, "side-5"],
	"fl": ["run_forward_left", 0.2, 3.5, 0.0, "side3.5"],
	"fl2": ["run_forward_left", 0.45, 3.5, 0.0, "side3.5"],
	"fr": ["run_forward_right", 0.2, 3.5, 0.0, "side-3.5"],
	"fr2": ["run_forward_right", 0.45, 3.5, 0.0, "side-3.5"],
	"jump": ["jump", 0.15, 5.0, 7.0, "air"],
	"jump2": ["jump", 0.35, 5.0, 2.0, "air"],
	"fall": ["fall", 0.2, 3.0, -12.0, "air"],
	"dash": ["sprint_forward", 0.1, 40.0, 0.0, ""],
	"slide": ["slide", 0.3, 9.0, 0.0, "sliding"],
	"crouch": ["crouch_kneel", 0.3, 0.0, 0.0, "crouch overidle"],
	# The 2026-11-15 crouch jog (scripts/crouch_bake.gd), legs over the idle like the real state.
	"cjog": ["crouch_jog_forward", 0.05, 5.0, 0.0, "crouch overidle"],
	"cjog2": ["crouch_jog_forward", 0.2, 5.0, 0.0, "crouch overidle"],
	"cjogback": ["crouch_jog_back", 0.2, -5.0, 0.0, "crouch overidle"],
	"cjogleft": ["crouch_jog_left", 0.2, 0.0, 0.0, "crouch overidle side5"],
	# A forward crouch-walk cycle strip (0.58 s cycle in quarters), coat on and off.
	"cf0": ["crouch_jog_forward", 0.0, 2.5, 0.0, "crouch overidle"],
	"cf1": ["crouch_jog_forward", 0.145, 2.5, 0.0, "crouch overidle"],
	"cf2": ["crouch_jog_forward", 0.29, 2.5, 0.0, "crouch overidle"],
	"cf3": ["crouch_jog_forward", 0.435, 2.5, 0.0, "crouch overidle"],
	"cfo0": ["crouch_jog_forward", 0.0, 2.5, 0.0, "crouch overidle off"],
	"cfo1": ["crouch_jog_forward", 0.145, 2.5, 0.0, "crouch overidle off"],
	"cfo2": ["crouch_jog_forward", 0.29, 2.5, 0.0, "crouch overidle off"],
	"cfo3": ["crouch_jog_forward", 0.435, 2.5, 0.0, "crouch overidle off"],
	"wallrun": ["wall_run_r", 0.3, 7.5, 0.0, "wall_r air"],
	"mantle": ["climb_up", 0.5, 0.0, 1.5, "wall_f air"],
	"vault": ["vault", 0.35, 6.0, 0.0, "air"],
	"wallclimb": ["wall_climb", 0.5, 0.0, 2.0, "wall_f air"],
}
# [yaw off his facing (deg, 0 = in front of him), distance, camera height, look-at height]
const VIEWS := [[180.0, 5.6, 1.4, 1.0], [150.0, 5.6, 2.0, 1.0], [90.0, 5.6, 1.3, 1.0], [20.0, 5.6, 1.4, 1.0]]
const CROP := Vector2i(640, 900)
const SETTLE := 70

var _out := ""
var _look := "airframe"
var _which := 0
var _names: Array = []
var _pilot: Node
var _cam: Camera3D
var _frames := 0
var _pose := -1
var _view := 0
var _sheet: Image
var _home := Vector3.ZERO

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_look = args[1] if args.size() > 1 else "airframe"
	_which = int(args[2]) if args.size() > 2 else 0
	_names = Array(args.slice(3)) if args.size() > 3 else POSES.keys()
	# Windowed probes otherwise overwrite the real user://loadout.json.
	var inv := root.get_node_or_null(^"/root/Inventory")
	if inv != null:
		inv.persist = false
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		if current_scene == null or _frames < 120:
			return _frames > 900
		var all: Array[Node] = []
		_find(current_scene, all)
		_pilot = all[_which]
		var airframe := current_scene.get_node_or_null(^"AirframeLook")
		var retro := current_scene.get_node_or_null(^"RetroLook")
		if _look == "retro":
			airframe.set_active(false)
			retro.apply_look(true)
		else:
			retro.apply_look(false)
			airframe.set_active(true)
		_pilot.frozen = true
		_pilot.anim_tree.active = false
		_home = _pilot.global_position
		_cam = Camera3D.new()
		_cam.fov = 40.0
		current_scene.add_child(_cam)
		_cam.current = true
		_frames = 0
		_next_pose()
		return false
	if _pose >= _names.size():
		return true
	var local := _frames % (SETTLE + VIEWS.size() * 4)
	# The clip is re-seeked every frame: nothing else is driving his skeleton.
	_hold_clip()
	if local >= SETTLE:
		var v := (local - SETTLE) / 4
		if (local - SETTLE) % 4 == 0:
			_aim(v)
		elif (local - SETTLE) % 4 == 3:
			_grab(v)
			if v == VIEWS.size() - 1:
				var path := "%s/coat_%s_%s_%d.png" % [_out, _look, _names[_pose], _which]
				print("saved ", path, " ", _sheet.save_png(path), "  hem tilts deg: ", _tilts())
				_next_pose()
	return false

func _next_pose() -> void:
	_pose += 1
	_frames = 0
	if _pose >= _names.size():
		return
	var p: Array = POSES[_names[_pose]]
	var extras: String = p[4]
	var coat: Node = _pilot.coat
	coat.set_on(not extras.contains("off"))
	var facing: Vector3 = _pilot._facing()
	coat.velocity_override = facing * float(p[2]) + Vector3.UP * float(p[3])
	# "sideN": N m/s toward his left (his mesh +X; negative = his right).
	for word in extras.split(" "):
		if word.begins_with("side"):
			var left: Vector3 = Vector3.UP.cross(facing).normalized()
			coat.velocity_override += left * float(word.substr(4))
	if coat.velocity_override.length() == 0.0:
		coat.velocity_override = null
	_pilot.is_crouching = extras.contains("crouch")
	_pilot.is_sliding = extras.contains("sliding")
	# In the air he is lifted off the floor, so the floor plane is out of it.
	_pilot.global_position = _home + (Vector3.UP * 3.0 if extras.contains("air") else Vector3.ZERO)
	_pilot.set_physics_process(not extras.contains("air"))
	coat.extra_planes = []
	var right: Vector3 = facing.cross(Vector3.UP).normalized()
	if extras.contains("wall_r"):
		coat.extra_planes = [[_pilot.global_position + right * 0.42, -right]]
	if extras.contains("wall_f"):
		coat.extra_planes = [[_pilot.global_position + facing * 0.38, -facing]]
	coat.reset()
	coat.leg_clearance = OS.get_environment("COAT_PROBE_NOCLEAR") == ""
	# COAT_PROBE_HIDE=name,name: hide those body pieces (finding what pokes through).
	for n in OS.get_environment("COAT_PROBE_HIDE").split(",", false):
		var mi: Node = coat.skeleton.get_node_or_null(NodePath(n))
		if mi != null:
			mi.visible = false
	_sheet = Image.create(CROP.x * VIEWS.size(), CROP.y, false, Image.FORMAT_RGBA8)

func _hold_clip() -> void:
	var p: Array = POSES[_names[_pose]]
	var player: AnimationPlayer = _pilot.anim_player
	if String(p[4]).contains("overidle"):
		# The crouch clips key only the hips and legs: lay them over the idle, as the state does.
		player.play(&"idle")
		player.seek(0.0, true)
	# The crouch lean (scripts/crouch_lean.gd) is driven by pilot9_animation.gd, which the probe
	# does not run: hold it here - kneel for the kneel, jog for the jog clips.
	var lean = _pilot.get(&"crouch_lean")
	if lean != null:
		for n in _pilot.find_children("*", "Node", true, false):
			var sc = n.get_script()
			if sc != null and String(sc.resource_path).ends_with("pilot9_animation.gd"):
				n.set_process(false)
				n.set_physics_process(false)
		var crouched := String(p[4]).contains("crouch")
		lean.crouch_target = 1.0 if crouched else 0.0
		lean.weight = lean.crouch_target
		lean.move = 1.0 if String(p[0]).begins_with("crouch_jog") else 0.0
		lean.aim = 0.0
	if player.has_animation(p[0]):
		player.play(p[0])
		player.seek(float(p[1]), true)
		player.pause()
	elif _frames == 1:
		print("NO CLIP ", p[0], " - have: ", player.get_animation_list())

func _aim(v: int) -> void:
	var view: Array = VIEWS[v]
	var p: Vector3 = _pilot.global_position
	var f: Vector3 = _pilot._facing().rotated(Vector3.UP, deg_to_rad(view[0]))
	_cam.global_position = p + f * float(view[1]) + Vector3.UP * float(view[2])
	_cam.look_at(p + Vector3.UP * float(view[3]), Vector3.UP)
	_cam.reset_physics_interpolation()

func _grab(v: int) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var size := img.get_size()
	var at := Vector2i((size.x - CROP.x) / 2, maxi((size.y - CROP.y) / 2, 0))
	_sheet.blit_rect(img, Rect2i(at, Vector2i(CROP.x, mini(CROP.y, size.y))), Vector2i(CROP.x * v, 0))

func _tilts() -> String:
	var coat: Node = _pilot.coat
	var out := PackedStringArray()
	for c in coat.CHAINS:
		out.append("%d/%d" % [roundi(coat.tilt_deg(c).length()), roundi(coat.tilt_deg(coat.CHAINS + c).length())])
	return ",".join(out)

func _find(n: Node, out: Array[Node]) -> void:
	if n.has_method(&"toggle_coat"):
		out.append(n)
	for c in n.get_children():
		_find(c, out)
