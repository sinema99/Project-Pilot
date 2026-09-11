@tool
extends Node3D

# The jump grid as geometry you can stand next to: a dev ruler whose every box, gap, pillar,
# label and tint is generated from pilot9's own exports at load.
# See docs/specs/pilot9-jump-grid-platform.md.
#
# NOTHING HERE IS A LITERAL METRE. The build instantiates scenes/pilot9.tscn, reads the
# exports off it, generates against them and frees it again - the same trick
# tests/test_pilot9_jump_grid.gd uses to read the grid without standing a pilot up. Retune
# `sprint_speed` and the lane labelled SPRINT physically moves. A hand-modelled ruler would
# have been faster to build and would have started lying the first time a dial moved,
# silently, which is the exact failure the jump grid spec exists to prevent.
#
# @tool for the reason scripts/rendering/apply_stylized.gd is: map layout happens in the
# editor viewport, and a ruler you have to launch the game to see is a ruler you will not
# use. Every generated child is added WITHOUT an `owner`, so none of it is serialised into
# the .tscn - a rebuild cannot leave stale boxes behind in a scene file, and the platform is
# always whatever pilot9.tscn currently says it is.
#
# The platform's local origin is the START STRIP'S WALKING SURFACE, not the centre of the
# slab. That is what lets scenes/trial.tscn spawn Pilot9 at the platform's own transform
# plus a few centimetres of y: the spawn point survives a regeneration that moves every lane,
# because the one place the layout is anchored is the one place the player is put.
#
# Footprint: the spec sketches "roughly 52 x 52 m". Built to the numbers it actually
# specifies - an 18 m lane needs 6 m of runway and a 5 m landing pad off the spine, and the
# pillar field has to sit a clear sprint jump beyond that - the slab comes out around
# 56 x 84 m. The layout is the spec's; only its sketch of the size was rounded.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
## The same script pilot9.tscn carries, held separately because the gaps are derived through
## its STATICS rather than through the instance - see _read_dials().
const PILOT_SCRIPT := preload("res://scripts/pilot9.gd")
const GRID_SHADER := "res://shaders/metre_grid.gdshader"

# --- layout ---------------------------------------------------------------
# These are the only numbers on the platform that are not read off pilot9, because they
# describe how the ruler is ARRANGED rather than what it measures. Every one of them is a
# number a wrong value would make ugly, not wrong.

## 3.0 m of lane with 1.0 m of void between, so two neighbouring gaps cannot be taken as one
## diagonal and a miss falls into a trench rather than onto the next lane.
const LANE_WIDTH := 3.0
const LANE_PITCH := 4.0
## Off the spine before the gap. The runway is for AIMING, not for accelerating -
## scripts/pilot9.gd assigns `velocity.x = direction.x * current_speed` outright, so sprint
## speed arrives on the frame the key goes down and no runway length changes it.
const TAKEOFF_LENGTH := 6.0
const LANDING_LENGTH := 5.0
## Half-depth of the central spine the lanes hang off.
const SPINE_HALF_DEPTH := 2.0
## Spine past the last lane: a long strip at one end to spawn on, a short one at the other.
const START_STRIP := 8.0
const END_STRIP := 2.0
## Pillar tops. Square, and small enough that a landing is a landing rather than a stroll.
const PILLAR_TOP := 1.5
## Bare slab left around everything, and how thick it is. The slab exists because trial.tscn
## has no ground plane at all - a fall off TrainingV falls forever, and the ruler is not
## inheriting that.
const SLAB_MARGIN := 3.0
const SLAB_THICKNESS := 1.0
## Grab strips and pillar caps float this far proud of the surface they mark, purely to keep
## two coplanar faces out of a z-fight.
const DECAL_LIFT := 0.01

# --- colour ---------------------------------------------------------------
# One distinction and only one: warm is what you CLEAR, cyan is what you GRAB.

