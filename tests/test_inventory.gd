extends "res://tests/test_case.gd"

# The inventory, asserted against docs/specs/inventory.md.

const UI_MANAGER := preload("res://scripts/ui/ui_manager.gd")
const SCREEN_SCRIPT := preload("res://scripts/ui/inventory_screen.gd")
const SCREEN_TSCN := "res://scenes/ui/inventory_screen.tscn"
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const RATION := preload("res://resources/items/ration.tres")
const BATTERY := preload("res://resources/items/battery.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")
const CRATE := preload("res://resources/items/rifle_crate.tres")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _inventory() -> Node:
	return _tree().root.get_node(^"Inventory")


# --- the test items -------------------------------------------------------------------

func test_the_four_placeholder_items() -> void:
	eq([RATION.size, RATION.max_stack], [Vector2i(1, 1), 5], "ration 1x1, stacks to 5")
	eq([BATTERY.size, BATTERY.max_stack], [Vector2i(1, 2), 1], "battery 1x2")
	eq([MEDKIT.size, MEDKIT.max_stack], [Vector2i(2, 2), 1], "medkit 2x2")
	eq([CRATE.size, CRATE.max_stack], [Vector2i(2, 4), 1], "rifle crate 2x4")


# --- the grid -------------------------------------------------------------------------

func test_the_player_grid_is_10_by_6() -> void:
	var inv := _inventory()
	eq([inv.grid.width, inv.grid.height], [10, 6], "one fixed 10 x 6 container")


func test_items_never_overlap_or_leave_the_grid() -> void:
	var g := ItemGrid.new(10, 6)
	var med := ItemStack.new(MEDKIT)
	check(g.place(med, Vector2i(0, 0), false), "a medkit fits in the corner")
	check(not g.fits(Vector2i(1, 1), Vector2i(1, 1)), "a cell under the medkit is taken")
	check(g.fits(Vector2i(2, 0), Vector2i(1, 1)), "the cell beside it is free")
	check(not g.fits(Vector2i(9, 0), Vector2i(2, 2)), "hanging off the right edge does not fit")
	check(not g.fits(Vector2i(0, 5), Vector2i(1, 2)), "hanging off the bottom does not fit")
	check(g.fits(Vector2i(0, 0), Vector2i(2, 2), med), "the item being moved does not block itself")
	eq(g.item_at(Vector2i(1, 1)), med, "item_at finds it from any of its cells")


func test_rotation_swaps_the_footprint() -> void:
	var s := ItemStack.new(CRATE)
	eq(s.footprint(), Vector2i(2, 4), "upright 2x4")
	s.rotated = true
	eq(s.footprint(), Vector2i(4, 2), "rotated 4x2")


func test_find_free_tries_upright_first_then_rotated() -> void:
	var g := ItemGrid.new(4, 3)
	eq(g.find_free(Vector2i(2, 4)), {"cell": Vector2i(0, 0), "rotated": true},
		"a 2x4 only fits a 4x3 grid on its side")
	eq(g.find_free(Vector2i(1, 2)), {"cell": Vector2i(0, 0), "rotated": false}, "upright when it can")


func test_add_tops_up_stacks_before_starting_a_new_one() -> void:
	var g := ItemGrid.new(10, 6)
	eq(g.add(RATION, 3), 3, "three rations go in")
	eq(g.add(RATION, 4), 4, "four more go in")
	eq(g.items.size(), 2, "the first stack filled to 5, the rest started a second")
	eq([g.items[0].count, g.items[1].count], [5, 2], "5 + 2")


func test_a_full_grid_takes_nothing() -> void:
	var g := ItemGrid.new(2, 2)
	g.add(MEDKIT, 1)
	eq(g.capacity_for(BATTERY), 0, "no room for a battery")
	eq(g.add(BATTERY, 1), 0, "add takes nothing")
	eq(g.items.size(), 1, "and changes nothing")


func test_merge_into_respects_the_stack_limit() -> void:
	var g := ItemGrid.new(10, 6)
	g.add(RATION, 4)
	var loose := ItemStack.new(RATION, 3)
	eq(g.merge_into(g.items[0], loose), 1, "only one fits on top of four")
	eq(loose.count, 2, "two stay in the hand")
	eq(g.merge_into(g.items[0], ItemStack.new(MEDKIT)), 0, "different kinds never merge")


