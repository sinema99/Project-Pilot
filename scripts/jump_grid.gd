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
## Rails are real Rail nodes, the ones a map pastes - so the ruler rides exactly what a map does.
const RAIL_SCRIPT := preload("res://scripts/rail.gd")
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

## Wall-run corridors: docs/specs/pilot9-jump-grid-platform.md, "The dash and wall-run
## addition". Ground flush against the wall before it drops away - same job as TAKEOFF_LENGTH,
## same number.
const WALL_RUN_APPROACH := 6.0
const WALL_RUN_WIDTH := 3.0
const WALL_RUN_THICKNESS := 1.0
## Wider than the corridor's own footprint (pad + wall, 4.0 m) is wide, on purpose - the same
## "further apart than a sprint jump plus the mantle assist" reasoning the pillar field pitch
## uses, applied to a row instead of a grid: a drift off one corridor must not be able to reach
## its neighbour's wall.
const WALL_RUN_PITCH := 10.0
const WALL_RUN_HEIGHT := 8.0
## How far the wall's base (and the catch slab under it) sits below the launch pad's floor -
## room for the droop and for a jump taken off the edge, so a run does not clip the pad on the
## way down.
const WALL_RUN_DROP := 4.0
const WALL_RUN_SLAB_THICKNESS := 1.0
## Gap left clear beyond the pillar field before the corridor row starts, so a chained pillar
## jump cannot carry into the first corridor's launch pad.
const WALL_RUN_FIELD_MARGIN := 4.0

## Rail stations: docs/specs/pilot9-rail-grind.md, "Test geometry". Each is a launch pad, a
## straight flat rail you jump onto off it, and - for the two jump-off stations - a landing pad
## exactly the gear's jump distance past the rail's end, its top level with his feet on the rail.
## The rail is long enough to reach either gear and hold it well before the end.
const RAIL_APPROACH := 6.0
const RAIL_LENGTH := 14.0
## How far above the launch pad the rail's centreline sits: under a single jump's 3 m apex with
## room to come down onto it, and over the pad so the jump is a jump.
const RAIL_LIFT := 1.0
const RAIL_PITCH := 10.0
## The parallel pair's centre-to-centre spacing - the spec's "~3 m, the 45 degree hop across".
const RAIL_PAIR_SPACING := 3.0

## Vault lanes: docs/specs/pilot9-vault.md, "Test bed". Each is a flat run-up long enough to
## reach a sprint, one thin wall, and a landing strip - all on the row's own floor, level with
## the slab, because a vault is a GROUND move and the pads everywhere else stand over it.
const VAULT_RUNUP := 10.0
const VAULT_LANDING := 6.0
## The thin walls' depth - the thin top the clip was authored for, and under vault_max_depth.
const VAULT_WALL_DEPTH := 0.4
const VAULT_PITCH := 5.0

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
	var dash_gap := 0.0          ## dash_distance()
	var wall_run_gap := 0.0      ## wall_run_distance(speed)
	var wall_run_sprint_gap := 0.0 ## wall_run_distance(sprint_speed)
	var rail_gap := 0.0          ## rail_jump_distance(rail_grind_speed)
	var rail_sprint_gap := 0.0   ## rail_jump_distance(rail_sprint_speed)
	var vault_band_min := 0.0    ## vault_band_min
	var vault_band_max := 0.0    ## vault_band_max
	var vault_max_depth := 0.0   ## vault_max_depth


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
	d.dash_gap = PILOT_SCRIPT.dash_distance_for(p.dash_speed, p.dash_time)
	d.wall_run_gap = PILOT_SCRIPT.wall_run_distance_for(p.speed, p.wall_run_flat_time)
	d.wall_run_sprint_gap = PILOT_SCRIPT.wall_run_distance_for(
		p.sprint_speed, p.wall_run_flat_time)
	d.rail_gap = PILOT_SCRIPT.rail_jump_distance_for(
		p.rail_grind_speed, p.jump_time_to_apex, p.jump_fall_multiplier)
	d.rail_sprint_gap = PILOT_SCRIPT.rail_jump_distance_for(
		p.rail_sprint_speed, p.jump_time_to_apex, p.jump_fall_multiplier)
	d.vault_band_min = p.vault_band_min
	d.vault_band_max = p.vault_band_max
	d.vault_max_depth = p.vault_max_depth
	p.free()
	return d


