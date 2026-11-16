extends Control

# The inventory: Tab, three boxes - portrait | your 10 x 6 grid | vicinity - drawn PS1 over a
# running world. A non-pausing UI screen (`&"inventory"` in ui_manager.gd). See
# docs/specs/inventory.md.
#
# Everything is drawn into one low-res canvas (a SubViewport `texel_scale()` times smaller than
# the window) and shown nearest through shaders/ui/inventory_ps1.gdshader. Layout, hit-testing and
# drawing all work in canvas texels; the mouse is divided down into them.
#
# Mouse: LMB click takes, LMB click places; R rotates what is held; RMB quick-moves (ground ->
# first free spot, grid -> ground); LMB drag on the portrait turns him. Tab / Esc close, and
# whatever is held goes back where it came from.
#
# STASH mode (docs/specs/mech-stash.md): opened for a mech through Inventory.open_stash(). The
# portrait is the mech, the right-hand box is its stash - a real grid like the pilot's - and RMB
# quick-moves between the two grids. No vicinity: nothing reaches the ground from here.

const InventoryScript := preload("res://scripts/inventory/inventory.gd")
const PS1_SHADER := preload("res://shaders/ui/inventory_ps1.gdshader")
const PORTRAIT_SCRIPT := preload("res://scripts/ui/inventory_portrait.gd")
const BASE_FONT := preload("res://assets/fonts/PixelifySans.ttf")
const WORLD_ITEM := preload("res://scripts/inventory/world_item.gd")

const CYAN := Color(0.251, 0.949, 0.902)
const CYAN_DIM := Color(0.251, 0.949, 0.902) * Color(0.35, 0.35, 0.35, 1.0)
const PLATE := Color(0.02, 0.055, 0.065, 1.0)
const BEVEL_SHADE := Color(0.0, 0.42, 0.42)
## Title-bar bands, light to dark, hard steps.
const BAND_A := Color(0.0, 0.30, 0.31)
const BAND_B := Color(0.0, 0.22, 0.24)
const BAND_C := Color(0.0, 0.14, 0.16)
const TEXT := Color(0.92, 0.95, 0.95)
const GOOD := Color(0.35, 1.0, 0.5)
const BAD := Color(1.0, 0.3, 0.25)

## Canvas lines on a 1080p-equivalent window. 360 = 3 px per texel at 1080p. The scale is the
## nearest whole number, so texels stay square and even.
@export var lines := 360.0
@export var unfold_time := 0.1
@export var fold_time := 0.08
## Seconds between the boxes starting to unfold, left to right.
@export var stagger := 0.03
## The world behind, darkened by this much.
@export var dim := 0.5
## Seconds between vicinity re-scans.
@export var vicinity_interval := 0.2

## Layout, texels.
const CELL := 16
const PAD := 4
const HEADER := 14
const GAP := 8
const PORTRAIT_W := 112
const SIDE_ROWS := 15
const HEADER_SIZE := 12
const LABEL_SIZE := 10
## Equipment slots inside the portrait box: clothes down the left edge, weapons down the right.
const SLOT_W := 24
const SLOT_H := 52
const SLOT_LABELS := {&"head": "HEAD", &"body": "BODY", &"legs": "LEGS", &"back": "BACK", &"weapon_1": "1", &"weapon_2": "2"}
## Clothes slots before the weapon gap (HEAD BODY LEGS BACK).
const CLOTHES_SLOTS := 4
## The worn backpack's box under the grid, in cell rows (docs/specs/pilot9-backpack.md).
const PACK_ROWS := 4
## The hover tooltip: width, and its offset from the cursor.
const TIP_W := 132
const TIP_OFFSET := Vector2i(8, 10)

## Category tints (corner glyph + item edge) - muted so they sit under the cyan UI.
const CATEGORY_COLORS := {
	&"food": Color(0.6, 0.85, 0.3),
	&"medical": Color(1.0, 0.45, 0.7),
	&"ammo": Color(1.0, 0.75, 0.25),
	&"gear": CYAN,
	&"junk": Color(0.62, 0.66, 0.66),
}
## Drag starts once the cursor has moved this many texels with the button down.
const DRAG_TEXELS := 2
## Seconds for the placement flash, the invalid-drop shake, and the popup unfold.
const FLASH_TIME := 0.06
const SHAKE_TIME := 0.2
const MENU_UNFOLD := 0.1
const MENU_ROW := 12
const SORT_W := 44
const CARD_W := 124

enum Box { PORTRAIT, GRID, VICINITY, PACK }

## Sound hooks: fired on pick / place / rotate / invalid / drop / sort. Nothing plays yet - the
## project has no audio; connect a player here when it does.
signal sound(kind: StringName)

var _font: FontFile
var _dim_rect: ColorRect
var _display: TextureRect
var _canvas_vp: SubViewport
var _canvas: Control
var _portrait: SubViewport

var _scale := 3
var _texels := Vector2i(640, 360)
var _mouse := Vector2i(-1000, -1000)

# Animation: seconds since present(), or since dismiss() while folding (_folding true).
var _t := 0.0
var _folding := false
var _held_pilot: Node = null
# STASH mode: the mech whose stash is open (null = the normal pilot screen), and the mech held
# still because it was opened from inside.
var _stash_mech: Node3D = null
var _held_mech: Node = null

# Vicinity: ground items nearest first, their packed spots, the scroll in rows.
var _vicinity: Array[Node3D] = []
var _packed: Array = []
var _vic_scroll := 0
var _vic_timer := 0.0
## Open pack windows (docs/specs/pilot9-backpack.md, "Pack windows"), back to front:
## {"grid": ItemGrid, "node": ground WorldItem or null, "stack": ItemStack in a grid or null,
## "pos": Vector2i texels}.
var _windows: Array = []
var _win_drag := -1
var _win_drag_off := Vector2i.ZERO

# What the cursor holds. `held` null = nothing.
var held: ItemStack = null
var _held_ground: Node3D = null
# The grid the held item was taken from (null = the ground).
var _held_grid: ItemGrid = null
var _held_offset := Vector2i.ZERO
var _held_origin := Vector2i.ZERO
var _held_origin_rot := false
# The equipment slot the held item came from (&"" = none): returning it re-wears it there.
var _held_slot: StringName = &""

var _turning := false

# Drag: the button went down on an item that is now held; it becomes a drag once the cursor moves.
var _drag_pending := false
var _dragging := false
var _press := Vector2i.ZERO
# The stack a split came off, so an unplaced half goes back into it.
var _held_split_src: ItemStack = null

# Feedback: placement flashes (texel rects + seconds left), the invalid-drop shake clock.
var _flashes: Array = []
var _shake := 0.0

# Context popup: {"at": texel pos, "entries": [{id, label, enabled}], "target": {...}}, its
# unfold clock, and the Inspect card (def + count, shown at `_card_at`).
var _menu: Dictionary = {}
var _menu_t := 0.0
var _card_def: ItemDef = null
var _card_count := 0
var _card_at := Vector2i.ZERO

# Sort: the vicinity sorts too while open; undo restores the grid snapshots until anything else
# changes them.
var _vic_sorted := false
var _undo: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = BASE_FONT.duplicate() as FontFile
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.hinting = TextServer.HINTING_LIGHT
	_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_font.generate_mipmaps = false

	_dim_rect = ColorRect.new()
	_dim_rect.name = "Dim"
	_dim_rect.color = Color(0, 0, 0, 0)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim_rect)

	_canvas_vp = SubViewport.new()
	_canvas_vp.name = "Canvas"
	_canvas_vp.transparent_bg = true
	_canvas_vp.disable_3d = true
	_canvas_vp.snap_2d_transforms_to_pixel = true
	_canvas_vp.snap_2d_vertices_to_pixel = true
	_canvas_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_canvas_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_canvas_vp)
	_canvas = Control.new()
	_canvas.name = "Draw"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_canvas)
	_canvas_vp.add_child(_canvas)

	_portrait = PORTRAIT_SCRIPT.new()
	_portrait.name = "Portrait"
	add_child(_portrait)

	_display = TextureRect.new()
	_display.name = "Display"
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.texture = _canvas_vp.get_texture()
	var mat := ShaderMaterial.new()
	mat.shader = PS1_SHADER
	_display.material = mat
	add_child(_display)

	set_process(false)


# --- open / close (called by ui_manager.gd) -------------------------------------------------

func present(_holo: bool = false) -> void:
	_folding = false
	_t = 0.0
	visible = true
	_resize_canvas()
	# STASH mode is asked for once, by whoever opened it; reading it clears it.
	_stash_mech = Inventory.stash_mech if is_instance_valid(Inventory.stash_mech) else null
	Inventory.stash_mech = null
	var pilot := Inventory.player()
	if pilot != null and pilot.has_method(&"set_inventory_hold"):
		pilot.set_inventory_hold(true)
		_held_pilot = pilot
	if _stash_mech != null and _stash_mech.get("pilot") != null and _stash_mech.has_method(&"set_stash_hold"):
		_stash_mech.set_stash_hold(true)
		_held_mech = _stash_mech
	if _stash_mech != null:
		_portrait.show_body(_stash_mech)
	else:
		_portrait.show_body(pilot)
	_vic_scroll = 0
	_close_menu()
	_card_def = null
	_flashes.clear()
	_shake = 0.0
	_drag_pending = false
	_dragging = false
	_vic_sorted = false
	_undo.clear()
	_vicinity.clear()
	_packed.clear()
	close_windows()
	if not is_stash_mode():
		_refresh_vicinity()
	_canvas_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)


