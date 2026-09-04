extends "res://tests/test_case.gd"

# Setsuna's locomotion state machine. See docs/specs/setsuna-animation-tree.md.
#
# The tree is a data file, so this pins the data: the states, the clip each one plays, and the
# whole transition table with its crossfades. What none of it can tell you is whether a 0.18 s
# fade across a stride actually reads as continuous motion - that is the QA pass in the spec.
#
# That question matters more than it used to. The 2026-09-03 SETSUNA.glb export deleted every
# start and end clip (RUN START/END, SPRINT START/LOOP/END, Jump_start/Jump_end, DASH_loop), so
# a crossfade is now the *only* thing between any two clips - there is no authored transition
# anywhere in her set. Every xfade below is load-bearing.
#
# The one thing worth saying twice: an xfade asserted here is the *spec's* number, not the file's.
# Retuning one in the editor is meant to fail this test until the spec is retuned with it.

const TREE_PATH := "res://resources/setsuna_locomotion_tree.tres"
const PLAYER_SCRIPT := "res://scripts/player.gd"
const Player := preload("res://scripts/player.gd")

const IMMEDIATE := AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
const AT_END := AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
const AUTO := AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
const TRAVEL := AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED

# state -> the clip it plays. RUN and DASH name the clip inside their blend tree; CROUCH is a
# blend space over three clips and is checked on its own below.
const STATE_CLIPS := {
	"IDLE": "SET IDLE",
	"RUN": "SET RUN LOOP",
	"JUMP": "SET JUMP LOOP",
	"FALL": "SET Falling",
	"DASH": "SET DASH",
}

# The three crouch poses, low end of the blend axis (leaning left) to high (leaning right).
const CROUCH_POINTS := [
	[-1.0, "SET CROUCH LOOP LEFT"],
	[0.0, "SET CROUCH LOOP"],
	[1.0, "SET CROUCH LOOP RIGHT"],
]

# The spec's transition table, as [from, to, xfade, switch mode, advance mode, condition].
#
# The four At End fall-throughs out of DASH carry a condition the spec's table leaves blank, and
# they have to: an eligible At End transition suppresses every eligible Immediate transition out
# of the same state, whatever order they sit in and whatever their priority. Since all four of
# DASH's exits are At End that is moot here, but the real invariant of this table is the one
# asserted below it - out of any state, at most one transition is ever eligible at once.
const TABLE := [
	["Start", "IDLE", 0.0, IMMEDIATE, AUTO, ""],

	["IDLE", "RUN", 0.18, IMMEDIATE, AUTO, "moving"],
	["IDLE", "CROUCH", 0.15, IMMEDIATE, AUTO, "crouching"],
	["IDLE", "FALL", 0.10, IMMEDIATE, AUTO, "off_floor"],

	["RUN", "IDLE", 0.18, IMMEDIATE, AUTO, "not_moving"],
	["RUN", "CROUCH", 0.15, IMMEDIATE, AUTO, "crouching"],
	["RUN", "FALL", 0.10, IMMEDIATE, AUTO, "off_floor"],

	["CROUCH", "IDLE", 0.15, IMMEDIATE, AUTO, "not_moving"],
	["CROUCH", "RUN", 0.18, IMMEDIATE, AUTO, "moving"],
	["CROUCH", "FALL", 0.10, IMMEDIATE, AUTO, "off_floor"],

	["JUMP", "IDLE", 0.20, IMMEDIATE, AUTO, "not_moving"],
	["JUMP", "RUN", 0.15, IMMEDIATE, AUTO, "moving"],
	["JUMP", "CROUCH", 0.15, IMMEDIATE, AUTO, "crouching"],

	["FALL", "IDLE", 0.12, IMMEDIATE, AUTO, "not_moving"],
	["FALL", "RUN", 0.12, IMMEDIATE, AUTO, "moving"],
	["FALL", "CROUCH", 0.12, IMMEDIATE, AUTO, "crouching"],

	["DASH", "FALL", 0.12, AT_END, AUTO, "off_floor"],
	["DASH", "RUN", 0.15, AT_END, AUTO, "moving"],
	["DASH", "IDLE", 0.15, AT_END, AUTO, "not_moving"],
	["DASH", "CROUCH", 0.15, AT_END, AUTO, "crouching"],
]

