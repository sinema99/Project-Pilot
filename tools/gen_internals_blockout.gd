extends SceneTree

# One-shot builder for the Internals greybox (map 1). See docs/specs/internals-map.md.
#
# Reads the layout tables (P pieces, D doors, R route, MARK markers) straight out of
# docs/specs/internals-plan.html, so the plan page and the greybox can never disagree on day one,
# and writes scenes/internals.tscn + Internals.tscn + resources/internals/*.tres.
#
# ONE-SHOT. Every node is saved with an owner, so the scene is yours to edit in the editor
# afterwards; running this again would throw those edits away, so it refuses to overwrite an
# existing scene unless you pass --force:
#
#   godot --headless --path . --script tools/gen_internals_blockout.gd -- --force
#
# Coordinates: plan x = Godot X, plan z = Godot Z, heights = Godot Y, origin = the plan's
# top-left corner. Walls are CSG: one Shell combiner unions every enclosure grown by WALL, then
# subtracts every enclosure's air shrunk by INSET (so two spaces that touch keep a wall between
# them), then the doors. Nested rooms (a room inside a hall's air) go after the air.

const PLAN := "res://docs/specs/internals-plan.html"
const SCENE := "res://scenes/internals.tscn"
const WRAPPER := "res://Internals.tscn"
const MAT_DIR := "res://resources/internals"
const CEL_BASE := "res://resources/cel_ground.tres"

const WALL := 1.0
const INSET := 0.5
const SLAB := 0.5
const DOOR_DEPTH := 5.0
## Enclosures whose footprint sits inside another enclosure's air: built after the air.
const NESTED := ["GV"]
## Shafts whose blocks hang as 2 m slabs instead of standing on the shaft floor.
const HANGING := ["P0"]

const ZONE_LIGHT := {
	1: Color(1.0, 0.86, 0.7), 2: Color(0.62, 0.86, 1.0), 3: Color(0.5, 0.9, 1.0),
	4: Color(1.0, 0.66, 0.3), 5: Color(0.45, 0.62, 1.0), 6: Color(0.45, 1.0, 0.6),
	7: Color(0.3, 0.85, 0.8), 8: Color(0.8, 0.6, 1.0), 9: Color(0.5, 0.65, 1.0),
	10: Color(1.0, 0.32, 0.25),
}

var _root: Node3D
var _mats := {}
var _zones := {}
var _pieces: Array = []
var _route: Array = []

func _initialize() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	if FileAccess.file_exists(SCENE) and not force:
		push_error("%s exists - it may hold hand edits. Pass -- --force to overwrite it." % SCENE)
		quit(1)
		return
	var html := FileAccess.get_file_as_string(PLAN)
	_pieces = _table(html, "P")
	var doors := _table(html, "D")
	_route = _table(html, "R")
	var marks := _table(html, "MARK")
	var rx := RegEx.create_from_string("\\n (\\d+):\\[\"([^\"]+)\"")
	for m in rx.search_all(html):
		_zones[int(m.get_string(1))] = m.get_string(2)
	if _pieces.is_empty() or doors.is_empty() or _route.is_empty():
		push_error("could not read the layout tables from %s" % PLAN)
		quit(1)
		return
	_make_materials()
	_build(doors, marks)
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE)
	if err != OK:
		push_error("saving %s failed: %d" % [SCENE, err])
		quit(1)
		return
	_save_wrapper()
	print("wrote %s: %d pieces, %d doors, %d zones" % [SCENE, _pieces.size(), doors.size(), _zones.size()])
	_root.free()
	quit(0)

# --- reading the plan ------------------------------------------------------

## The JS array literal `const <name> = [ ... ];` as parsed rows.
func _table(html: String, name: String) -> Array:
	var start := html.find("const %s = [" % name)
	if start < 0:
		return []
	var open := html.find("[", start)
	var close := html.find("\n];", open)
	var body := html.substr(open, close - open + 2)
	var lines := PackedStringArray()
	for line in body.split("\n"):
		var cut := line.find("//")
		lines.append(line if cut < 0 else line.substr(0, cut))
	var text := "\n".join(lines)
	text = RegEx.create_from_string(",\\s*\\]").sub(text, "]", true)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []

func _piece(id: String) -> Array:
	for p in _pieces:
		if p[0] == id:
			return p
	return []

static func _h(p: Array) -> float:
	return float(p[9]) if p.size() > 9 else 0.0