func dismiss() -> void:
	_close_menu()
	_win_drag = -1
	_card_def = null
	_return_held()
	_release_pilot()
	_turning = false
	_folding = true
	_t = 0.0


func is_open() -> bool:
	return visible and not _folding


## STASH mode: the grid on the right - the vehicle's own (a speeder's) or EXIA's.
func stash_grid() -> ItemGrid:
	return Inventory.stash_of(_stash_mech)


## STASH mode: the portrait box's title - the vehicle's `display_name`, else EXIA.
func stash_title() -> String:
	var n: Variant = _stash_mech.get(&"display_name") if _stash_mech != null else null
	return String(n) if n is String and n != "" else "EXIA"


## True while open on a mech's stash rather than the vicinity.
func is_stash_mode() -> bool:
	return _stash_mech != null


func _release_pilot() -> void:
	if _held_pilot != null and is_instance_valid(_held_pilot):
		_held_pilot.set_inventory_hold(false)
	_held_pilot = null
	if _held_mech != null and is_instance_valid(_held_mech):
		_held_mech.set_stash_hold(false)
	_held_mech = null


func _finish_close() -> void:
	close_windows()
	visible = false
	_folding = false
	_portrait.hide_pilot()
	_canvas_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)


func _notification(what: int) -> void:
	# ui_manager.gd hides screens outright in some paths (a scene change clears the stack).
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and _portrait != null:
		_return_held()
		_release_pilot()
		_portrait.hide_pilot()
		set_process(false)


