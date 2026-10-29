extends SceneTree

# Throwaway probe, WINDOWED (the headless dummy renderer draws nothing): a contact sheet of 12 frames
# across each clip EXIA builds in code (left to right, top row first), side view on a floor grid with
# a line every 1 m (5 m bold), to screenshots/mech-moves/<clip>-side.png; the run and the sprint also
# from three-quarters front (<clip>-front.png). See docs/specs/exia-movement.md.
#   godot --path . --script tests/_probe_mech_moves.gd

const CLIPS := ["MECH_run", "MECH_sprint", "MECH_stand_idle", "MECH_turn_step", "MECH_stop_L",
	"MECH_jump_crouch", "MECH_jump_air", "MECH_land"]
const FRONT := ["MECH_run", "MECH_sprint"]
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
var _sheets: Dictionary = {}

# Frames to let the window come up before the first shot: the very first draw is empty.
const WARMUP := 10

func _initialize() -> void:
	_out = ProjectSettings.globalize_path("res://screenshots/mech-moves/")
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

	for clip in CLIPS:
		for view in (["side", "front"] if FRONT.has(clip) else ["side"]):
			for i in SHEET_FRAMES:
				_jobs.append({clip = clip, view = view, cell = i})

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
		for key in _sheets:
			(_sheets[key] as Image).save_png(_out + key + ".png")
		print("saved %d sheets to %s" % [_sheets.size(), _out])
		return true
	var job: Dictionary = _jobs[idx]
	_mech.global_position = Vector3.ZERO
	_mech.velocity = Vector3.ZERO
	if step == 0:
		var clip: Animation = _ap.get_animation(job.clip)
		var span := clip.length if clip.loop_mode != Animation.LOOP_NONE else clip.length * SHEET_FRAMES / (SHEET_FRAMES - 1)
		_ap.play(job.clip)
		_ap.seek(minf(span * job.cell / SHEET_FRAMES, clip.length), true)
		_ap.pause()
		var centre := Vector3(0.0, 3.4, 0.0)
		if job.view == "side":
			_cam.global_position = centre + Vector3(24.0, 0.5, 0.0)
		else:
			_cam.global_position = centre + Vector3(16.0, 3.0, 18.0)
		_cam.look_at(centre)
	elif step == 2:
		var img := root.get_viewport().get_texture().get_image()
		# A square around the mech, shrunk into its cell of the sheet.
		var side := mini(img.get_width(), img.get_height()) * 4 / 5
		var crop := img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2,
			side, side))
		crop.resize(SHEET_CELL, SHEET_CELL)
		var key: String = "%s-%s" % [job.clip, job.view]
		if not _sheets.has(key):
			_sheets[key] = Image.create(SHEET_CELL * SHEET_FRAMES / 2, SHEET_CELL * 2, false, crop.get_format())
		var cell: int = job.cell
		(_sheets[key] as Image).blit_rect(crop, Rect2i(0, 0, SHEET_CELL, SHEET_CELL),
			Vector2i((cell % (SHEET_FRAMES / 2)) * SHEET_CELL, (cell / (SHEET_FRAMES / 2)) * SHEET_CELL))
	return false