# --- the build ------------------------------------------------------------

func _build(d: Dials) -> void:
	# The ladder is derived from the gaps, not counted out: the single-jump side runs every
	# whole metre up to what a sprint clears, the double-jump side carries on from there to
	# what two jumps clear. Raise sprint_speed and the ladder grows a rung on its own.
	var single := _whole_metres(1, d.sprint_gap)
	var double := _whole_metres(int(round(d.sprint_gap)) + 1, d.double_gap)
	# The dash's own rung, spliced into whichever side it falls on rather than assumed to be a
	# whole metre already in the ladder - see "The dash and wall-run addition" in the spec. At
	# the shipping tuning it already IS a whole metre (10) inside `double`, so this is a no-op
	# there; it only matters the day someone retunes dash_speed or dash_time off that.
	_splice_rung(single, double, d.dash_gap, d.sprint_gap)
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

	var wall_lengths := _wall_run_lengths(d)
	var wall_span_x := 0.0
	if not wall_lengths.is_empty():
		wall_span_x = (
			float(wall_lengths.size() - 1) * WALL_RUN_PITCH
			+ WALL_RUN_WIDTH + WALL_RUN_THICKNESS)
	var wall_half_x := wall_span_x * 0.5
	var wall_near_z := field_far_z - PILLAR_TOP * 0.5 - WALL_RUN_FIELD_MARGIN

	_build_slab(
		minf(spine_min_x, minf(-field_half_x, -wall_half_x)),
		maxf(spine_max_x, maxf(field_half_x, wall_half_x)),
		field_far_z - PILLAR_TOP * 0.5, single_far)
	_build_spine(d, spine_min_x, spine_max_x)
	_build_lanes(d, single, double, positions)
	_build_pillars(d, heights, pitch, cols, field_near_z)
	_build_wall_runs(d, wall_lengths, wall_near_z)
	var wall_depth := RAIL_APPROACH
	for length in wall_lengths:
		wall_depth = maxf(wall_depth, length)
	var rails_far := _build_rails(d, wall_near_z - wall_depth - WALL_RUN_FIELD_MARGIN * 2.0)
	# Flush against the rail row's floor, so the two rows are one walk rather than two islands.
	_build_vaults(d, rails_far - SLAB_MARGIN)


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


func _build_lanes(d: Dials, single: Array[float], double: Array[float], positions: int) -> void:
	var group := Node3D.new()
	group.name = "Lanes"
	add_child(group)
	var span := float(positions - 1) * LANE_PITCH
	for i in single.size():
		_build_lane(d, group, single[i], -span * 0.5 + float(i) * LANE_PITCH, 1.0, i)
	for i in double.size():
		_build_lane(d, group, double[i], -span * 0.5 + float(i) * LANE_PITCH, -1.0, i)


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


func _build_wall_runs(d: Dials, lengths: Array[float], near_z: float) -> void:
	if lengths.is_empty():
		return
	var group := Node3D.new()
	group.name = "WallRuns"
	add_child(group)
	var span := float(lengths.size() - 1) * WALL_RUN_PITCH
	for i in lengths.size():
		_build_wall_run(d, group, lengths[i], -span * 0.5 + float(i) * WALL_RUN_PITCH, near_z)