# --- vicinity --------------------------------------------------------------------------

func test_vicinity_packs_nearest_first_top_to_bottom() -> void:
	var inv_script: GDScript = load("res://scripts/inventory/inventory.gd")
	var spots: Array = inv_script.pack([Vector2i(2, 4), Vector2i(2, 2), Vector2i(1, 1)], 10)
	eq(spots[0], {"cell": Vector2i(0, 0), "rotated": false}, "the nearest goes top-left")
	eq(spots[1], {"cell": Vector2i(2, 0), "rotated": false}, "the next beside it")
	eq(spots[2], {"cell": Vector2i(4, 0), "rotated": false}, "and the next")
	var narrow: Array = inv_script.pack([Vector2i(1, 1), Vector2i(4, 1)], 2)
	eq(narrow[1], {"cell": Vector2i(1, 0), "rotated": true}, "too wide upright stands on its side beside it")


func test_the_vicinity_and_pickup_numbers() -> void:
	var inv := _inventory()
	approx(inv.VICINITY_RADIUS, 2.5, 0.0001, "vicinity is 2.5 m")
	approx(inv.PICKUP_REACH, 2.0, 0.0001, "F reaches 2 m")


func test_f_pickup_needs_reach_and_facing() -> void:
	var fwd := Vector3(0, 0, -1)
	check(WorldItem.in_pickup_reach(Vector3(0, 0, -1.5), Vector3.ZERO, fwd), "1.5 m ahead is in reach")
	check(not WorldItem.in_pickup_reach(Vector3(0, 0, -2.5), Vector3.ZERO, fwd), "2.5 m ahead is out")
	check(not WorldItem.in_pickup_reach(Vector3(0, 0, 1.5), Vector3.ZERO, fwd), "behind him is out")
	check(WorldItem.in_pickup_reach(Vector3(0.1, -0.6, 0.1), Vector3.ZERO, fwd), "at his feet counts")


func test_world_items_carry_the_trial_test_loot() -> void:
	var packed: PackedScene = load("res://scenes/trial.tscn")
	var state := packed.get_state()
	var loot := 0
	for i in state.get_node_count():
		if str(state.get_node_path(i)).begins_with("./TestLoot/"):
			loot += 1
	eq(loot, 5, "one of each test item lies near the trial spawn")


# --- the UI stack ----------------------------------------------------------------------

func test_the_inventory_screen_runs_over_a_live_world() -> void:
	var state := UI_MANAGER.resolve([], UI_MANAGER.Action.PUSH, true, &"inventory")
	eq(state["stack"], [&"inventory"], "Tab pushes the inventory")
	eq(state["paused"], false, "the world keeps running")
	eq(state["cursor_captured"], false, "the cursor shows")
	var back := UI_MANAGER.resolve([&"inventory"], UI_MANAGER.Action.BACK, true)
	eq(back["stack"], [], "Esc closes it - it never opens the pause menu")
	check(not UI_MANAGER.wants_dim([&"inventory"]), "it draws its own dim")
	check(UI_MANAGER.wants_dim([&"shell"]), "the shell still gets the flat dim")


func test_the_pause_menu_has_no_inventory_tab() -> void:
	var shell: GDScript = load("res://scripts/ui/shell.gd")
	for tab: Dictionary in shell.TABS:
		check(tab["label"] != "INVENTORY", "INVENTORY left the pause shell")
	check(InputMap.has_action(&"inventory"), "the inventory action exists")
	var keys: Array = []
	for e in InputMap.action_get_events(&"inventory"):
		if e is InputEventKey:
			keys.append((e as InputEventKey).physical_keycode)
	eq(keys, [KEY_TAB], "bound to Tab")


# --- the screen ------------------------------------------------------------------------

func test_texels_are_whole_pixels() -> void:
	eq(SCREEN_SCRIPT.scale_for(1080.0, 360.0), 3, "3 px per texel at 1080p")
	eq(SCREEN_SCRIPT.scale_for(800.0, 360.0), 2, "2 at 800")
	eq(SCREEN_SCRIPT.scale_for(1440.0, 360.0), 4, "4 at 1440")
	eq(SCREEN_SCRIPT.scale_for(200.0, 360.0), 1, "never below 1")