static func _flag(p: Array) -> String:
	return str(p[10]) if p.size() > 10 else ""

static func _encloses(kind: String) -> bool:
	return kind in ["room", "corridor", "shaft", "tease"]

# --- materials -------------------------------------------------------------

func _make_materials() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var tones := {
		"shell": Color(0.30, 0.32, 0.36), "floor": Color(0.56, 0.54, 0.49),
		"solid": Color(0.42, 0.45, 0.48), "gate": Color(0.62, 0.30, 0.22),
		"chest": Color(0.85, 0.62, 0.22),
	}
	for key in tones:
		var path := "%s/%s.tres" % [MAT_DIR, key]
		var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("color", tones[key])
		m.resource_path = ""
		ResourceSaver.save(m, path)
		_mats[key] = load(path)
	for key in ["glow_rest", "glow_pickup"]:
		var path := "%s/%s.tres" % [MAT_DIR, key]
		var g := StandardMaterial3D.new()
		var c := Color(1.0, 0.85, 0.5) if key == "glow_rest" else Color(0.3, 0.95, 1.0)
		g.albedo_color = c
		g.emission_enabled = true
		g.emission = c
		g.emission_energy_multiplier = 3.0
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ResourceSaver.save(g, path)
		_mats[key] = load(path)

# --- building --------------------------------------------------------------

func _own(n: Node, parent: Node, name: String) -> Node:
	n.name = name
	parent.add_child(n)
	n.owner = _root
	return n

func _box(parent: Node, name: String, center: Vector3, size: Vector3, op := CSGShape3D.OPERATION_UNION,
		mat: Material = null, collide := false) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = center
	b.operation = op
	b.use_collision = collide
	if mat != null:
		b.material = mat
	return _own(b, parent, name) as CSGBox3D

func _combiner(parent: Node, name: String, op := CSGShape3D.OPERATION_UNION) -> CSGCombiner3D:
	var c := CSGCombiner3D.new()
	c.operation = op
	return _own(c, parent, name) as CSGCombiner3D

func _zone_node(parent: Node, zone: int) -> Node3D:
	var name := "Z%02d_%s" % [zone, str(_zones.get(zone, "Zone")).replace(" ", "")]
	var n := parent.get_node_or_null(name) as Node3D
	if n == null:
		n = _own(Node3D.new(), parent, name) as Node3D
	return n

func _build(doors: Array, marks: Array) -> void:
	_root = Node3D.new()
	_root.name = "Internals"
	_root.set_script(load("res://scripts/mission_map.gd"))
	_environment()
	var map := _own(Node3D.new(), _root, "Map") as Node3D

	# Walls: outers, then airs, then nested rooms, then doors.
	var shell := _combiner(map, "Shell")
	shell.use_collision = true
	var enclosures := _pieces.filter(func(p): return _encloses(p[2]))
	var normal := enclosures.filter(func(p): return not (p[0] in NESTED))
	var nested := enclosures.filter(func(p): return p[0] in NESTED)
	for zone in _zones:
		var outers := normal.filter(func(p): return int(p[1]) == zone)
		if outers.is_empty():
			continue
		var g := _combiner(shell, "Walls_Z%02d" % zone)
		for p in outers:
			_enclosure_box(g, p, true)
	for zone in _zones:
		var airs := normal.filter(func(p): return int(p[1]) == zone)
		if airs.is_empty():
			continue
		var g := _combiner(shell, "Air_Z%02d" % zone, CSGShape3D.OPERATION_SUBTRACTION)
		for p in airs:
			_enclosure_box(g, p, false)
	if not nested.is_empty():
		var nw := _combiner(shell, "Nested_Walls")
		var na := _combiner(shell, "Nested_Air", CSGShape3D.OPERATION_SUBTRACTION)
		for p in nested:
			_enclosure_box(nw, p, true)
			_enclosure_box(na, p, false)
	var dg := _combiner(shell, "Doors", CSGShape3D.OPERATION_SUBTRACTION)
	for d in doors:
		_door_box(dg, d)

	for p in _pieces:
		var zn := _zone_node(map, int(p[1]))
		match str(p[2]):
			"floor":
				_floor(zn, p)
			"solid":
				_solid(zn, p)
			"tease":
				_floor(zn, p)
			"kill":
				_kill(zn, p)
		if _encloses(p[2]) and p[2] != "tease":
			_lights(zn, p)
	for d in doors:
		if d.size() > 7 and str(d[7]) != "":
			_gate(map, d)
	_markers(map, marks)

	var pilot := (load("res://scenes/pilot9.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as CharacterBody3D
	_own(pilot, _root, "Pilot9")
	# Base kit only: mantle and vault stay, the double jump comes from the Capacitor Vault.
	pilot.set("air_jumps", 0)
	for flag in ["can_dash", "can_wall_run", "can_wall_climb", "can_rail_grind", "can_rail_switch"]:
		pilot.set(flag, false)
	_root.set("map", map)
	_root.set("pilot", pilot)

	var hud := CanvasLayer.new()
	hud.set_script(load("res://scripts/mission/mission_hud.gd"))
	_own(hud, _root, "MissionHud")
	_look_rigs(pilot)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.37, 0.42)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.05, 0.06)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_own(we, _root, "WorldEnvironment")

