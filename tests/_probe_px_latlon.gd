extends SceneTree

# Throwaway: intro shot at t=0, unprojects display pixels (2000x1125 frame) to Earth lat / lon.
const PX := [[916,203],[938,265],[1072,265],[1128,180],[1284,191],[1395,247],[1407,303],[1340,314],[1250,414],[1083,504],[938,559],[804,615],[744,604],[726,504],[771,441],[865,381],[749,303],[827,247],[1440,575]]
var _f := 0

func _initialize() -> void:
	root.size = Vector2i(2560, 1440)
	change_scene_to_file("res://scenes/cutscene_intro_space.tscn")

func _process(_d: float) -> bool:
	_f += 1
	if current_scene == null or _f < 10:
		return false
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	ap.pause()
	ap.seek(0.0, true)
	if _f < 14:
		return false
	var cam: Camera3D = current_scene.get_node("CameraRig/Camera3D")
	var planet: MeshInstance3D = current_scene.get_node("PlanetTilt/Planet")
	var c := planet.global_position
	var r := 4000.0 * planet.global_transform.basis.get_scale().x
	for p in PX:
		var sp := Vector2(p[0], p[1]) * 1.28 * Vector2(root.get_visible_rect().size) / Vector2(2560, 1440)
		var o := cam.project_ray_origin(sp)
		var d := cam.project_ray_normal(sp)
		var oc := o - c
		var b := oc.dot(d)
		var disc := b * b - (oc.length_squared() - r * r)
		if disc < 0.0:
			print(p, " miss")
			continue
		var hit := o + d * (-b - sqrt(disc))
		var e := (planet.global_transform.affine_inverse() * hit).normalized()
		print(p, " lat %.1f lon %.1f" % [rad_to_deg(asin(e.y)), rad_to_deg(atan2(-e.z, e.x))])
	return true
