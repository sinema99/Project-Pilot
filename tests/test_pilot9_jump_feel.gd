extends "res://tests/test_case.gd"

# Covers the jump weight pass. See docs/specs/pilot9-jump-feel.md.
#
# The thing this file exists to catch is that gravity went LOCAL. `jump_gravity` is pilot9's
# own, and get_gravity() stayed behind in _apply_slide_bonus() because `slide_slope_accel: 1.0`
# is documented against the 9.8 it returns. Anyone "tidying" the two back into one number, in
# either direction, breaks the other feature silently - a 2.6x slide is not a crash, it is a
# slide that feels wrong three commits later. The two source assertions at the bottom are the
# only thing standing between that and a play session.
#
# The other silent failure is `_coyote_left` not being zeroed by a jump. Nothing errors: the
# grace simply outlives the jump that used it, and a second press inside the window takes a
# free jump that never touches `_air_jumps_left`. It reads as the double jump being flaky
# rather than as coyote time being wrong.
#
# _gravity_scale() and _cut_rise() are static and fully parameterised so the whole arc can be
# integrated here with no tree and no Input. Nothing in this file enters the tree.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const DT := 1.0 / 60.0

var _instances: Array[Node] = []

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

func _script() -> GDScript:
	return load("res://scripts/pilot9.gd") as GDScript

func _source() -> String:
	var f := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	return f.get_as_text() if f != null else ""

# The body of a named function, from its `func` line to the next top-level `func`.
func _body(text: String, header: String) -> String:
	var start := text.find(header)
	if start < 0:
		return ""
	var rest := text.substr(start + header.length())
	var stop := rest.find("\nfunc ")
	return rest if stop < 0 else rest.substr(0, stop)

# The jump-feel pass's own values, applied to an instance so the tests below measure the
# MECHANISM rather than whatever the exports currently happen to be.
#
# They stopped being the same thing on 2026-09-10: the movement reset parked every assist in
# this file at a neutral value, and these tests were reading those exports straight off the
# scene, so all four of them started failing while the code they cover was untouched. The
# defaults are now guarded by tests/test_pilot9_movement_reset.gd, which is where a changed
# shipping value SHOULD fail. Here we switch the layer on and check it still works, so the
# feature stays covered while it is parked and the next tuning pass has something to trust.
#
# See docs/specs/pilot9-jump-feel.md for where each number comes from.
func _tuned(p: Node) -> Node:
	p.jump_height = 2.3
	p.jump_time_to_apex = 0.38
	p.jump_fall_multiplier = 1.9
	p.jump_cut = 0.4
	p.jump_apex_speed = 1.5
	p.jump_apex_scale = 0.6
	p.max_fall_speed = 28.0
	return p

# One jump, integrated the way _physics_process actually runs it: velocity is stepped first
# and the body moves on the stepped value (semi-implicit Euler, which is what move_and_slide()
# gives us), and the jump frame itself moves on the launch velocity before gravity has been
# applied once. Returns [apex, airtime].
func _arc(p: Node, held: bool, apex_speed: float = -1.0) -> Array:
	var s := _script()
	var band: float = p.jump_apex_speed if apex_speed < 0.0 else apex_speed
	var vy: float = p.jump_velocity
	var y := 0.0
	var t := DT
	var apex := 0.0
	y += vy * DT
	while y > 0.0 and t < 10.0:
		var sc: float = s._gravity_scale(vy, p.jump_fall_multiplier, band,
			p.jump_apex_scale)
		vy = maxf(vy - p.jump_gravity * sc * DT, -p.max_fall_speed)
		vy = s._cut_rise(vy, held, p.jump_velocity * p.jump_cut)
		y += vy * DT
		t += DT
		apex = maxf(apex, y)
	return [apex, t]

# --- _gravity_scale(): the asymmetry ---------------------------------------

# The one rule that makes the fall stop feeling like swimming.
func test_he_falls_harder_than_he_rises() -> void:
	var s := _script()
	# Outside the apex band in both directions, so only the asymmetry is in play.
	approx(s._gravity_scale(5.0, 1.9, 1.5, 0.6), 1.0, 0.0001,
		"rising is not plain gravity - the rise is supposed to be the reference")
	approx(s._gravity_scale(-5.0, 1.9, 1.5, 0.6), 1.9, 0.0001,
		"falling is not multiplied - a symmetric fall is most of what 'floaty' names")