# --- input --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var ui := get_node_or_null(^"/root/UI")
	if ui == null or get_tree().paused:
		return
	if event.is_action_pressed(&"inventory") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if is_open():
			ui.back()
		elif ui.stack.is_empty() and ui.shell_enabled:
			# Aboard a mech, Tab is the stash (docs/specs/mech-stash.md, decision 7).
			var mech := Inventory.piloted_mech()
			if mech != null:
				if mech.can_open_stash():
					Inventory.open_stash(mech)
				return
			var pilot := Inventory.player()
			if pilot != null and pilot.has_method(&"can_open_inventory") and pilot.can_open_inventory():
				ui.open(&"inventory")
		return
	if not is_open():
		return
	# Esc / pause go on to ui_manager.gd, which backs this screen out.
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		# Esc closes the popup or the Inspect card first; the screen closes on the next one.
		if not _menu.is_empty() or _card_def != null:
			_close_menu()
			_card_def = null
			get_viewport().set_input_as_handled()
		elif not _windows.is_empty() and held == null:
			# Then the front pack window, one per press.
			close_window(_windows.size() - 1)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.is_echo():
			match k.physical_keycode:
				KEY_R:
					rotate_held()
				KEY_T:
					sort_all()
				KEY_Q:
					quick_drop(_mouse)
				KEY_Z:
					if k.ctrl_pressed:
						undo_sort()
		# Nothing else in the world reads the keyboard while this is open: F would open a door, 1/2
		# would switch pilots.
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseMotion:
		_mouse = to_texel((event as InputEventMouseMotion).position)
		if _win_drag >= 0:
			window_drag_to(_mouse)
		if _turning:
			_portrait.turn((event as InputEventMouseMotion).relative.x)
		if _drag_pending and not _dragging and held != null \
				and Vector2(_mouse - _press).length() > DRAG_TEXELS:
			_dragging = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = to_texel(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = _mouse
				if _menu.is_empty() and _card_def == null and window_press(_mouse):
					pass
				elif mb.shift_pressed and held == null:
					shift_click(_mouse)
				elif mb.ctrl_pressed and held == null:
					split_click(_mouse)
				else:
					var had := held != null
					left_click(_mouse)
					# Picked something up with this press: it is a drag if the cursor now moves.
					_drag_pending = not had and held != null
			else:
				_turning = false
				_win_drag = -1
				if _dragging:
					release_drag(_mouse)
				_drag_pending = false
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _menu.is_empty() and _card_def == null:
				raise_window(window_at(_mouse))
			right_click(_mouse)
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if not is_stash_mode() and box_rect(Box.VICINITY).has_point(_mouse) and window_at(_mouse) < 0:
				scroll_vicinity(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
	accept_event()


func to_texel(screen_pos: Vector2) -> Vector2i:
	return Vector2i(floori(screen_pos.x / _scale), floori(screen_pos.y / _scale))


# --- actions (public so tests can drive them with texel positions) -------------------------

func left_click(at: Vector2i) -> void:
	# A popup or an Inspect card eats the click: a row picks, anywhere else just closes it.
	if not _menu.is_empty():
		var id := menu_entry_at(at)
		var menu_target: Dictionary = _menu["target"]
		_close_menu()
		if id != &"":
			menu_choose(id, menu_target)
		return
	if _card_def != null:
		_card_def = null
		return
	if sort_button_rect().has_point(at) and held == null and window_at(at) < 0:
		sort_all()
		return
	var on_window := window_at(at) >= 0
	if held == null:
		var worn_slot := slot_at(at)
		if worn_slot != &"":
			var worn := Inventory.unequip(worn_slot)
			if worn != null:
				_hold(worn, Vector2i.ZERO, null)
				_held_slot = worn_slot
			return
		if box_rect(Box.PORTRAIT).has_point(at) and not on_window:
			_turning = true
			return
		var hit := _grid_hit(at)
		if not hit.is_empty():
			var g: ItemGrid = hit["grid"]
			var it := g.item_at(hit["cell"])
			if it != null and it.def.mech_only:
				_take_crate(it, g)
				return
			if it != null:
				_hold(it, hit["cell"] - it.cell, null)
				_held_grid = g
				g.remove(it)
			return
		if is_stash_mode():
			return
		var ground := vicinity_item_at(at)
		if ground != null:
			var stack := ItemStack.new(ground.def, mini(ground.count, ground.def.max_stack), ground.get(&"contents"))
			var i := _vicinity.find(ground)
			stack.rotated = _packed[i]["rotated"]
			_hold(stack, vicinity_cell_at(at) - _vic_spot(i), ground)
		return
	var onto := slot_at(at)
	if onto != &"":
		_place_in_slot(onto)
		return
	var target := _grid_hit(at)
	if not target.is_empty():
		_place_held(target["grid"], target["cell"] - _held_offset, target["cell"])
		if held != null:
			_invalid()
	elif on_window:
		_invalid()
	elif not is_stash_mode() and box_rect(Box.VICINITY).has_point(at):
		if _held_ground == null:
			if Inventory.drop(held, Inventory.player()) == null:
				_return_held()
				return
			sound.emit(&"drop")
		held = null
		_held_ground = null
		_held_split_src = null
		_held_slot = &""
		_refresh_vicinity()


## The button came up after a drag: place where it is, and anything that does not take goes
## back to where it came from.
func release_drag(at: Vector2i) -> void:
	_dragging = false
	_drag_pending = false
	if held == null:
		return
	left_click(at)
	if held != null:
		_return_held()


## Shift + LMB: an instant transfer. Grid -> ground (or grid <-> stash in STASH mode), ground ->
## grid, worn -> grid. Whatever fits moves; nothing else changes.
func shift_click(at: Vector2i) -> void:
	if held != null:
		return
	var worn_slot := slot_at(at)
	if worn_slot != &"":
		unequip_to_grid(worn_slot)
		return
	var hit := _grid_hit(at)
	if not hit.is_empty():
		var g: ItemGrid = hit["grid"]
		var it := g.item_at(hit["cell"])
		if it != null:
			if _is_window_grid(g):
				# Out of an open pack: into his grid, then the worn pack.
				for to in Inventory.carry_grids():
					quick_move(it, g, to)
					if not g.items.has(it):
						break
			elif front_window_grid() != null and Inventory.carry_grids().has(g):
				# Into the front pack window only - no spill into others.
				if quick_move(it, g, front_window_grid()) <= 0:
					_invalid()
			else:
				_transfer(it, g)
		return
	if is_stash_mode():
		return
	var ground := vicinity_item_at(at)
	if ground != null:
		_take_ground(ground)


func _transfer(it: ItemStack, g: ItemGrid) -> void:
	if it.def.mech_only:
		_take_crate(it, g)
	elif is_stash_mode():
		if g == stash_grid():
			# Into his grid first, then the worn pack.
			for to in Inventory.carry_grids():
				quick_move(it, g, to)
				if not g.items.has(it):
					break
		else:
			quick_move(it, g, stash_grid())
	else:
		g.remove(it)
		Inventory.drop(it, Inventory.player())
		sound.emit(&"drop")
		_refresh_vicinity()


func _take_ground(ground: Node3D) -> void:
	if Inventory.take(ground) > 0:
		sound.emit(&"place")
	_refresh_vicinity()


## Ctrl + LMB: half of a stack (rounded up) comes up on the cursor.
func split_click(at: Vector2i) -> void:
	if held != null:
		return
	var hit := _grid_hit(at)
	if not hit.is_empty():
		var g: ItemGrid = hit["grid"]
		var it := g.item_at(hit["cell"])
		if it != null:
			_split_from_grid(g, it, hit["cell"])
		return
	if is_stash_mode():
		return
	var ground := vicinity_item_at(at)
	if ground != null:
		_split_ground(ground, at)


func _half(n: int) -> int:
	@warning_ignore("integer_division")
	return (n + 1) / 2


func _split_from_grid(g: ItemGrid, it: ItemStack, cell: Vector2i) -> bool:
	if not it.def.stackable() or it.count < 2:
		return false
	var half := g.split(it, _half(it.count))
	if half == null:
		return false
	_hold(half, Vector2i.ZERO, null)
	_held_grid = g
	_held_split_src = it
	_held_origin = it.cell
	_held_origin_rot = it.rotated
	sound.emit(&"pick")
	return true


func _split_ground(ground: Node3D, _at: Vector2i) -> bool:
	if not ground.def.stackable() or ground.count < 2:
		return false
	var stack := ItemStack.new(ground.def, _half(mini(ground.count, ground.def.max_stack)))
	var i := _vicinity.find(ground)
	stack.rotated = _packed[i]["rotated"]
	_hold(stack, Vector2i.ZERO, ground)
	sound.emit(&"pick")
	return true


## Q: drop the held item at his feet, or the one under the cursor. Not in STASH mode.
func quick_drop(at: Vector2i) -> void:
	if is_stash_mode() or not _menu.is_empty():
		return
	if held != null:
		if _held_ground != null:
			_return_held()
			return
		var dropped := held
		held = null
		_held_slot = &""
		_held_split_src = null
		_held_grid = null
		Inventory.drop(dropped, Inventory.player())
		sound.emit(&"drop")
		_refresh_vicinity()
		return
	var hit := _grid_hit(at)
	if hit.is_empty():
		return
	var it := (hit["grid"] as ItemGrid).item_at(hit["cell"])
	if it != null and not it.def.mech_only:
		(hit["grid"] as ItemGrid).remove(it)
		Inventory.drop(it, Inventory.player())
		sound.emit(&"drop")
		_refresh_vicinity()


func _invalid() -> void:
	_shake = SHAKE_TIME
	sound.emit(&"invalid")


## Drops the held item on equipment slot `slot`: refused if the slot does not take it, otherwise
## worn, and whatever was worn there comes up on the cursor in its place.
func _place_in_slot(slot: StringName) -> void:
	if held == null or _held_ground != null or not InventoryScript.slot_accepts(slot, held.def):
		return
	var placed := held
	var displaced := Inventory.equip(slot, placed)
	held = null
	_held_grid = null
	_held_slot = &""
	if displaced != null:
		_hold(displaced, Vector2i.ZERO, null)
		_held_slot = slot


## RMB on a worn item: to the first free spot in the grid, if there is room.
func unequip_to_grid(slot: StringName) -> bool:
	var worn := Inventory.item_in(slot)
	if worn == null:
		return false
	var spot := Inventory.grid.find_free(worn.def.size)
	if spot.is_empty():
		return false
	Inventory.unequip(slot)
	return Inventory.grid.place(worn, spot["cell"], spot["rotated"])


func right_click(at: Vector2i) -> void:
	if not _menu.is_empty():
		_close_menu()
		return
	if _card_def != null:
		_card_def = null
		return
	if held != null:
		_return_held()
		return
	open_menu(at)


# --- context popup ----------------------------------------------------------------------------

## The popup for whatever is under `at`: {"at", "entries", "target"}; empty = nothing there.
## Entries are {"id", "label", "enabled"}. Pure data, so tests read it without drawing.
func menu_for(at: Vector2i) -> Dictionary:
	var entries: Array = []
	var target := {}
	var worn_slot := slot_at(at)
	if worn_slot != &"":
		var worn := Inventory.item_in(worn_slot)
		if worn == null:
			return {}
		target = {"kind": "worn", "slot": worn_slot, "def": worn.def, "count": 1}
		entries.append(_entry(&"unequip", "TAKE OFF", not Inventory.grid.find_free(worn.def.size).is_empty()))
	else:
		var hit := _grid_hit(at)
		if not hit.is_empty():
			var g: ItemGrid = hit["grid"]
			var it := g.item_at(hit["cell"])
			if it == null:
				return {}
			target = {"kind": "grid", "grid": g, "stack": it, "def": it.def, "count": it.count}
			if it.def.mech_only:
				entries.append(_entry(&"carry", "CARRY", is_stash_mode()))
			elif is_stash_mode():
				entries.append(_entry(&"move", "MOVE", true))
			else:
				entries.append(_entry(&"drop", "DROP", true))
			if it.def.stackable() and it.count >= 2:
				entries.append(_entry(&"split", "SPLIT", true))
			if it.def.is_container() and not _is_window_grid(g):
				target["rect"] = Rect2i(_grid_origin(g) + it.cell * CELL, it.footprint() * CELL + Vector2i.ONE)
				if not is_stash_mode() and InventoryScript.slot_accepts(Inventory.SLOT_BACK, it.def):
					entries.append(_entry(&"equip", "EQUIP", true))
				entries.append(_entry(&"open", "OPEN", true))
		elif not is_stash_mode():
			var ground := vicinity_item_at(at)
			if ground == null:
				return {}
			target = {"kind": "ground", "node": ground, "def": ground.def, "count": ground.count}
			entries.append(_entry(&"take", "TAKE", Inventory.can_take(ground)))
			if ground.def.stackable() and ground.count >= 2:
				entries.append(_entry(&"split", "SPLIT", true))
			if ground.def.is_container():
				var i := _vicinity.find(ground)
				target["rect"] = Rect2i(_content_rect(Box.VICINITY).position + (_vic_spot(i) - Vector2i(0, _vic_scroll)) * CELL,
					_vic_footprint(i) * CELL + Vector2i.ONE)
				if InventoryScript.slot_accepts(Inventory.SLOT_BACK, ground.def):
					entries.append(_entry(&"equip", "EQUIP", true))
				entries.append(_entry(&"open", "OPEN", true))
		else:
			return {}
	entries.append(_entry(&"inspect", "INSPECT", true))
	return {"at": at, "entries": entries, "target": target}


func _entry(id: StringName, label: String, enabled: bool) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled}


func open_menu(at: Vector2i) -> bool:
	var m := menu_for(at)
	if m.is_empty():
		return false
	_menu = m
	_menu_t = 0.0
	return true


func _close_menu() -> void:
	_menu = {}
	_menu_t = 0.0


func menu_is_open() -> bool:
	return not _menu.is_empty()


func menu_entries() -> Array:
	return _menu.get("entries", [])


## The popup's rectangle in texels, kept inside the canvas.
func menu_rect() -> Rect2i:
	var entries: Array = _menu.get("entries", [])
	var w := 0
	for e in entries:
		w = maxi(w, int(_font.get_string_size(e["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x))
	var win_size := Vector2i(w + 12, entries.size() * MENU_ROW + 4)
	var pos: Vector2i = _menu.get("at", Vector2i.ZERO) + Vector2i(2, 2)
	pos.x = clampi(pos.x, 0, maxi(_texels.x - win_size.x, 0))
	pos.y = clampi(pos.y, 0, maxi(_texels.y - win_size.y, 0))
	return Rect2i(pos, win_size)


## The enabled row id under `at`, or &"".
func menu_entry_at(at: Vector2i) -> StringName:
	if _menu.is_empty():
		return &""
	var r := menu_rect()
	if not r.has_point(at):
		return &""
	@warning_ignore("integer_division")
	var i := (at.y - r.position.y - 2) / MENU_ROW
	var entries: Array = _menu["entries"]
	if i < 0 or i >= entries.size() or not entries[i]["enabled"]:
		return &""
	return entries[i]["id"]


## Runs a popup row on the thing it was opened for.
func menu_choose(id: StringName, target: Dictionary = _menu.get("target", {})) -> void:
	match id:
		&"inspect":
			_card_def = target["def"]
			_card_count = target["count"]
			_card_at = menu_rect().position if not _menu.is_empty() else _mouse
		&"unequip":
			unequip_to_grid(target["slot"])
		&"drop", &"move", &"carry":
			var st: ItemStack = target["stack"]
			if (target["grid"] as ItemGrid).items.has(st):
				_transfer(st, target["grid"])
		&"take":
			if is_instance_valid(target["node"]):
				_take_ground(target["node"])
		&"equip":
			equip_pack(target)
		&"open":
			open_window(target, target.get("rect", Rect2i(_mouse, Vector2i.ONE)))
		&"split":
			if target["kind"] == "grid":
				var st: ItemStack = target["stack"]
				_split_from_grid(target["grid"], st, st.cell)
			elif is_instance_valid(target["node"]):
				_split_ground(target["node"], _mouse)


## EQUIP on a pack (docs/specs/pilot9-backpack.md, "Pack windows"): it goes on his back with its
## contents. A pack already worn swaps out - onto the ground where the new one lay, or into the
## grid spot the new one left (else any free spot, else his feet).
func equip_pack(target: Dictionary) -> bool:
	var stack: ItemStack
	var node: Variant = target.get("node", null)
	var from: ItemGrid = target.get("grid", null)
	if target["kind"] == "ground":
		if not is_instance_valid(node):
			return false
		stack = ItemStack.new(node.def, 1, node.contents)
	else:
		stack = target["stack"]
		if from == null or not from.items.has(stack):
			return false
	if not InventoryScript.slot_accepts(Inventory.SLOT_BACK, stack.def):
		return false
	var cell := stack.cell
	var rot := stack.rotated
	if from != null:
		from.remove(stack)
	var old := Inventory.equip(Inventory.SLOT_BACK, stack)
	if target["kind"] == "ground":
		var ground := node as Node3D
		if old != null and ground.get_parent() != null:
			# The worn one lands exactly where the new one lay, contents and all.
			var swapped: Node3D = WORLD_ITEM.new()
			swapped.def = old.def
			swapped.count = 1
			swapped.contents = old.contents
			ground.get_parent().add_child(swapped)
			swapped.global_transform = ground.global_transform
		ground.queue_free()
		ground.remove_from_group(Inventory.WORLD_ITEM_GROUP)
	elif old != null:
		if not from.place(old, cell, rot) and not InventoryScript.place_anywhere(from, old):
			Inventory.drop(old, Inventory.player())
	sound.emit(&"place")
	_refresh_vicinity()
	_prune_windows()
	return true


## A crate leaves the stash for his hands (docs/specs/pilot9-crate-carry.md): only from outside the
## mech, with empty hands, and the screen closes on it. Anything else does nothing.
func _take_crate(it: ItemStack, from: ItemGrid) -> bool:
	if not is_stash_mode() or _held_pilot == null or not is_instance_valid(_held_pilot):
		return false
	var carry: Variant = _held_pilot.get(&"carry")
	if not (carry is Node) or carry.def != null:
		return false
	var item_def := it.def
	from.remove(it)
	# The screen still holds him frozen, which can_begin_carry() refuses: release first.
	_release_pilot_hold()
	if not carry.pick_up(item_def, _held_pilot.global_position):
		from.place(it, it.cell, it.rotated)
		if _held_pilot != null:
			_held_pilot.set_inventory_hold(true)
		return false
	var ui := get_node_or_null(^"/root/UI")
	if ui != null:
		ui.close()
	return true


## Lets go of the frozen pilot early (the screen is about to close on a crate pick-up). Keeps
## _held_pilot so a failed pick-up can freeze him again.
func _release_pilot_hold() -> void:
	if _held_pilot != null and is_instance_valid(_held_pilot):
		_held_pilot.set_inventory_hold(false)


## RMB in STASH mode: as much of `it` as fits goes to `to` (existing stacks first, then the first
## free spot); what moved leaves `from`. No room = nothing happens. Returns how many moved.
static func quick_move(it: ItemStack, from: ItemGrid, to: ItemGrid) -> int:
	if it.def.is_container():
		# Whole, contents and all.
		var spot := to.find_free(it.def.size) if to.accepts(it.def) else {}
		if spot.is_empty():
			return 0
		from.remove(it)
		to.place(it, spot["cell"], spot["rotated"])
		return 1
	var n := to.add(it.def, it.count)
	if n <= 0:
		return 0
	it.count -= n
	if it.count <= 0:
		from.remove(it)
	else:
		from.changed.emit()
	return n


func rotate_held() -> void:
	if held == null or held.def.size.x == held.def.size.y:
		return
	held.rotated = not held.rotated
	sound.emit(&"rotate")
	var fp := held.footprint()
	_held_offset = Vector2i(mini(_held_offset.y, fp.x - 1), mini(_held_offset.x, fp.y - 1))


func scroll_vicinity(rows: int) -> void:
	_vic_scroll = clampi(_vic_scroll + rows, 0, maxi(_vicinity_rows() - SIDE_ROWS, 0))


func _hold(stack: ItemStack, offset: Vector2i, ground: Node3D) -> void:
	held = stack
	_held_ground = ground
	_held_split_src = null
	sound.emit(&"pick")
	var fp := stack.footprint()
	_held_offset = Vector2i(clampi(offset.x, 0, fp.x - 1), clampi(offset.y, 0, fp.y - 1))
	_held_origin = stack.cell
	_held_origin_rot = stack.rotated


func _place_held(grid: ItemGrid, cell: Vector2i, pointed: Vector2i) -> void:
	if _held_ground != null and not is_instance_valid(_held_ground):
		held = null
		_held_ground = null
		return
	if not grid.accepts(held.def):
		return
	if grid.fits(cell, held.footprint()):
		var placed := held
		held = null
		_held_slot = &""
		_held_split_src = null
		grid.place(placed, cell, placed.rotated)
		_flashes.append([Rect2i(_grid_origin(grid) + cell * CELL, placed.footprint() * CELL), FLASH_TIME])
		sound.emit(&"place")
		_spend_ground(placed.count)
		_held_ground = null
		_held_grid = null
		return
	# Onto the same stackable kind: top it up.
	var under := grid.item_at(pointed)
	if under != null:
		var moved := grid.merge_into(under, held)
		if moved > 0:
			sound.emit(&"place")
			_flashes.append([Rect2i(_grid_origin(grid) + under.cell * CELL, under.footprint() * CELL), FLASH_TIME])
			_spend_ground(moved)
			if held.count <= 0:
				held = null
				_held_ground = null


## A ground item handed `n` of itself to the grid: shrink it, free it when empty.
func _spend_ground(n: int) -> void:
	if _held_ground == null:
		return
	_held_ground.count -= n
	if _held_ground.count <= 0:
		_held_ground.queue_free()
		# Out of the group now, so the rescan below does not list it for its last frame.
		_held_ground.remove_from_group(Inventory.WORLD_ITEM_GROUP)
	_refresh_vicinity()


func _return_held() -> void:
	if held == null:
		return
	if _held_split_src != null:
		# The other half is still in the grid: pour this back into it, else fall through.
		var src := _held_split_src
		_held_split_src = null
		var home := _held_grid if _held_grid != null else Inventory.grid
		if home.items.has(src) and src.def == held.def:
			var n := mini(src.def.max_stack - src.count, held.count)
			src.count += n
			held.count -= n
			home.changed.emit()
			if held.count <= 0:
				held = null
				_held_grid = null
				return
	if _held_slot != &"":
		# It came off a slot: back on it if that is free, else the grid, else the ground.
		var slot := _held_slot
		_held_slot = &""
		if Inventory.item_in(slot) == null and InventoryScript.slot_accepts(slot, held.def):
			Inventory.equip(slot, held)
			held = null
			return
		var spot_free := Inventory.grid.find_free(held.def.size)
		if not spot_free.is_empty() and Inventory.grid.place(held, spot_free["cell"], spot_free["rotated"]):
			held = null
			return
		Inventory.drop(held, Inventory.player())
		held = null
		return
	if _held_ground == null:
		var grid := _held_grid if _held_grid != null else Inventory.grid
		if not grid.place(held, _held_origin, _held_origin_rot):
			var spot := grid.find_free(held.def.size)
			if spot.is_empty() or not grid.place(held, spot["cell"], spot["rotated"]):
				Inventory.drop(held, Inventory.player())
	held = null
	_held_ground = null
	_held_grid = null


# --- sort -----------------------------------------------------------------------------------

## T / the SORT button: repack the pack (and the stash, aboard), group the vicinity by category.
## Ignored with something in the hand.
func sort_all() -> void:
	if held != null:
		return
	var grids: Array[ItemGrid] = Inventory.carry_grids()
	if is_stash_mode():
		grids.append(stash_grid())
	var snaps: Array = []
	for g in grids:
		snaps.append([g, g.snapshot()])
	var any := false
	for g in grids:
		any = g.sort_items() or any
	if not is_stash_mode():
		_vic_sorted = true
		_refresh_vicinity()
	if not any:
		_invalid()
		return
	var after: Array = []
	for g in grids:
		after.append(g.snapshot())
	_undo = [snaps, after]
	sound.emit(&"sort")
	for g in grids:
		_flash_grid(g)


## Ctrl+Z: put the grids back as they were before the last sort - only while they are exactly as
## the sort left them, so it can never eat something moved since.
func undo_sort() -> bool:
	if _undo.is_empty() or held != null:
		return false
	var snaps: Array = _undo[0]
	var after: Array = _undo[1]
	for i in snaps.size():
		if (snaps[i][0] as ItemGrid).snapshot() != after[i]:
			_undo.clear()
			return false
	for e in snaps:
		(e[0] as ItemGrid).restore(e[1])
	_undo.clear()
	sound.emit(&"place")
	return true


func can_undo_sort() -> bool:
	return not _undo.is_empty()


func _flash_grid(g: ItemGrid) -> void:
	for it in g.items:
		_flashes.append([Rect2i(_grid_origin(g) + it.cell * CELL, it.footprint() * CELL), FLASH_TIME])


## Where grid `g` is drawn: his grid in the middle box, the worn pack under it, a stash in the
## right one, an opened pack in its window.
func _grid_origin(g: ItemGrid) -> Vector2i:
	if g == Inventory.grid:
		return _content_rect(Box.GRID).position
	if g != null and g == Inventory.pack_grid():
		return _content_rect(Box.PACK).position
	for w: Dictionary in _windows:
		if w["grid"] == g:
			return window_grid_origin(w)
	return _content_rect(Box.VICINITY).position


func sort_button_rect() -> Rect2i:
	var r := box_rect(Box.GRID)
	return Rect2i(r.end.x - SORT_W - 3, r.position.y + 2, SORT_W, HEADER - 4)


# --- vicinity -------------------------------------------------------------------------------

func _refresh_vicinity() -> void:
	_vic_timer = 0.0
	_vicinity = Inventory.vicinity(Inventory.player())
	if _vic_sorted:
		_vicinity.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return ItemGrid.sort_key_before(a.def, a.def.size, b.def, b.def.size))
	# The one being carried stays listed even if it leaves range mid-carry; it is still on the
	# ground.
	var sizes: Array = []
	for item in _vicinity:
		sizes.append(item.def.size)
	_packed = InventoryScript.pack(sizes, Inventory.VICINITY_W)
	scroll_vicinity(0)
	_prune_windows()


func _item_rows() -> int:
	var rows := 0
	for i in _packed.size():
		rows = maxi(rows, _vic_spot(i).y + _vic_footprint(i).y)
	return rows


func _vicinity_rows() -> int:
	return _item_rows()


func _vic_spot(i: int) -> Vector2i:
	return _packed[i]["cell"]


func _vic_footprint(i: int) -> Vector2i:
	return ItemStack.footprint_of(_vicinity[i].def.size, _packed[i]["rotated"])


func vicinity_cell_at(at: Vector2i) -> Vector2i:
	var r := _content_rect(Box.VICINITY)
	if not r.has_point(at):
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	return (at - r.position) / CELL + Vector2i(0, _vic_scroll)


func vicinity_item_at(at: Vector2i) -> Node3D:
	var cell := vicinity_cell_at(at)
	if cell.x < 0 or window_at(at) >= 0:
		return null
	for i in _vicinity.size():
		if is_instance_valid(_vicinity[i]) and Rect2i(_vic_spot(i), _vic_footprint(i)).has_point(cell):
			return _vicinity[i]
	return null


func vicinity_items() -> Array[Node3D]:
	return _vicinity


# --- pack windows (docs/specs/pilot9-backpack.md, "Pack windows") ------------------------------

const WIN_STEP := Vector2i(8, 8)
const WIN_CLOSE := 9

## Opens a window on the pack `target` points at (a menu target: "node" on the ground, or "stack"
## in a grid), next to `anchor` (the pack's own rect, texels). Already open: brought to the front.
func open_window(target: Dictionary, anchor: Rect2i) -> void:
	var node: Node3D = target.get("node", null)
	var stack: ItemStack = target.get("stack", null)
	var g: ItemGrid = node.contents if node != null else (stack.contents if stack != null else null)
	if g == null:
		return
	for i in _windows.size():
		if _windows[i]["grid"] == g:
			raise_window(i)
			return
	var w := {"grid": g, "node": node, "stack": stack, "def": target["def"], "pos": Vector2i.ZERO}
	var win_size := window_size(w)
	var pos := Vector2i(anchor.end.x + 2, anchor.position.y)
	if pos.x + win_size.x > _texels.x:
		pos.x = anchor.position.x - win_size.x - 2
	pos = _clamp_window(pos, win_size)
	# A step down-right per window already sitting there, so every title bar stays grabbable.
	for _n in 16:
		var taken := false
		for o: Dictionary in _windows:
			if o["pos"] == pos:
				taken = true
		if not taken:
			break
		pos = _clamp_window(pos + WIN_STEP, win_size)
	w["pos"] = pos
	_windows.append(w)
	sound.emit(&"pick")


func window_size(w: Dictionary) -> Vector2i:
	var g: ItemGrid = w["grid"]
	return Vector2i(g.width * CELL + PAD * 2 + 1, HEADER + g.height * CELL + PAD + 1)


func window_rect(w: Dictionary) -> Rect2i:
	return Rect2i(w["pos"], window_size(w))


func window_grid_origin(w: Dictionary) -> Vector2i:
	return w["pos"] + Vector2i(PAD, HEADER)


## The X in the title bar.
func window_close_rect(w: Dictionary) -> Rect2i:
	var r := window_rect(w)
	return Rect2i(r.end.x - WIN_CLOSE - 3, r.position.y + 2, WIN_CLOSE, HEADER - 4)


func window_title_rect(w: Dictionary) -> Rect2i:
	var r := window_rect(w)
	return Rect2i(r.position.x, r.position.y, r.size.x, HEADER)


func _clamp_window(pos: Vector2i, win_size: Vector2i) -> Vector2i:
	return Vector2i(clampi(pos.x, 0, maxi(_texels.x - win_size.x, 0)), clampi(pos.y, 0, maxi(_texels.y - win_size.y, 0)))


## The front-most window under `at`, or -1.
func window_at(at: Vector2i) -> int:
	for i in range(_windows.size() - 1, -1, -1):
		if window_rect(_windows[i]).has_point(at):
			return i
	return -1


func windows() -> Array:
	return _windows


func raise_window(i: int) -> void:
	if i < 0 or i >= _windows.size() or i == _windows.size() - 1:
		return
	var w: Dictionary = _windows[i]
	_windows.remove_at(i)
	_windows.append(w)


func close_window(i: int) -> void:
	if i < 0 or i >= _windows.size():
		return
	if _win_drag == i:
		_win_drag = -1
	_windows.remove_at(i)
	sound.emit(&"drop")


func close_windows() -> void:
	_windows.clear()
	_win_drag = -1


## The front window's grid (where SHIFT sends things from his grids), or null.
func front_window_grid() -> ItemGrid:
	return _windows.back()["grid"] if not _windows.is_empty() else null


func _is_window_grid(g: ItemGrid) -> bool:
	for w: Dictionary in _windows:
		if w["grid"] == g:
			return true
	return false


## LMB press on a window: raises it, then the X closes it and the title bar starts a drag. True
## when the press is spent on the window chrome.
func window_press(at: Vector2i) -> bool:
	var i := window_at(at)
	if i < 0:
		return false
	raise_window(i)
	var w: Dictionary = _windows.back()
	if window_close_rect(w).has_point(at):
		close_window(_windows.size() - 1)
		return true
	if window_title_rect(w).has_point(at):
		_win_drag = _windows.size() - 1
		_win_drag_off = at - (w["pos"] as Vector2i)
		return true
	return false


func window_drag_to(at: Vector2i) -> void:
	if _win_drag < 0 or _win_drag >= _windows.size():
		return
	var w: Dictionary = _windows[_win_drag]
	w["pos"] = _clamp_window(at - _win_drag_off, window_size(w))


## Closes any window whose pack is gone: a ground pack out of the vicinity (taken, equipped, out
## of range, freed), a grid pack no longer in his grid or the stash. A pack on the cursor keeps
## its window.
func _prune_windows() -> void:
	for i in range(_windows.size() - 1, -1, -1):
		var w: Dictionary = _windows[i]
		var keep := true
		var stack: ItemStack = w["stack"]
		if w["grid"] == Inventory.pack_grid():
			keep = false
		elif stack == null:
			var node: Variant = w["node"]
			keep = is_instance_valid(node) and not (node as Node).is_queued_for_deletion() 				and (node == _held_ground or _vicinity.has(node))
		else:
			keep = stack == held or Inventory.grid.items.has(stack) 				or (is_stash_mode() and stash_grid().items.has(stack))
		if not keep:
			_windows.remove_at(i)
			if _win_drag == i:
				_win_drag = -1
			elif _win_drag > i:
				_win_drag -= 1


func _draw_windows() -> void:
	var hit_i := window_at(_mouse)
	for i in _windows.size():
		var w: Dictionary = _windows[i]
		var r := window_rect(w)
		_canvas.draw_rect(Rect2(r), PLATE)
		_bevel(r)
		var bar := Rect2i(r.position.x + 2, r.position.y + 2, r.size.x - 4, HEADER - 4)
		_canvas.draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, 3), BAND_A)
		_canvas.draw_rect(Rect2(bar.position.x, bar.position.y + 3, bar.size.x, 3), BAND_B)
		_canvas.draw_rect(Rect2(bar.position.x, bar.position.y + 6, bar.size.x, bar.size.y - 6), BAND_C)
		var g: ItemGrid = w["grid"]
		var title := "%s %dx%d" % [(w["def"] as ItemDef).display_name, g.width, g.height]
		_text(Vector2i(r.position.x + PAD + 1, r.position.y + 11), title, HEADER_SIZE, CYAN)
		var x := window_close_rect(w)
		var hot := i == hit_i and x.has_point(_mouse)
		_canvas.draw_rect(Rect2(x), BAND_B if hot else PLATE)
		_outline(x, CYAN if hot else CYAN_DIM)
		var c := CYAN if hot else TEXT
		var mid := x.get_center()
		for d in range(-2, 3):
			_canvas.draw_rect(Rect2(mid.x + d, mid.y + d, 1, 1), c)
			_canvas.draw_rect(Rect2(mid.x + d, mid.y - d, 1, 1), c)
		var cell := Vector2i(-1, -1)
		if i == hit_i:
			var hit := _grid_hit(_mouse)
			if not hit.is_empty() and hit["grid"] == g:
				cell = hit["cell"]
		_draw_item_grid(g, window_grid_origin(w), cell)


# --- layout (texels) ------------------------------------------------------------------------

func texel_scale() -> int:
	return _scale


static func scale_for(window_height: float, canvas_lines: float) -> int:
	return maxi(1, roundi(window_height / canvas_lines))


func _resize_canvas() -> void:
	var vp := get_viewport_rect().size
	_scale = scale_for(vp.y, lines)
	_texels = Vector2i(ceili(vp.x / _scale), ceili(vp.y / _scale))
	_canvas_vp.size = _texels
	_canvas.size = Vector2(_texels)
	_display.position = Vector2.ZERO
	_display.size = Vector2(_texels * _scale)
	(_display.material as ShaderMaterial).set_shader_parameter(&"canvas_texels", Vector2(_texels))
	var pr := box_rect(Box.PORTRAIT)
	_portrait.size = Vector2i(pr.size.x - 2, pr.size.y - HEADER - 1)


func box_rect(box: Box) -> Rect2i:
	var grid_w := Inventory.GRID_W * CELL + PAD * 2
	var grid_h := HEADER + Inventory.GRID_H * CELL + PAD
	var pack_h := HEADER + PACK_ROWS * CELL + PAD
	var side_h := HEADER + SIDE_ROWS * CELL + PAD
	var vic_w := Inventory.VICINITY_W * CELL + PAD * 2
	var total_w := PORTRAIT_W + GAP + grid_w + GAP + vic_w
	@warning_ignore("integer_division")
	var x0 := (_texels.x - total_w) / 2
	@warning_ignore("integer_division")
	var y0 := (_texels.y - side_h) / 2 - 6
	# The middle column: slot row, grid, pack box. Its space is kept with no pack worn, so the
	# grid never jumps when one goes on.
	var column := SLOT_H + 4 + grid_h + 4 + pack_h
	@warning_ignore("integer_division")
	var mid_y := y0 + maxi((side_h - column) / 2, 0) + SLOT_H + 4
	match box:
		Box.PORTRAIT:
			return Rect2i(x0, y0, PORTRAIT_W, side_h)
		Box.GRID:
			return Rect2i(x0 + PORTRAIT_W + GAP, mid_y, grid_w, grid_h)
		Box.PACK:
			return Rect2i(x0 + PORTRAIT_W + GAP, mid_y + grid_h + 4, grid_w, pack_h)
		_:
			return Rect2i(x0 + PORTRAIT_W + GAP + grid_w + GAP, y0, vic_w, side_h)


## The equipment slot rectangles in the portrait box (texels). Not in STASH mode: the portrait is
## a vehicle then.
func slot_rect(slot: StringName) -> Rect2i:
	# One row above the inventory box: four clothes, a gap, two weapons.
	var g := box_rect(Box.GRID)
	var n := Inventory.EQUIP_SLOTS.size()
	var row_w := SLOT_W * n + 4 * (n - 2) + 8
	@warning_ignore("integer_division")
	var left := g.position.x + (g.size.x - row_w) / 2
	var top := g.position.y - 4 - SLOT_H
	var i: int = Inventory.EQUIP_SLOTS.find(slot)
	var x := left + i * (SLOT_W + 4) + (4 if i >= CLOTHES_SLOTS else 0)
	return Rect2i(x, top, SLOT_W, SLOT_H)


## The slot under `at`, or &"" - none in STASH mode.
func slot_at(at: Vector2i) -> StringName:
	if is_stash_mode() or window_at(at) >= 0:
		return &""
	for slot in Inventory.EQUIP_SLOTS:
		if slot_rect(slot).has_point(at):
			return slot
	return &""


func _content_rect(box: Box) -> Rect2i:
	var r := box_rect(box)
	return Rect2i(r.position.x + PAD, r.position.y + HEADER, r.size.x - PAD * 2, r.size.y - HEADER - PAD)


func grid_cell_at(at: Vector2i) -> Vector2i:
	var r := _content_rect(Box.GRID)
	if not r.has_point(at):
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	return (at - r.position) / CELL


func grid_cell_origin(cell: Vector2i) -> Vector2i:
	return _content_rect(Box.GRID).position + cell * CELL


## STASH mode: the stash cell under `at`, or (-1, -1). The stash lives in the vicinity box.
func stash_cell_at(at: Vector2i) -> Vector2i:
	if not is_stash_mode():
		return Vector2i(-1, -1)
	var r := _content_rect(Box.VICINITY)
	if not r.has_point(at):
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	var cell := (at - r.position) / CELL
	if cell.x >= stash_grid().width or cell.y >= stash_grid().height:
		return Vector2i(-1, -1)
	return cell


func stash_cell_origin(cell: Vector2i) -> Vector2i:
	return _content_rect(Box.VICINITY).position + cell * CELL


# Which real grid is under `at`: {"grid": ItemGrid, "cell": Vector2i}, or {} for none.
func _grid_hit(at: Vector2i) -> Dictionary:
	var wi := window_at(at)
	if wi >= 0:
		var w: Dictionary = _windows[wi]
		var g: ItemGrid = w["grid"]
		@warning_ignore("integer_division")
		var c := (at - window_grid_origin(w)) / CELL
		if at.x >= window_grid_origin(w).x and at.y >= window_grid_origin(w).y and c.x < g.width and c.y < g.height:
			return {"grid": g, "cell": c}
		return {}
	var cell := grid_cell_at(at)
	if cell.x >= 0:
		return {"grid": Inventory.grid, "cell": cell}
	cell = pack_cell_at(at)
	if cell.x >= 0:
		return {"grid": Inventory.pack_grid(), "cell": cell}
	cell = stash_cell_at(at)
	if cell.x >= 0:
		return {"grid": stash_grid(), "cell": cell}
	return {}


## The worn pack's cell under `at`, or (-1, -1) (also with no pack worn).
func pack_cell_at(at: Vector2i) -> Vector2i:
	var pack := Inventory.pack_grid()
	if pack == null:
		return Vector2i(-1, -1)
	var r := _content_rect(Box.PACK)
	if not r.has_point(at):
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	var cell := (at - r.position) / CELL
	if cell.x >= pack.width or cell.y >= pack.height:
		return Vector2i(-1, -1)
	return cell


func pack_cell_origin(cell: Vector2i) -> Vector2i:
	return _content_rect(Box.PACK).position + cell * CELL


func _hint_y() -> int:
	var r := box_rect(Box.PORTRAIT)
	return r.end.y + 10


# --- per frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_menu_t += delta
	_shake = maxf(_shake - delta, 0.0)
	for f in _flashes:
		f[1] -= delta
	_flashes = _flashes.filter(func(f: Array) -> bool: return f[1] > 0.0)
	if _folding:
		if _t >= fold_time:
			_finish_close()
			return
	else:
		_vic_timer += delta
		if _vic_timer >= vicinity_interval and held == null and not is_stash_mode():
			_refresh_vicinity()
		_prune_windows()
	if _canvas_vp.size != _texels or get_viewport_rect().size != Vector2(_display.size):
		_resize_canvas()
	_dim_rect.color = Color(0, 0, 0, dim * _open_amount(0))
	_canvas.queue_redraw()


## 0 folded .. 1 open, for box `index` (0 left .. 3).
func _open_amount(index: int) -> float:
	if _folding:
		return 1.0 - clampf(_t / maxf(fold_time, 0.001), 0.0, 1.0)
	return clampf((_t - index * stagger) / maxf(unfold_time, 0.001), 0.0, 1.0)


# --- drawing --------------------------------------------------------------------------------

func _draw_canvas() -> void:
	_draw_box(Box.PORTRAIT, 0, stash_title() if is_stash_mode() else "PILOT")
	_draw_box(Box.GRID, 1, "INVENTORY")
	if Inventory.pack_grid() != null:
		_draw_box(Box.PACK, 1, Inventory.item_in(Inventory.SLOT_BACK).def.display_name)
	_draw_box(Box.VICINITY, 2, "STASH" if is_stash_mode() else "VICINITY")
	if _open_amount(2) < 1.0:
		return
	_draw_portrait()
	if not is_stash_mode():
		_draw_slots()
	_draw_grid()
	if Inventory.pack_grid() != null:
		_draw_item_grid(Inventory.pack_grid(), _content_rect(Box.PACK).position, pack_cell_at(_mouse))
	if is_stash_mode():
		_draw_stash()
	else:
		_draw_vicinity()
	_draw_windows()
	_draw_hints()
	_draw_sort_button()
	_draw_flashes()
	_draw_held()
	_draw_menu()
	_draw_card()
	_draw_tooltip()


func _draw_box(box: Box, index: int, title: String) -> void:
	var r := box_rect(box)
	var f := _open_amount(index)
	if f <= 0.0:
		return
	var h := maxi(2, roundi(r.size.y * f))
	@warning_ignore("integer_division")
	var y := r.position.y + (r.size.y - h) / 2
	_canvas.draw_rect(Rect2(r.position.x, y, r.size.x, h), PLATE)
	_bevel(Rect2i(r.position.x, y, r.size.x, h))
	if f >= 1.0 and title != "":
		# Title bar: three hard colour bands, no blend.
		var bar := Rect2i(r.position.x + 2, r.position.y + 2, r.size.x - 4, HEADER - 4)
		_canvas.draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, 3), BAND_A)
		_canvas.draw_rect(Rect2(bar.position.x, bar.position.y + 3, bar.size.x, 3), BAND_B)
		_canvas.draw_rect(Rect2(bar.position.x, bar.position.y + 6, bar.size.x, bar.size.y - 6), BAND_C)
		_text(Vector2i(r.position.x + PAD + 1, r.position.y + 11), title, HEADER_SIZE, CYAN)


