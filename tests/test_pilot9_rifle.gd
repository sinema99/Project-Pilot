extends "res://tests/test_case.gd"

# docs/specs/pilot9-rifle.md. The rifle model (the user's own Blender rifle.glb, about 1.5 m), the held item (two-handed
# chest carry at every pace, off in the air and in a slide), its place as weapon 1, and the one-time
# save migration that swaps an old save's staff for it. How it looks in his hands is judged in
# play (tests/_probe_rifle_shot.gd for screenshots).

const RIFLE_SCENE := "res://scenes/items/rifle.tscn"
const RIFLE_HELD := "res://resources/items/rifle.tres"
const RIFLE_DEF := preload("res://resources/items/rifle_weapon.tres")
const STAFF_DEF := preload("res://resources/items/staff_weapon.tres")
const HOLDER := preload("res://scripts/items/item_holder.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"

var _rifle: Node3D = null


func _make_rifle() -> Node3D:
	var node := (load(RIFLE_SCENE) as PackedScene).instantiate() as Node3D
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	return node


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = node.global_transform.affine_inverse() * m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _triangles(node: Node3D) -> int:
	var n := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx = arrays[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return n


func test_the_model_is_the_users_glb_about_1_5_m_long() -> void:
	var r := _make_rifle()
	var box := _bounds(r)
	check(absf(box.size.z - 1.5) < 0.1, "about 1.5 m from butt to muzzle, got %s" % box.size.z)
	check(r.find_children("*", "MeshInstance3D", true, false).size() >= 1, "the GLB's mesh is under it")
	check(_triangles(r) > 100, "it carries the modelled geometry")
	r.queue_free()


func test_the_item_frame_has_its_grip_at_the_origin_and_the_muzzle_down_minus_z() -> void:
	var r := _make_rifle()
	var box := _bounds(r)
	check(box.position.z < -1.0 and box.end.z > 0.3, "muzzle on -Z, butt on +Z")
	check(box.position.y < -0.05 and box.end.y > 0.1, "magazine below the grip, scope above")
	var muzzle := r.get_node("Muzzle") as Marker3D
	check(muzzle.position.z < -1.0, "the muzzle marker sits at the end of the barrel")
	r.queue_free()


func test_every_surface_carries_the_cel_material() -> void:
	var r := _make_rifle()
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			check(m.get_surface_override_material(i) is ShaderMaterial, "surface %d is cel painted" % i)
	r.queue_free()


func test_the_held_item_holds_both_arms_two_handed_and_cannot_reflect() -> void:
	var held := load(RIFLE_HELD) as HeldItem
	eq(held.idle_rotations.size(), 8, "idle carry sets both arms")
	eq(held.hold_rotations.size(), 8, "the same chest carry at a sprint")
	for bone in held.idle_rotations:
		check(HOLDER.ARM_BONES.has(String(bone)), "%s is an arm bone the holder knows" % bone)
	check(not held.can_reflect, "only the staff reflects")
	check(held.hold_at_any_speed, "carried at every pace")
	eq(held.hold_rotations, held.idle_rotations, "one chest carry, no separate sprint pose")
	check(held.hold_off_states.has(&"slide"), "the slide uses its own arms")


func test_the_arm_override_is_off_in_the_air_and_on_the_ground() -> void:
	var held := load(RIFLE_HELD) as HeldItem
	for state in [&"jump", &"fall", &"climb", &"wall_run", &"wall_climb", &"rail", &"slide"]:
		eq(HOLDER.item_target_for(held, state, 0.0, 3.0, 8.0), 0.0, "%s releases the arms" % state)
	for state in [&"Locomotion", &"crouch", &"jump_land"]:
		eq(HOLDER.item_target_for(held, state, 0.0, 3.0, 8.0), 1.0, "%s keeps the carry, even standing" % state)


func test_it_is_a_6x2_weapon_item_and_the_default_on_slot_1() -> void:
	eq(RIFLE_DEF.size, Vector2i(6, 2), "6x2 in the grid")
	eq(RIFLE_DEF.slot, &"weapon", "a weapon")
	eq(RIFLE_DEF.held_item, load(RIFLE_HELD), "wired to its held item")
	eq(Inventory.DEFAULT_LOADOUT[&"weapon_1"], "res://resources/items/rifle_weapon.tres", "rifle on 1")
	eq(Inventory.DEFAULT_LOADOUT[&"weapon_2"], "res://resources/items/revolver_weapon.tres", "revolver on 2")
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	eq(pilot.starting_item, load(RIFLE_HELD), "he spawns carrying it")
	eq(pilot.weapon_slots[0], load(RIFLE_HELD), "slot 1 is the rifle")
	pilot.free()


func test_an_old_save_swaps_the_staff_for_the_rifle_and_keeps_the_staff_in_the_grid() -> void:
	var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node("/root/Inventory")
	var was_persist: bool = inv.persist
	inv.persist = false
	var old := {"version": 1, "grid": [], "equipment": {
		"weapon_1": {"id": "staff"}, "weapon_2": {"id": "revolver"}}}
	inv.loadout_from_dict(old)
	eq(inv.item_in(&"weapon_1").def, RIFLE_DEF, "the rifle took slot 1")
	eq(inv.item_in(&"weapon_2").def.id, &"revolver", "slot 2 untouched")
	var in_grid := false
	for it in inv.grid.items:
		if it.def == STAFF_DEF:
			in_grid = true
	check(in_grid, "the staff went to the grid, not lost")
	# A current save is left alone: the staff stays where the player put it.
	inv.loadout_from_dict({"version": 2, "grid": [], "equipment": {"weapon_1": {"id": "staff"}}})
	eq(inv.item_in(&"weapon_1").def, STAFF_DEF, "a version-2 save keeps its staff on 1")
	eq(inv.loadout_to_dict()["version"], 2, "saves are written as version 2")
	inv.seed_equipment()
	inv.persist = was_persist