# Zero is falling. It is the one frame the sign test could plausibly get wrong, and getting it
# wrong puts a rise-weight frame at the exact top of every jump.
func test_the_apex_frame_counts_as_falling() -> void:
	var s := _script()
	approx(s._gravity_scale(0.0, 1.9, 0.0, 0.6), 1.9, 0.0001,
		"vy == 0 was treated as rising")

# --- _gravity_scale(): the apex hang ---------------------------------------

func test_the_hang_relaxes_gravity_near_the_top() -> void:
	var s := _script()
	approx(s._gravity_scale(1.0, 1.9, 1.5, 0.6), 0.6, 0.0001,
		"rising inside the apex band was not relaxed")
	approx(s._gravity_scale(-1.0, 1.9, 1.5, 0.6), 1.9 * 0.6, 0.0001,
		"falling inside the apex band was not relaxed - the hang has to be symmetric or the " +
		"top of the arc has a kink in it")

func test_the_apex_band_is_symmetric_about_zero() -> void:
	var s := _script()
	# Same distance from the apex, one either side: the band decision must match even though
	# the weights do not.
	var up: float = s._gravity_scale(1.4, 1.9, 1.5, 0.6)
	var down: float = s._gravity_scale(-1.4, 1.9, 1.5, 0.6)
	approx(up / 1.0, 0.6, 0.0001, "1.4 m/s up was outside the 1.5 band")
	approx(down / 1.9, 0.6, 0.0001, "1.4 m/s down was outside the 1.5 band")

func test_the_band_edge_is_exclusive_and_does_not_leak() -> void:
	var s := _script()
	approx(s._gravity_scale(1.5, 1.9, 1.5, 0.6), 1.0, 0.0001,
		"the speed AT the band edge was relaxed - the band is supposed to be strictly inside")
	approx(s._gravity_scale(1.6, 1.9, 1.5, 0.6), 1.0, 0.0001,
		"a speed outside the band was relaxed")

# Both dials have to switch the hang off, because the spec offers both as the way to do it.
func test_the_hang_can_be_switched_off() -> void:
	var s := _script()
	approx(s._gravity_scale(0.5, 1.9, 1.5, 1.0), 1.0, 0.0001,
		"apex_scale 1.0 did not disable the hang")
	approx(s._gravity_scale(0.5, 1.9, 0.0, 0.6), 1.0, 0.0001,
		"apex_speed 0.0 did not disable the hang")
	approx(s._gravity_scale(-0.5, 1.9, 0.0, 0.6), 1.9, 0.0001,
		"apex_speed 0.0 left the fall weight wrong")

# --- _cut_rise(): variable jump height -------------------------------------

func test_holding_the_button_never_cuts() -> void:
	var s := _script()
	approx(s._cut_rise(9.0, true, 3.9), 9.0, 0.0001,
		"a held jump was cut - every jump is the full arc while the button is down")

func test_letting_go_while_rising_clamps() -> void:
	var s := _script()
	approx(s._cut_rise(9.0, false, 3.9), 3.9, 0.0001,
		"releasing did not clamp the rise - without this every jump is the same jump and " +
		"the player has no authority over the arc")

# The clamp is a ceiling, not an assignment. Releasing late must not ADD height.
func test_the_cut_never_raises_a_slow_rise() -> void:
	var s := _script()
	approx(s._cut_rise(2.0, false, 3.9), 2.0, 0.0001,
		"a rise already below the cut speed was raised to it - the cut is a ceiling")

func test_the_cut_never_touches_a_fall() -> void:
	var s := _script()
	approx(s._cut_rise(-12.0, false, 3.9), -12.0, 0.0001,
		"the cut reached a falling velocity")
	approx(s._cut_rise(0.0, false, 3.9), 0.0, 0.0001,
		"the cut reached the apex frame")

# --- the derived pair ------------------------------------------------------