# One corridor: a launch pad flush against the base of a wall that keeps going past the pad's
# far edge, so leaving the pad leaves him airborne and still hugging the face - the attach gates
# fire because of what the geometry does, not because of an instruction to the player. A catch
# slab runs the whole length underneath, flush with the wall's own base, so a run that droops
# out early lands rather than falling forever. See "The dash and wall-run addition" in
# docs/specs/pilot9-jump-grid-platform.md.
func _build_wall_run(d: Dials, group: Node3D, length: float, x: float, near_z: float) -> void:
	var limit := _wall_run_limit(length, d)
	var tint := _warm_between(length, 1.0, d.wall_run_sprint_gap) if limit != "" else COLOUR_PAD

	var corridor := Node3D.new()
	corridor.name = "WallRun_%sm" % _metre_tag(length)
	group.add_child(corridor)

	var wall_x := x + WALL_RUN_WIDTH * 0.5 + WALL_RUN_THICKNESS * 0.5
	var far_z := near_z - length

	_box(corridor, "Launch",
		Vector3(WALL_RUN_WIDTH, d.pad_height, WALL_RUN_APPROACH),
		Vector3(x, d.pad_height * 0.5, near_z - WALL_RUN_APPROACH * 0.5),
		tint if limit != "" else COLOUR_PAD)

	# The wall stands proud of the pad by a few metres (room to jump alongside it) and reaches
	# well below it (room for the droop, plus the catch slab flush against its own base).
	var wall_top := d.pad_height + (WALL_RUN_HEIGHT - WALL_RUN_DROP - WALL_RUN_SLAB_THICKNESS)
	var wall_base := wall_top - WALL_RUN_HEIGHT
	_box(corridor, "Wall",
		Vector3(WALL_RUN_THICKNESS, WALL_RUN_HEIGHT, length),
		Vector3(wall_x, (wall_base + wall_top) * 0.5, near_z - length * 0.5),
		tint)

	_box(corridor, "Catch",
		Vector3(WALL_RUN_WIDTH + WALL_RUN_THICKNESS, WALL_RUN_SLAB_THICKNESS, length),
		Vector3(x + WALL_RUN_THICKNESS * 0.5, wall_base - WALL_RUN_SLAB_THICKNESS * 0.5,
			near_z - length * 0.5),
		COLOUR_SLAB)

	# Over the far end, past the ground that has already dropped away - reading it means having
	# got that far, not reading it from the launch pad before trying.
	_label(corridor, "Label", _marker_text(length, limit),
		Vector3(wall_x, wall_top - 0.6, far_z + 0.4),
		tint if limit != "" else Color.WHITE)


## Returns the far edge of the row's floor, where the next row can start.
func _build_rails(d: Dials, near_z: float) -> float:
	var group := Node3D.new()
	group.name = "Rails"
	add_child(group)
	var stations := [
		{"gap": d.rail_gap, "limit": "RAIL"},
		{"gap": d.rail_sprint_gap, "limit": "RAIL SPRINT"},
		{"gap": 0.0, "limit": "RAIL HOP"},
	]
	var span := float(stations.size() - 1) * RAIL_PITCH
	var deepest := 0.0
	for st: Dictionary in stations:
		deepest = maxf(deepest, float(st["gap"]))
	var row_depth := RAIL_APPROACH + RAIL_LENGTH + deepest + LANDING_LENGTH
	# The row's own floor, flush with the slab's top. A miss lands on it rather than in the void,
	# and the launch pads stand pad_height over it so getting back up is a mantle.
	_box(group, "Floor",
		Vector3(span + RAIL_PITCH, SLAB_THICKNESS, row_depth + SLAB_MARGIN * 2.0),
		Vector3(0.0, -SLAB_THICKNESS * 0.5, near_z - row_depth * 0.5),
		COLOUR_SLAB)
	for i in stations.size():
		var st: Dictionary = stations[i]
		_build_rail_station(d, group, -span * 0.5 + float(i) * RAIL_PITCH, near_z,
			float(st["gap"]), String(st["limit"]))
	return near_z - row_depth - SLAB_MARGIN


