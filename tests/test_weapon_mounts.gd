extends "res://tests/test_case.gd"

# Holstered weapons on his body (docs/specs/pilot9-weapon-mounts.md): the rifle on the pack's left,
# the revolver on the right thigh, gone while drawn, travelling with the materialize.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const Mounts := preload("res://scripts/items/weapon_mounts.gd")
const RIFLE := preload("res://resources/items/rifle.tres")
const REVOLVER := preload("res://resources/items/revolver.tres")


func test_slot_basis_points_the_barrel_and_the_top() -> void:
	var b := Mounts.slot_basis(Vector3.UP, Vector3.RIGHT)
	check((b * Vector3(0, 0, -1)).is_equal_approx(Vector3.UP), "-Z (the barrel) points up")
	check((b * Vector3.UP).is_equal_approx(Vector3.RIGHT), "+Y (the top) points outward")
	check(b.is_conformal() and is_equal_approx(b.determinant(), 1.0), "a clean rotation")
	var d := Mounts.slot_basis(Vector3.DOWN, Vector3.BACK)
	check((d * Vector3(0, 0, -1)).is_equal_approx(Vector3.DOWN), "muzzle down")
	check(d.determinant() > 0.0, "right-handed")


func test_hand_amount_is_the_rest_of_the_body_copy() -> void:
	eq(Mounts.hand_amount(false, true, false, 0.0, 0.15, 0.2), 0.0, "another weapon: nothing in hand")
	eq(Mounts.hand_amount(true, false, false, 0.0, 0.15, 0.2), 0.0, "holstered: all on the body")
	eq(Mounts.hand_amount(true, true, false, 0.0, 0.15, 0.2), 1.0, "drawn: all in the hand")
	eq(Mounts.hand_amount(true, true, true, 0.1, 0.15, 0.2), 0.0, "arm still coming out")
	eq(Mounts.hand_amount(true, true, true, 0.4, 0.15, 0.2), 1.0, "sweep done")
	var mid := Mounts.hand_amount(true, true, true, 0.25, 0.15, 0.2)
	check(mid > 0.0 and mid < 1.0, "mid-sweep is partly each")


func test_slot_glow() -> void:
	eq(Mounts.slot_glow(0.0, 0.3), 0.0, "whole: no glow")
	eq(Mounts.slot_glow(0.3, 0.3), 1.0, "nearly gone: full glow")


func _pilot() -> Node:
	var inv := (Engine.get_main_loop() as SceneTree).root.get_node(^"Inventory")
	inv.persist = false
	var p: Node = (load(PILOT_TSCN) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	return p


func test_pilot_shows_both_weapons_holstered() -> void:
	var p := _pilot()
	p.weapon_mounts.set_items([RIFLE, REVOLVER, null])
	eq(p.weapon_mounts._mounts.size(), 2, "one body copy per slotted weapon with a slot")
	for m in p.weapon_mounts._mounts:
		check(m.node.visible, "holstered weapons show")
	var rifle_socket: BoneAttachment3D = p.weapon_mounts._mounts[0].socket
	var revolver_socket: BoneAttachment3D = p.weapon_mounts._mounts[1].socket
	eq(rifle_socket.bone_name, &"UpperChest", "the rifle rides the chest")
	eq(revolver_socket.bone_name, &"RightUpperLeg", "the revolver rides the right thigh")
	p.queue_free()


func test_drawn_weapon_leaves_its_slot() -> void:
	var p := _pilot()
	p.weapon_mounts.set_items([RIFLE, REVOLVER])
	p.set_item(RIFLE)
	p.toggle_drawn()
	p.weapon_mounts._process(0.0)
	check(not p.weapon_mounts._mounts[0].node.visible, "the drawn rifle is gone from the body")
	check(p.weapon_mounts._mounts[1].node.visible, "the revolver stays")
	p.toggle_drawn()
	p.weapon_mounts._process(0.0)
	check(p.weapon_mounts._mounts[0].node.visible, "holstered, it is back")
	p.queue_free()


func test_staff_gets_no_body_slot() -> void:
	var p := _pilot()
	var staff := load("res://resources/items/staff.tres") as HeldItem
	p.weapon_mounts.set_items([staff])
	eq(p.weapon_mounts._mounts.size(), 0, "the staff stays hidden when holstered")
	p.queue_free()