# Godot 4's AnimationNodeStateMachine has no "Any State" node, so the spec's two Any State rows
# are spelled out from every other state instead - the fallback the spec names. Travel-only, so
# they never auto-fire, and never from the destination itself.
const TRAVEL_TARGETS := ["JUMP", "DASH"]
const TRAVEL_XFADE := 0.05

func _tree() -> AnimationNodeStateMachine:
	return load(TREE_PATH) as AnimationNodeStateMachine

func _anim_player() -> AnimationPlayer:
	var glb: PackedScene = load("res://assets/setsuna.glb")
	return glb.instantiate().find_child("AnimationPlayer", true, false) as AnimationPlayer

# The clip an Animation state plays, reaching through the blend tree for the two scaled ones.
func _clip_of(node: AnimationNode) -> String:
	if node is AnimationNodeAnimation:
		return String((node as AnimationNodeAnimation).animation)
	if node is AnimationNodeBlendTree:
		var inner := (node as AnimationNodeBlendTree).get_node("Animation")
		if inner is AnimationNodeAnimation:
			return String((inner as AnimationNodeAnimation).animation)
	return ""

# Every clip a state can play, blend spaces included - what the export has to carry for the
# state to show anything at all.
func _clips_of(node: AnimationNode) -> PackedStringArray:
	if node is AnimationNodeBlendSpace1D:
		var space := node as AnimationNodeBlendSpace1D
		var out: PackedStringArray = []
		for i in space.get_blend_point_count():
			out.append(_clip_of(space.get_blend_point_node(i)))
		return out
	var one := _clip_of(node)
	return [] if one == "" else PackedStringArray([one])

# --- states ----------------------------------------------------------------

func test_every_state_plays_the_clip_the_spec_names() -> void:
	var sm := _tree()
	check(sm != null, "resources/setsuna_locomotion_tree.tres should load")
	for state in STATE_CLIPS:
		check(sm.has_node(state), "the tree should have a %s state" % state)
		eq(_clip_of(sm.get_node(state)), STATE_CLIPS[state], "%s plays its spec'd clip" % state)
	check(sm.has_node("CROUCH"), "the tree should have a CROUCH state")
	# Six states plus the Start and End the root machine always carries.
	eq(sm.get_node_list().size(), 8, "six states, plus Start and End")

# Every clip of hers carries the `SET ` prefix as of the 2026-09-03 export - the user's marker
# for "this action belongs to Setsuna" rather than to EXIA or to the PLACEHOLDER junk that rides
# along in the same GLB. A state naming an unprefixed clip is naming something that is either
# gone or was never hers.
func test_every_clip_the_tree_plays_is_one_of_setsunas() -> void:
	var sm := _tree()
	for state in sm.get_node_list():
		for clip in _clips_of(sm.get_node(state)):
			check(clip.begins_with("SET "), "%s plays '%s', which is not a SET clip" % [state, clip])

# A clip renamed or dropped in a re-export leaves an AnimationNodeAnimation pointing at nothing,
# and the state silently plays no motion at all. setsuna_import.gd's allow-list is the switch
# that decides this, so this is really a test of the two files agreeing.
func test_every_clip_the_tree_names_is_in_the_export() -> void:
	var ap := _anim_player()
	check(ap != null, "the imported GLB should have an AnimationPlayer")
	var sm := _tree()
	for state in sm.get_node_list():
		for clip in _clips_of(sm.get_node(state)):
			check(ap.has_animation(clip), "%s plays '%s', which is not in the export" % [state, clip])