func _enclosure_box(parent: Node, p: Array, outer: bool) -> void:
	var x := float(p[4]); var z := float(p[5]); var w := float(p[6]); var d := float(p[7])
	var y := float(p[8]); var h := _h(p)
	var grow := WALL if outer else -INSET
	var y0 := y - (WALL if outer else 0.0)
	var y1 := y + h + (WALL if outer else 0.0)
	var size := Vector3(w + 2.0 * grow, y1 - y0, d + 2.0 * grow)
	var center := Vector3(x + w * 0.5, (y0 + y1) * 0.5, z + d * 0.5)
	_box(parent, "%s_%s" % [p[0], "outer" if outer else "air"], center, size, CSGShape3D.OPERATION_UNION, _mats["shell"])

func _door_box(parent: Node, d: Array) -> void:
	var x := float(d[1]); var z := float(d[2]); var y := float(d[3])
	var w := float(d[4]); var h := float(d[5])
	if str(d[6]) == "x":
		_box(parent, str(d[0]), Vector3(x, y + h * 0.5, z + w * 0.5), Vector3(DOOR_DEPTH, h, w), CSGShape3D.OPERATION_UNION, _mats["shell"])
	else:
		_box(parent, str(d[0]), Vector3(x + w * 0.5, y + h * 0.5, z), Vector3(w, h, DOOR_DEPTH), CSGShape3D.OPERATION_UNION, _mats["shell"])

## The enclosure whose footprint holds (x, z) and whose height range holds y, preferring rooms.
func _container(x: float, z: float, y: float) -> Array:
	var best: Array = []
	for p in _pieces:
		if not (p[2] in ["room", "shaft", "corridor"]):
			continue
		if x < float(p[4]) or x > float(p[4]) + float(p[6]) or z < float(p[5]) or z > float(p[5]) + float(p[7]):
			continue
		if y < float(p[8]) - 0.01 or y > float(p[8]) + _h(p) + 0.01:
			continue
		if best.is_empty() or best[2] == "shaft":
			best = p
	return best

func _floor(parent: Node, p: Array) -> void:
	var x := float(p[4]); var z := float(p[5]); var w := float(p[6]); var d := float(p[7]); var y := float(p[8])
	var c := _container(x + w * 0.5, z + d * 0.5, y)
	var bottom := y - SLAB
	if not c.is_empty() and c[2] == "room":
		bottom = float(c[8])
	_box(parent, str(p[0]), Vector3(x + w * 0.5, (y + bottom) * 0.5, z + d * 0.5), Vector3(w, y - bottom, d),
		CSGShape3D.OPERATION_UNION, _mats["floor"], true)
	var roof := _h(p)
	if p[2] == "floor" and roof > 0.0 and w > 8.0:
		_box(parent, "%s_roof" % p[0], Vector3(x + w * 0.5, y + roof + SLAB * 0.5, z + d * 0.5),
			Vector3(w - 8.0, SLAB, d), CSGShape3D.OPERATION_UNION, _mats["solid"], true)
	_id_label(parent, p, Vector3(x + w * 0.5, y + 0.05, z + d * 0.5))

func _solid(parent: Node, p: Array) -> void:
	var x := float(p[4]); var z := float(p[5]); var w := float(p[6]); var d := float(p[7]); var y := float(p[8])
	var c := _container(x + w * 0.5, z + d * 0.5, y)
	var bottom := y - 2.0
	if not c.is_empty() and not (c[0] in HANGING):
		bottom = float(c[8])
	_box(parent, str(p[0]), Vector3(x + w * 0.5, (y + bottom) * 0.5, z + d * 0.5), Vector3(w, y - bottom, d),
		CSGShape3D.OPERATION_UNION, _mats["solid"], true)
	_id_label(parent, p, Vector3(x + w * 0.5, y + 0.05, z + d * 0.5))

