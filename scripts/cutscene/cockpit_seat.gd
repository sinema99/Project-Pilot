@tool
class_name CockpitSeat
extends Node3D

# The floating cockpit seat for cutscene shot 2, modelled part by part from the user's line sketch.
# See docs/specs/cutscene-cockpit.md.
#
# Seat space: origin on the floor of the seat unit under the seat pan, +Z is the way the pilot
# faces, +X is his left (pilot9.glb faces +Z). Parts come from the table in _build() as
# rounded-edge meshes (scripts/cutscene/seat_mesh.gd), added without an owner so the .tscn stores
# none of them; edit the table, not the nodes.
#
# Structural parts get the cel ink. Hardware (screws, slots, seams, buttons) does not: the outline
# is a fixed pixel width, and on a 1 cm screw it would swallow the part.
#
# The pose targets live here so the pilot follows the seat: scripts/cutscene/seated_pose.gd reads
# them every skeleton update.

const SHELL := Color(0.28, 0.33, 0.41)
const SHELL_DARK := Color(0.18, 0.22, 0.28)
const CUSHION := Color(0.6, 0.45, 0.3)
const CUSHION_DARK := Color(0.4, 0.28, 0.18)
const TRIM := Color(0.86, 0.33, 0.22)
const GRIP := Color(0.08, 0.08, 0.09)
const PANEL := Color(0.2, 0.22, 0.25)
const GLOW := Color(0.4, 0.95, 1.0)

const CEL := preload("res://resources/cel_character.tres")
const OUTLINE := preload("res://resources/cel_outline_material.tres")

## Backrest recline, degrees back from upright. The pilot's torso leans with it.
@export_range(0.0, 30.0, 0.5) var recline_degrees := 12.0:
	set(value):
		recline_degrees = value
		_rebuild()

@export_group("Pose targets")
## Where his Hips bone sits, seat space.
@export var hip_target := Vector3(0.0, 0.56, -0.12)
## Wrists, seat space. Just behind each grip stick, so the fist closes over it.
@export var left_wrist_target := Vector3(0.4, 0.78, 0.33)
@export var right_wrist_target := Vector3(-0.4, 0.78, 0.33)
## Ankles, seat space, on the footrest.
@export var left_foot_target := Vector3(0.15, 0.17, 0.6)
@export var right_foot_target := Vector3(-0.15, 0.17, 0.6)
## Grip centres, seat space, centred on each control box. The sticks are built here.
@export var left_grip := Vector3(0.4, 0.75, 0.4)
@export var right_grip := Vector3(-0.4, 0.75, 0.4)

var _materials: Dictionary[Color, Material] = {}


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.owner == null and c.has_meta(&"generated"):
			remove_child(c)
			c.queue_free()
	_build()


# ---------------------------------------------------------------- the seat, part by part

func _build() -> void:
	_build_base()
	_build_pan()
	_build_back()
	_build_pods()
	for side: float in [1.0, -1.0]:
		_build_console(side)
	_build_instruments()


# Stepped plinth under the pan, a leg step forward of it and the slanted footrest.
func _build_base() -> void:
	_box("Plinth", SHELL, Vector3(0.62, 0.3, 0.78), 0.045, _at(Vector3(0.0, 0.15, -0.06)))
	_box("PlinthSkirt", SHELL_DARK, Vector3(0.54, 0.08, 0.7), 0.025, _at(Vector3(0.0, -0.03, -0.06)))
	# An access hatch and a vent on his-left side of the plinth, the side the camera sees.
	var side := Transform3D(Basis(), Vector3(0.31, 0.0, 0.0))
	_plate("PlinthHatch", SHELL_DARK, side, Vector3(0.0, 0.16, -0.18), Vector3.RIGHT, Vector3.BACK, Vector2(0.16, 0.34))
	for i in 4:
		@warning_ignore("integer_division")
		_screw("PlinthHatchScrew%d" % i, side * Vector3(0.0, 0.16 + 0.065 * (1 - 2 * (i / 2)), -0.18 + 0.15 * (1 - 2 * (i % 2))), Vector3.RIGHT)
	_slots("PlinthVent", side, Vector3(0.0, 0.16, 0.18), Vector3.RIGHT, Vector3.BACK, 5, Vector2(0.012, 0.11), 0.024)

	_box("LegStep", SHELL, Vector3(0.44, 0.2, 0.32), 0.04,
			_at(Vector3(0.0, 0.1, 0.42)), {"taper": Vector2(0.92, 0.85), "shear": Vector2(0.0, -0.02)})
	# A row of round buttons down each side of the leg step, more on the camera side.
	for i in 3:
		_button("LegButtonL%d" % i, Vector3(0.22, 0.11, 0.33 + 0.07 * i), Vector3.RIGHT, 0.018, GRIP if i < 2 else TRIM)
	for i in 2:
		_button("LegButtonR%d" % i, Vector3(-0.22, 0.11, 0.36 + 0.07 * i), Vector3.LEFT, 0.018, GRIP)
	var foot := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, 0.1, 0.64))
	_box("Footrest", SHELL, Vector3(0.56, 0.06, 0.36), 0.025, foot)
	# Two dark tread pads, one per sole.
	for x: float in [0.15, -0.15]:
		_box("Tread" + ("L" if x > 0.0 else "R"), PANEL, Vector3(0.16, 0.012, 0.26), 0.005,
				foot * _at(Vector3(x, 0.033, -0.01)), {}, false)


