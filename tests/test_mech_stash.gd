extends "res://tests/test_case.gd"

# EXIA's stash, the PILOT / STASH option list, hold-to-exit and the stash screen, asserted against
# docs/specs/mech-stash.md. Physics is not stepped here: the hold is driven through
# step_exit_hold() and the screen through left_click / right_click with texel positions.

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const FACE_SCRIPT := preload("res://scripts/ui/interaction_panel_face.gd")
const SCREEN_SCRIPT := preload("res://scripts/ui/inventory_screen.gd")
const SCREEN_TSCN := "res://scenes/ui/inventory_screen.tscn"
const INVENTORY_SCRIPT := preload("res://scripts/inventory/inventory.gd")
const MechScene := preload("res://scenes/mech.tscn")
const BATTERY := preload("res://resources/items/battery.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")
const CRATE := preload("res://resources/items/rifle_crate.tres")
const RATION := preload("res://resources/items/ration.tres")

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


class _StubPilot extends Node3D:
	func exit_vehicle(_pos: Vector3, _yaw: float) -> void:
		pass


# --- the stash ------------------------------------------------------------------------

func test_the_stash_is_10_by_12_and_bigger_than_the_pilot_grid() -> void:
	var inv := _inventory()
	eq([inv.stash.width, inv.stash.height], [10, 12], "10 x 12")
	check(inv.stash.width * inv.stash.height > inv.grid.width * inv.grid.height, "bigger than his")


func test_the_test_seed() -> void:
	var g := ItemGrid.new(10, 12)
	INVENTORY_SCRIPT.seed_stash(g)
	var kinds: Array = []
	for it in g.items:
		kinds.append(String(it.def.id))
	kinds.sort()
	eq(kinds, ["battery", "medkit", "medkit", "rifle_crate"], "crate, two medkits, a battery")


# --- the option list ------------------------------------------------------------------

func test_a_list_offer_scrolls_clamped_and_resets() -> void:
	var p: Node = _in_tree((load(PROMPT_SCRIPT.SCENE_PATH) as PackedScene).instantiate())
	var src := _in_tree(Node.new())
	var opts := PackedStringArray(["PILOT", "STASH"])
	p.offer(src, 1.0, &"interact", "PILOT", -1.0, opts)
	p.commit()
	eq(p.selected_option(), "PILOT", "starts on PILOT")
	p.scroll_selection(1)
	eq(p.selected_option(), "STASH", "wheel down: STASH")
	p.scroll_selection(1)
	eq(p.selected_option(), "STASH", "clamped at the bottom, no wrap")
	p.offer(src, 1.0, &"interact", "PILOT", -1.0, opts)
	p.commit()
	eq(p.selected_option(), "STASH", "the highlight survives the next frame's bid")
	p.scroll_selection(-5)
	eq(p.selected_option(), "PILOT", "clamped at the top")
	p.scroll_selection(1)
	p.commit()  # nobody bid: out of range
	p.offer(src, 1.0, &"interact", "PILOT", -1.0, opts)
	p.commit()
	eq(p.selected_option(), "PILOT", "walking off resets it to PILOT")


func test_a_single_word_offer_ignores_the_wheel() -> void:
	var p: Node = _in_tree((load(PROMPT_SCRIPT.SCENE_PATH) as PackedScene).instantiate())
	var src := _in_tree(Node.new())
	p.offer(src, 1.0, &"interact", "OPEN")
	p.commit()
	check(not p.is_offering_list(), "a door's OPEN is not a list - the wheel stays free")
	p.scroll_selection(1)
	eq(p.selected_option(), "OPEN", "and scrolling does nothing to it")


func test_the_face_grows_a_row_per_option_and_room_for_the_bar() -> void:
	var one: Vector2i = FACE_SCRIPT.size_for(PackedStringArray(["PILOT"]), false)
	var two: Vector2i = FACE_SCRIPT.size_for(PackedStringArray(["PILOT", "STASH"]), false)
	var bar: Vector2i = FACE_SCRIPT.size_for(PackedStringArray(["EXIT"]), true)
	eq(one.y, FACE_SCRIPT.HEIGHT, "one row is the old panel")
	eq(two.y, FACE_SCRIPT.HEIGHT + FACE_SCRIPT.ROW_STEP, "two rows")
	check(bar.y > FACE_SCRIPT.HEIGHT, "the bar adds height")