const COLOUR_SLAB := Color(0.24, 0.25, 0.28)
const COLOUR_SPINE := Color(0.34, 0.36, 0.40)
const COLOUR_PAD := Color(0.46, 0.48, 0.52)
const COLOUR_PILLAR := Color(0.42, 0.44, 0.48)
const COLOUR_GRAB := Color(0.20, 0.78, 0.92)
## Ends of the warm ramp. Which METRE gets which colour is derived (see _warm): the ramp is
## pinned to the smallest and largest named limit, so the 3 m gap and the 3 m apex pillar
## come out the same colour without either of them being told what colour it is.
const WARM_LOW := Color(1.00, 0.84, 0.26)
const WARM_HIGH := Color(0.86, 0.20, 0.14)

const LABEL_FONT_SIZE := 64
const LABEL_PIXEL_SIZE := 0.015


## Every number the platform is built from, read once off a throwaway pilot9 and then never
## consulted again. Held together in one object so a build cannot half-read a pilot that was
## retuned between two calls.
class Dials extends RefCounted:
	var walk_gap := 0.0          ## jump_distance(walk_speed)
	var run_gap := 0.0           ## jump_distance(speed)
	var sprint_gap := 0.0        ## jump_distance(sprint_speed)
	var double_gap := 0.0        ## the sprint gap once per jump he has
	var single_apex := 0.0       ## jump_height
	var double_apex := 0.0       ## jump_height once per jump he has
	var single_mantle := 0.0     ## the highest lip a single jump reaches
	var double_mantle := 0.0     ## the highest lip a double jump reaches
	var grab_depth := 0.0        ## climb_probe_reach
	var pad_height := 0.0        ## how far the pads stand over the slab
	var headroom := 0.0          ## climb_headroom


@export_tool_button("Rebuild now") var rebuild_action: Callable = rebuild

## Applied to every generated node, so the layout below can be written with the slab top at
## y = 0 and the lane block centred on x = 0 while the node's own origin still lands on the
## start strip. Set once per build, before anything is placed.
var _shift := Vector3.ZERO
var _materials: Dictionary[Color, Material] = {}


func _ready() -> void:
	rebuild()


## Throws the whole platform away and generates it again from pilot9.tscn. Safe to call at
## any time; the editor button and _ready() both come through here.
func rebuild() -> void:
	_clear()
	var d := _read_dials()
	if d == null:
		push_warning("jump_grid: could not read %s; nothing generated." % PILOT_TSCN)
		return
	_build(d)


func _clear() -> void:
	_materials.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()


# --- reading pilot9 -------------------------------------------------------

# Instantiated and freed without ever entering the tree. pilot9.gd resolves its node
# references through @onready, which never runs for a node with no tree above it, so none of
# them are touched here - only the exports, which are set the moment the scene is built.
#
# EXPORTS AND NOTHING ELSE, and that is a hard constraint rather than a preference. In the
# editor the instance below is a PLACEHOLDER: the editor refuses to instantiate a non-@tool
# script, so `p` carries the exported properties and no methods and no computed properties
# at all. Calling `p.jump_distance(...)` here is what left the platform generating nothing in
# the editor while it built correctly in game. The gaps come through PILOT_SCRIPT's statics
# instead (see jump_distance_for in scripts/pilot9.gd), which run in both contexts and are
# still the one copy of the formula.
func _read_dials() -> Dials:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var p := ps.instantiate()
	if p == null:
		return null

	var d := Dials.new()
	# `1 + air_jumps` and not a literal 2, for both the horizontal and the vertical ceiling.
	# The spec writes the double mantle as `jump_height * 2 + climb_band_max`; at the
	# shipping `air_jumps: 1` the two are the same number, and this one tracks the export.
	var jumps := 1.0 + float(p.air_jumps)
	d.walk_gap = PILOT_SCRIPT.jump_distance_for(
		p.walk_speed, p.jump_time_to_apex, p.jump_fall_multiplier)
	d.run_gap = PILOT_SCRIPT.jump_distance_for(
		p.speed, p.jump_time_to_apex, p.jump_fall_multiplier)
	d.sprint_gap = PILOT_SCRIPT.jump_distance_for(
		p.sprint_speed, p.jump_time_to_apex, p.jump_fall_multiplier)
	d.double_gap = d.sprint_gap * jumps
	d.single_apex = p.jump_height
	d.double_apex = p.jump_height * jumps
	# `peak + band`, never `apex + band`: the mantle probe fires on every airborne frame, so
	# he passes through every height on the way up AND on the way down.
	d.single_mantle = p.jump_height + p.climb_band_max
	d.double_mantle = p.jump_height * jumps + p.climb_band_max
	d.grab_depth = p.climb_probe_reach
	d.headroom = p.climb_headroom
	# Just past the middle of the climb band, so a miss drops to the slab and can be mantled
	# back onto the pad from standing. A RATIO rather than a metre on purpose: 1.5 m is only
	# correct while the band is 0.9-1.9, and this stays inside the band wherever the band
	# goes. Getting back up is the loop that runs hundreds of times a session; it is the one
	# worth making free.
	d.pad_height = lerpf(p.climb_band_min, p.climb_band_max, 0.6)
	p.free()
	return d