# The crouch is three static poses rather than a cycle: LEFT and RIGHT are the crouch leaning to
# one side and the plain loop is the upright crouch between them. player.gd puts the axis on
# whichever way she is turning, so the lean reads as her banking into the corner.
func test_crouch_is_a_blend_space_over_the_three_poses() -> void:
	var crouch := _tree().get_node("CROUCH") as AnimationNodeBlendSpace1D
	check(crouch != null, "CROUCH should be a BlendSpace1D")
	eq(crouch.min_space, -1.0, "the axis runs from a full left lean")
	eq(crouch.max_space, 1.0, "to a full right lean")
	check(crouch.sync, "sync keeps the three poses' playheads aligned through the blend")
	eq(crouch.get_blend_point_count(), CROUCH_POINTS.size(), "three points: left, neutral, right")
	for i in CROUCH_POINTS.size():
		eq(crouch.get_blend_point_position(i), CROUCH_POINTS[i][0], "crouch point %d sits at its spec'd position" % i)
		eq(_clip_of(crouch.get_blend_point_node(i)), CROUCH_POINTS[i][1], "crouch point %d plays its spec'd pose" % i)

# The three speed-scaled states. player.gd drives "parameters/<state>/TimeScale/scale", which
# only exists if the state is a blend tree with the node named exactly TimeScale wired to the
# output. RUN is one of them since SPRINT LOOP was dropped: the gait change is a playback rate on
# the one run cycle now, where it used to be a blend between two clips. JUMP is the odd one -
# its rate never changes, it is just permanently doubled.
func test_the_scaled_states_route_their_clip_through_a_timescale() -> void:
	var sm := _tree()
	for state in ["RUN", "DASH", "JUMP"]:
		var bt := sm.get_node(state) as AnimationNodeBlendTree
		check(bt != null, "%s should be a blend tree" % state)
		check(bt.has_node("TimeScale"), "%s needs a node named TimeScale" % state)
		check(bt.get_node("TimeScale") is AnimationNodeTimeScale, "%s/TimeScale is a TimeScale" % state)
		# Flat triples of [to node, input index, from node] - the blend tree exposes its wiring
		# as this property and nothing else.
		eq(bt.get("node_connections"), [&"output", 0, &"TimeScale", &"TimeScale", 0, &"Animation"],
			"%s wires its clip through the TimeScale into the output" % state)

# --- transitions -----------------------------------------------------------

func test_the_transition_table_matches_the_spec() -> void:
	var sm := _tree()
	var got: Array = []
	for i in sm.get_transition_count():
		var t := sm.get_transition(i)
		if t.advance_mode == TRAVEL:
			continue
		got.append([String(sm.get_transition_from(i)), String(sm.get_transition_to(i)),
			snappedf(t.xfade_time, 0.001), t.switch_mode, t.advance_mode, String(t.advance_condition)])
	eq(got, TABLE, "the condition-driven transitions, in order")

# Nothing in her set is an authored transition any more, so every hand-off between two states has
# to carry a real crossfade or it is a hard cut on screen. Start -> IDLE is the exception: there
# is no outgoing pose to fade from on the first frame.
func test_every_transition_crossfades() -> void:
	var sm := _tree()
	for i in sm.get_transition_count():
		var from := String(sm.get_transition_from(i))
		if from == "Start":
			continue
		check(sm.get_transition(i).xfade_time > 0.0,
			"%s -> %s is a hard cut" % [from, sm.get_transition_to(i)])

# The invariant the whole table rests on. Godot resolves two eligible transitions out of one
# state by taking the At End one and dropping the Immediate one on the floor - not by order, not
# by priority - so a state with two live exits does not do the more urgent thing, it does the
# later one. Every case below has to leave exactly one exit open, or a move is silently lost.
#
# Sweeps every world state player.gd can write: on the floor or not, holding a direction or not,
# crouching or not. The four bools are mutually exclusive by construction now, which is what
# retired the pre-ANDed polarity pairs the old gait-split table needed.
func test_no_state_ever_has_two_live_exits() -> void:
	var sm := _tree()
	for on_floor in [true, false]:
		for pressing in [true, false]:
			for is_crouching in [true, false]:
				var live := _conditions(on_floor, pressing, is_crouching)
				var world := "on_floor=%s pressing=%s crouching=%s" % [on_floor, pressing, is_crouching]
				eq(live.size(), 1, "exactly one condition is live at %s" % world)
				for state in sm.get_node_list():
					var open: PackedStringArray = []
					for i in sm.get_transition_count():
						var t := sm.get_transition(i)
						if String(sm.get_transition_from(i)) != String(state) or t.advance_mode != AUTO:
							continue
						var cond := String(t.advance_condition)
						if cond == "" or live.has(cond):
							open.append(String(sm.get_transition_to(i)))
					check(open.size() <= 1, "%s has %d live exits (%s) at %s"
						% [state, open.size(), ", ".join(open), world])

