extends SceneTree

# Turns the Earth so Florida sits under the end of the Vanguard's dive in cutscene shot 1
# (docs/specs/cutscene-intro-space.md, "Planet upgrade"). The planet shaders read the surface by
# object-space direction, which IS the Earth direction (+y = north, the spin axis), so this sets
# the PlanetTilt node's rotation and writes it into the scene. It also prints the latitude / longitude box the frame sees
# over the whole shot, which is the crop tools/gen_planet_earth.py bakes.
#   godot --headless --path . --script tools/gen_planet_earth_frame.gd
#
# Earth direction convention (shared with the shaders and the bake): y = north,
# x = cos(lat) cos(lon), z = -cos(lat) sin(lon), longitude east-positive. A positive turn about +y
# moves the surface east, the way the Earth spins, so the planet's 0.06 rad turn reads right.

const SCENE := "res://scenes/cutscene_intro_space.tscn"
const DIVE_END := 12.0
const SHOT_END := 12.3
const FLORIDA_LAT := 27.8
const FLORIDA_LON := -81.7

var _frames := 0


static func earth_dir(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon))


static func lat_lon(e: Vector3) -> Vector2:
	e = e.normalized()
	return Vector2(rad_to_deg(asin(clampf(e.y, -1.0, 1.0))), rad_to_deg(atan2(-e.z, e.x)))


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 3:
		return false
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	var tilt: Node3D = current_scene.get_node("PlanetTilt")
	var planet: Node3D = current_scene.get_node("PlanetTilt/Planet")
	var cam: Camera3D = current_scene.get_node("CameraRig/Camera3D")
	var ship: Node3D = current_scene.get_node("CameraRig/ShipPath/ShipFollow")
	var radius: float = (planet as MeshInstance3D).mesh.radius
	ap.pause()
	ap.seek(DIVE_END, true)
	# Where the ship's speck is on the planet: the line of sight through it, onto the surface.
	var hit := _ray_sphere(cam.global_position, (ship.global_position - cam.global_position).normalized(),
			planet.global_position, radius)
	assert(hit != Vector3.INF, "line of sight through the ship misses the planet")
	var h_w := (hit - planet.global_position).normalized()
	# Florida as it sits in PlanetTilt space at that moment (the planet has turned a little).
	var g := Basis(Vector3.UP, planet.rotation.y) * earth_dir(FLORIDA_LAT, FLORIDA_LON)
	# North (the spin axis, PlanetTilt's +y) as close to the old 18 deg tilt as Florida's latitude
	# allows: swung toward or away from the camera in the plane of Florida and the old axis.
	var old_up := tilt.global_transform.basis.y.normalized()
	var colat := deg_to_rad(90.0 - FLORIDA_LAT)
	var side := h_w.cross(old_up).normalized()
	var n_w := h_w.rotated(side, colat).normalized()
	if n_w.dot(old_up) < 0.0:
		n_w = h_w.rotated(side, -colat).normalized()
	var tilt_basis := _frame(h_w, n_w) * _frame(g, Vector3.UP).transposed()
	print("north swung %.1f deg off the old axis" % rad_to_deg(n_w.angle_to(old_up)))
	tilt.global_transform.basis = tilt_basis
	ap.seek(DIVE_END, true)
	print("check: under the ship is %s" % lat_lon(
			(planet.global_transform.affine_inverse() * hit).normalized()))
	_print_bounds(ap, planet, cam, radius)
	_save(tilt_basis)
	return true


# Orthonormal basis with `a` as x and `up` (made perpendicular) as y.
func _frame(a: Vector3, up: Vector3) -> Basis:
	var y := (up - a * up.dot(a)).normalized()
	return Basis(a, y, a.cross(y))


func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> Vector3:
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.length_squared() - r * r)
	if disc < 0.0:
		return Vector3.INF
	return o + d * (-b - sqrt(disc))


# The lat / lon box of every surface point any pixel sees at the start and end of the shot.
func _print_bounds(ap: AnimationPlayer, planet: Node3D, cam: Camera3D, radius: float) -> void:
	var lo := Vector2(90, 180)
	var hi := Vector2(-90, -180)
	var size := Vector2(1920, 1080)
	for t in [0.0, SHOT_END]:
		ap.seek(t, true)
		var inv := planet.global_transform.affine_inverse()
		for yi in 41:
			for xi in 61:
				var px := Vector2(xi / 60.0, yi / 40.0) * size
				var o := cam.project_ray_origin(px)
				var d := _ray_dir(cam, px, size)
				var hit := _ray_sphere(o, d, planet.global_position, radius)
				if hit == Vector3.INF:
					# Past the limb: the nearest surface point is the tangent point, keep it so the
					# crop includes the limb itself.
					var c := planet.global_position
					var p := o + d * (c - o).dot(d)
					hit = c + (p - c).normalized() * radius
				var ll := lat_lon((inv * hit).normalized())
				lo = Vector2(minf(lo.x, ll.x), minf(lo.y, ll.y))
				hi = Vector2(maxf(hi.x, ll.x), maxf(hi.y, ll.y))
	print("visible box: lat %.1f .. %.1f, lon %.1f .. %.1f" % [lo.x, hi.x, lo.y, hi.y])


# Ray direction through a pixel of a 1920x1080 frame at the camera's fov (headless has no window
# of that size, so the projection is done by hand rather than with project_ray_normal).
func _ray_dir(cam: Camera3D, px: Vector2, size: Vector2) -> Vector3:
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var ndc := Vector2(px.x / size.x * 2.0 - 1.0, 1.0 - px.y / size.y * 2.0)
	var local := Vector3(ndc.x * tan_v * size.x / size.y, ndc.y * tan_v, -1.0).normalized()
	return (cam.global_transform.basis * local).normalized()


func _save(b: Basis) -> void:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var head := "[node name=\"PlanetTilt\" type=\"Node3D\" parent=\".\"]\ntransform = Transform3D("
	var start := text.find(head)
	assert(start >= 0, "PlanetTilt transform not found")
	start += head.length()
	var end := text.find(")", start)
	var origin: Vector3 = (current_scene.get_node("PlanetTilt") as Node3D).position
	# .tscn stores the basis row by row (b.x is a column).
	var value := "%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s" % [
			b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, origin.x, origin.y, origin.z]
	text = text.substr(0, start) + value + text.substr(end)
	f = FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(text)
	print("PlanetTilt basis = ", b)