# The whole reparameterisation, checked by running it backwards: the height and the time the
# designer typed have to be the height and the time the physics produces.
func test_the_derived_pair_reproduces_the_height_and_the_time() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var v: float = root.jump_velocity
	var g: float = root.jump_gravity
	approx(v * v / (2.0 * g), root.jump_height, 0.0001,
		"v^2/2g does not come back to jump_height - the derivation is wrong")
	approx(v / g, root.jump_time_to_apex, 0.0001,
		"v/g does not come back to jump_time_to_apex - the derivation is wrong")

func test_the_derived_pair_tracks_the_dials() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.jump_height = 3.0
	root.jump_time_to_apex = 0.5
	approx(root.jump_velocity, 12.0, 0.0001, "jump_velocity did not follow jump_height")
	approx(root.jump_gravity, 24.0, 0.0001, "jump_gravity did not follow jump_time_to_apex")

# --- the shipping arc ------------------------------------------------------

# The regression fence. These are the numbers the pass was built to produce, integrated
# through the real functions at the real tick rate.
#
# NOT the shipping arc any more - the 2026-09-10 reset parked it, and pilot9 currently jumps
# the slower pre-pass arc. This measures what the jump-feel values DO when they are switched
# back on, which is the thing worth fencing: the arc a future tuning pass will be restoring
# toward. tests/test_pilot9_movement_reset.gd owns what actually ships.
func test_the_jump_feel_values_still_produce_the_specced_arc() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_tuned(root)
	approx(root.jump_velocity, 12.1053, 0.001, "the launch speed moved")
	approx(root.jump_gravity, 31.8560, 0.001, "the rise gravity moved")
	var arc := _arc(root, true)
	approx(arc[0], 2.4246, 0.01,
		"the apex moved - every lip in the map is measured against what he can reach")
	approx(arc[1], 0.7333, 0.01,
		"the airtime moved - this is the whole point of the pass, and it is also what sets " +
		"how far a running jump carries")

# The property that makes `jump_height` safe to turn on its own, and the reason raising it from
# 1.85 m to 2.3 m cost nothing: rise time is `jump_time_to_apex` by construction and fall time
# is t_apex / sqrt(fall_multiplier), neither of which has a height in it. Airtime - and
# therefore every gap he can cross - belongs to `jump_time_to_apex` ALONE.
#
# Checked with the hang off, because that is where the property is exact. See the test below
# for the one thing that spoils it.
#
# Tolerance is ONE FRAME, not a sub-millisecond epsilon. _arc() integrates at 60 Hz and counts
# whole frames, so which side of a frame boundary the landing falls on is worth 16.7 ms of
# measured airtime on its own - and a taller jump moves faster through the last frame, so it
# lands on a different side of it. That is quantisation, not a height term. A real leak would
# scale with the height ratio and blow straight past a frame.
func test_height_does_not_change_the_airtime() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var tall := _arc(root, true, 0.0)
	root.jump_height = 1.0
	var short := _arc(root, true, 0.0)
	check(short[0] < tall[0] * 0.6, "lowering jump_height did not lower the apex")
	approx(short[1], tall[1], DT + 0.0001,
		"a 1.0 m jump and a 3.0 m jump differ by more than a frame of airtime - height is " +
		"leaking into the clock, and therefore into how far a running jump carries")

# ...and the exception, which is worth knowing about before someone tunes the height a long
# way down. `jump_apex_speed` is an absolute m/s band, so a SHORTER jump - which is a weaker
# gravity - dwells inside it longer and picks up more hang. A 1.0 m jump runs about 50 ms
# longer than a 2.3 m one for that reason and no other.
#
# Harmless at the heights this game uses, and the fix if it ever stops being harmless is to
# scale `jump_apex_speed` off `jump_velocity` rather than dialling it in metres per second.
func test_the_apex_hang_is_the_one_thing_height_leaks_through() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_tuned(root)
	var tall := _arc(root, true)
	root.jump_height = 1.0
	var short := _arc(root, true)
	check(short[1] > tall[1],
		"a shorter jump did not pick up more hang - if this ever stops being true the band " +
		"has been changed and the comment above is stale")
	check(short[1] - tall[1] < 0.1,
		("the hang added %.3f s to a 1.0 m jump over a 2.3 m one - that is no longer a " +
		"rounding difference, and jump_apex_speed should be scaled off jump_velocity") %
		(short[1] - tall[1]))