func _draw_portrait() -> void:
	var r := box_rect(Box.PORTRAIT)
	_canvas.draw_texture_rect(_portrait.get_texture(),
		Rect2(r.position.x + 1, r.position.y + HEADER, _portrait.size.x, _portrait.size.y), false)


func _draw_slots() -> void:
	var hover := slot_at(_mouse)
	for slot in Inventory.EQUIP_SLOTS:
		var r := slot_rect(slot)
		_canvas.draw_rect(Rect2(r), PLATE)
		var edge := CYAN_DIM
		if held != null and hover == slot:
			edge = GOOD if (_held_ground == null and InventoryScript.slot_accepts(slot, held.def)) else BAD
		elif held == null and hover == slot and Inventory.item_in(slot) != null:
			edge = CYAN
		_outline(r, edge)
		var worn := Inventory.item_in(slot)
		if worn == null:
			var label: String = SLOT_LABELS[slot]
			var w := int(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x)
			if w <= r.size.x - 4:
				@warning_ignore("integer_division")
				_text(r.position + Vector2i((r.size.x - w) / 2, r.size.y / 2 + 4), label, LABEL_SIZE, CYAN_DIM)
			else:
				# Too wide for the narrow slot: one letter per line, centred.
				var line_h := 10
				@warning_ignore("integer_division")
				var y0 := r.position.y + (r.size.y - label.length() * line_h) / 2 + 8
				for c in label.length():
					var ch := label[c]
					var cw := int(_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x)
					@warning_ignore("integer_division")
					_text(Vector2i(r.position.x + (r.size.x - cw) / 2, y0 + c * line_h), ch, LABEL_SIZE, CYAN_DIM)
		else:
			_draw_item_fit(r, worn.def)