# Seat pan: a shell, the dark piping and a domed cushion with a rolled front edge.
func _build_pan() -> void:
	_box("PanShell", SHELL, Vector3(0.66, 0.1, 0.74), 0.035, _at(Vector3(0.0, 0.36, -0.03)))
	_box("PanPiping", CUSHION_DARK, Vector3(0.52, 0.05, 0.62), 0.022, _at(Vector3(0.0, 0.425, 0.0)), {}, false)
	_box("PanCushion", CUSHION, Vector3(0.49, 0.06, 0.52), 0.028, _at(Vector3(0.0, 0.45, -0.04)),
			{"puff": 0.025, "subdiv": 6})
	_box("PanRoll", CUSHION, Vector3(0.49, 0.085, 0.1), 0.042, _at(Vector3(0.0, 0.445, 0.255)))


# Backrest tub (shell + wings), two stacked cushions, and the headrest on its own neck.
func _build_back() -> void:
	var back := Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(recline_degrees)), Vector3(0.0, 0.41, -0.38))
	_box("BackShell", SHELL, Vector3(0.62, 0.82, 0.12), 0.045, back * _at(Vector3(0.0, 0.4, -0.03)),
			{"taper": Vector2(0.9, 1.0)})
	_box("SpineBlock", SHELL, Vector3(0.38, 0.86, 0.24), 0.05, back * _at(Vector3(0.0, 0.4, -0.2)))
	for side: float in [1.0, -1.0]:
		var s := "L" if side > 0.0 else "R"
		_box("BackWing" + s, SHELL, Vector3(0.08, 0.66, 0.17), 0.035,
				back * Transform3D(Basis(Vector3.UP, deg_to_rad(-10.0) * side), Vector3(0.28 * side, 0.38, 0.06)),
				{"taper": Vector2(0.8, 0.75)})
	_box("BackPiping", CUSHION_DARK, Vector3(0.47, 0.71, 0.03), 0.015, back * _at(Vector3(0.0, 0.405, 0.035)), {}, false)
	_cushion("BackLumbar", Vector3(0.44, 0.29, 0.06), back * _at(Vector3(0.0, 0.22, 0.06)), 0.022)
	_cushion("BackUpper", Vector3(0.44, 0.37, 0.06), back * _at(Vector3(0.0, 0.565, 0.06)), 0.026)

	# Headrest: two neck posts out of the shell top, a rounded block leaning a little forward, a
	# pad, thin red strips down its front edges, and the two screws the sketch draws on its face.
	for x: float in [0.1, -0.1]:
		_cylinder("HeadPost" + ("L" if x > 0.0 else "R"), PANEL, 0.018, 0.08, 0.004,
				back * _at(Vector3(x, 0.81, -0.02)), false)
	var head := back * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3(0.0, 0.94, 0.01))
	_box("Headrest", SHELL, Vector3(0.4, 0.26, 0.14), 0.05, head, {"taper": Vector2(0.92, 0.9)})
	_cushion("HeadPad", Vector3(0.27, 0.15, 0.04), head * _at(Vector3(0.0, -0.01, 0.07)), 0.014)
	for side: float in [1.0, -1.0]:
		_box("HeadCheek" + ("L" if side > 0.0 else "R"), TRIM, Vector3(0.022, 0.19, 0.035), 0.009,
				head * _at(Vector3(0.188 * side, -0.005, 0.058)), {}, false)
		_screw("HeadScrew" + ("L" if side > 0.0 else "R"), head * Vector3(0.165 * side, 0.095, 0.07), head.basis * Vector3.BACK)
	# The round fitting the sketch has on the headrest's right flank.
	_button("HeadPort", head * Vector3(-0.21, -0.04, -0.02), head.basis * Vector3.LEFT, 0.03, PANEL)