func test_exia_offers_pilot_and_stash_on_the_ground() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var p: Node = PROMPT_SCRIPT.acquire(exia)
	if p != null:
		_live.append(p)
	var body := _in_tree(Node3D.new()) as Node3D
	exia.player_in_range = body
	exia._bid_prompt()
	p.commit()
	eq(p.shown_options(), PackedStringArray(["PILOT", "STASH"]), "PILOT over STASH")
	check(p.is_offering_list(), "the wheel is the panel's while it shows")
	exia.player_in_range = null


# --- hold to exit ---------------------------------------------------------------------

func test_aboard_nothing_shows_until_f_goes_down() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.pilot = pilot
	exia._update_prompt()
	eq(exia.prompt_text, "", "no panel aboard")
	approx(exia.exit_progress(), -1.0, 0.0001, "no bar")
	exia.exit_hold = 0.0
	exia._update_prompt()
	eq(exia.prompt_text, "EXIT", "F down: EXIT")
	exia.pilot = null


func test_letting_go_early_cancels() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.pilot = pilot
	exia.exit_hold = 0.0
	exia.step_exit_hold(true, 0.3)
	approx(exia.exit_progress(), 0.5, 0.01, "half a hold is half a bar")
	exia.step_exit_hold(false, 0.016)
	check(exia.exit_hold < 0.0, "released: the hold is gone")
	eq(exia.prompt_text, "", "and the panel folds")
	eq(exia.pilot, pilot, "still aboard")
	exia.pilot = null


func test_a_full_hold_at_speed_waits_and_release_cancels() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.pilot = pilot
	exia.velocity = Vector3(0.0, 0.0, 14.0)
	exia.exit_hold = 0.0
	for i in 40:
		exia.step_exit_hold(true, 0.016)
	check(exia.exit_pending, "full bar at a sprint: the braking wait")
	eq(exia.prompt_text, "EXIT...", "reads EXIT...")
	approx(exia.exit_progress(), 1.0, 0.0001, "bar full while it waits")
	exia.step_exit_hold(false, 0.016)
	check(not exia.exit_pending, "let go during the wait: called off")
	exia.pilot = null


func test_exit_hold_time() -> void:
	approx(MechScene.instantiate().get_script().EXIT_HOLD_TIME, 0.6, 0.0001, "0.6 s")


# --- stash hold -----------------------------------------------------------------------

func test_the_stash_hold_cancels_an_exit_and_the_sprint() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.pilot = pilot
	exia.exit_hold = 0.2
	exia.sprint_toggled = true
	exia.set_stash_hold(true)
	check(exia.stash_hold, "held")
	check(exia.exit_hold < 0.0, "the exit hold is dropped")
	check(not exia.sprint_toggled, "the sprint is dropped")
	exia.set_stash_hold(false)
	exia.pilot = null


func test_no_stash_mid_sequence() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot := _in_tree(_StubPilot.new())
	exia.pilot = pilot
	exia.embark_left = 1.0
	check(not exia.can_open_stash(), "not while climbing in")
	exia.embark_left = 0.0
	exia.unseal_left = 1.0
	check(not exia.can_open_stash(), "not while the canopy opens")
	exia.unseal_left = 0.0
	exia.pilot = null
	check(not exia.can_open_stash(), "not with nobody aboard")


func test_exia_is_found_as_the_piloted_mech() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var inv := _inventory()
	eq(inv.piloted_mech(), null, "empty: no piloted mech")
	var pilot := _in_tree(_StubPilot.new())
	exia.pilot = pilot
	eq(inv.piloted_mech(), exia, "aboard: that one")
	exia.pilot = null


# --- the stash screen -----------------------------------------------------------------

func _stash_screen(mech: Node3D) -> Control:
	var s: Control = (load(SCREEN_TSCN) as PackedScene).instantiate()
	_in_tree(s)
	_inventory().stash_mech = mech
	s.present()
	return s