func _screen() -> Control:
	var s: Control = (load(SCREEN_TSCN) as PackedScene).instantiate()
	_tree().root.add_child(s)
	s.present()
	return s


func test_click_take_click_place_and_rotate() -> void:
	var inv := _inventory()
	var saved: ItemGrid = inv.grid
	inv.grid = ItemGrid.new(10, 6)
	var s := _screen()
	var bat := ItemStack.new(BATTERY)
	inv.grid.place(bat, Vector2i(0, 0), false)
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	eq(s.held, bat, "a click takes the battery into the hand")
	eq(inv.grid.items.size(), 0, "it left the grid while held")
	s.rotate_held()
	check(bat.rotated, "R turns it on its side")
	s.left_click(s.grid_cell_origin(Vector2i(4, 2)) + Vector2i(3, 3))
	eq(s.held, null, "a second click places it")
	eq([bat.cell, bat.rotated], [Vector2i(4, 2), true], "where it was put, on its side")
	# Take it again and close: it goes home.
	s.left_click(s.grid_cell_origin(Vector2i(4, 2)) + Vector2i(3, 3))
	s.dismiss()
	eq(s.held, null, "closing empties the hand")
	eq(inv.grid.items, [bat], "the held item went back into the grid")
	eq(bat.cell, Vector2i(4, 2), "to the spot it came from")
	s.free()
	inv.grid = saved


func test_a_blocked_place_keeps_it_in_the_hand() -> void:
	var inv := _inventory()
	var saved: ItemGrid = inv.grid
	inv.grid = ItemGrid.new(10, 6)
	var s := _screen()
	var med := ItemStack.new(MEDKIT)
	var bat := ItemStack.new(BATTERY)
	inv.grid.place(med, Vector2i(0, 0), false)
	inv.grid.place(bat, Vector2i(5, 0), false)
	s.left_click(s.grid_cell_origin(Vector2i(5, 0)) + Vector2i(3, 3))
	s.left_click(s.grid_cell_origin(Vector2i(1, 1)) + Vector2i(3, 3))
	eq(s.held, bat, "onto the medkit does not place")
	s.dismiss()
	s.free()
	inv.grid = saved


func test_the_boxes_sit_left_to_right_inside_the_canvas() -> void:
	var s := _screen()
	var p: Rect2i = s.box_rect(SCREEN_SCRIPT.Box.PORTRAIT)
	var g: Rect2i = s.box_rect(SCREEN_SCRIPT.Box.GRID)
	var v: Rect2i = s.box_rect(SCREEN_SCRIPT.Box.VICINITY)
	var pack: Rect2i = s.box_rect(SCREEN_SCRIPT.Box.PACK)
	check(p.end.x < g.position.x and g.end.x < v.position.x, "portrait | grid | vicinity")
	check(p.size.y > p.size.x and v.size.y > g.size.y, "tall sides, a shorter landscape middle")
	check(g.size.x > g.size.y, "the middle is landscape")
	check(pack.position.y > g.end.y, "the backpack box sits under the grid")
	check(p.position.x >= 0 and v.end.x <= 640, "everything fits a 640-texel canvas")
	s.dismiss()
	s.free()


# --- pilot9 ----------------------------------------------------------------------------

func test_the_hold_freezes_him_and_lets_go() -> void:
	var pilot: Node = (load(PILOT_TSCN) as PackedScene).instantiate()
	_tree().root.add_child(pilot)
	check(not pilot.frozen, "a controlled pilot starts free")
	pilot.set_inventory_hold(true)
	check(pilot.frozen, "the open inventory holds him")
	check(not pilot.can_open_inventory(), "and a held pilot cannot open it again")
	pilot.set_controlled(false)
	pilot.set_controlled(true)
	check(pilot.frozen, "a pilot switch does not drop the hold")
	pilot.set_inventory_hold(false)
	check(not pilot.frozen, "closing lets him go")
	pilot.is_dashing = true
	check(not pilot.can_open_inventory(), "not mid-dash")
	pilot.is_dashing = false
	pilot.visible = false
	check(not pilot.can_open_inventory(), "not aboard EXIA (hidden)")
	pilot.free()