# One station. Everything runs toward -Z: pad, rail, gap, landing. The landing pad's top sits at
# the rail's TOP - where his feet ride - so the gap is flat-to-flat, the same measurement the
# jump grid's lanes make.
func _build_rail_station(d: Dials, group: Node3D, x: float, near_z: float, gap: float,
		limit: String) -> void:
	var station := Node3D.new()
	station.name = "Rail_%s" % (_metre_tag(gap) + "m" if gap > 0.0 else "Hop")
	group.add_child(station)

	_box(station, "Launch",
		Vector3(LANE_WIDTH, d.pad_height, RAIL_APPROACH),
		Vector3(x, d.pad_height * 0.5, near_z - RAIL_APPROACH * 0.5),
		COLOUR_PAD)

	var rail_y := d.pad_height + RAIL_LIFT
	var rail_start := near_z - RAIL_APPROACH
	var rail_end := rail_start - RAIL_LENGTH
	var xs: Array[float] = [x]
	if gap <= 0.0:
		xs = [x - RAIL_PAIR_SPACING * 0.5, x + RAIL_PAIR_SPACING * 0.5]
	var top := rail_y
	for j in xs.size():
		var rail = RAIL_SCRIPT.new()
		rail.name = "Rail" if xs.size() == 1 else "Rail%d" % (j + 1)
		var c := Curve3D.new()
		c.add_point(Vector3.ZERO)
		c.add_point(Vector3(0.0, 0.0, rail_end - rail_start))
		rail.curve = c
		rail.position = Vector3(xs[j], rail_y, rail_start) + _shift
		station.add_child(rail)
		top = rail_y + float(rail.rail_radius)

	var tint := COLOUR_GRAB
	if gap > 0.0:
		tint = _warm_between(gap, d.rail_gap, d.rail_sprint_gap)
		_box(station, "Landing",
			Vector3(LANE_WIDTH, top, LANDING_LENGTH),
			Vector3(x, top * 0.5, rail_end - gap - LANDING_LENGTH * 0.5),
			tint)
	var text := "%s · %s" % [_metre_text(RAIL_PAIR_SPACING if gap <= 0.0 else gap), limit]
	_label(station, "Label", text,
		Vector3(x, rail_y + 1.6, rail_start - 1.0), tint)


func _build_vaults(d: Dials, near_z: float) -> void:
	var group := Node3D.new()
	group.name = "Vaults"
	add_child(group)
	# The band in four even steps - 0.5 / 0.7 / 0.9 / 1.1 / 1.3 at the shipping dials - then the
	# two controls: a thin wall just over the band (the jump, and the mantle it carries into) and
	# a block in the band but twice too deep to vault (a platform, jumped onto).
	var lanes: Array[Dictionary] = []
	for k in 5:
		lanes.append({"h": lerpf(d.vault_band_min, d.vault_band_max, float(k) / 4.0),
			"depth": VAULT_WALL_DEPTH, "limit": "VAULT"})
	lanes.append({"h": d.vault_band_max + 0.2, "depth": VAULT_WALL_DEPTH, "limit": "JUMP"})
	lanes.append({"h": lerpf(d.vault_band_min, d.vault_band_max, 0.75),
		"depth": d.vault_max_depth * 2.0, "limit": "TOO DEEP"})
	var span := float(lanes.size() - 1) * VAULT_PITCH
	var deepest := 0.0
	for lane in lanes:
		deepest = maxf(deepest, float(lane["depth"]))
	var row_depth := VAULT_RUNUP + deepest + VAULT_LANDING
	_box(group, "Floor",
		Vector3(span + VAULT_PITCH, SLAB_THICKNESS, row_depth + SLAB_MARGIN * 2.0),
		Vector3(0.0, -SLAB_THICKNESS * 0.5, near_z - row_depth * 0.5),
		COLOUR_SLAB)
	for i in lanes.size():
		_build_vault_lane(d, group, lanes[i], -span * 0.5 + float(i) * VAULT_PITCH, near_z)