# Three pods behind the backrest, on a mount: a tall one on his left with a round port, a grille
# on top and the seat's one red band, a big one behind the headrest, a narrower one on his right
# with a slatted face.
func _build_pods() -> void:
	_box("PodMount", SHELL_DARK, Vector3(1.14, 0.14, 0.32), 0.04, _at(Vector3(0.0, 0.3, -0.7)))

	var l := Vector3(0.47, 0.67, -0.68)
	var ls := Vector3(0.3, 0.86, 0.46)
	_box("PodL", SHELL, ls, 0.06, _at(l), {"taper": Vector2(1.0, 0.9)})
	_box("PodLBand", TRIM, Vector3(ls.x + 0.012, 0.05, ls.z * 0.985 + 0.012), 0.05, _at(l + Vector3(0.0, -0.32, 0.0)), {}, false)
	var lx := Transform3D(Basis(), l + Vector3(ls.x * 0.5, 0.0, 0.0))
	_plate("PodLPlate", SHELL_DARK, lx, Vector3(0.0, 0.14, 0.03), Vector3.RIGHT, Vector3.BACK, Vector2(0.24, 0.26))
	_port("PodLPort", lx * Vector3(0.0, 0.14, 0.03), Vector3.RIGHT, 0.075)
	for i in 4:
		@warning_ignore("integer_division")
		_screw("PodLScrew%d" % i, lx * Vector3(0.0, 0.14 + 0.1 * (1 - 2 * (i / 2)), 0.03 + 0.11 * (1 - 2 * (i % 2))), Vector3.RIGHT)
	_seam("PodLSeam", lx, Vector3(0.0, -0.12, 0.0), Vector3.RIGHT, Vector3.BACK, ls.z - 0.08)
	var lt := Transform3D(Basis(), l + Vector3(0.0, ls.y * 0.5, -0.01))
	_slots("PodLGrille", lt, Vector3.ZERO, Vector3.UP, Vector3.RIGHT, 6, Vector2(0.014, 0.2), 0.04)

	var c := Vector3(0.0, 1.06, -0.92)
	var cs := Vector3(0.62, 0.44, 0.44)
	_box("PodC", SHELL, cs, 0.07, _at(c), {"taper": Vector2(0.94, 0.86), "shear": Vector2(0.0, -0.03)})
	_box("PodCBase", SHELL, Vector3(0.4, 0.4, 0.34), 0.05, _at(c + Vector3(0.0, -0.4, 0.04)))
	var ct := Transform3D(Basis(), c + Vector3(0.0, cs.y * 0.5, 0.0))
	_plate("PodCHatch", SHELL_DARK, ct, Vector3(0.04, 0.0, 0.0), Vector3.UP, Vector3.RIGHT, Vector2(0.22, 0.36))
	for i in 2:
		_screw("PodCScrew%d" % i, ct * Vector3(-0.2, 0.0, 0.08 * (1 - 2 * i)), Vector3.UP)

	var r := Vector3(-0.46, 0.7, -0.64)
	var rs := Vector3(0.27, 0.8, 0.4)
	_box("PodR", SHELL, rs, 0.055, _at(r), {"taper": Vector2(0.94, 0.92)})
	var rf := Transform3D(Basis(), r + Vector3(0.0, 0.0, rs.z * 0.5))
	_slots("PodRSlats", rf, Vector3(0.0, 0.24, 0.0), Vector3.BACK, Vector3.UP, 5, Vector2(0.012, 0.17), 0.03)
	_seam("PodRSeam", rf, Vector3(0.0, 0.08, 0.0), Vector3.BACK, Vector3.RIGHT, rs.x - 0.07)
	_button("PodRPort", r + Vector3(-rs.x * 0.5, -0.05, 0.02), Vector3.LEFT, 0.05, PANEL)


