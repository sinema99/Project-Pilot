extends SceneTree
# Throwaway probe, WINDOWED: pilot9 mounted on Speeder1 in trial, held in a ride state and shot from
# four sides. One sheet per state:   godot --path . --script tests/_probe_speeder_ride.gd -- <out_dir> [state ...]
# States: park | fast | turn | look
const STATES := {
	"park": [0.0, 0.0, 0.0, 0.0, -1.0],   # speed share, steer, head-look yaw (deg), throttle, swing (-1 = seated)
	"fast": [1.0, 0.0, 0.0, 1.0, -1.0],
	"turn": [0.8, 1.0, 0.0, 1.0, -1.0],
	"look": [0.0, 0.0, 50.0, 0.0, -1.0],
	"swing0": [0.0, 0.0, 0.0, 0.0, 0.0],
	"swing3": [0.0, 0.0, 0.0, 0.0, 0.3],
	"swing5": [0.0, 0.0, 0.0, 0.0, 0.5],
	"swing7": [0.0, 0.0, 0.0, 0.0, 0.7],
}
# [yaw off the bike's nose (deg), distance, camera height, look-at height]
const VIEWS := [[90.0, 6.9, 1.2, 1.0], [35.0, 7.4, 2.2, 0.9], [180.0, 7.2, 1.8, 1.0], [-90.0, 6.9, 1.2, 1.0]]
const CROP := Vector2i(640, 640)
const SETTLE := 40
var _out := ""
var _names: Array = []
var _f := 0
var _bike: Node
var _pilot: Node
var _cam: Camera3D
var _state := -1
var _sheet: Image
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	_names = Array(a.slice(1)) if a.size() > 1 else STATES.keys()
	change_scene_to_file("res://scenes/trial.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if _bike == null:
		if current_scene == null or _f < 90:
			return false
		_bike = current_scene.get_node("Speeder1")
		_pilot = current_scene.get_node("Pilot9")
		_pilot.global_position = _bike.global_position + Vector3(1.2, 0.3, 0)
		_bike.mount(_pilot)
		_pilot.ride_pose.record = true
		if OS.get_environment("NOCOAT") != "":
			_pilot.coat.set_on(false)
		_bike.mount_left = 0.0
		_cam = Camera3D.new(); _cam.fov = 40.0
		current_scene.add_child(_cam)
		# The bike re-takes the view for its rider every frame; point it at the probe's camera.
		_bike.camera = _cam
		_f = 0
		return false
	if _f == 30:
		_bike.set_physics_process(false)
		_next()
	if _state < 0:
		return false
	if _state >= _names.size():
		return true
	var st: Array = STATES[_names[_state]]
	_bike._speed_share = st[0]
	_bike.speed = st[0] * _bike.max_speed
	if _pilot.coat.is_on:
		_pilot.coat.velocity_override = _bike.global_basis.z * _bike.speed
	_bike.steer = st[1]
	_bike.throttle = st[3]
	_bike.dismount_swing_time = 1000.0
	_bike.dismount_left = st[4] * 1000.0 if st[4] >= 0.0 else 0.0
	_bike.grounded = true
	_bike.camera_yaw = _bike.yaw_behind(_bike.rotation.y) - deg_to_rad(st[2])
	_cam.current = true
	var local := _f - 30
	var per := 6
	if local >= SETTLE:
		var v := (local - SETTLE) / per
		var sub := (local - SETTLE) % per
		if v >= VIEWS.size():
			var path := "%s/ride_%s.png" % [_out, _names[_state]]
			print("saved ", path, " ", _sheet.save_png(path))
			_dump()
			_next()
			return false
		if sub == 0:
			var view: Array = VIEWS[v]
			var p: Vector3 = _bike.global_position
			var fwd: Vector3 = _bike.global_basis.z.rotated(Vector3.UP, deg_to_rad(view[0]))
			_cam.global_position = p + fwd * float(view[1]) + Vector3.UP * float(view[2])
			_cam.look_at(p + Vector3.UP * float(view[3]), Vector3.UP)
			_cam.reset_physics_interpolation()
		if sub == per - 1:
			var img := root.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
			var sz := img.get_size()
			_sheet.blit_rect(img, Rect2i((sz - CROP) / 2, CROP), Vector2i(CROP.x * v, 0))
	return false
func _next() -> void:
	_state += 1
	_f = 30
	_sheet = Image.create(CROP.x * VIEWS.size(), CROP.y, false, Image.FORMAT_RGBA8)

func _dump() -> void:
	var sk: Skeleton3D = _pilot.get_node("character/Armature/GeneralSkeleton")
	var inv: Transform3D = _bike.tilt.global_transform.affine_inverse()
	for b in ["Hips", "Spine", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightFoot", "RightHand"]:
		var i := sk.find_bone(b)
		print("  ", b, " ", (inv * (sk.global_transform * _pilot.ride_pose.posed.get(StringName(b), Vector3.ZERO))).snappedf(0.01))
	var rp: SkeletonModifier3D = _pilot.ride_pose
	print("  runs ", rp.runs, " active ", rp.active, " skel ", rp.get_skeleton(), " idx ", rp.get_index(), "/", rp.get_parent().get_child_count(), " cb ", sk.modifier_callback_mode_process)
	for c in rp.get_parent().get_children().slice(rp.get_index()):
		print("   after: ", c.name, " ", c.get_class(), " ", c.get_script().resource_path if c.get_script() else "", " active=", c.get("active"), " infl=", c.get("influence"))
	print("  grip_left ", _bike.grip_left, " peg_left ", _bike.peg_left, " seat ", _bike.seat_point, " infl ", _pilot.ride_pose.influence)
