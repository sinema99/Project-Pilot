extends "res://tests/test_case.gd"

# The crate carry, asserted against docs/specs/pilot9-crate-carry.md: the 3 x 3 mech-only item, the
# carry state and its lockouts, the EXIA LOAD CRATE panel and the stash loading. Physics is not
# stepped: states are driven by hand.

const CRATE := preload("res://resources/items/crate.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")
const MechScene := preload("res://scenes/mech.tscn")
const PilotScene := preload("res://scenes/pilot9.tscn")
const WORLD_CRATE := preload("res://scripts/inventory/world_crate.gd")
const WORLD_ITEM := preload("res://scripts/inventory/world_item.gd")

var _live: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _inventory() -> Node:
	return _tree().root.get_node(^"Inventory")


func _in_tree(n: Node) -> Node:
	_tree().root.add_child(n)
	_live.append(n)
	return n


func end() -> void:
	for n in _live:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.free()
	_live.clear()
	super()


## A stand-in for a pilot beside the mech: a `carry` that holds a def, and what EXIA reads.
class _StubCarry extends Node:
	var def: ItemDef = null
	var loaded_into: ItemGrid = null

	func start_load(grid: ItemGrid, _toward: Vector3) -> bool:
		loaded_into = grid
		return true

	func pick_up(item: ItemDef, _home: Vector3) -> bool:
		if def != null:
			return false
		def = item
		return true


class _StubPilot extends Node3D:
	var carry := _StubCarry.new()
	var controlled := true
	var frozen := false
	var held := false

	func set_inventory_hold(on: bool) -> void:
		held = on
		frozen = on

	func enter_vehicle(_m: Node3D) -> void:
		pass


# --- the item -------------------------------------------------------------------------

func test_the_crate_is_a_3_by_3_mech_only_item() -> void:
	eq(CRATE.size, Vector2i(3, 3), "3 x 3")
	check(CRATE.mech_only, "mech only")
	eq(CRATE.max_stack, 1, "does not stack")
	check(not MEDKIT.mech_only, "ordinary items are not")


func test_the_pilot_grid_never_takes_a_crate() -> void:
	var inv := _inventory()
	var item: Node3D = WORLD_ITEM.new()
	item.def = CRATE
	_in_tree(item)
	check(not inv.can_take(item), "can_take refuses")
	eq(inv.take(item), 0, "take takes none")
	check(is_instance_valid(item) and not item.is_queued_for_deletion(), "it stays on the ground")


func test_a_crate_takes_nine_cells_of_the_stash() -> void:
	var g := ItemGrid.new(10, 12)
	eq(g.add(CRATE, 1), 1, "one in")
	var s: ItemStack = g.items[0]
	eq(s.rect().size, Vector2i(3, 3), "a 3 x 3 footprint")


func test_a_full_stash_has_no_room() -> void:
	var g := ItemGrid.new(5, 5)
	eq(g.add(CRATE, 1), 1, "the first fits")
	eq(g.capacity_for(CRATE), 0, "no second 3 x 3 gap in a 5 x 5")


# --- the world crate ------------------------------------------------------------------

func test_a_world_crate_defaults_to_the_crate_item() -> void:
	var c: Node3D = WORLD_CRATE.new()
	_in_tree(c)
	eq(c.def, CRATE, "the crate def")
	check(c.is_in_group(&"world_crate"), "in the world_crate group")
	approx(c.home.y, 0.0, 0.0001, "home is where it stood")


# --- the pilot ------------------------------------------------------------------------

func test_begin_carry_flags_and_end_carry_clears_them() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	check(pilot.carry != null, "the carry node is built")
	check(not pilot.is_carrying, "empty hands to begin with")
	pilot.is_crouching = true
	pilot.sprint_toggled = true
	pilot.begin_carry()
	check(pilot.is_carrying, "carrying")
	check(not pilot.is_crouching, "the crouch is cleared")
	check(not pilot.sprint_toggled, "the sprint is cleared")
	pilot.end_carry()
	check(not pilot.is_carrying, "released")


func test_carrying_asks_for_the_walk_and_nothing_faster() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	pilot.begin_carry()
	pilot.input_dir = Vector2(0.0, -1.0)
	pilot.sprint_toggled = true
	var want: float = pilot._requested_speed()
	check(not pilot.is_sprinting, "never sprinting")
	approx(want, pilot.walk_speed, 0.0001, "the walk speed, floor or not")


func test_a_crate_cannot_be_picked_up_in_the_air() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	# No physics step: he is not on the floor.
	check(not pilot.can_begin_carry(), "not off the floor")
	check(not pilot.carry.pick_up(CRATE, Vector3.ZERO), "pick_up refuses")
	check(not pilot.is_carrying, "and nothing changed")


func test_release_hands_back_the_crate_and_empties_the_hands() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	pilot.carry.def = CRATE
	pilot.begin_carry()
	var got: ItemDef = pilot.carry.release()
	eq(got, CRATE, "what he held")
	check(pilot.carry.def == null and not pilot.is_carrying, "hands empty")