# --- the polish pass (docs/specs/inventory.md, "Polish pass") ------------------------------

func _swap_grid() -> Array:
	var inv := _inventory()
	var saved: ItemGrid = inv.grid
	inv.grid = ItemGrid.new(10, 6)
	return [inv, saved]


func test_items_carry_a_category_and_a_description() -> void:
	for def: ItemDef in [RATION, BATTERY, MEDKIT, CRATE]:
		check(ItemDef.CATEGORIES.has(def.category), "%s has a known category" % def.display_name)
		check(def.description != "", "%s has an Inspect description" % def.display_name)
	eq([RATION.category, MEDKIT.category, CRATE.category], [&"food", &"medical", &"ammo"], "the test items")


func test_drag_places_on_release_and_a_bad_drop_goes_home() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	var bat := ItemStack.new(BATTERY)
	var med := ItemStack.new(MEDKIT)
	inv.grid.place(bat, Vector2i(0, 0), false)
	inv.grid.place(med, Vector2i(5, 0), false)
	# Press on the battery, drag, release on a free cell.
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	eq(s.held, bat, "the press picked it up")
	s._dragging = true
	s._mouse = s.grid_cell_origin(Vector2i(3, 3)) + Vector2i(3, 3)
	s.release_drag(s._mouse)
	eq([s.held, bat.cell], [null, Vector2i(3, 3)], "released on a free cell it lands there")
	# Drag it onto the medkit: it cannot go, so it returns to where the drag began.
	s.left_click(s.grid_cell_origin(Vector2i(3, 3)) + Vector2i(3, 3))
	s._dragging = true
	s.release_drag(s.grid_cell_origin(Vector2i(5, 0)) + Vector2i(3, 3))
	eq([s.held, bat.cell], [null, Vector2i(3, 3)], "released on the medkit it goes home")
	# Released over nothing at all: home too.
	s.left_click(s.grid_cell_origin(Vector2i(3, 3)) + Vector2i(3, 3))
	s._dragging = true
	s.release_drag(Vector2i(2, 2))
	eq([s.held, bat.cell], [null, Vector2i(3, 3)], "released over empty space it goes home")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]


func test_a_click_still_carries_it_until_the_next_click() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	var bat := ItemStack.new(BATTERY)
	inv.grid.place(bat, Vector2i(0, 0), false)
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	check(s.held == bat, "without a drag the item stays on the cursor after release")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]


func test_ctrl_click_takes_half_a_stack_and_putting_it_back_re_merges() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	var rations := ItemStack.new(RATION, 5)
	inv.grid.place(rations, Vector2i(0, 0), false)
	s.split_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	eq([s.held.count, rations.count], [3, 2], "half, rounded up, comes up; the rest stays")
	s.dismiss()
	eq([inv.grid.items.size(), rations.count], [1, 5], "closing pours it back into the stack")
	var single := ItemStack.new(RATION, 1)
	inv.grid.place(single, Vector2i(4, 0), false)
	s.split_click(s.grid_cell_origin(Vector2i(4, 0)) + Vector2i(3, 3))
	eq(s.held, null, "a stack of one cannot be split")
	s.free()
	inv.grid = ctx[1]


func test_the_popup_lists_the_right_rows() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	inv.grid.place(ItemStack.new(RATION, 3), Vector2i(0, 0), false)
	inv.grid.place(ItemStack.new(MEDKIT), Vector2i(4, 0), false)
	check(s.open_menu(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3)), "RMB on an item opens a popup")
	var ids: Array = s.menu_entries().map(func(e: Dictionary) -> StringName: return e["id"])
	eq(ids, [&"drop", &"split", &"inspect"], "a stack: drop, split, inspect")
	s.menu_choose(&"inspect")
	eq(s._card_def, RATION, "Inspect shows that item's card")
	s._close_menu()
	s._card_def = null
	s.open_menu(s.grid_cell_origin(Vector2i(4, 0)) + Vector2i(3, 3))
	ids = s.menu_entries().map(func(e: Dictionary) -> StringName: return e["id"])
	eq(ids, [&"drop", &"inspect"], "a single item has no split")
	s._close_menu()
	check(not s.open_menu(s.grid_cell_origin(Vector2i(9, 5))), "RMB on an empty cell opens nothing")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]