# The floatiness claim, stated as a comparison rather than a constant: whatever the numbers
# are, the jump has to be meaningfully quicker than the 1.22 s it replaced.
func test_the_jump_is_faster_than_the_one_it_replaced() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_tuned(root)
	var arc := _arc(root, true)
	check(arc[1] < 0.85,
		("airtime is %.3f s - the jump this pass replaced was 1.22 s and the complaint was " +
		"that it was floaty") % arc[1])

# A tap has to be a materially different jump from a hold, or the cut is decorative.
func test_a_tap_is_a_hop_and_a_hold_is_the_full_arc() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_tuned(root)
	var tap := _arc(root, false)
	var hold := _arc(root, true)
	check(tap[0] < hold[0] * 0.5,
		("a tap reached %.2f m against a hold's %.2f m - the cut is not doing enough to be " +
		"felt") % [tap[0], hold[0]])
	check(tap[0] > 0.35,
		("a tap reached only %.2f m - too low to clear anything, which makes the cut a " +
		"punishment rather than a choice") % tap[0])

# --- terminal velocity -----------------------------------------------------

func test_a_long_fall_is_clamped() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var vy := 0.0
	var s := _script()
	for i in 600:
		var sc: float = s._gravity_scale(vy, root.jump_fall_multiplier, root.jump_apex_speed,
			root.jump_apex_scale)
		vy = maxf(vy - root.jump_gravity * sc * DT, -root.max_fall_speed)
	approx(vy, -root.max_fall_speed, 0.0001,
		"a ten-second fall did not settle at max_fall_speed")

# The map's tallest lip is 13.3 m and the clamp is only supposed to bite well into a drop -
# a short hop must never meet it, or the fall weight is a lie for the jumps people make most.
func test_a_short_fall_is_not_clamped() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var arc := _arc(root, true)
	check(arc[0] > 0.0, "the arc did not run")
	var vy := 0.0
	var y := 0.0
	var s := _script()
	while -y < 2.0:
		var sc: float = s._gravity_scale(vy, root.jump_fall_multiplier, root.jump_apex_speed,
			root.jump_apex_scale)
		vy = maxf(vy - root.jump_gravity * sc * DT, -root.max_fall_speed)
		y += vy * DT
	check(vy > -root.max_fall_speed,
		"a 2 m drop already hit terminal velocity - the clamp is far too low")

# --- the timers ------------------------------------------------------------

# The load-bearing line, and the one whose absence looks like a flaky double jump rather
# than like a coyote bug.
func test_a_jump_spends_the_coyote_window() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root._coyote_left = root.coyote_time
	root._take_floor_jump()
	approx(root._coyote_left, 0.0, 0.0001,
		"the coyote window survived the jump that used it - a second press inside it now " +
		"takes a free jump that never touches _air_jumps_left")

func test_the_floor_jump_leaves_him_standing_and_not_sliding() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.is_crouching = true
	root.is_sliding = true
	root._take_floor_jump()
	check(not root.is_crouching, "the jump was swallowed by the crouch")
	check(not root.is_sliding, "the jump did not leave the slide - it is the only early exit")
	approx(root.velocity.y, root.jump_velocity, 0.0001, "the jump did not launch him")
	check(root.is_jumping, "is_jumping was not set")

# All three ways of taking a floor jump have to BE the same jump, or coyote time and the
# buffer are two subtly different jumps wearing the floor jump's name.
func test_all_three_floor_jumps_are_the_same_jump() -> void:
	var src := _source()
	var body := _body(src, "func _handle_gravity_and_jump(delta: float) -> void:")
	if body == "":
		fail("could not find _handle_gravity_and_jump() in scripts/pilot9.gd")
		return
	eq(body.count("_take_floor_jump()"), 2,
		"the buffered jump and the coyote/floor press should both route through " +
		"_take_floor_jump() and nothing else should")
	eq(body.count("velocity.y = jump_velocity"), 2,
		"a floor jump path is assigning velocity.y itself instead of going through " +
		"_take_floor_jump() - only the mantle exit and the air jump may do that")

