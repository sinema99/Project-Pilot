extends SceneTree

# Sets the roll of the Vanguard's flight path in cutscene shot 1 (docs/specs/cutscene-intro-space.md,
# revision 5): every path point's tilt turns the ship so its top points at the planet's centre at
# the moment the ship is there. Run after tools/gen_intro_space_path.py (which leaves tilts at 0):
#   godot --headless --path . --script tools/gen_intro_space_tilts.gd
# Writes the tilts into scenes/cutscene_intro_space.tscn and prints how close the result is.

const SCENE := "res://scenes/cutscene_intro_space.tscn"
const FLY_START := 7.0
const FLY_TIME := 5.0

var _frames := 0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 3:
		return false
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	var path: Path3D = current_scene.get_node("CameraRig/ShipPath")
	var planet: Node3D = current_scene.get_node("PlanetTilt/Planet")
	var curve := path.curve
	ap.pause()
	for i in curve.point_count:
		curve.set_point_tilt(i, 0.0)
	# Two passes: the second only mops up the error from tilt being interpolated between points.
	for pass_i in 2:
		var tilts := PackedFloat32Array()
		for i in curve.point_count:
			var off := curve.get_closest_offset(curve.get_point_position(i))
			var err := _roll_error(curve, off, _planet_local(ap, path, planet, off / curve.get_baked_length()))
			tilts.append(curve.get_point_tilt(i) + err)
		# Unwrap so neighbouring tilts never jump a full turn.
		for i in range(1, tilts.size()):
			tilts[i] = tilts[i - 1] + wrapf(tilts[i] - tilts[i - 1], -PI, PI)
		for i in curve.point_count:
			curve.set_point_tilt(i, tilts[i])
	var worst := 0.0
	var n := 200
	for k in n + 1:
		var r := float(k) / n
		var e := absf(_roll_error(curve, r * curve.get_baked_length(), _planet_local(ap, path, planet, r)))
		worst = maxf(worst, e)
	print("roll error, worst over the flight: %.2f deg" % rad_to_deg(worst))
	_save_tilts(curve)
	return true


# Planet centre in ShipPath space when the ship is `ratio` along the path (constant speed).
func _planet_local(ap: AnimationPlayer, path: Path3D, planet: Node3D, ratio: float) -> Vector3:
	ap.seek(FLY_START + FLY_TIME * ratio, true)
	return path.global_transform.affine_inverse() * planet.global_position


# Angle (about the direction of travel) from the path's up at `off` to "towards the planet".
func _roll_error(curve: Curve3D, off: float, planet_local: Vector3) -> float:
	var xf := curve.sample_baked_with_rotation(off, false, true)
	var fwd := -xf.basis.z
	var want := (planet_local - xf.origin).slide(fwd).normalized()
	return xf.basis.y.signed_angle_to(want, fwd)


func _save_tilts(curve: Curve3D) -> void:
	var parts := PackedStringArray()
	for i in curve.point_count:
		parts.append("%.4f" % curve.get_point_tilt(i))
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var re := RegEx.create_from_string("(\\[sub_resource type=\"Curve3D\" id=\"Curve3D_ship\"\\][\\s\\S]*?\"tilts\": PackedFloat32Array\\()[^)]*\\)")
	var m := re.search(text)
	assert(m != null, "Curve3D_ship tilts not found")
	text = text.substr(0, m.get_start()) + m.get_string(1) + ", ".join(parts) + ")" + text.substr(m.get_end())
	f = FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote %d tilts, %.1f to %.1f deg" % [curve.point_count,
			rad_to_deg(curve.get_point_tilt(0)), rad_to_deg(curve.get_point_tilt(curve.point_count - 1))])