func test_a_popup_click_outside_just_closes_it() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	var med := ItemStack.new(MEDKIT)
	inv.grid.place(med, Vector2i(0, 0), false)
	s.open_menu(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	s.left_click(Vector2i(1, 1))
	check(not s.menu_is_open(), "the popup is gone")
	eq(s.held, null, "and the click did nothing else")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]


func test_sort_merges_stacks_groups_categories_and_undo_restores() -> void:
	var g := ItemGrid.new(10, 6)
	g.place(ItemStack.new(CRATE), Vector2i(8, 0), false)
	g.place(ItemStack.new(RATION, 3), Vector2i(5, 5), false)
	g.place(ItemStack.new(MEDKIT), Vector2i(0, 4), false)
	g.place(ItemStack.new(RATION, 4), Vector2i(2, 0), false)
	var before := g.snapshot()
	check(g.sort_items(), "the repack fits")
	var counts := {}
	for it in g.items:
		counts[it.def] = counts.get(it.def, 0) + it.count
	eq([counts[RATION], counts[MEDKIT], counts[CRATE]], [7, 1, 1], "nothing was lost")
	eq(g.items.filter(func(i: ItemStack) -> bool: return i.def == RATION).size(), 2, "7 rations = a full 5 and a 2")
	eq(g.items[0].def, MEDKIT, "medical first")
	eq(g.items[g.items.size() - 1].def, CRATE, "ammo after food")
	g.restore(before)
	eq(g.snapshot(), before, "restore puts the old layout back")


func test_screen_undo_only_works_while_the_grid_is_as_sort_left_it() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	inv.grid.place(ItemStack.new(RATION, 3), Vector2i(6, 4), false)
	inv.grid.place(ItemStack.new(MEDKIT), Vector2i(3, 2), false)
	var before: Array = inv.grid.snapshot()
	s.sort_all()
	check(s.can_undo_sort(), "a sort can be undone")
	check(s.undo_sort(), "Ctrl+Z undoes it")
	eq(inv.grid.snapshot(), before, "the layout is back")
	s.sort_all()
	inv.grid.add(BATTERY, 1)
	check(not s.undo_sort(), "after anything else changed the grid, undo does nothing")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]


func test_the_drop_preview_says_fit_merge_or_bad() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	var rations := ItemStack.new(RATION, 2)
	var med := ItemStack.new(MEDKIT)
	inv.grid.place(rations, Vector2i(0, 0), false)
	inv.grid.place(med, Vector2i(4, 0), false)
	s._hold(ItemStack.new(RATION, 1), Vector2i.ZERO, null)
	s._mouse = s.grid_cell_origin(Vector2i(2, 2)) + Vector2i(3, 3)
	eq(s.drop_preview()["state"], "fit", "a free cell fits")
	s._mouse = s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3)
	eq(s.drop_preview()["state"], "merge", "onto a matching stack with room merges")
	s._mouse = s.grid_cell_origin(Vector2i(4, 0)) + Vector2i(3, 3)
	eq(s.drop_preview()["state"], "bad", "onto a medkit does not")
	s._mouse = Vector2i(2, 2)
	eq(s.drop_preview(), {}, "over no grid there is no preview")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]


func test_sound_hooks_fire() -> void:
	var ctx := _swap_grid()
	var inv: Node = ctx[0]
	var s := _screen()
	var heard: Array = []
	s.sound.connect(func(kind: StringName) -> void: heard.append(kind))
	inv.grid.place(ItemStack.new(BATTERY), Vector2i(0, 0), false)
	inv.grid.place(ItemStack.new(MEDKIT), Vector2i(5, 0), false)
	s.left_click(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(3, 3))
	s.rotate_held()
	s.left_click(s.grid_cell_origin(Vector2i(5, 0)) + Vector2i(3, 3))
	s.left_click(s.grid_cell_origin(Vector2i(3, 3)) + Vector2i(3, 3))
	eq(heard, [&"pick", &"rotate", &"invalid", &"place"], "pick, rotate, invalid, place")
	s.dismiss()
	s.free()
	inv.grid = ctx[1]
