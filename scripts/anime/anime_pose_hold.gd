## The last skeleton modifier on a held character. LIVE does nothing; HOLD copies the pose once and
## writes it back (an accent); CYCLE copies a new drawing whenever the stride tracker says so and
## writes the last one back in between (a drawn walk / run). Skeleton3D puts the un-modified pose
## back after each update, so everything underneath keeps running on real time. Driven by
## AnimeHold - see docs/specs/anime-animation.md.
extends SkeletonModifier3D

enum Mode { LIVE, HOLD, CYCLE }

var mode := Mode.LIVE
## Set by AnimeHold for an accent's first frame: copy the pose on this update.
var capture_pending := false
## Travel direction in skeleton space, flat, unit length (or zero). Set by AnimeHold each frame.
var travel := Vector3.ZERO
var stride := AnimeStride.new()
## Drawings taken in CYCLE. Read by the probe and tests.
var drawings := 0

var _poses: Array[Transform3D] = []
var _have := false
var _last_mode := Mode.LIVE
var _left := -1
var _right := -1


func _ready() -> void:
	var skel := get_parent() as Skeleton3D
	if skel:
		skel.child_entered_tree.connect(_on_sibling_added)


## Stays the last modifier: one added after it would otherwise draw on top of the held pose.
func _on_sibling_added(node: Node) -> void:
	if node != self and node is SkeletonModifier3D:
		_move_to_end.call_deferred()


func _move_to_end() -> void:
	var skel := get_parent()
	if skel and get_index() != skel.get_child_count() - 1:
		skel.move_child(self, -1)


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if mode != _last_mode:
		# Entering a cycle or leaving to live starts fresh; the first drawing is the pose now.
		if mode != Mode.HOLD:
			_have = false
		if mode == Mode.CYCLE:
			stride.reset()
		_last_mode = mode
	match mode:
		Mode.LIVE:
			return
		Mode.HOLD:
			if capture_pending or not _have:
				_capture(skel)
			else:
				_write(skel)
		Mode.CYCLE:
			var now := Time.get_ticks_usec() / 1000000.0
			if stride.update(now, stride_signal(skel), delta) or not _have:
				_capture(skel)
				drawings += 1
			else:
				_write(skel)
	capture_pending = false


## (left foot - right foot) . travel, in skeleton space, from the pose the modifiers before this
## one left. Positive with the left foot ahead.
func stride_signal(skel: Skeleton3D) -> float:
	if _left < 0:
		_left = skel.find_bone("LeftFoot")
		_right = skel.find_bone("RightFoot")
	if _left < 0 or _right < 0 or travel == Vector3.ZERO:
		return 0.0
	var gap := skel.get_bone_global_pose(_left).origin - skel.get_bone_global_pose(_right).origin
	return gap.dot(travel)


func _capture(skel: Skeleton3D) -> void:
	var count := skel.get_bone_count()
	_poses.resize(count)
	for i in count:
		_poses[i] = skel.get_bone_pose(i)
	_have = true


func _write(skel: Skeleton3D) -> void:
	if _poses.size() != skel.get_bone_count():
		_capture(skel)
		return
	for i in _poses.size():
		skel.set_bone_pose(i, _poses[i])
