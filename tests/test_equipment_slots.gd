extends "res://tests/test_case.gd"

# Equipment slots (docs/specs/equipment-slots.md): the model on the Inventory autoload, the slots on
# the inventory screen, what they do to pilot9, and the save.

const SCREEN_TSCN := "res://scenes/ui/inventory_screen.tscn"
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const HAT := preload("res://resources/items/cowboy_hat.tres")
const COAT := preload("res://resources/items/trench_coat.tres")
const STAFF := preload("res://resources/items/staff_weapon.tres")
const RIFLE := preload("res://resources/items/rifle_weapon.tres")
const REVOLVER := preload("res://resources/items/revolver_weapon.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")

var _extra: Node = null


func _inv() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"Inventory")


func _reset() -> void:
	var inv := _inv()
	inv.persist = false
	for it in inv.grid.items.duplicate():
		inv.grid.remove(it)
	inv.seed_equipment()
	inv.equipment_changed.emit()


func _screen() -> Control:
	var s: Control = (load(SCREEN_TSCN) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	s.present()
	return s


func _centre(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


func test_defaults_hat_coat_pack_rifle_revolver() -> void:
	_reset()
	var inv := _inv()
	eq(inv.item_in(&"head").def, HAT, "hat on the head")
	eq(inv.item_in(&"body").def, COAT, "coat on the body")
	eq(inv.item_in(&"legs"), null, "legs empty")
	eq(inv.item_in(&"back").def.id, &"backpack", "a backpack on the back")
	eq(inv.item_in(&"back").contents.items.size(), 0, "and it is empty")
	eq(inv.item_in(&"weapon_1").def, RIFLE, "rifle on 1")
	eq(inv.item_in(&"weapon_2").def, REVOLVER, "revolver on 2")
	eq([HAT.size, COAT.size], [Vector2i(2, 2), Vector2i(3, 3)], "hat 2x2, coat 3x3")


func test_slots_only_take_their_own_kind() -> void:
	var inv := _inv()
	check(inv.slot_accepts(&"head", HAT), "hat fits head")
	check(not inv.slot_accepts(&"body", HAT), "hat is not a coat")
	check(not inv.slot_accepts(&"head", COAT), "coat is not a hat")
	check(inv.slot_accepts(&"weapon_1", REVOLVER) and inv.slot_accepts(&"weapon_2", STAFF),
		"either weapon in either weapon slot")
	check(not inv.slot_accepts(&"legs", HAT), "nothing fits legs yet")
	check(not inv.slot_accepts(&"head", MEDKIT), "a medkit is not wearable")


func test_equip_swaps_and_refuses() -> void:
	_reset()
	var inv := _inv()
	var other := ItemStack.new(HAT)
	var old: ItemStack = inv.equip(&"head", other)
	eq(old.def, HAT, "the worn hat comes back")
	eq(inv.item_in(&"head"), other, "the new one is worn")
	var coat := ItemStack.new(COAT)
	eq(inv.equip(&"head", coat), coat, "a coat on the head is refused (handed back)")
	eq(inv.item_in(&"head"), other, "and nothing changed")


func test_dragging_between_grid_and_slot() -> void:
	_reset()
	var inv := _inv()
	var s := _screen()
	# Pick the hat up off HEAD, drop it in the grid.
	s.left_click(_centre(s.slot_rect(&"head")))
	check(s.held != null and s.held.def == HAT, "clicking a worn hat picks it up")
	eq(inv.item_in(&"head"), null, "and the slot is empty")
	s.left_click(s.grid_cell_origin(Vector2i(1, 1)) + Vector2i(2, 2))
	check(s.held == null, "the hat landed in the grid")
	eq(inv.grid.items.size(), 1, "one item in the grid")
	# Back onto the head.
	s.left_click(s.grid_cell_origin(Vector2i(1, 1)) + Vector2i(2, 2))
	s.left_click(_centre(s.slot_rect(&"head")))
	eq(inv.item_in(&"head").def, HAT, "dropping it on HEAD wears it")
	eq(inv.grid.items.size(), 0, "grid empty again")
	s.queue_free()


func test_wrong_slot_refuses_and_full_slot_swaps() -> void:
	_reset()
	var inv := _inv()
	var s := _screen()
	s.left_click(_centre(s.slot_rect(&"head")))
	s.left_click(_centre(s.slot_rect(&"body")))
	check(s.held != null and s.held.def == HAT, "a hat on BODY is refused; it stays on the cursor")
	eq(inv.item_in(&"body").def, COAT, "the coat stays put")
	# Weapon swap: hold the rifle, drop it on 2.
	s.right_click(Vector2i(-5, -5))
	s.left_click(_centre(s.slot_rect(&"weapon_1")))
	check(s.held != null and s.held.def == RIFLE, "rifle picked up off slot 1")
	s.left_click(_centre(s.slot_rect(&"weapon_2")))
	eq(inv.item_in(&"weapon_2").def, RIFLE, "rifle now on 2")
	check(s.held != null and s.held.def == REVOLVER, "the revolver comes up on the cursor")
	s.left_click(_centre(s.slot_rect(&"weapon_1")))
	eq(inv.item_in(&"weapon_1").def, REVOLVER, "and goes to 1")
	s.queue_free()


func test_shift_click_unequips_to_the_grid() -> void:
	_reset()
	var inv := _inv()
	var s := _screen()
	s.shift_click(_centre(s.slot_rect(&"body")))
	eq(inv.item_in(&"body"), null, "the coat came off")
	eq(inv.grid.items.size(), 1, "into the grid")
	eq(inv.grid.items[0].def, COAT, "it is the coat")
	s.queue_free()


func test_closing_with_a_slot_item_held_puts_it_back() -> void:
	_reset()
	var inv := _inv()
	var s := _screen()
	s.left_click(_centre(s.slot_rect(&"head")))
	s._return_held()
	eq(inv.item_in(&"head").def, HAT, "the hat is back on the head")
	s.queue_free()


func test_slots_hide_in_stash_mode() -> void:
	_reset()
	var s := _screen()
	check(s.slot_at(_centre(s.slot_rect(&"head"))) == &"head", "visible on the pilot screen")
	s._stash_mech = Node3D.new()
	eq(s.slot_at(_centre(s.slot_rect(&"head"))), &"", "no slot hits in STASH mode")
	s._stash_mech.free()
	s._stash_mech = null
	s.queue_free()


func test_slots_sit_in_a_row_above_the_inventory() -> void:
	var s := _screen()
	var grid: Rect2i = s.box_rect(s.Box.GRID)
	var top: Rect2i = s.box_rect(s.Box.PORTRAIT)
	for slot in _inv().EQUIP_SLOTS:
		var r: Rect2i = s.slot_rect(slot)
		check(r.end.y <= grid.position.y, "%s is above the inventory" % slot)
		check(r.position.x >= grid.position.x and r.end.x <= grid.end.x, "%s is within the inventory's width" % slot)
		check(r.position.y >= top.position.y, "%s is on screen" % slot)
	check(not s.slot_rect(&"head").intersects(s.slot_rect(&"weapon_1")), "clothes and weapons do not touch")
	s.queue_free()


func test_pilot_follows_the_slots() -> void:
	_reset()
	_extra = (load(PILOT_TSCN) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_extra)
	var inv := _inv()
	check(_extra.is_hat_on() and _extra.is_coat_on(), "he spawns wearing both")
	eq(_extra.weapon_slots.size(), 2, "two weapon slots")
	eq(_extra.weapon_slots[0], RIFLE.held_item, "1 is the rifle")
	eq(_extra.weapon_slots[1], REVOLVER.held_item, "2 is the revolver")
	eq(_extra.staff_slot(), -1, "no staff is slotted by default, so nothing reflects")
	# The staff takes slot 1 off the rifle.
	inv.equip(&"weapon_1", ItemStack.new(STAFF, 1))
	eq(_extra.weapon_slots[0], STAFF.held_item, "1 is the staff once it is slotted")
	_extra.item_holder.set_item(STAFF.held_item)
	_extra.item_holder.set_drawn(true)
	# The drawn staff leaves its slot: holstered at once, nothing swapped in is drawn.
	var staff: ItemStack = inv.unequip(&"weapon_1")
	check(not _extra.is_item_drawn() and _extra.item_holder.held_item == null, "the drawn staff is holstered when unslotted")
	eq(_extra.weapon_slots[0], null, "slot 1 is empty")
	check(not _extra.press_weapon(0), "an empty slot's key does nothing")
	inv.equip(&"weapon_1", staff)
	check(not _extra.is_item_drawn(), "slotting it back does not draw it")
	eq(_extra.staff_slot(), 0, "the staff is found on 1")
	# Swap the two: the staff is now 2.
	var rev: ItemStack = inv.unequip(&"weapon_2")
	inv.equip(&"weapon_2", inv.unequip(&"weapon_1"))
	inv.equip(&"weapon_1", rev)
	eq(_extra.staff_slot(), 1, "after the swap the staff is on 2")
	_extra.queue_free()
	_extra = null
	_reset()


func test_save_roundtrip() -> void:
	_reset()
	var inv := _inv()
	inv.grid.add(MEDKIT, 1)
	var coat: ItemStack = inv.unequip(&"body")
	inv.grid.add(COAT, 1)
	var data: Dictionary = inv.loadout_to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	_reset()
	inv.loadout_from_dict(parsed)
	eq(inv.item_in(&"body"), null, "the coat is still off")
	eq(inv.item_in(&"head").def, HAT, "the hat is still on")
	eq(inv.item_in(&"weapon_2").def, REVOLVER, "the revolver is still on 2")
	var defs := []
	for it in inv.grid.items:
		defs.append(it.def)
	check(defs.has(MEDKIT) and defs.has(COAT), "grid contents came back")
	check(coat != null, "sanity")
	_reset()