## `def` scaled to sit inside `r` with its own proportions, a texel in from the edge.
func _draw_item_fit(r: Rect2i, def: ItemDef) -> void:
	var inner := Rect2(r.position + Vector2i.ONE, r.size - Vector2i(2, 2))
	var tex := Inventory.icon_for(def)
	var aspect := float(def.size.x) / float(def.size.y)
	var fit := inner.size
	if fit.x / fit.y > aspect:
		fit.x = fit.y * aspect
	else:
		fit.y = fit.x / aspect
	fit = fit.floor()
	var at := (inner.position + (inner.size - fit) / 2.0).floor()
	if tex != null:
		_canvas.draw_texture_rect(tex, Rect2(at, fit), false)
	else:
		_canvas.draw_rect(Rect2(at, fit), def.color.darkened(0.35))
		_outline(Rect2i(at, fit), def.color.lightened(0.25))


func _draw_cells(origin: Vector2i, cols: int, rows: int) -> void:
	for c in cols + 1:
		_canvas.draw_rect(Rect2(origin.x + c * CELL, origin.y, 1, rows * CELL + 1), CYAN_DIM)
	for r in rows + 1:
		_canvas.draw_rect(Rect2(origin.x, origin.y + r * CELL, cols * CELL + 1, 1), CYAN_DIM)