func test_the_buffer_only_arms_with_no_air_jump_left() -> void:
	var src := _source()
	var body := _body(src, "func _handle_gravity_and_jump(delta: float) -> void:")
	if body == "":
		fail("could not find _handle_gravity_and_jump() in scripts/pilot9.gd")
		return
	var arm := body.find("_jump_buffered = jump_buffer_time")
	var air := body.find("elif _air_jumps_left > 0:")
	check(arm >= 0, "the jump buffer is never armed")
	check(air >= 0 and air < arm,
		"the buffer is armed before the air-jump branch is considered - a press with a " +
		"double jump available would be banked for the landing instead of spent now")

func test_the_buffer_is_spent_on_the_floor_and_cleared() -> void:
	var src := _source()
	var body := _body(src, "func _handle_gravity_and_jump(delta: float) -> void:")
	if body == "":
		fail("could not find _handle_gravity_and_jump() in scripts/pilot9.gd")
		return
	check(body.contains("if is_on_floor() and _jump_buffered > 0.0:"),
		"the buffered jump is not spent on a grounded frame")
	var spend := body.find("if is_on_floor() and _jump_buffered > 0.0:")
	var press := body.find("if frozen or not Input.is_action_just_pressed(\"jump\"):")
	check(press >= 0 and spend < press,
		"the buffered jump is read after the fresh press - a player who both buffered and " +
		"pressed on the landing frame gets two reads of one intent")

func test_a_freeze_drops_both_graces() -> void:
	var src := _source()
	var body := _body(src, "func _handle_gravity_and_jump(delta: float) -> void:")
	if body == "":
		fail("could not find _handle_gravity_and_jump() in scripts/pilot9.gd")
		return
	var idx := body.find("if frozen:")
	check(idx >= 0, "there is no frozen branch clearing the graces")
	var after := body.substr(idx, 200)
	check(after.contains("_coyote_left = 0.0") and after.contains("_jump_buffered = 0.0"),
		"a freeze does not clear both the coyote window and the jump buffer - a stale press " +
		"firing on the frame he unpauses is not something anyone asked for")

func test_the_mantle_drops_both_graces() -> void:
	var src := _source()
	# In the entry snap since 2026-09-23 - the mantle is started from two places now
	# (_handle_mantle_trigger()'s two regimes), and both go through _start_climb().
	var body := _body(src, "func _start_climb(lip: Vector3, wall_normal: Vector3) -> void:")
	if body == "":
		fail("could not find _start_climb() in scripts/pilot9.gd")
		return
	check(body.contains("_coyote_left = 0.0") and body.contains("_jump_buffered = 0.0"),
		"a mantle does not clear the graces - _climb_jump_buffered is the only buffer that " +
		"should survive into the exit, and two racing to spend one press is one too many")

# --- gravity stayed local (the whole "don't break the slide" claim) --------

func test_the_jump_uses_its_own_gravity_and_not_the_projects() -> void:
	var src := _source()
	var body := _body(src, "func _handle_gravity_and_jump(delta: float) -> void:")
	if body == "":
		fail("could not find _handle_gravity_and_jump() in scripts/pilot9.gd")
		return
	check(not body.contains("get_gravity()"),
		"the jump is reading get_gravity() again - that is the project default (9.8, real " +
		"Earth) and it is what made the jump floaty in the first place")
	check(body.contains("jump_gravity"),
		"the jump is not reading jump_gravity")

func test_the_slide_still_reads_the_project_gravity() -> void:
	var src := _source()
	check(src.contains("get_gravity().length()"),
		"_apply_slide_bonus() no longer reads get_gravity() - `slide_slope_accel: 1.0` is " +
		"documented as real physics against the project's 9.8, and moving the slide onto " +
		"jump_gravity would make every slide 2.6x steeper")

func test_the_project_gravity_is_untouched() -> void:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		fail("could not read project.godot")
		return
	var text := f.get_as_text()
	check(not text.contains("default_gravity"),
		"project.godot now overrides gravity - that setting is also the slide's and EXIA's, " +
		"and a pilot's jump is not grounds for re-weighting the mech")
