extends "res://tests/test_case.gd"

# pilot9 boards EXIA. See docs/specs/pilot9-mech-mount.md.
#
# There is no mount animation: F is a cut both ways. pilot9 gets two of the six pilot-contract
# methods - enter_vehicle() and exit_vehicle() - and none of the four climb methods, so
# mech.gd's has_method-guarded fallback takes him aboard on the spot (_board() with seal_left
# at 0) and lets him out at ExitPoint (_can_climb_down() false).
#
# The contract is duck-typed and nothing asserts the two pilots share a shape, so these pin it
# from both ends: the methods pilot9 must answer, and the ones he must NOT - a climb quietly
# reappearing on him is as much a regression as a cut method going missing.

const PilotScript := preload("res://scripts/pilot9.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const TRIAL_TSCN := "res://scenes/trial.tscn"
const MechScene := preload("res://scenes/mech.tscn")

var _pilot: Node = null
var _instances: Array[Node] = []

# Setsuna's shape, for the riding half of the _board() guard: a pilot WITH ride() still rides
# spine.003 shut.
class _RidingPilot extends Node3D:
	var boarded := false
	func enter_vehicle(_vehicle: Node3D) -> void:
		boarded = true
	func exit_vehicle(_pos: Vector3, _yaw: float) -> void:
		pass
	func ride(_seat: Transform3D) -> void:
		pass

# One shared in-tree pilot9. enter_vehicle()/exit_vehicle() reach @onready nodes and write
# global_position, both of which are errors on a CharacterBody3D with no tree above it, and an
# in-tree scene per test piles up render/physics RIDs a --script run never frees. Reset to a
# known state each call - a shared instance means the last test's writes would bleed on.
func _pilot9() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.is_climbing = false
	_pilot.is_sliding = false
	_pilot.is_slide_holding = false
	_pilot.is_crouching = false
	_pilot.sprint_toggled = false
	_pilot.is_sprinting = false
	_pilot.is_walking = false
	_pilot._slide_buffered = false
	_pilot._slide_cooldown_left = 0.0
	_pilot._climb_end_position = Vector3.ZERO
	_pilot._climb_start_position = Vector3.ZERO
	_pilot.velocity = Vector3.ZERO
	_pilot.visible = true
	_pilot.collision_shape.disabled = false
	_pilot.set_physics_process(true)
	_pilot.set_process_unhandled_input(true)
	_pilot.anim_tree.active = true
	_pilot.global_position = Vector3.ZERO
	_pilot.character.rotation = Vector3.ZERO
	_pilot.camera_pivot.rotation = Vector3.ZERO
	return _pilot

func _instantiate(path: String) -> Node:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	return n

func _instantiate_in_tree(scene: PackedScene) -> Node:
	if scene == null:
		return null
	var n := scene.instantiate()
	_instances.append(n)
	var loop := Engine.get_main_loop() as SceneTree
	if loop:
		loop.root.add_child(n)
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

# --- the contract, both ends ---------------------------------------------------

func test_pilot9_answers_the_two_cut_methods_and_none_of_the_climb() -> void:
	var methods := {}
	var arg_counts := {}
	var script: GDScript = load("res://scripts/pilot9.gd")
	for m in script.get_script_method_list():
		methods[String(m.name)] = true
		arg_counts[String(m.name)] = (m.args as Array).size()
	check(methods.has("enter_vehicle"),
		"mech.gd only arms the 'F pilot' prompt for bodies with enter_vehicle()")
	check(methods.has("exit_vehicle"), "F while piloting has to hand him back")
	eq(arg_counts.get("exit_vehicle", -1), 2,
		"exit_vehicle(exit_position, facing_yaw) - duck-typed, so the signature is pinned here")
	check(not methods.has("ride"),
		"pilot9 must NOT have ride(): it is the guard mech.gd::_board() gates seal_left on, and " +
		"a no-op ride() would buy 2 s of canopy beat with nothing on screen to explain it")
	for climb_method in ["embark_length", "begin_embark", "begin_unseal", "begin_disembark"]:
		check(not methods.has(climb_method),
			"pilot9 has no climb, so %s must stay absent - a climb quietly appearing is caught here"
			% climb_method)

# --- enter_vehicle ----------------------------------------------------------

func test_enter_vehicle_hides_him_and_stops_his_body() -> void:
	var p := _pilot9()
	if p == null:
		fail("scenes/pilot9.tscn did not load"); return
	p.enter_vehicle(null)
	check(not p.visible, "he disappears on the frame F is pressed")
	check(p.collision_shape.disabled, "his collision shape is switched off aboard")
	check(not p.is_physics_processing(), "his _physics_process is stopped")
	check(not p.is_processing_unhandled_input(), "his input handler is stopped")
	check(not p.anim_tree.active, "the locomotion tree is switched off while EXIA drives")

func test_boarding_ends_every_live_verb() -> void:
	var cases := [
		{"flags": {"is_sliding": true}, "what": "mid-slide"},
		{"flags": {"is_sliding": true, "is_slide_holding": true}, "what": "mid-held-slide"},
		{"flags": {"is_crouching": true}, "what": "mid-crouch"},
		{"flags": {"is_climbing": true}, "what": "mid-mantle"},
	]
	for c in cases:
		var p := _pilot9()
		if p == null:
			fail("scenes/pilot9.tscn did not load"); return
		for k in (c["flags"] as Dictionary):
			p.set(k, true)
		p.enter_vehicle(null)
		check(not p.is_sliding, "%s: is_sliding left set" % c["what"])
		check(not p.is_slide_holding, "%s: is_slide_holding left set" % c["what"])
		check(not p.is_crouching, "%s: is_crouching left set" % c["what"])
		check(not p.is_climbing, "%s: is_climbing left set" % c["what"])

func test_boarding_clears_the_air_slide_buffer_and_the_gaits() -> void:
	var p := _pilot9()
	if p == null:
		fail("scenes/pilot9.tscn did not load"); return
	p._slide_buffered = true
	p.sprint_toggled = true
	p.is_sprinting = true
	p.is_walking = true
	p.enter_vehicle(null)
	check(not p._slide_buffered,
		"a queued air-slide press would fire the instant he is handed back on the ground")
	check(not p.sprint_toggled and not p.is_sprinting and not p.is_walking,
		"the gaits are cleared so he does not resume a run he started before the drive")

# --- exit_vehicle ---------------------------------------------------------

func test_exit_vehicle_places_faces_and_aims_him() -> void:
	var p := _pilot9()
	if p == null:
		fail("scenes/pilot9.tscn did not load"); return
	p.enter_vehicle(null)
	var spot := Vector3(4.0, 1.0, -9.0)
	p.exit_vehicle(spot, 1.2)
	approx(p.global_position.distance_to(spot), 0.0, 0.001, "he lands exactly where ExitPoint is")
	approx(p.character.rotation.y, 1.2, 0.001,
		"the MESH child faces the given yaw - the body's own yaw is never written")
	approx(wrapf(p.camera_pivot.rotation.y - (1.2 + PI), -PI, PI), 0.0, 0.001,
		"camera_pivot sits half a turn round: behind him, looking at the machine")
	approx(p.camera_pivot.rotation.x, PilotScript.EXIT_PITCH, 0.001, "and at the fixed exit pitch")
	check(p.camera_3d.current, "his camera takes the picture; mech.gd then pans the view into it")

func test_exit_vehicle_restores_his_body_and_starts_locomotion() -> void:
	var p := _pilot9()
	if p == null:
		fail("scenes/pilot9.tscn did not load"); return
	p.enter_vehicle(null)
	p.exit_vehicle(Vector3.ZERO, 0.0)
	check(p.visible, "he is back on screen")
	check(not p.collision_shape.disabled, "his collision shape is back")
	check(p.is_physics_processing(), "his _physics_process is running again")
	check(p.is_processing_unhandled_input(), "his input handler is back")
	check(p.anim_tree.active, "the locomotion tree has the skeleton again")
	var playback = p.anim_tree["parameters/playback"]
	check(playback != null, "the tree exposes parameters/playback")

# "Starts the state machine at Locomotion" resists a headless behaviour check: playback.start()
# only records a request, the target becomes current on the next processed frame, and with no
# floor under a --script pilot9 the advance expressions then carry him straight to `fall`
# whatever he was started in - so start(&"Locomotion") and no start() at all look identical a
# frame later. Pinned instead as: the call is in exit_vehicle(), and its target is a real state.
func test_exit_vehicle_starts_the_machine_at_a_real_locomotion_state() -> void:
	var p := _pilot9()
	if p == null:
		fail("scenes/pilot9.tscn did not load"); return
	var sm := p.anim_tree.tree_root as AnimationNodeStateMachine
	check(sm != null and sm.has_node("Locomotion"),
		"the tree has no `Locomotion` state for playback.start() to land on - pilot9's idle is " +
		"a corner of the Locomotion blend tree, so that is the state exit_vehicle() names")

	var f := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	check(f != null, "scripts/pilot9.gd is unreadable")
	if f != null:
		var src := f.get_as_text()
		check(src.contains("exit_vehicle") and src.contains("playback.start(&\"Locomotion\")"),
			"exit_vehicle() must start the state machine outright - board him mid-jump and the " +
			"tree is parked in jump/fall, and trusting the expressions to walk back steps him " +
			"out of a powered-down mech into a fall")

# --- a real round trip through mech.tscn ---------------------------------------

func test_a_board_exit_round_trip_ends_at_exitpoint_with_the_mech_empty() -> void:
	var exia := _instantiate_in_tree(MechScene)
	var p := _pilot9()
	if exia == null or p == null:
		fail("could not stand up EXIA + pilot9"); return
	exia.global_position = Vector3(0, 0, -12)
	p.global_position = Vector3(0, 0, -6)
	exia.player_in_range = p

	exia._enter_mech()
	eq(exia.pilot, p, "F took him aboard")
	check(not p.visible, "and he is hidden on the spot - there is no climb to watch")
	approx(exia.seal_left, 0.0, 0.0001, "no ride() on pilot9, so no canopy beat")

	exia._exit_mech()
	eq(exia.pilot, null, "F again left the mech unpiloted")
	approx(p.global_position.distance_to(exia.exit_point.global_position), 0.0, 0.01,
		"he is put out at ExitPoint, 3.6 m off the back of the machine")
	check(p.visible, "and back on screen")

# The other side of the guard: Setsuna's shape - a pilot WITH ride() - still gets the canopy
# beat. seal_left > 0 and enter_vehicle() held back until the seal finishes.
func test_a_pilot_with_ride_still_gets_the_canopy_beat() -> void:
	var exia := _instantiate_in_tree(MechScene)
	if exia == null:
		fail("could not stand up EXIA"); return
	var pilot := _RidingPilot.new()
	exia.add_child(pilot)
	exia.pilot = pilot
	exia._board()
	check(exia.seal_left > 0.0,
		"a pilot with ride() rides spine.003 shut over MECH_launch's length before being hidden")
	check(not pilot.boarded,
		"enter_vehicle() waits for the seal, so a riding pilot is still on screen after _board()")

# --- trial.tscn -------------------------------------------------------------

func test_trial_carries_exia_and_its_cel_pass() -> void:
	var root := _instantiate(TRIAL_TSCN)
	if root == null:
		fail("scenes/trial.tscn did not load"); return
	var exia := root.get_node_or_null("EXIA")
	check(exia is CharacterBody3D, "trial.tscn has no EXIA CharacterBody3D")
	if exia:
		var scr := exia.get_script() as Script
		check(scr != null and scr.resource_path == "res://scripts/mech.gd",
			"EXIA is not driven by scripts/mech.gd")
		check(exia.get_node_or_null("Model") != null,
			"EXIA has no Model node for the cel pass to target")
	var applier := root.get_node_or_null("ApplyCelMech")
	check(applier != null, "trial.tscn has no ApplyCelMech")
	if applier:
		check(applier.material != null, "ApplyCelMech has no material assigned")
		check(applier.targets.size() == 1 and str(applier.targets[0]) == "../EXIA/Model",
			"ApplyCelMech no longer targets ../EXIA/Model")