func _draw_grid() -> void:
	_draw_item_grid(Inventory.grid, _content_rect(Box.GRID).position, grid_cell_at(_mouse))


func _draw_stash() -> void:
	_draw_item_grid(stash_grid(), _content_rect(Box.VICINITY).position, stash_cell_at(_mouse))


# A real grid: lines, items, the hover edge, and the dimmed spot a held item came from.
func _draw_item_grid(g: ItemGrid, origin: Vector2i, cell: Vector2i) -> void:
	_draw_cells(origin, g.width, g.height)
	for it in g.items:
		_draw_item(origin + it.cell * CELL, it.footprint(), it.def, it.count)
	if held != null and _held_grid == g and _held_ground == null and _held_split_src == null:
		var home := Rect2i(origin + _held_origin * CELL, ItemStack.footprint_of(held.def.size, _held_origin_rot) * CELL + Vector2i.ONE)
		_canvas.draw_rect(Rect2(home), Color(0, 0, 0, 0.45))
		_outline(home, CYAN_DIM)
	elif held == null and cell.x >= 0 and _menu.is_empty():
		var hover := g.item_at(cell)
		if hover != null:
			_outline(Rect2i(origin + hover.cell * CELL, hover.footprint() * CELL + Vector2i.ONE), CYAN)


