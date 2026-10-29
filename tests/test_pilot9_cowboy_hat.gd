extends "res://tests/test_case.gd"

# docs/specs/pilot9-cowboy-hat.md. The key, the socket, on/off, the materials, the mesh facing out
# and the ghosts picking it up. How it looks on him is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const HAT_MESH := preload("res://scripts/items/cowboy_hat_mesh.gd")
const HAT_HOLDER := preload("res://scripts/items/hat_holder.gd")
const CEL_SHADER := preload("res://shaders/cel/cel-shader-base.gdshader")

# One shared in-tree instance, for the reason tests/test_pilot9_dash.gd gives.
var _pilot: Node = null

# The pilot with the hat off and unfrozen, whatever the last test left.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.frozen = false
	if _pilot.is_hat_on():
		_pilot.toggle_hat()
	return _pilot

func _press_hat() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"hat"
	ev.pressed = true
	return ev

func test_hat_is_bound_to_h() -> void:
	check(InputMap.has_action(&"hat"), "project.godot has no `hat` action")
	if not InputMap.has_action(&"hat"):
		return
	var found := false
	for ev in InputMap.action_get_events(&"hat"):
		if ev is InputEventKey and ev.physical_keycode == KEY_H:
			found = true
	check(found, "`hat` should be on H")

func test_spawns_off_on_the_head() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.hat_holder
	check(h != null and h.hat != null, "the hat should be built at spawn")
	if h == null or h.hat == null:
		return
	eq(h.head_socket.bone_name, "Head", "hat socket bone")
	check(h.head_socket.bone_idx >= 0, "Head should resolve on pilot9's skeleton")
	eq(h.hat.get_parent(), h.head_socket, "the hat sits in the head socket")
	check(not pilot.is_hat_on() and not h.hat.visible, "he should spawn without it")

func test_toggle_shows_and_hides_it() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.toggle_hat()
	check(pilot.is_hat_on() and pilot.hat_holder.hat.visible, "one toggle puts it on")
	pilot.toggle_hat()
	check(not pilot.is_hat_on() and not pilot.hat_holder.hat.visible, "a second takes it off")

func test_h_reaches_only_the_pilot_being_played() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot._input(_press_hat())
	check(pilot.is_hat_on(), "H should put it on")
	pilot._input(_press_hat())
	check(not pilot.is_hat_on(), "H again should take it off")
	pilot.frozen = true
	pilot._input(_press_hat())
	check(not pilot.is_hat_on(), "a parked (frozen) pilot ignores H")
	pilot.frozen = false

func test_felt_and_band_are_brown_cel() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var felt := pilot.hat_holder.hat.get_node_or_null(^"Felt") as MeshInstance3D
	var band := pilot.hat_holder.hat.get_node_or_null(^"Band") as MeshInstance3D
	check(felt != null and band != null, "the hat should have Felt and Band meshes")
	if felt == null or band == null:
		return
	for part: MeshInstance3D in [felt, band]:
		var mat := part.material_override as ShaderMaterial
		check(mat != null and mat.shader == CEL_SHADER, "%s should wear the cel shader" % part.name)
		check(mat != null and mat.next_pass != null, "%s should keep the ink pass" % part.name)
	eq(felt.material_override.get_shader_parameter(&"color"), HAT_HOLDER.FELT_COLOR, "felt colour")
	eq(band.material_override.get_shader_parameter(&"color"), HAT_HOLDER.BAND_COLOR, "band colour")

# Faces out, or the cel bands and the ink hull turn inside out. Godot's front faces wind clockwise,
# so an outward shell has a negative signed volume (the CCW formula), and its normals agree with
# the winding.
func test_mesh_faces_outward() -> void:
	for mesh: ArrayMesh in [HAT_MESH.build_felt(), HAT_MESH.build_band()]:
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var volume := 0.0
		var agree := 0
		for t in idx.size() / 3:
			var a := verts[idx[t * 3]]
			var b := verts[idx[t * 3 + 1]]
			var c := verts[idx[t * 3 + 2]]
			volume += a.dot(b.cross(c))
			var n := normals[idx[t * 3]] + normals[idx[t * 3 + 1]] + normals[idx[t * 3 + 2]]
			if n.dot((b - a).cross(c - a)) < 0.0:
				agree += 1
		check(volume < 0.0, "the hat shell should wind outward")
		check(agree > idx.size() / 3 * 0.95, "hat normals should agree with the winding (%d of %d)" 			% [agree, idx.size() / 3])

func test_ghosts_wear_it() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.toggle_hat()
	pilot._afterimage._build_if_stale()
	var felt: Node = pilot.hat_holder.hat.get_node(^"Felt")
	check(pilot._afterimage._sources.has(felt), "the afterimage pool should copy the hat")
	pilot.toggle_hat()

func test_hat_swaps_in_the_cut_head() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.hat_holder
	check(not h.hatted.is_empty(), "his head mesh should have a hatted (skull top cut) copy")
	for mi: MeshInstance3D in h.hatted:
		var pair: Array = h.hatted[mi]
		eq(mi.mesh, pair[0], "hat off, %s wears its own mesh" % mi.name)
		eq(pair[1].get_surface_count(), pair[0].get_surface_count(), "the cut keeps every surface")
	pilot.toggle_hat()
	for mi: MeshInstance3D in h.hatted:
		eq(mi.mesh, h.hatted[mi][1], "hat on, %s wears the cut mesh" % mi.name)
	pilot.toggle_hat()
	for mi: MeshInstance3D in h.hatted:
		eq(mi.mesh, h.hatted[mi][0], "hat off again, %s gets its own mesh back" % mi.name)

func test_raked_fit_scales_and_tips_it_forward() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var t: Transform3D = pilot.hat_holder.hat.transform
	check(pilot.hat_tilt < 0.0, "the default fit rakes the hat forward")
	check(absf(t.basis.get_scale().x - pilot.hat_scale) < 0.001, "hat_scale scales the whole hat")
	check(t.basis.z.normalized().y < 0.0, "raked forward, the front of the hat points down")

# Raked forward, more of an ear fin is under the band than of the skull. The skull must still be
# the piece that is cut, not deleted whole: pilot9's skull is ~230 triangles, his fins 1280 each.
func test_raked_cut_keeps_the_skull() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.hat_holder
	for mi: MeshInstance3D in h.hatted:
		var cut: Mesh = h.hatted[mi][1]
		var kept := 0
		for s in cut.get_surface_count():
			kept += (cut.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		check(kept > 250, "%s should keep his skull under the hat, kept %d triangles" % [mi.name, kept])

# User, 2026-10-23: the ears come out through the hat. pilot9's two fins are 1280 triangles each;
# only the skull top under the crown goes.
func test_ears_come_through_the_hat() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var h: Node = pilot.hat_holder
	for mi: MeshInstance3D in h.hatted:
		var own: Mesh = h.hatted[mi][0]
		var cut: Mesh = h.hatted[mi][1]
		for s in own.get_surface_count():
			var before := (own.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var after := (cut.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(before - after < 200, "%s surf %d: only the skull top should go, lost %d of %d" 				% [mi.name, s, before - after, before])