# --- the build ------------------------------------------------------------

func _build(d: Dials) -> void:
	# The ladder is derived from the gaps, not counted out: the single-jump side runs every
	# whole metre up to what a sprint clears, the double-jump side carries on from there to
	# what two jumps clear. Raise sprint_speed and the ladder grows a rung on its own.
	var single := _whole_metres(1, d.sprint_gap)
	var double := _whole_metres(int(round(d.sprint_gap)) + 1, d.double_gap)
	var positions: int = maxi(single.size(), double.size())
	if positions <= 0:
		push_warning("jump_grid: pilot9's gaps came out under a metre; nothing to build.")
		return

	var lane_span := float(positions - 1) * LANE_PITCH
	var lane_min_x := -lane_span * 0.5 - LANE_WIDTH * 0.5
	var lane_max_x := lane_span * 0.5 + LANE_WIDTH * 0.5
	var spine_min_x := lane_min_x - START_STRIP
	var spine_max_x := lane_max_x + END_STRIP

	# See _shift: this is what moves the platform's origin onto the start strip's surface.
	_shift = Vector3(-(spine_min_x + START_STRIP * 0.5), -d.pad_height, 0.0)

	# The far face of the deepest lane on each side, which is what the slab and the pillar
	# field have to clear.
	var single_far := SPINE_HALF_DEPTH + TAKEOFF_LENGTH + _last(single) + LANDING_LENGTH
	var double_far := -(SPINE_HALF_DEPTH + TAKEOFF_LENGTH + _last(double) + LANDING_LENGTH)

	var heights := _pillar_heights(d)
	# Derived, and this is the whole reason pillar-to-pillar chaining is impossible rather
	# than merely discouraged: a top's width plus a sprint jump plus the forward grab the
	# mantle adds, rounded up to a whole metre so the surface's 5 m lines still land on the
	# pitch. At the shipping numbers that is 12.0 m, leaving 10.5 m of clear edge.
	var pitch := ceilf(PILLAR_TOP + d.sprint_gap + d.grab_depth + 0.5)
	var cols: int = maxi(1, int(ceil(heights.size() / 2.0)))
	var rows: int = int(ceil(float(heights.size()) / float(cols)))
	# The near row sits a full pitch past the deepest landing pad, so the pads cannot be used
	# as a launch platform into the field either.
	var field_near_z := double_far - pitch
	var field_far_z := field_near_z - float(rows - 1) * pitch
	var field_half_x := float(cols - 1) * 0.5 * pitch + PILLAR_TOP * 0.5

	_build_slab(
		minf(spine_min_x, -field_half_x), maxf(spine_max_x, field_half_x),
		field_far_z - PILLAR_TOP * 0.5, single_far)
	_build_spine(d, spine_min_x, spine_max_x)
	_build_lanes(d, single, double, positions)
	_build_pillars(d, heights, pitch, cols, field_near_z)


