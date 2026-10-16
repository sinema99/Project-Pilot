extends SceneTree

# Throwaway probe, WINDOWED (the headless dummy renderer draws nothing): poses MECH_sprint at
# the left foot's plant, low point, mid-stance, toe-off and flight and saves each from the side and
# from three-quarters front - 10 PNGs to screenshots/mech-sprint/, named <pose>-<view>.png - plus
# `cycle-side.png`, a contact sheet of 12 side views across the whole 1.0 s cycle (left to right,
# top row first) so the rhythm can be read, not just the key poses. A floor grid line every 1 m so
# stride and toe height can be read off the image.
#   godot --path . --script tests/_probe_mech_sprint.gd

# Seconds into the clip; the left foot plants at 0.
const POSES := {"plant": 0.0, "low": 0.07, "midstance": 0.175, "toeoff": 0.34, "flight": 0.425}
const SHEET_FRAMES := 12
const SHEET_CELL := 400
const GRID_SHADER := """
shader_type spatial;
render_mode unshaded;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(world.xz - 0.5) - 0.5) / fwidth(world.xz);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 m = abs(fract(world.xz / 5.0 - 0.5) - 0.5) / fwidth(world.xz / 5.0);
	float major = 1.0 - min(min(m.x, m.y), 1.0);
	ALBEDO = mix(vec3(0.82, 0.84, 0.86), vec3(0.2, 0.22, 0.28), max(line * 0.5, major));
}
"""

var _mech: Node3D
var _ap: AnimationPlayer
var _cam: Camera3D
var _jobs: Array = []
var _frame := 0
var _out := ""
var _sheet: Image = null

const MechSprint := preload("res://scripts/mech_sprint.gd")
# Frames to let the window come up before the first shot: the very first draw is empty.
const WARMUP := 10

func _initialize() -> void:
	_out = ProjectSettings.globalize_path("res://screenshots/mech-sprint/")
	DirAccess.make_dir_recursive_absolute(_out)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var shader := Shader.new()
	shader.code = GRID_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	floor_mesh.material_override = mat
	root.add_child(floor_mesh)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)

	_mech = load("res://scenes/mech.tscn").instantiate()
	root.add_child(_mech)
	# Its own physics loop would play MECH_idle over the posed clip.
	_mech.set_physics_process(false)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true

	for pose in POSES:
		for view in ["side", "front"]:
			_jobs.append({pose = pose, view = view, t = POSES[pose]})
	for i in SHEET_FRAMES:
		_jobs.append({pose = "", view = "side", t = MechSprint.LENGTH * i / SHEET_FRAMES, cell = i})

func _process(_delta: float) -> bool:
	_frame += 1
	if _ap == null:
		_ap = _mech.anim_player
		return false
	if _frame < WARMUP:
		return false
	# Three frames per shot: pose, let the skeleton and the draw settle, save.
	var step := (_frame - WARMUP) % 3
	var idx := (_frame - WARMUP) / 3
	if idx >= _jobs.size():
		_sheet.save_png(_out + "cycle-side.png")
		print("saved %d frames and the cycle sheet to %s" % [POSES.size() * 2, _out])
		return true
	var job: Dictionary = _jobs[idx]
	_mech.global_position = Vector3.ZERO
	_mech.velocity = Vector3.ZERO
	if step == 0:
		_ap.play("MECH_sprint")
		_ap.seek(job.t, true)
		_ap.pause()
		var centre := Vector3(0.0, 3.4, 0.0)
		if job.view == "side":
			_cam.global_position = centre + Vector3(24.0, 0.5, 0.0)
		else:
			_cam.global_position = centre + Vector3(16.0, 3.0, 18.0)
		_cam.look_at(centre)
	elif step == 2:
		var img := root.get_viewport().get_texture().get_image()
		if job.pose != "":
			img.save_png(_out + "%s-%s.png" % [job.pose, job.view])
			return false
		# A square around the mech, shrunk into its cell of the sheet.
		var side := mini(img.get_width(), img.get_height()) * 4 / 5
		var crop := img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2,
			side, side))
		crop.resize(SHEET_CELL, SHEET_CELL)
		if _sheet == null:
			_sheet = Image.create(SHEET_CELL * SHEET_FRAMES / 2, SHEET_CELL * 2, false, crop.get_format())
		var cell: int = job.cell
		_sheet.blit_rect(crop, Rect2i(0, 0, SHEET_CELL, SHEET_CELL),
			Vector2i((cell % (SHEET_FRAMES / 2)) * SHEET_CELL, (cell / (SHEET_FRAMES / 2)) * SHEET_CELL))
	return false