## The piece's id painted flat on its top, readable from above, so feedback can name it.
func _id_label(parent: Node, p: Array, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = str(p[0])
	l.font_size = 48
	l.pixel_size = 0.01
	l.modulate = Color(1, 1, 1, 0.35)
	l.outline_size = 0
	l.position = at
	l.rotation = Vector3(-PI * 0.5, 0, 0)
	l.visibility_range_end = 40.0
	_own(l, parent, "%s_label" % p[0])

func _kill(parent: Node, p: Array) -> void:
	var x := float(p[4]); var z := float(p[5]); var w := float(p[6]); var d := float(p[7]); var y := float(p[8])
	var a := Area3D.new()
	a.set_script(load("res://scripts/mission/kill_volume.gd"))
	a.position = Vector3(x + w * 0.5, y - 1.5, z + d * 0.5)
	_own(a, parent, str(p[0]))
	var s := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(w, 3.0, d)
	s.shape = b
	_own(s, a, "Shape")

func _lights(parent: Node, p: Array) -> void:
	var x := float(p[4]); var z := float(p[5]); var w := float(p[6]); var d := float(p[7])
	var y := float(p[8]); var h := _h(p)
	var col: Color = ZONE_LIGHT.get(int(p[1]), Color.WHITE)
	var step := 22.0 if p[2] == "shaft" else 12.0
	var nx := maxi(1, int(round(w / step)))
	var nz := maxi(1, int(round(d / step)))
	var shaft: bool = p[2] == "shaft"
	var ly := y + h * 0.7 if shaft else y + h - 1.0
	var rng := h * 1.1 + 10.0 if shaft else maxf(10.0, step * 1.4)
	var n := 0
	for i in nx:
		for k in nz:
			var o := OmniLight3D.new()
			o.light_color = col
			o.light_energy = 4.0 if shaft else 3.0
			o.omni_range = rng
			o.position = Vector3(x + w * (i + 0.5) / nx, ly, z + d * (k + 0.5) / nz)
			_own(o, parent, "%s_light%d" % [p[0], n])
			n += 1

func _gate(parent: Node, d: Array) -> void:
	var x := float(d[1]); var z := float(d[2]); var y := float(d[3]); var w := float(d[4]); var h := float(d[5])
	var along_x := str(d[6]) == "x"
	var side := 1.0 if str(d[7]) == "+" else -1.0
	var gate := StaticBody3D.new()
	gate.set_script(load("res://scripts/mission/one_way_gate.gd"))
	gate.position = Vector3(x, y + h * 0.5, z + w * 0.5) if along_x else Vector3(x + w * 0.5, y + h * 0.5, z)
	_own(gate, parent, "Gate_%s" % d[0])
	var size := Vector3(0.6, h, w) if along_x else Vector3(w, h, 0.6)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	_own(cs, gate, "Shape")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mats["gate"]
	_own(mi, gate, "Mesh")
	var opener := Area3D.new()
	opener.position = (Vector3(2.0, 0, 0) if along_x else Vector3(0, 0, 2.0)) * side
	_own(opener, gate, "Opener")
	var os := CollisionShape3D.new()
	var ob := BoxShape3D.new()
	ob.size = Vector3(3.0, h, w) if along_x else Vector3(w, h, 3.0)
	os.shape = ob
	_own(os, opener, "Shape")

## Height of the route node nearest (x, z): markers carry no height of their own.
func _route_y(x: float, z: float) -> float:
	var best := 1e9
	var y := 0.0
	for r in _route:
		var dd := Vector2(float(r[0]) - x, float(r[1]) - z).length()
		if dd < best:
			best = dd
			y = float(r[2])
	return y

## Yaw facing from the route node nearest (x, z) towards the next one.
func _route_facing(x: float, z: float) -> Basis:
	var best := 1e9
	var bi := 0
	for i in _route.size():
		var dd := Vector2(float(_route[i][0]) - x, float(_route[i][1]) - z).length()
		if dd < best:
			best = dd
			bi = i
	var nxt: Array = _route[mini(bi + 1, _route.size() - 1)]
	var dir := Vector3(float(nxt[0]) - x, 0, float(nxt[1]) - z)
	if dir.length() < 0.1:
		return Basis()
	# -Z is forward.
	return Basis(Vector3.UP, atan2(-dir.x, -dir.z))

func _markers(map: Node3D, marks: Array) -> void:
	var g := _own(Node3D.new(), map, "Markers") as Node3D
	var rest_i := 0
	var chest_i := 0
	for m in marks:
		var kind := str(m[0])
		var x := float(m[1]); var z := float(m[2])
		var at := Vector3(x, _route_y(x, z), z)
		match kind:
			"spawn":
				var sp := Marker3D.new()
				sp.transform = Transform3D(_route_facing(x, z), at)
				_own(sp, map, "spawn")
			"rest":
				rest_i += 1
				var pad := Area3D.new()
				pad.set_script(load("res://scripts/mission/rest_pad.gd"))
				pad.set("index", rest_i)
				pad.transform = Transform3D(_route_facing(x, z), at)
				_own(pad, g, "Rest%d" % rest_i)
				_area_shape(pad, Vector3(3, 2, 3), Vector3(0, 1, 0))
				_box(pad, "Plate", Vector3(0, 0.05, 0), Vector3(3, 0.1, 3), CSGShape3D.OPERATION_UNION, _mats["glow_rest"])
				_box(pad, "Pillar", Vector3(1.8, 1.25, 1.8), Vector3(0.3, 2.5, 0.3), CSGShape3D.OPERATION_UNION, _mats["glow_rest"])
				var o := OmniLight3D.new()
				o.light_color = Color(1, 0.9, 0.7)
				o.light_energy = 2.0
				o.omni_range = 7.0
				o.position = Vector3(0, 2.5, 0)
				_own(o, pad, "Light")
			"dj":
				var pk := Area3D.new()
				pk.set_script(load("res://scripts/mission/ability_pickup.gd"))
				pk.position = at + Vector3(0, 1.2, 0)
				_own(pk, g, "DoubleJump")
				_area_shape(pk, Vector3(2, 2.4, 2), Vector3.ZERO)
				_box(pk, "Core", Vector3.ZERO, Vector3(0.8, 0.8, 0.8), CSGShape3D.OPERATION_UNION, _mats["glow_pickup"])
				var o := OmniLight3D.new()
				o.light_color = Color(0.3, 0.95, 1.0)
				o.light_energy = 3.0
				o.omni_range = 10.0
				_own(o, pk, "Light")
			"chest":
				chest_i += 1
				_box(g, "Chest%d" % chest_i, at + Vector3(0, 0.4, 0), Vector3(1.2, 0.8, 0.8), CSGShape3D.OPERATION_UNION, _mats["chest"], true)
			"end":
				var ex := Area3D.new()
				ex.set_script(load("res://scripts/mission/exit_volume.gd"))
				ex.position = at
				_own(ex, g, "Exit")
				_area_shape(ex, Vector3(8, 4, 8), Vector3(0, 2, 0))
				var l := Label3D.new()
				l.text = "EXIT"
				l.font_size = 160
				l.pixel_size = 0.01
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				l.position = Vector3(0, 3, 0)
				_own(l, ex, "Label")

func _area_shape(a: Area3D, size: Vector3, offset: Vector3) -> void:
	var s := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	s.shape = b
	s.position = offset
	_own(s, a, "Shape")

func _look_rigs(pilot: Node) -> void:
	var cel := Node.new()
	cel.set_script(load("res://scripts/rendering/apply_stylized.gd"))
	_own(cel, _root, "ApplyCelPilot9")
	cel.set("material", load("res://resources/pilot_cel_character.tres"))
	var targets: Array[NodePath] = [NodePath("../Pilot9")]
	cel.set("targets", targets)
	cel.set("derive_from_surfaces", true)
	var pw := CanvasLayer.new()
	pw.set_script(load("res://scripts/rendering/pixel_world.gd"))
	_own(pw, _root, "PixelWorld")
	var pl := Node.new()
	pl.set_script(load("res://scripts/rendering/pixel_look.gd"))
	_own(pl, _root, "PixelLook")
	var rl := Node.new()
	rl.set_script(load("res://scripts/rendering/retro_look.gd"))
	_own(rl, _root, "RetroLook")

func _save_wrapper() -> void:
	var w := Node3D.new()
	w.name = "Node3D"
	var inst := (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	w.add_child(inst)
	inst.owner = w
	var packed := PackedScene.new()
	packed.pack(w)
	ResourceSaver.save(packed, WRAPPER)
	w.free()