func _build_slab(min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	var size := Vector3(
		(max_x - min_x) + SLAB_MARGIN * 2.0,
		SLAB_THICKNESS,
		(max_z - min_z) + SLAB_MARGIN * 2.0)
	var centre := Vector3((min_x + max_x) * 0.5, -SLAB_THICKNESS * 0.5, (min_z + max_z) * 0.5)
	_box(self, "Slab", size, centre, COLOUR_SLAB)


func _build_spine(d: Dials, min_x: float, max_x: float) -> void:
	_box(self, "Spine",
		Vector3(max_x - min_x, d.pad_height, SPINE_HALF_DEPTH * 2.0),
		Vector3((min_x + max_x) * 0.5, d.pad_height * 0.5, 0.0),
		COLOUR_SPINE)


func _build_lanes(d: Dials, single: Array[int], double: Array[int], positions: int) -> void:
	var group := Node3D.new()
	group.name = "Lanes"
	add_child(group)
	var span := float(positions - 1) * LANE_PITCH
	for i in single.size():
		_build_lane(d, group, float(single[i]), -span * 0.5 + float(i) * LANE_PITCH, 1.0, i)
	for i in double.size():
		_build_lane(d, group, float(double[i]), -span * 0.5 + float(i) * LANE_PITCH, -1.0, i)


# One lane: takeoff pad, gap, landing pad, the grab strip on the landing lip, and the label
# hanging over the void being measured. `side` is +1 for the single-jump range and -1 for the
# double-jump range, so the split falls on the geometry: which side of the spine you are
# standing on already tells you which jump you need.
func _build_lane(d: Dials, group: Node3D, gap: float, x: float, side: float, index: int) -> void:
	var limit := _lane_limit(gap, d)
	var tint := _warm(gap, d) if limit != "" else COLOUR_PAD

	var lane := Node3D.new()
	lane.name = "Lane_%sm" % _metre_tag(gap)
	group.add_child(lane)

	var near := SPINE_HALF_DEPTH
	var takeoff_far := near + TAKEOFF_LENGTH
	var landing_near := takeoff_far + gap
	var landing_far := landing_near + LANDING_LENGTH

	_box(lane, "Takeoff",
		Vector3(LANE_WIDTH, d.pad_height, TAKEOFF_LENGTH),
		Vector3(x, d.pad_height * 0.5, side * (near + takeoff_far) * 0.5),
		tint)
	_box(lane, "Landing",
		Vector3(LANE_WIDTH, d.pad_height, LANDING_LENGTH),
		Vector3(x, d.pad_height * 0.5, side * (landing_near + landing_far) * 0.5),
		tint)

	# The mantle probe takes any lip inside the climb band within `climb_probe_reach` ahead,
	# on every airborne frame - so an undershoot that falls past this face gets rescued, and
	# a failed 12 m jump reads as a cleared 12 m lane. The lips are left grabbable on purpose
	# (real map geometry has square ledges), so the asterisk is painted on the floor in front
	# of you rather than left to memory: land past the strip and you cleared it outright,
	# land on it and the mantle carried you. An approximation - the real band also depends on
	# fall speed - but it is there on every attempt.
	_quad(lane, "GrabStrip",
		Vector2(LANE_WIDTH, d.grab_depth),
		Vector3(x, d.pad_height + DECAL_LIFT, side * (landing_near + d.grab_depth * 0.5)),
		COLOUR_GRAB)

	# Over the void, because the void is the thing being measured - and stepped up a rung per
	# lane. Lanes are 4 m apart and a caption like "18 m · DOUBLE" is wider than that, so at
	# one height the row reads as a single smear of overlapping text from anywhere down the
	# spine. FOUR rungs and not three: the named limits land every third lane, so a 3-rung
	# cycle put WALK, RUN and SPRINT back on one line - the three captions most worth reading.
	_label(lane, "Label", _marker_text(gap, limit),
		Vector3(x, d.pad_height + 2.0 + float(index % 4) * 1.4, side * (takeoff_far + gap * 0.5)),
		tint if limit != "" else Color.WHITE)


func _build_pillars(d: Dials, heights: Array[float], pitch: float, cols: int, near_z: float) -> void:
	var group := Node3D.new()
	group.name = "Pillars"
	add_child(group)
	var span := float(cols - 1) * pitch
	for i in heights.size():
		var col := i % cols
		var row := i / cols
		_build_pillar(d, group, heights[i],
			-span * 0.5 + float(col) * pitch,
			near_z - float(row) * pitch)


# One free-standing pillar. A staircase would have been half the size and would have measured
# nothing - mantle 1 m, then 2 m from there, and you have tested three 1 m steps and learned
# nothing about a 3 m ledge. The whole point of the mantle ceilings is what he reaches FROM
# THE FLOOR, so every pillar is approached from the slab.
func _build_pillar(d: Dials, group: Node3D, height: float, x: float, z: float) -> void:
	var limit := _pillar_limit(height, d)
	var tint := COLOUR_PILLAR
	if limit == "MANTLE" or limit == "DOUBLE MANTLE":
		tint = COLOUR_GRAB
	elif limit != "":
		tint = _warm(height, d)

	var pillar := Node3D.new()
	pillar.name = "Pillar_%sm" % _metre_tag(height)
	group.add_child(pillar)

	_box(pillar, "Body",
		Vector3(PILLAR_TOP, height, PILLAR_TOP),
		Vector3(x, height * 0.5, z),
		tint)

	# The same grab strip a landing pad carries, wrapped all the way round because a pillar
	# is approached from any side: the whole top goes cyan, then whatever is further than a
	# grab's reach from every edge is painted back in the pillar's own colour.
	_quad(pillar, "GrabStrip", Vector2(PILLAR_TOP, PILLAR_TOP),
		Vector3(x, height + DECAL_LIFT, z), COLOUR_GRAB)
	var inner := PILLAR_TOP - d.grab_depth * 2.0
	if inner > 0.0:
		_quad(pillar, "ClearCap", Vector2(inner, inner),
			Vector3(x, height + DECAL_LIFT * 2.0, z), tint)

	_label(pillar, "Label", _marker_text(height, limit),
		Vector3(x, height + 1.2, z),
		tint if limit != "" else Color.WHITE)


# --- node helpers ---------------------------------------------------------

# A solid box: one StaticBody3D carrying the collision the player actually stands on and the
# mesh that draws it. Mesh and shape are always given the SAME Vector3 - the ruler you look
# at and the ruler you land on cannot be allowed to drift apart - and nothing here is ever
# built by scaling a node, so the shader's world normals stay unit length.
func _box(parent: Node, nm: String, size: Vector3, centre: Vector3, tint: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = centre + _shift
	parent.add_child(body)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(tint)
	# Every surface here is unshaded, so a shadow cast onto the platform cannot be seen on
	# it. Casting would be pure cost.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body


# A flat tinted panel laid on top of a surface. No collider, deliberately: a grab strip is a
# marking on the floor and must not be something the player can catch a foot on.
func _quad(parent: Node, nm: String, size: Vector2, centre: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = nm
	mesh.position = centre + _shift
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = _material(tint)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh


func _label(parent: Node, nm: String, text: String, centre: Vector3, tint: Color) -> Label3D:
	var label := Label3D.new()
	label.name = nm
	label.position = centre + _shift
	label.text = text
	label.font_size = LABEL_FONT_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.outline_size = LABEL_FONT_SIZE / 4
	label.modulate = tint
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Discard rather than blend: a field of billboards otherwise sorts against itself and
	# labels flicker in front of each other as the camera turns.
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	parent.add_child(label)
	return label


# One material per tint, minted on demand. Without the cache a platform this size would carry
# a few hundred identical ShaderMaterials.
func _material(tint: Color) -> Material:
	if _materials.has(tint):
		return _materials[tint]
	var mat := ShaderMaterial.new()
	mat.shader = load(GRID_SHADER) as Shader
	mat.set_shader_parameter("base_color", tint)
	_materials[tint] = mat
	return mat


# --- numbers --------------------------------------------------------------

# Whole metres from `from_m` up to and including the last one that fits inside `to_m`. Three
# boxes at 3 / 6 / 9 would be the tidy version and would answer the wrong question: a 9 m gap
# is one he clears with ZERO margin, and what a map actually needs to know is where the
# comfortable distance is. That is not a number the physics can be asked for - it is one you
# find by jumping 7, then 8, then 9, and noticing where it stops feeling free. A ladder costs
# one `for` loop and answers it.
func _whole_metres(from_m: int, to_m: float) -> Array[int]:
	var out: Array[int] = []
	for m in range(from_m, int(floor(to_m + 0.001)) + 1):
		out.append(m)
	return out


func _last(metres: Array[int]) -> float:
	return float(metres[-1]) if not metres.is_empty() else 0.0


# The ten pillar tops: every whole metre up to the double-jump mantle ceiling, plus the two
# ceilings themselves - because the two heights that matter most are not whole numbers.
# Sorted, so filling the field row-major puts the ladder in reading order.
func _pillar_heights(d: Dials) -> Array[float]:
	var out: Array[float] = []
	for m in range(1, int(ceil(d.double_mantle - 0.001)) + 1):
		out.append(float(m))
	out.append(d.single_mantle)
	out.append(d.double_mantle)
	out.sort()
	return out


## The named limit a gap is, or "" for a rung of the ladder that is only a distance.
func _lane_limit(gap: float, d: Dials) -> String:
	if _same(gap, d.walk_gap):
		return "WALK"
	if _same(gap, d.run_gap):
		return "RUN"
	if _same(gap, d.sprint_gap):
		return "SPRINT"
	if _same(gap, d.double_gap):
		return "DOUBLE"
	return ""


## The named limit a pillar top is, or "". Apexes are what he CLEARS and mantles what he
## GRABS; _build_pillar turns that distinction into warm or cyan. Mantles are tested first
## because a ceiling is the more surprising of the two, and at some tunings the pair could
## collide on one height.
func _pillar_limit(height: float, d: Dials) -> String:
	if _same(height, d.single_mantle):
		return "MANTLE"
	if _same(height, d.double_mantle):
		return "DOUBLE MANTLE"
	if _same(height, d.single_apex):
		return "APEX"
	if _same(height, d.double_apex):
		return "DOUBLE APEX"
	return ""


# Warm ramp, pinned to the smallest and largest named limit rather than to a list of colours.
# This is what makes the 3 m gap and the 3 m apex pillar come out the same colour without
# either of them being told what colour it is - and it moves with the dials, so a faster
# sprint re-ranks the ramp instead of stranding it.
func _warm(metres: float, d: Dials) -> Color:
	var t := clampf(inverse_lerp(d.walk_gap, d.double_gap, metres), 0.0, 1.0)
	return WARM_LOW.lerp(WARM_HIGH, t)


func _marker_text(metres: float, limit: String) -> String:
	var head := "%s m" % _metre_text(metres)
	return head if limit == "" else "%s · %s" % [head, limit]


# "7" for a whole metre, "4.9" otherwise. The label is what
# tests/test_pilot9_jump_grid_platform.gd parses back out and measures the geometry against,
# so this is load-bearing rather than cosmetic.
func _metre_text(metres: float) -> String:
	if _same(metres, roundf(metres)):
		return str(int(round(metres)))
	return String.num(metres, 2).rstrip("0").rstrip(".")


# Node names cannot carry a dot.
func _metre_tag(metres: float) -> String:
	return _metre_text(metres).replace(".", "p")


func _same(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