# The four condition bools, derived exactly as the tail of player.gd's _physics_process derives
# them. Returns the ones that are true - and there is always exactly one.
func _conditions(on_floor: bool, pressing: bool, is_crouching: bool) -> PackedStringArray:
	var live: PackedStringArray = []
	if not on_floor:
		live.append("off_floor")
		return live
	if is_crouching:
		live.append("crouching")
		return live
	live.append("moving" if pressing else "not_moving")
	return live

# The spec's two Any State rows. One hop from everywhere else means travel() crossfades in over
# TRAVEL_XFADE instead of teleporting, which is what Godot does when it can find no path.
func test_the_script_driven_entries_reach_every_other_state() -> void:
	var sm := _tree()
	var states: Array = []
	for state in sm.get_node_list():
		if state != "Start" and state != "End":
			states.append(String(state))
	for target: String in TRAVEL_TARGETS:
		for from: String in states:
			var expected: bool = from != target
			var linked: bool = sm.has_transition(from, target) and _mode(sm, from, target) == TRAVEL
			eq(linked, expected,
				"%s -> %s should%s be a travel-only transition" % [from, target, "" if expected else " not"])

func test_the_script_driven_entries_never_auto_fire() -> void:
	var sm := _tree()
	var count := 0
	for i in sm.get_transition_count():
		var t := sm.get_transition(i)
		if t.advance_mode != TRAVEL:
			continue
		count += 1
		check(TRAVEL_TARGETS.has(String(sm.get_transition_to(i))),
			"only the jump and the dash are entered by travel()")
		eq(String(t.advance_condition), "", "a travel-only transition carries no condition")
		eq(t.switch_mode, IMMEDIATE, "the jump and the dash start on the press, not at a clip end")
		approx(t.xfade_time, TRAVEL_XFADE, 0.001, "the discrete moves get the shortest crossfade")
	eq(count, 10, "five states each into JUMP and DASH")

func _mode(sm: AnimationNodeStateMachine, from: String, to: String) -> int:
	var i := _index(sm, from, to)
	return -1 if i < 0 else sm.get_transition(i).advance_mode

func _index(sm: AnimationNodeStateMachine, from: String, to: String) -> int:
	for i in sm.get_transition_count():
		if String(sm.get_transition_from(i)) == from and String(sm.get_transition_to(i)) == to:
			return i
	return -1

# --- the script's half of the contract -------------------------------------

# A condition the tree reads and player.gd never writes is a transition that can never fire, and
# nothing anywhere reports it - the state just sits there. Cheapest possible guard: the parameter
# path has to appear in the source.
func test_player_gd_writes_every_condition_the_tree_reads() -> void:
	var f := FileAccess.open(PLAYER_SCRIPT, FileAccess.READ)
	check(f != null, "scripts/player.gd should be readable")
	var src := f.get_as_text()
	var sm := _tree()
	var seen: Dictionary = {}
	for i in sm.get_transition_count():
		var cond := String(sm.get_transition(i).advance_condition)
		if cond == "" or seen.has(cond):
			continue
		seen[cond] = true
		check(src.contains("parameters/conditions/%s\"" % cond),
			"player.gd never writes parameters/conditions/%s" % cond)
	eq(seen.size(), 4, "four condition bools drive the table")