func test_stash_mode_swaps_the_vicinity_for_the_stash() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var s := _stash_screen(exia)
	check(s.is_stash_mode(), "opened for a mech: STASH mode")
	eq(_inventory().stash_mech, null, "the request is spent once read")
	eq(s.vicinity_items().size(), 0, "no vicinity in this mode")
	check(s.stash_cell_at(s.stash_cell_origin(Vector2i(9, 11)) + Vector2i(3, 3)) == Vector2i(9, 11),
		"the bottom-right stash cell is under the right-hand box")
	s.dismiss()


func test_click_moves_an_item_from_stash_to_pilot_grid() -> void:
	var inv := _inventory()
	var saved_g: ItemGrid = inv.grid
	var saved_s: ItemGrid = inv.stash
	inv.grid = ItemGrid.new(10, 6)
	inv.stash = ItemGrid.new(10, 12)
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var s := _stash_screen(exia)
	var crate := ItemStack.new(CRATE)
	inv.stash.place(crate, Vector2i(2, 3), false)
	s.left_click(s.stash_cell_origin(Vector2i(2, 3)) + Vector2i(3, 3))
	eq(s.held, crate, "took the crate out of the stash")
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	eq(s.held, null, "placed")
	eq(inv.grid.items, [crate], "now in his grid")
	eq(inv.stash.items.size(), 0, "and out of the stash")
	# Take it back and close: it goes home - to his grid, where it was taken from.
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	s.dismiss()
	eq(inv.grid.items, [crate], "closing returns it to the grid it came from")
	inv.grid = saved_g
	inv.stash = saved_s


func test_shift_click_moves_across_and_merges_stacks() -> void:
	var inv := _inventory()
	var saved_g: ItemGrid = inv.grid
	var saved_s: ItemGrid = inv.stash
	inv.grid = ItemGrid.new(10, 6)
	inv.stash = ItemGrid.new(10, 12)
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var s := _stash_screen(exia)
	var bat := ItemStack.new(BATTERY)
	inv.grid.place(bat, Vector2i(0, 0), false)
	s.shift_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	eq(inv.grid.items.size(), 0, "shift-click: out of his grid")
	eq(inv.stash.items.size(), 1, "into the stash")
	s.shift_click(s.stash_cell_origin(inv.stash.items[0].cell) + Vector2i(3, 3))
	eq(inv.grid.items.size(), 1, "shift-click in the stash: back to him")
	# Stacks merge first.
	inv.grid.items.clear()
	inv.stash.items.clear()
	var a := ItemStack.new(RATION, 2)
	var b := ItemStack.new(RATION, 2)
	inv.grid.place(a, Vector2i(0, 0), false)
	inv.stash.place(b, Vector2i(5, 5), false)
	s.shift_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	eq([inv.stash.items.size(), b.count], [1, 4], "rations topped up the stash's stack")
	s.dismiss()
	inv.grid = saved_g
	inv.stash = saved_s


func test_quick_move_with_no_room_does_nothing() -> void:
	var from := ItemGrid.new(10, 6)
	var to := ItemGrid.new(2, 2)
	to.place(ItemStack.new(MEDKIT), Vector2i(0, 0), false)
	var crate := ItemStack.new(CRATE)
	from.place(crate, Vector2i(0, 0), false)
	eq(SCREEN_SCRIPT.quick_move(crate, from, to), 0, "nothing moved")
	eq(from.items, [crate], "it stays put")


func test_nothing_reaches_the_ground_in_stash_mode() -> void:
	var inv := _inventory()
	var saved_g: ItemGrid = inv.grid
	inv.grid = ItemGrid.new(10, 6)
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var s := _stash_screen(exia)
	var bat := ItemStack.new(BATTERY)
	inv.grid.place(bat, Vector2i(0, 0), false)
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	# Click on the stash box's header strip - inside the box, outside its cells.
	var r: Rect2i = s.box_rect(SCREEN_SCRIPT.Box.VICINITY)
	s.left_click(r.position + Vector2i(4, 4))
	eq(s.held, bat, "no drop: still in the hand")
	s.dismiss()
	eq(inv.grid.items, [bat], "home again")
	inv.grid = saved_g
