extends "res://tests/test_case.gd"

# Two pilot9s in the trial, 1 and 2 to swap between them, the second wearing
# PILOT9decimateTest's body. See docs/specs/pilot-switch.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const TRIAL_TSCN := "res://scenes/trial.tscn"
const DECIMATE_GLB := "res://assets/pilot9_decimate.glb"
const SwitcherScript := preload("res://scripts/pilot_switcher.gd")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _skeleton_meshes(pilot: Node) -> Array[Node]:
	var skel := pilot.get_node("character/Armature/GeneralSkeleton")
	var out: Array[Node] = []
	for c in skel.get_children():
		if c is MeshInstance3D:
			out.append(c)
	return out

func _vertex_total(meshes: Array[Node]) -> int:
	var n := 0
	for m in meshes:
		var mesh := (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n

# A switcher over two fresh in-tree pilots, the second wearing the decimated body.
func _rig() -> Dictionary:
	var ps := load(PILOT_TSCN) as PackedScene
	var root := Node3D.new()
	var a := ps.instantiate()
	a.name = &"A"
	var b := ps.instantiate()
	b.name = &"B"
	b.body_glb = load(DECIMATE_GLB)
	root.add_child(a)
	root.add_child(b)
	b.position = Vector3(1.5, 0, 0)
	var sw := SwitcherScript.new()
	sw.pilots = [NodePath("../A"), NodePath("../B")] as Array[NodePath]
	root.add_child(sw)
	_tree().root.add_child(root)
	return {"root": root, "a": a, "b": b, "sw": sw}

func _press_key(sw: Node, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	sw._unhandled_input(ev)

func test_trial_has_both_pilots_original_first() -> void:
	var trial := (load(TRIAL_TSCN) as PackedScene).instantiate()
	var original := trial.get_node_or_null("Pilot9")
	var decimate := trial.get_node_or_null("Pilot9Decimate")
	check(original != null and decimate != null, "trial carries Pilot9 and Pilot9Decimate")
	if original != null and decimate != null:
		check(original.body_glb == null, "the original keeps pilot9.tscn's own body")
		check(decimate.body_glb != null and decimate.body_glb.resource_path == DECIMATE_GLB,
			"the second pilot wears pilot9_decimate.glb")
		approx(decimate.position.distance_to(original.position), 1.5, 0.01,
			"the second pilot stands next to the first")
	var sw := trial.get_node_or_null("PilotSwitcher")
	check(sw != null, "trial has a PilotSwitcher")
	if sw != null:
		eq(sw.pilots, [NodePath("../Pilot9"), NodePath("../Pilot9Decimate")] as Array[NodePath],
			"1 is the original, 2 the decimated one")
		check(sw.get_index() > decimate.get_index(), "the switcher readies after both pilots")
	var cel := trial.get_node_or_null("ApplyCelPilot9")
	check(cel != null and cel.targets.has(NodePath("../Pilot9Decimate")),
		"the pilot cel material reaches the second pilot too")
	trial.free()

func test_body_glb_replaces_the_meshes_on_the_same_skeleton() -> void:
	var r := _rig()
	var a_meshes := _skeleton_meshes(r.a)
	var b_meshes := _skeleton_meshes(r.b)
	var b_names: Array = b_meshes.map(func(m: Node) -> String: return String(m.name))
	check(b_names.has("Cube") and not b_names.has("Cube_048"),
		"B's skeleton holds the decimated GLB's meshes, not pilot9.tscn's: %s" % [b_names])
	check(_vertex_total(b_meshes) * 10 < _vertex_total(a_meshes),
		"B's body is the decimated one (%d verts vs %d)" % [_vertex_total(b_meshes), _vertex_total(a_meshes)])
	var skel: Node = r.b.get_node("character/Armature/GeneralSkeleton")
	for m in b_meshes:
		var mi := m as MeshInstance3D
		check(mi.get_node_or_null(mi.skeleton) == skel and mi.skin != null,
			"%s is skinned to B's own skeleton" % mi.name)
	check(r.a.anim_tree.anim_player == r.b.anim_tree.anim_player,
		"same animation wiring on both")
	r.root.free()

func test_first_pilot_is_played_on_load() -> void:
	var r := _rig()
	check(r.a.controlled and not r.a.frozen, "A starts in control")
	check(not r.b.controlled and r.b.frozen, "B starts parked")
	check(r.a.camera_3d.current, "A's camera is the view")
	check(r.a.is_in_group(&"reflect_target") and not r.b.is_in_group(&"reflect_target"),
		"only the played pilot is shot at")
	check(r.a.hologram.is_in_group(&"hologram_host") and not r.b.hologram.is_in_group(&"hologram_host"),
		"the pause hologram opens on the played pilot")
	r.root.free()

func test_2_and_1_swap_control() -> void:
	var r := _rig()
	_press_key(r.sw, KEY_2)
	check(r.b.controlled and not r.b.frozen and r.a.frozen, "2 hands control to B")
	check(r.b.camera_3d.current and not r.a.camera_3d.current, "2 moves the view to B")
	check(r.b.hologram.is_in_group(&"hologram_host") and not r.a.hologram.is_in_group(&"hologram_host"),
		"the hologram host follows")
	_press_key(r.sw, KEY_1)
	check(r.a.controlled and r.b.frozen, "1 hands control back to A")
	check(r.a.camera_3d.current, "1 moves the view back to A")
	_press_key(r.sw, KEY_3)
	check(r.a.controlled, "a key with no pilot behind it does nothing")
	r.root.free()

func test_parked_pilot_ignores_movement_input() -> void:
	var r := _rig()
	_press_key(r.sw, KEY_2)
	Input.action_press(&"forward")
	for i in 5:
		r.a._physics_process(1.0 / 60.0)
		r.b._physics_process(1.0 / 60.0)
	Input.action_release(&"forward")
	var a_flat := Vector2(r.a.velocity.x, r.a.velocity.z)
	var b_flat := Vector2(r.b.velocity.x, r.b.velocity.z)
	check(a_flat.length() < 0.001, "the parked pilot does not walk (%s)" % a_flat)
	check(b_flat.length() > 0.1, "the played pilot does (%s)" % b_flat)
	r.root.free()

func test_no_switch_out_of_a_vehicle() -> void:
	var r := _rig()
	# pilot9.enter_vehicle() switches his physics off for the ride.
	r.a.set_physics_process(false)
	_press_key(r.sw, KEY_2)
	check(r.a.controlled and r.b.frozen, "A stays in control while aboard")
	r.root.free()
