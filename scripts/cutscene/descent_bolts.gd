class_name DescentBolts
extends Node3D

# The background lightning strikes in the descent shot (docs/specs/cutscene-descent.md, "Storm
# side" rows 28-29): jagged bolts with a white-hot core and a fork or two, dropping from the cloud
# through the band of sky above the mountains. Each is drawn in sketch pixels, from just behind the
# deck's front edge (DescentShot.lip_y) down to just under the horizon, then pushed out to
# DescentShot.BOLT_DISTANCE, so its top hides behind the deck and its foot behind the near ridge.
# Flat strips facing the locked camera. Brightness is the IntroSpaceLightning pulse shape on the
# shot clock, so seeking shows the same frame.

const SHADER := preload("res://shaders/cutscene/bolt.gdshader")
## Sketch y of a bolt's foot: just under the horizon, behind the near ridge.
const FOOT_Y := 556.0
## How far behind the deck's edge (sketch px) a bolt's top starts.
const TOP_HIDDEN := 30.0
## Strip width (m) at BOLT_DISTANCE: about 6 px at 1080p, core a third of it.
const WIDTH := 38.0
const FORK_WIDTH := 0.55

## One per strike: {flash: IntroSpaceLightning.Flash, x: sketch x, mesh: MeshInstance3D}.
var strikes: Array[Dictionary] = []
var _decay := 0.05


## Builds one bolt per bolt_table row (see DescentShot.bolt_table).
func build(table: Array, decay: float, seed_ := 23) -> void:
	for c in get_children():
		c.free()
	strikes.clear()
	_decay = decay
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for row: Array in table:
		var f := IntroSpaceLightning.Flash.new()
		f.start = row[0]
		f.peak = row[3]
		f.pulses = PackedFloat32Array(row[2])
		var x: float = row[1]
		var mi := MeshInstance3D.new()
		mi.name = "Bolt%d" % strikes.size()
		mi.mesh = _bolt_mesh(rng, x, float(row[5]))
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		strikes.append({flash = f, x = x, mesh = mi})


## Shows shot time `t`.
func apply(t: float) -> void:
	for s: Dictionary in strikes:
		var b := (s.flash as IntroSpaceLightning.Flash).brightness_at(t, _decay)
		var mi: MeshInstance3D = s.mesh
		mi.visible = b > 0.01
		(mi.material_override as ShaderMaterial).set_shader_parameter(&"brightness", b)


## Brightness of each strike at `t`.
func brightness_at(t: float) -> Array[float]:
	var out: Array[float] = []
	for s: Dictionary in strikes:
		out.append((s.flash as IntroSpaceLightning.Flash).brightness_at(t, _decay))
	return out


## For the snow curtain: the brightest `slots` live strikes behind it, as Vector4(sketch x as a
## fraction of the frame, 0, 0, brightness), padded with dark entries.
func curtain_glows(t: float, slots: int) -> Array[Vector4]:
	var live: Array[Vector4] = []
	for s: Dictionary in strikes:
		if s.x > DescentShot.CURTAIN_END_X:
			continue
		var b := (s.flash as IntroSpaceLightning.Flash).brightness_at(t, _decay)
		if b > 0.01:
			live.append(Vector4(s.x / DescentShot.SKETCH_SIZE.x, 0.0, 0.0, b))
	live.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w > b.w)
	live.resize(mini(live.size(), slots))
	while live.size() < slots:
		live.append(Vector4.ZERO)
	return live


# --- the bolt's shape --------------------------------------------------------------------------

func _bolt_mesh(rng: RandomNumberGenerator, x: float, drift: float) -> ArrayMesh:
	var top := Vector2(x, DescentShot.lip_y(x) - TOP_HIDDEN)
	var main := _jagged(rng, top, Vector2(x + drift, FOOT_Y), 6, 0.22)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_strip(st, main, WIDTH, 1.0)
	# One or two forks off the upper two thirds, heading down and away to one side.
	for i in rng.randi_range(1, 2):
		var from := main[int(main.size() * rng.randf_range(0.15, 0.6))]
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var to := from + Vector2(side * rng.randf_range(50.0, 110.0), rng.randf_range(70.0, 140.0))
		_strip(st, _jagged(rng, from, to, 4, 0.25), WIDTH * FORK_WIDTH, 0.7)
	return st.commit()


## A jagged line from `a` to `b` in sketch px: midpoint displacement, `levels` deep, each midpoint
## pushed sideways by up to `rough` of its segment's length.
func _jagged(rng: RandomNumberGenerator, a: Vector2, b: Vector2, levels: int, rough: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	for level in levels:
		var next := PackedVector2Array()
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var n := (q - p).orthogonal().normalized()
			next.append(p)
			next.append((p + q) * 0.5 + n * (q - p).length() * rng.randf_range(-rough, rough))
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


## Appends a camera-facing strip along sketch polyline `line`, `width` m wide. UV.x runs across it;
## COLOR.a is the strip's strength (forks are dimmer).
func _strip(st: SurfaceTool, line: PackedVector2Array, width: float, strength: float) -> void:
	var world := PackedVector3Array()
	for px in line:
		world.append(DescentShot.sketch_point(px, DescentShot.BOLT_DISTANCE))
	for i in world.size() - 1:
		var a := world[i]
		var b := world[i + 1]
		var view := (a - DescentShot.CAMERA_POSITION).normalized()
		var side := (b - a).cross(view).normalized() * width * 0.5
		# Each segment runs a little past its ends so the joints have no gaps.
		var along := (b - a).normalized() * width * 0.25
		var quad := [a - along - side, a - along + side, b + along + side, b + along - side]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(1, 1, 1, strength))
			st.set_uv(uvs[k])
			st.add_vertex(quad[k])