# An arm console on one side: the long body the forearm lies on, a strut down to the pan, the
# control box the stick stands on, and the rounded handset-shaped cap hanging off the front. The
# left console (camera side) carries the slotted button strip; the right one a screwed plate.
func _build_console(side: float) -> void:
	var s := "L" if side > 0.0 else "R"
	var x := 0.37 * side
	_box("Console" + s, SHELL, Vector3(0.15, 0.15, 0.54), 0.035, _at(Vector3(x, 0.595, 0.0)),
			{"taper": Vector2(0.9, 1.0)})
	_box("ConsoleStrut" + s, SHELL, Vector3(0.1, 0.2, 0.26), 0.03, _at(Vector3(x, 0.42, -0.1)))
	var outer := Transform3D(Basis(), Vector3(x + 0.075 * side, 0.0, 0.0))
	_seam("ConsoleSeam" + s, outer, Vector3(0.0, 0.6, 0.04), Vector3.RIGHT * side, Vector3.BACK, 0.36)
	_plate("ConsolePlate" + s, SHELL_DARK, outer, Vector3(0.0, 0.59, -0.16), Vector3.RIGHT * side, Vector3.BACK, Vector2(0.08, 0.1))
	for i in 2:
		_screw("ConsolePlateScrew%s%d" % [s, i], outer * Vector3(0.0, 0.59, -0.16 + 0.035 * (1 - 2 * i)), Vector3.RIGHT * side)

	var box := Vector3(x + 0.03 * side, 0.6, 0.4)
	_box("ControlBox" + s, SHELL, Vector3(0.21, 0.14, 0.24), 0.035, _at(box), {"taper": Vector2(0.94, 0.9)})
	var top := Transform3D(Basis(), box + Vector3(0.0, 0.07, 0.0))
	if side > 0.0:
		_plate("ButtonStrip", SHELL_DARK, top, Vector3(0.072, 0.0, 0.0), Vector3.UP, Vector3.BACK, Vector2(0.045, 0.17))
		_slots("ButtonSlots", top, Vector3(0.072, 0.002, 0.0), Vector3.UP, Vector3.BACK, 7, Vector2(0.008, 0.03), 0.021)
	else:
		_plate("SquarePlate", PANEL, top, Vector3(0.0, 0.0, 0.065), Vector3.UP, Vector3.BACK, Vector2(0.08, 0.07))
		for i in 4:
			@warning_ignore("integer_division")
			_screw("SquarePlateScrew%d" % i, top * Vector3(0.03 * (1 - 2 * (i / 2)), 0.0, 0.065 + 0.025 * (1 - 2 * (i % 2))), Vector3.UP)
		_button("SquarePlateKnob", top * Vector3(0.0, 0.0, 0.065), Vector3.UP, 0.016, GRIP)

	# Handset cap: a fat bar with round ends across the front, sitting low, with a dark window.
	var cap := Vector3(x + 0.035 * side, 0.565, 0.565)
	_box("HandsetCap" + s, SHELL, Vector3(0.25, 0.12, 0.13), 0.055, _at(cap))
	_box("HandsetWindow" + s, PANEL, Vector3(0.11, 0.045, 0.01), 0.008, _at(cap + Vector3(0.0, 0.005, 0.066)), {}, false)

	# The stick: rubber boot, shaft, head, red thumb button and a trigger.
	var grip := left_grip if side > 0.0 else right_grip
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(12.0))
	_cylinder("GripBoot" + s, GRIP, 0.04, 0.03, 0.012, Transform3D(tilt, grip + Vector3(0.0, -0.075, -0.015)), true, 0.026)
	_cylinder("Grip" + s, GRIP, 0.022, 0.17, 0.008, Transform3D(tilt, grip))
	var head := Transform3D(tilt, grip + Vector3(0.0, 0.1, 0.022))
	_box("GripHead" + s, GRIP, Vector3(0.055, 0.045, 0.075), 0.016, head)
	_button("GripButton" + s, head * Vector3(0.0, 0.023, 0.012), tilt * Vector3.UP, 0.011, TRIM)
	_box("GripTrigger" + s, PANEL, Vector3(0.02, 0.03, 0.012), 0.004, head * _at(Vector3(0.0, -0.02, 0.04)), {}, false)