# The other four parameter paths the script drives by name.
func test_player_gd_drives_the_crouch_axis_and_every_time_scale() -> void:
	var f := FileAccess.open(PLAYER_SCRIPT, FileAccess.READ)
	check(f != null, "scripts/player.gd should be readable")
	var src := f.get_as_text()
	for path in ["parameters/RUN/TimeScale/scale", "parameters/DASH/TimeScale/scale",
			"parameters/JUMP/TimeScale/scale", "parameters/CROUCH/blend_position"]:
		check(src.contains(path), "player.gd should drive %s" % path)

# JUMP's rate is the one that is a constant rather than a calculation, so it is the one that can
# quietly go back to 1.0 - a TimeScale left unwritten is not an error anywhere, the cycle just
# plays at its authored cadence again and reads as a pose on a short hop.
func test_the_airborne_cycle_plays_at_double_speed() -> void:
	var f := FileAccess.open(PLAYER_SCRIPT, FileAccess.READ)
	check(f != null, "scripts/player.gd should be readable")
	var src := f.get_as_text()
	check(src.contains("const JUMP_CLIP_SCALE = 2.0"), "the airborne cycle runs at 2x")
	check(src.contains("anim_tree[\"parameters/JUMP/TimeScale/scale\"] = JUMP_CLIP_SCALE"),
		"player.gd should write JUMP_CLIP_SCALE into the JUMP TimeScale")

# --- the crouch lean --------------------------------------------------------

# The crouch is three held poses and this function, so an axis that silently never leaves 0 is a
# CROUCH state that sits upright forever - no error anywhere, and it looks exactly like a lean
# that was never wired. The sign is the other silent one: get it backwards and she banks out of
# every corner instead of into it, which is a perfectly ordinary-looking animation.
#
# The input is her signed heading lag in radians, positive going left (her nose is local +Z, so
# her right is local -X and turning that way *decreases* rotation.y). The axis is signed the
# other way round, +1 being the right-hand pose, so a right turn is a negative lag.
const LEAN_TURNS := [
	[0.0, 0.0, "pointing where she is going"],
	[-deg_to_rad(45.0), 1.0, "a hard right turn"],
	[deg_to_rad(45.0), -1.0, "a hard left turn"],
	[-deg_to_rad(7.5), 0.5, "an easy right turn"],
	[deg_to_rad(7.5), -0.5, "an easy left turn"],
]

# Holds one turn long enough for the ease to arrive and returns where the axis lands.
func _hold_turn(player: Node, lag: float, frames: int) -> float:
	var axis := 0.0
	for i in frames:
		axis = player._step_crouch_lean(lag, 1.0 / 60.0)
	return axis

func test_the_crouch_lean_banks_into_the_turn() -> void:
	var player = Player.new()
	for row in LEAN_TURNS:
		# From upright each time: what the axis settles on is this turn, not the last one.
		player._crouch_lean = 0.0
		var axis := _hold_turn(player, row[0], 120)
		approx(axis, row[1], 0.0001, "%s should hold axis %.1f" % [row[2], row[1]])
	player.free()

# Past CROUCH_LEAN_ANGLE she is already all the way over, so a sharper corner cannot push the
# axis off the end of the blend space and onto a pose that isn't there.
func test_the_crouch_lean_stays_on_the_blend_axis() -> void:
	var player = Player.new()
	for lag in [-PI, -PI * 0.5, PI * 0.5, PI]:
		player._crouch_lean = 0.0
		var axis := _hold_turn(player, lag, 120)
		check(axis >= -1.0 and axis <= 1.0, "a %.0f degree turn stays on the axis (got %.2f)"
			% [rad_to_deg(lag), axis])
	player.free()