func test_loading_puts_the_crate_in_the_grid_after_the_animation() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	pilot.carry.def = CRATE
	pilot.begin_carry()
	var g := ItemGrid.new(10, 12)
	check(pilot.carry.start_load(g, Vector3.ZERO), "started")
	check(pilot.carry.is_loading(), "loading")
	check(not pilot.carry.start_load(g, Vector3.ZERO), "a second press is ignored")
	pilot.carry._tick_load(0.2)
	eq(g.items.size(), 0, "not yet")
	pilot.carry._tick_load(0.25)
	eq(g.items.size(), 1, "the grid has it")
	check(not pilot.is_carrying, "hands empty")


func test_loading_into_a_full_grid_keeps_the_crate() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	pilot.carry.def = CRATE
	pilot.begin_carry()
	var g := ItemGrid.new(3, 3)
	g.add(CRATE, 1)
	pilot.carry.start_load(g, Vector3.ZERO)
	pilot.carry._tick_load(0.5)
	check(pilot.is_carrying, "still in his hands")
	eq(g.items.size(), 1, "the grid is unchanged")


func test_a_fall_knocks_the_crate_out_of_his_hands() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	pilot.carry.def = CRATE
	pilot.begin_carry()
	pilot.carry.tick(0.2)
	check(pilot.is_carrying, "a short hop keeps it")
	pilot.carry.tick(0.2)
	check(not pilot.is_carrying, "airborne 0.4 s: dropped")
	var crates := _tree().get_nodes_in_group(&"world_crate")
	check(crates.size() >= 1, "it is a world crate again")
	for c in crates:
		_live.append(c)


func test_switching_pilots_drops_the_crate() -> void:
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	pilot.carry.def = CRATE
	pilot.begin_carry()
	pilot.controlled = false
	pilot.carry.tick(0.016)
	check(not pilot.is_carrying, "the pilot being left puts it down")
	for c in _tree().get_nodes_in_group(&"world_crate"):
		_live.append(c)


# --- EXIA's panel ---------------------------------------------------------------------

func test_exia_offers_load_crate_while_he_carries_one() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.player_in_range = pilot
	exia._update_prompt()
	eq(exia.prompt_text, "PILOT", "empty hands: the usual")
	pilot.carry.def = CRATE
	exia._update_prompt()
	eq(exia.prompt_text, "LOAD CRATE", "a crate and room: LOAD CRATE")
	exia.player_in_range = null


func test_exia_says_stash_full_when_there_is_no_gap() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.player_in_range = pilot
	pilot.carry.def = CRATE
	var inv := _inventory()
	var saved: Array = inv.stash.items.duplicate()
	# Fill every 3 x 3 gap in the 10 x 12 stash.
	while inv.stash.add(CRATE, 1) > 0:
		pass
	exia._update_prompt()
	eq(exia.prompt_text, "STASH FULL", "no room for a crate")
	check(not exia.crate_fits(), "crate_fits agrees")
	inv.stash.items.clear()
	for it in saved:
		inv.stash.items.append(it)
	exia.player_in_range = null


# --- the stash screen -----------------------------------------------------------------

const SCREEN_TSCN := "res://scenes/ui/inventory_screen.tscn"


func _stash_screen_with(pilot: Node3D, exia: Node3D) -> Control:
	pilot.add_to_group(&"player")
	var s: Control = (load(SCREEN_TSCN) as PackedScene).instantiate()
	_in_tree(s)
	_inventory().stash_mech = exia
	s.present()
	return s


func test_a_crate_leaves_the_stash_into_empty_hands() -> void:
	var inv := _inventory()
	var saved_s: ItemGrid = inv.stash
	inv.stash = ItemGrid.new(10, 12)
	var crate := ItemStack.new(CRATE)
	inv.stash.place(crate, Vector2i(2, 3), false)
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	var s := _stash_screen_with(pilot, exia)
	s.left_click(s.stash_cell_origin(Vector2i(2, 3)) + Vector2i(3, 3))
	eq(pilot.carry.def, CRATE, "it is in his hands")
	eq(inv.stash.items.size(), 0, "and out of the stash")
	eq(s.held, null, "never on the cursor")
	inv.stash = saved_s


func test_a_crate_stays_when_his_hands_are_full() -> void:
	var inv := _inventory()
	var saved_s: ItemGrid = inv.stash
	inv.stash = ItemGrid.new(10, 12)
	var crate := ItemStack.new(CRATE)
	inv.stash.place(crate, Vector2i(2, 3), false)
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	pilot.carry.def = CRATE
	var s := _stash_screen_with(pilot, exia)
	s.shift_click(s.stash_cell_origin(Vector2i(2, 3)) + Vector2i(3, 3))
	eq(inv.stash.items, [crate], "RMB with full hands: nothing happens")
	s.left_click(s.stash_cell_origin(Vector2i(2, 3)) + Vector2i(3, 3))
	eq(inv.stash.items, [crate], "so does LMB")
	eq(s.held, null, "and it is not lifted on the cursor")
	inv.stash = saved_s