# Instrument block in front of the knees on a pedestal out of the footrest, its face tilted up at
# the pilot: a big hooded gauge with a grid on its glass, two small dials and a row of keys.
func _build_instruments() -> void:
	_box("PedestalFoot", SHELL, Vector3(0.24, 0.1, 0.16), 0.03, _at(Vector3(0.0, 0.08, 0.9)))
	_box("Pedestal", SHELL, Vector3(0.11, 0.46, 0.09), 0.03,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0.0, 0.34, 0.9)), {"taper": Vector2(1.3, 1.0)})
	var block := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-40.0)), Vector3(0.0, 0.66, 0.86))
	_box("Instruments", SHELL, Vector3(0.62, 0.15, 0.25), 0.04, block, {"taper": Vector2(0.95, 0.92)})
	_box("InstrumentFace", PANEL, Vector3(0.54, 0.02, 0.18), 0.012, block * _at(Vector3(0.0, 0.07, 0.01)), {}, false)
	for side: float in [1.0, -1.0]:
		_screw("InstrumentScrew" + ("L" if side > 0.0 else "R"), block * Vector3(0.29 * side, 0.068, -0.09), block.basis * Vector3.UP)

	var gauge := block * _at(Vector3(-0.14, 0.08, 0.0))
	_cylinder("GaugeHood", SHELL_DARK, 0.1, 0.05, 0.012, gauge * _at(Vector3(0.0, 0.02, 0.0)))
	_disc("Gauge", 0.08, gauge * _at(Vector3(0.0, 0.046, 0.0)))
	# The sketch's gauge glass is cross-hatched.
	for i in 5:
		var o := (i - 2) * 0.03
		var chord := 2.0 * sqrt(maxf(0.08 * 0.08 - o * o, 0.0))
		_box("GaugeGridX%d" % i, PANEL, Vector3(chord, 0.003, 0.004), 0.001, gauge * _at(Vector3(0.0, 0.05, o)), {}, false)
		_box("GaugeGridZ%d" % i, PANEL, Vector3(0.004, 0.003, chord), 0.001, gauge * _at(Vector3(o, 0.05, 0.0)), {}, false)
	for i in 2:
		var dial := block * _at(Vector3(0.07 + 0.13 * i, 0.08, 0.02))
		_cylinder("DialBezel%d" % i, SHELL_DARK, 0.05, 0.03, 0.008, dial * _at(Vector3(0.0, 0.01, 0.0)))
		_disc("Dial%d" % i, 0.038, dial * _at(Vector3(0.0, 0.026, 0.0)))
		_box("DialNeedle%d" % i, PANEL, Vector3(0.004, 0.003, 0.03), 0.001,
				dial * Transform3D(Basis(Vector3.UP, deg_to_rad(35.0 - 80.0 * i)), Vector3(0.0, 0.029, 0.012)), {}, false)
	# Keys along the near lip, toward the pilot.
	for i in 6:
		_box("Key%d" % i, GRIP, Vector3(0.03, 0.012, 0.022), 0.004,
				block * _at(Vector3(-0.2 + 0.05 * i, 0.078, -0.1)), {}, false)


# ---------------------------------------------------------------- builders

func _at(p: Vector3) -> Transform3D:
	return Transform3D(Basis(), p)


func _box(part: String, color: Color, size: Vector3, radius: float, xform: Transform3D, opts := {},
		outline := true) -> MeshInstance3D:
	var bevel := 2 if radius > 0.015 else 1
	return _add(part, _mesh(SeatMesh.rounded_box(size, radius, bevel, opts), color, outline), xform)


# A padded cushion facing local +Z of xform: `size` is width, height, thickness; it domes out
# toward +Z by `puff`.
func _cushion(part: String, size: Vector3, xform: Transform3D, puff: float) -> MeshInstance3D:
	var arrays := SeatMesh.rounded_box(Vector3(size.x, size.z, size.y), minf(size.z * 0.5, 0.03), 2,
			{"puff": puff, "subdiv": 6})
	return _add(part, _mesh(arrays, CUSHION, true), xform * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))


# A cylinder standing on its own local Y, rims rounded to `edge`.
func _cylinder(part: String, color: Color, radius: float, height: float, edge: float, xform: Transform3D,
		outline := true, top_radius := -1.0) -> MeshInstance3D:
	var segs := 24 if radius > 0.04 else 14
	return _add(part, _mesh(SeatMesh.rounded_cylinder(radius, height, edge, segs, top_radius), color, outline), xform)


# A glowing gauge face, lying in its local XZ plane. Unlit, no ink.
func _disc(part: String, radius: float, xform: Transform3D) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.006
	m.radial_segments = 24
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = GLOW
	m.material = mat
	return _add(part, m, xform)