# The poses are held, so the axis has to ease rather than snap - and it has to arrive inside the
# corner, which is what a lean speed set too low would fail. A tapped turn is over in about
# 0.3 s, so half a lean inside 0.1 s is the bar.
func test_the_crouch_lean_eases_but_keeps_up_with_the_corner() -> void:
	var player = Player.new()
	var first: float = player._step_crouch_lean(-deg_to_rad(45.0), 1.0 / 60.0)
	check(first > 0.0, "one frame of a right turn should have started the bank")
	check(first < 0.5, "the lean should ease rather than snap to the pose (got %.2f)" % first)
	var sixth: float = _hold_turn(player, -deg_to_rad(45.0), 5)
	check(sixth > 0.5, "the bank should be half over inside 0.1 s (got %.2f)" % sixth)
	# And straightening out brings her back upright.
	approx(_hold_turn(player, 0.0, 120), 0.0, 0.0001,
		"lining up with the input returns her to the upright crouch")
	player.free()

# SET Falling is the one clip of hers that does not loop cleanly - its first and last frames are
# ~29 degrees apart across the legs and arms, so LOOP_LINEAR snaps once a second on a long drop.
# The fake is to ping-pong it: forwards, then straight back down, so the only join is the clip
# against its own mirror and the pose either end is identical by construction. Nothing reports a
# clip quietly going back to LOOP_LINEAR, and the pop it brings back only shows on a *long* fall,
# so this pins the loop mode and the mismatch that is the reason for it.
func test_falling_ping_pongs_instead_of_looping() -> void:
	var f := FileAccess.open(PLAYER_SCRIPT, FileAccess.READ)
	check(f != null, "scripts/player.gd should be readable")
	var src := f.get_as_text()
	check(src.contains("get_animation(ANIM_FALL).loop_mode = Animation.LOOP_PINGPONG"),
		"player.gd should ping-pong SET Falling rather than loop it")
	check(src.contains("const ANIM_FALL := \"SET Falling\""),
		"player.gd should name the falling clip as exported")
	check(not src.contains("\"SET JUMP LOOP\", \"SET Falling\""),
		"SET Falling should be out of the LOOP_LINEAR list - it is set apart, below it")

# The widest end-to-end gap across `clip`'s rotation tracks, in degrees - how far the pose has to
# snap back when the clip wraps.
func _loop_gap_degrees(clip: Animation) -> float:
	var worst := 0.0
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var first: Quaternion = clip.rotation_track_interpolate(track, 0.0)
		var last: Quaternion = clip.rotation_track_interpolate(track, clip.length)
		worst = maxf(worst, rad_to_deg(first.angle_to(last)))
	return worst

# The mismatch itself, so that the day the poses are matched in Blender this fails and says the
# ping-pong can go. ~29 degrees as this export stands; anything inside a couple of degrees is a
# clip that loops cleanly on its own and does not need the fake.
func test_falling_still_needs_the_fake() -> void:
	var gap := _loop_gap_degrees(_anim_player().get_animation("SET Falling"))
	check(gap > 2.0,
		"SET Falling's ends now match to %.1f degrees - the ping-pong fake can go" % gap)

# The other side of it: a clip that *does* loop cleanly is left on LOOP_LINEAR, so the ping-pong
# stays a fix for one broken clip rather than a house style. SET JUMP LOOP is the airborne cycle
# she hangs in for just as long, and it wraps without one.
func test_the_airborne_cycle_does_not_need_it() -> void:
	var gap := _loop_gap_degrees(_anim_player().get_animation("SET JUMP LOOP"))
	check(gap < 2.0,
		"SET JUMP LOOP wraps %.1f degrees out - it would need the same fake" % gap)

# The clip the vehicle handover plays raw, around the tree rather than through it. It is the one
# name in player.gd that is not reached via a state, so a rename in Blender breaks the climb into
# EXIA silently - begin_embark() just returns 0.0 and she is boarded on the spot.
func test_the_embark_clip_the_script_names_is_in_the_export() -> void:
	var f := FileAccess.open(PLAYER_SCRIPT, FileAccess.READ)
	check(f != null, "scripts/player.gd should be readable")
	check(f.get_as_text().contains("const ANIM_EMBARK := \"SET embark\""),
		"player.gd should name the embark clip as exported")
	check(_anim_player().has_animation("SET embark"), "'SET embark' should survive the import allow-list")