# One lane, running toward -Z: VAULT_RUNUP of bare floor, the wall, VAULT_LANDING past it. The
# label reads the wall's height, which is what the lane measures.
func _build_vault_lane(d: Dials, group: Node3D, lane: Dictionary, x: float, near_z: float) -> void:
	var h: float = lane["h"]
	var depth: float = lane["depth"]
	var limit: String = lane["limit"]
	var tint := _warm_between(h, d.vault_band_min, d.vault_band_max)
	if limit == "JUMP":
		tint = COLOUR_GRAB
	elif limit == "TOO DEEP":
		tint = COLOUR_PILLAR
	var node := Node3D.new()
	node.name = "Vault_%sm%s" % [_metre_tag(h), "" if limit == "VAULT" else "_" + limit.replace(" ", "")]
	group.add_child(node)
	var face_z := near_z - VAULT_RUNUP
	_box(node, "Wall", Vector3(LANE_WIDTH, h, depth), Vector3(x, h * 0.5, face_z - depth * 0.5), tint)
	_label(node, "Label", "%s m · %s" % [_metre_text(h), limit],
		Vector3(x, h + 1.2, face_z - depth * 0.5), tint)


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
func _whole_metres(from_m: int, to_m: float) -> Array[float]:
	var out: Array[float] = []
	for m in range(from_m, int(floor(to_m + 0.001)) + 1):
		out.append(float(m))
	return out


func _last(metres: Array[float]) -> float:
	return metres[-1] if not metres.is_empty() else 0.0


## Drops a named, possibly-fractional distance into whichever ladder it falls on - `single` at
## or under `threshold`, `double` past it - the same move `_pillar_heights()` already makes for
## the two mantle ceilings. Without this, a rung only exists at whole metres and a knob retuned
## off one (the dash, if `dash_speed` or `dash_time` ever moves) silently loses its label rather
## than growing its own rung.
func _splice_rung(single: Array[float], double: Array[float], value: float, threshold: float) -> void:
	_splice(single if value <= threshold else double, value)


## Inserts `value` into `arr` if it is not already there (within `_same()`), keeping it sorted.
func _splice(arr: Array[float], value: float) -> void:
	if value <= 0.0:
		return
	for existing in arr:
		if _same(existing, value):
			return
	arr.append(value)
	arr.sort()


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


## Every whole metre from 1 to the sprint wall-run's own ceiling, the corridor row's version of
## the gap ladder and the pillar field's "every metre, not just the limits" reasoning: three
## corridors at 1 / 10 / 15 would answer whether the tech works, not where it stops feeling free.
func _wall_run_lengths(d: Dials) -> Array[float]:
	var out := _whole_metres(1, d.wall_run_sprint_gap)
	_splice(out, d.wall_run_gap)
	_splice(out, d.wall_run_sprint_gap)
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
	if _same(gap, d.dash_gap):
		return "DASH"
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
	return _warm_between(metres, d.walk_gap, d.double_gap)


## The same ramp, pinned to a caller-chosen pair of ends instead of the gap ladder's own -
## the wall-run corridors are a separate axis (a length run alongside, not a gap cleared) with
## its own smallest and largest named rung, and forcing them onto the gap ladder's ramp would
## make a 10 m corridor and a 10 m gap the same colour by accident rather than by the ramp
## agreeing they are both roughly "sprint-ish".
func _warm_between(metres: float, low: float, high: float) -> Color:
	var t := clampf(inverse_lerp(low, high, metres), 0.0, 1.0)
	return WARM_LOW.lerp(WARM_HIGH, t)


## The named limit a wall-run corridor's length is, or "" for a plain rung.
func _wall_run_limit(length: float, d: Dials) -> String:
	if _same(length, d.wall_run_gap):
		return "RUN"
	if _same(length, d.wall_run_sprint_gap):
		return "SPRINT"
	return ""


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