# A screw head on a face: a small dark dome.
func _screw(part: String, pos: Vector3, normal: Vector3) -> void:
	_cylinder(part, GRIP, 0.011, 0.008, 0.003, Transform3D(SeatMesh.facing(normal), pos), false)


# A round button (or fitting) standing proud of a face.
func _button(part: String, pos: Vector3, normal: Vector3, radius: float, color: Color) -> void:
	_cylinder(part, color, radius, 0.016, radius * 0.35, Transform3D(SeatMesh.facing(normal), pos), false)


# A round recessed port: a dark-mint collar with a black hole in it.
func _port(part: String, pos: Vector3, normal: Vector3, radius: float) -> void:
	var b := SeatMesh.facing(normal)
	_cylinder(part, SHELL_DARK, radius, 0.02, 0.008, Transform3D(b, pos), false)
	_cylinder(part + "Hole", GRIP, radius * 0.72, 0.006, 0.002, Transform3D(b, pos + normal.normalized() * 0.009), false)


# A thin plate lying flat on a face: hatches, seam lines, panels. `frame` is the face's frame,
# `local` the plate centre in it, `normal` the face direction and `along` the plate's long way,
# both in frame space. `size` is (across, along). It stands `thick` / 2 proud of the face.
func _plate(part: String, color: Color, frame: Transform3D, local: Vector3, normal: Vector3, along: Vector3,
		size: Vector2, thick := 0.006) -> void:
	var n := (frame.basis * normal).normalized()
	var z := (frame.basis * along).normalized()
	var x := n.cross(z).normalized()
	_add(part, _mesh(SeatMesh.rounded_box(Vector3(size.x, thick, size.y), minf(thick, 0.006), 1), color, false),
			Transform3D(Basis(x, n, x.cross(n)), frame * local))


# A recessed-looking seam line: a narrow dark strip barely proud of the face.
func _seam(part: String, frame: Transform3D, local: Vector3, normal: Vector3, along: Vector3, length: float) -> void:
	_plate(part, SHELL_DARK, frame, local, normal, along, Vector2(0.008, length), 0.004)


# A row of `count` dark slots on a face, stepping along `step_dir`: grilles and button strips.
# `size` is each slot's footprint: x along step_dir, y across it.
func _slots(part: String, frame: Transform3D, local: Vector3, normal: Vector3, step_dir: Vector3, count: int,
		size: Vector2, pitch: float) -> void:
	var n := (frame.basis * normal).normalized()
	var x := (frame.basis * step_dir).normalized()
	var z := x.cross(n).normalized()
	var b := Basis(x, n, z)
	for i in count:
		var off := (i - (count - 1) * 0.5) * pitch
		_add("%s%d" % [part, i], _mesh(SeatMesh.rounded_box(Vector3(size.x, 0.006, size.y), 0.003, 1), GRIP, false),
				Transform3D(b, frame * local + x * off))


func _add(part: String, mesh: Mesh, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part
	mi.mesh = mesh
	mi.transform = xform
	mi.set_meta(&"generated", true)
	add_child(mi)
	return mi


# The arrays as a mesh: one cel surface, plus (when inked) the outline hull with normals averaged
# across every vertex sharing a position.
func _mesh(arrays: Array, color: Color, outline: bool) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, _cel(color))
	if outline:
		var hull := arrays.duplicate()
		hull[Mesh.ARRAY_NORMAL] = welded_normals(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL])
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hull)
		out.surface_set_material(1, OUTLINE)
	return out


## Each vertex's normal replaced by the normalised sum of the normals of every vertex at the same
## position: a corner points out along its diagonal, so the outline hull stays closed.
static func welded_normals(verts: PackedVector3Array, normals: PackedVector3Array) -> PackedVector3Array:
	var sums: Dictionary[Vector3, Vector3] = {}
	for i in verts.size():
		var key := verts[i].snapped(Vector3.ONE * 1e-4)
		sums[key] = sums.get(key, Vector3.ZERO) + normals[i]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		out[i] = sums[verts[i].snapped(Vector3.ONE * 1e-4)].normalized()
	return out


func _cel(color: Color) -> Material:
	if not _materials.has(color):
		var m: ShaderMaterial = CEL.duplicate()
		m.next_pass = null
		m.set_shader_parameter(&"color", color)
		_materials[color] = m
	return _materials[color]