## Where the held item would land under the cursor: {"state": "fit" | "merge" | "bad", "rect":
## texel rect to outline, "origin": where to draw it}, or {} when the cursor is over no grid.
func drop_preview() -> Dictionary:
	if held == null:
		return {}
	var hit := _grid_hit(_mouse)
	if hit.is_empty():
		return {}
	var g: ItemGrid = hit["grid"]
	var cell: Vector2i = hit["cell"]
	var origin := _grid_origin(g)
	var at := cell - _held_offset
	var fp := held.footprint()
	if g.accepts(held.def) and g.fits(at, fp):
		var o := origin + at * CELL
		return {"state": "fit", "rect": Rect2i(o, fp * CELL + Vector2i.ONE), "origin": o}
	var under := g.item_at(cell)
	if under != null and under.def == held.def and held.def.stackable() and under.count < under.def.max_stack:
		return {"state": "merge", "rect": Rect2i(origin + under.cell * CELL, under.footprint() * CELL + Vector2i.ONE)}
	return {"state": "bad", "rect": Rect2i(origin + at * CELL, fp * CELL + Vector2i.ONE)}


func _draw_flashes() -> void:
	for f in _flashes:
		var a: float = clampf(f[1] / FLASH_TIME, 0.0, 1.0) * 0.55
		_canvas.draw_rect(Rect2(f[0]), Color(CYAN.r, CYAN.g, CYAN.b, a))


func _draw_vicinity() -> void:
	var r := _content_rect(Box.VICINITY)
	_draw_cells(r.position, Inventory.VICINITY_W, SIDE_ROWS)
	for i in _vicinity.size():
		var item := _vicinity[i]
		if not is_instance_valid(item) or item == _held_ground:
			continue
		var spot := _vic_spot(i) - Vector2i(0, _vic_scroll)
		var fp := _vic_footprint(i)
		if spot.y < 0 or spot.y + fp.y > SIDE_ROWS:
			continue
		_draw_item(r.position + spot * CELL, fp, item.def, item.count)
		if held == null and _menu.is_empty() and item == vicinity_item_at(_mouse):
			_outline(Rect2i(r.position + spot * CELL, fp * CELL + Vector2i.ONE), CYAN)
	if _vicinity.is_empty():
		_text(Vector2i(r.position.x + 4, r.position.y + 14), "NOTHING NEARBY", LABEL_SIZE, CYAN_DIM)
	if _vicinity_rows() > SIDE_ROWS:
		# A one-texel scroll bar along the right edge.
		var total := float(_vicinity_rows())
		var bar_h := int(r.size.y * SIDE_ROWS / total)
		var bar_y := r.position.y + int(r.size.y * _vic_scroll / total)
		_canvas.draw_rect(Rect2(r.end.x + 1, bar_y, 1, bar_h), CYAN)
	if held != null and _held_ground == null and r.has_point(_mouse) and window_at(_mouse) < 0:
		_outline(r, GOOD)


func _draw_item(at: Vector2i, fp: Vector2i, def: ItemDef, count: int) -> void:
	var rect := Rect2i(at + Vector2i(1, 1), fp * CELL - Vector2i(1, 1))
	var icon := Inventory.icon_for(def) if def.slot != &"" else null
	if icon != null:
		_canvas.draw_rect(Rect2(rect), PLATE)
		_outline(rect, def.color.lightened(0.25))
		var inner := Rect2(rect.position + Vector2i.ONE, rect.size - Vector2i(2, 2))
		if fp != def.size:
			# Rotated: the icon turns a quarter with it.
			_canvas.draw_set_transform(inner.get_center(), PI / 2.0)
			var sz := Vector2(inner.size.y, inner.size.x)
			_canvas.draw_texture_rect(icon, Rect2(-sz / 2.0, sz), false)
			_canvas.draw_set_transform(Vector2.ZERO, 0.0)
		else:
			_canvas.draw_texture_rect(icon, inner, false)
	else:
		_canvas.draw_rect(Rect2(rect), def.color.darkened(0.35))
		_outline(rect, def.color.lightened(0.25))
	_draw_glyph(Vector2i(rect.end.x - 6, rect.position.y + 2), def.category)
	if fp.x >= 2 and icon == null:
		var name_text := def.display_name
		var max_w := rect.size.x - 4
		while name_text.length() > 1 and _font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x > max_w:
			name_text = name_text.substr(0, name_text.length() - 1)
		_text(rect.position + Vector2i(2, 9), name_text, LABEL_SIZE, TEXT)
	if def.stackable():
		var n := str(count)
		var w := int(_font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x)
		_text(rect.end - Vector2i(w + 2, 2), n, LABEL_SIZE, TEXT)


func _draw_held() -> void:
	if held == null:
		return
	var pv := drop_preview()
	if not pv.is_empty():
		var c: Color = CYAN if pv["state"] == "fit" else (GOOD if pv["state"] == "merge" else BAD)
		var r: Rect2i = pv["rect"]
		_canvas.draw_rect(Rect2(r), Color(c.r, c.g, c.b, 0.18))
		_outline(r, c)
	var fp := held.footprint()
	@warning_ignore("integer_division")
	var at := _mouse - _held_offset * CELL - Vector2i(CELL / 2, CELL / 2)
	# A fit snaps the item onto the cells it would land in; anything else follows the cursor.
	if not pv.is_empty() and pv["state"] == "fit":
		at = pv["origin"]
	if _shake > 0.0:
		at.x += [-1, 1, -1, 1][int(_shake / 0.05) % 4]
	# A one-texel lift shadow.
	_canvas.draw_rect(Rect2(at + Vector2i(2, 2), fp * CELL - Vector2i.ONE), Color(0, 0, 0, 0.5))
	_draw_item(at, fp, held.def, held.count)


## 4 x 4 category marks: food a dot, medical a cross, ammo a bar, gear a bracket, junk a dash.
const GLYPHS := {
	&"food": ["0000", "0110", "0110", "0000"],
	&"medical": ["0110", "0110", "1111", "0110"],
	&"ammo": ["0110", "0110", "0110", "0110"],
	&"gear": ["1111", "1000", "1000", "1000"],
	&"junk": ["0000", "1111", "1111", "0000"],
}


func _draw_glyph(at: Vector2i, category: StringName) -> void:
	var rows: Array = GLYPHS.get(category, GLYPHS[&"junk"])
	var c: Color = CATEGORY_COLORS.get(category, CATEGORY_COLORS[&"junk"])
	for y in 4:
		for x in 4:
			if (rows[y] as String)[x] == "1":
				_canvas.draw_rect(Rect2(at.x + x, at.y + y, 1, 1), c)


func _draw_sort_button() -> void:
	var r := sort_button_rect()
	var hot := held == null and r.has_point(_mouse)
	_canvas.draw_rect(Rect2(r), PLATE)
	_outline(r, CYAN if hot else CYAN_DIM)
	var label := "SORT  T"
	var w := int(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x)
	@warning_ignore("integer_division")
	_text(Vector2i(r.position.x + (r.size.x - w) / 2, r.position.y + 8), label, LABEL_SIZE, CYAN if hot else TEXT)


func _draw_menu() -> void:
	if _menu.is_empty():
		return
	var r := menu_rect()
	var f := clampf(_menu_t / MENU_UNFOLD, 0.0, 1.0)
	var h := maxi(2, roundi(r.size.y * f))
	@warning_ignore("integer_division")
	var y := r.position.y + (r.size.y - h) / 2
	_canvas.draw_rect(Rect2(r.position.x, y, r.size.x, h), PLATE)
	_bevel(Rect2i(r.position.x, y, r.size.x, h))
	if f < 1.0:
		return
	var entries: Array = _menu["entries"]
	for i in entries.size():
		var row := Rect2i(r.position.x + 2, r.position.y + 2 + i * MENU_ROW, r.size.x - 4, MENU_ROW)
		var e: Dictionary = entries[i]
		var hot: bool = e["enabled"] and row.has_point(_mouse)
		if hot:
			_canvas.draw_rect(Rect2(row), BAND_B)
			_outline(row, CYAN)
		var c: Color = (CYAN if hot else TEXT) if e["enabled"] else CYAN_DIM
		_text(Vector2i(row.position.x + 4, row.position.y + 9), e["label"], LABEL_SIZE, c)


func _draw_card() -> void:
	if _card_def == null:
		return
	var d := _card_def
	var text_lines: Array = [[d.display_name, HEADER_SIZE, TEXT],
		["%s   %dx%d" % [String(d.category).to_upper(), d.size.x, d.size.y], LABEL_SIZE,
			CATEGORY_COLORS.get(d.category, CYAN)]]
	var detail: Array = []
	if d.stackable():
		detail.append("%d / %d" % [_card_count, d.max_stack])
	if d.weight > 0.0:
		detail.append("%.1f KG" % (d.weight * _card_count))
	if not detail.is_empty():
		text_lines.append(["   ".join(detail), LABEL_SIZE, CYAN])
	var head := text_lines.size()
	for row in _wrap((d.description if d.description != "" else "No notes.").to_upper(), CARD_W - 12):
		text_lines.append([row, LABEL_SIZE, TEXT])
	var h := 8 + text_lines.size() * 11 + 7
	var pos := _card_at
	pos.x = clampi(pos.x, 0, maxi(_texels.x - CARD_W, 0))
	pos.y = clampi(pos.y, 0, maxi(_texels.y - h, 0))
	var r := Rect2i(pos.x, pos.y, CARD_W, h)
	_canvas.draw_rect(Rect2(r), PLATE)
	_bevel(r)
	var y := r.position.y + 12
	for i in text_lines.size():
		if i == head:
			y += 3
		_text(Vector2i(r.position.x + 6, y), text_lines[i][0], text_lines[i][1], text_lines[i][2])
		y += 11


## Greedy word wrap to `width` texels at the label size.
func _wrap(text: String, width: int) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" "):
		var trial: String = word if line == "" else line + " " + word
		if line != "" and _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x > width:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


## What the cursor is over, for the tooltip: {"def", "count", "fp"} for an item, {"slot"} for an
## empty equipment slot, {} for nothing. Pure, so tests read it.
func hover_info(at: Vector2i) -> Dictionary:
	var slot := slot_at(at)
	if slot != &"":
		var worn := Inventory.item_in(slot)
		if worn == null:
			return {"slot": slot}
		return {"def": worn.def, "count": 1, "fp": worn.def.size}
	var hit := _grid_hit(at)
	if not hit.is_empty():
		var it := (hit["grid"] as ItemGrid).item_at(hit["cell"])
		return {"def": it.def, "count": it.count, "fp": it.footprint()} if it != null else {}
	if not is_stash_mode():
		var ground := vicinity_item_at(at)
		if ground != null:
			return {"def": ground.def, "count": ground.count, "fp": ground.def.size}
	return {}


## True while the tooltip may show: nothing held or dragged, no popup, no Inspect card.
func tooltip_allowed() -> bool:
	return held == null and not _dragging and _menu.is_empty() and _card_def == null


## The hover tooltip (docs/specs/pilot9-backpack.md, decision 6): at once, below-right of the
## cursor, flipped at the canvas edges.
func _draw_tooltip() -> void:
	if not tooltip_allowed():
		return
	var info := hover_info(_mouse)
	if info.is_empty():
		return
	var text_lines: Array = []
	if info.has("slot"):
		text_lines.append(["%s - EMPTY" % SLOT_LABELS.get(info["slot"], "SLOT"), LABEL_SIZE, CYAN_DIM])
	else:
		var d: ItemDef = info["def"]
		var fp: Vector2i = info["fp"]
		text_lines.append([d.display_name, HEADER_SIZE, TEXT])
		var detail := "%s   %dx%d" % [String(d.category).to_upper(), fp.x, fp.y]
		if d.stackable():
			detail += "   %d / %d" % [info["count"], d.max_stack]
		if d.is_container():
			detail += "   HOLDS %dx%d" % [d.container_size.x, d.container_size.y]
		text_lines.append([detail, LABEL_SIZE, CATEGORY_COLORS.get(d.category, CYAN)])
		if d.description != "":
			for row in _wrap(d.description.to_upper(), TIP_W - 12):
				text_lines.append([row, LABEL_SIZE, TEXT])
	var w := TIP_W
	if text_lines.size() == 1:
		w = int(_font.get_string_size(text_lines[0][0], HORIZONTAL_ALIGNMENT_LEFT, -1, text_lines[0][1]).x) + 12
	var h := 6 + text_lines.size() * 11 + 4
	var pos := _mouse + TIP_OFFSET
	if pos.x + w > _texels.x:
		pos.x = _mouse.x - TIP_OFFSET.x - w
	if pos.y + h > _texels.y:
		pos.y = _mouse.y - TIP_OFFSET.y - h
	pos.x = maxi(pos.x, 0)
	pos.y = maxi(pos.y, 0)
	var r := Rect2i(pos, Vector2i(w, h))
	_canvas.draw_rect(Rect2(r), PLATE)
	_bevel(r)
	var y := r.position.y + 12
	for line in text_lines:
		_text(Vector2i(r.position.x + 6, y), line[0], line[1], line[2])
		y += 11


const HINTS_IDLE := [["LMB", "TAKE / PLACE"], ["SHIFT", "QUICK MOVE"], ["CTRL", "HALF"],
	["RMB", "MENU"], ["R", "ROTATE"], ["T", "SORT"], ["Q", "DROP"], ["TAB", "CLOSE"]]
const HINTS_HELD := [["LMB", "PLACE"], ["RMB", "PUT BACK"], ["R", "ROTATE"], ["Q", "DROP"]]

func _draw_hints() -> void:
	var HINTS: Array = HINTS_HELD if held != null else HINTS_IDLE
	if is_stash_mode():
		HINTS = HINTS.filter(func(h: Array) -> bool: return h[0] != "Q")
	var parts: Array = []
	var total := 0
	for h in HINTS:
		var kw := int(_font.get_string_size(h[0], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x) + 6
		var lw := int(_font.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x)
		parts.append([kw, lw])
		total += kw + 4 + lw + 14
	total -= 14
	@warning_ignore("integer_division")
	var x := (_texels.x - total) / 2
	var y := _hint_y()
	for i in HINTS.size():
		var kw: int = parts[i][0]
		var lw: int = parts[i][1]
		_outline(Rect2i(x, y, kw, 12), CYAN)
		_text(Vector2i(x + 3, y + 9), HINTS[i][0], LABEL_SIZE, CYAN)
		_text(Vector2i(x + kw + 4, y + 9), HINTS[i][1], LABEL_SIZE, TEXT)
		x += kw + 4 + lw + 14


## PS1 window edge: bright top-left, dark bottom-right, corner texels notched.
func _bevel(r: Rect2i) -> void:
	_canvas.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, 1), CYAN)
	_canvas.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), CYAN)
	_canvas.draw_rect(Rect2(r.position.x + 1, r.end.y - 1, r.size.x - 2, 1), BEVEL_SHADE)
	_canvas.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), BEVEL_SHADE)


func _outline(r: Rect2i, c: Color) -> void:
	_canvas.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), c)
	_canvas.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), c)
	_canvas.draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), c)
	_canvas.draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), c)


func _text(at: Vector2i, s: String, font_size: int, c: Color) -> void:
	_canvas.draw_string(_font, Vector2(at), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)
