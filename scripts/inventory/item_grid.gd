class_name ItemGrid
extends RefCounted

# A Tetris container: W x H cells, items occupying rectangles that never overlap. Pure - no
# nodes - so the rules are asserted directly by tests/test_inventory.gd. Today the player has one
# (10 x 6, owned by the Inventory autoload); worn gear can bring more later.
# See docs/specs/inventory.md.

signal changed

var width := 10
var height := 6
var items: Array[ItemStack] = []
## True for a container's own grid: it never takes a container (no packs in packs).
var no_containers := false


func _init(w: int = 10, h: int = 6) -> void:
	width = w
	height = h


## A container's grid: `size`, refusing containers.
static func make_container(size: Vector2i) -> ItemGrid:
	var g := ItemGrid.new(size.x, size.y)
	g.no_containers = true
	return g


## Whether this grid may hold `def` at all (a container's grid refuses containers).
func accepts(def: ItemDef) -> bool:
	return def != null and not (no_containers and def.is_container())


## True when a `footprint` rectangle at `cell` is inside the grid and touches no item except
## `ignore` (the one being moved).
func fits(cell: Vector2i, footprint: Vector2i, ignore: ItemStack = null) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x + footprint.x > width or cell.y + footprint.y > height:
		return false
	var r := Rect2i(cell, footprint)
	for it in items:
		if it != ignore and it.rect().intersects(r):
			return false
	return true


func item_at(cell: Vector2i) -> ItemStack:
	for it in items:
		if it.rect().has_point(cell):
			return it
	return null


## First free spot scanning rows top to bottom, upright before rotated. {} = no room.
## Returns {"cell": Vector2i, "rotated": bool}.
func find_free(size: Vector2i) -> Dictionary:
	for rot in ([false, true] if size.x != size.y else [false]):
		var fp := ItemStack.footprint_of(size, rot)
		for y in height - fp.y + 1:
			for x in width - fp.x + 1:
				if fits(Vector2i(x, y), fp):
					return {"cell": Vector2i(x, y), "rotated": rot}
	return {}


## Puts `stack` at `cell` with `rotated`. False (and nothing changes) if it does not fit.
func place(stack: ItemStack, cell: Vector2i, is_rotated: bool) -> bool:
	if not accepts(stack.def) or not fits(cell, ItemStack.footprint_of(stack.def.size, is_rotated), stack):
		return false
	stack.cell = cell
	stack.rotated = is_rotated
	if not items.has(stack):
		items.append(stack)
	changed.emit()
	return true


func remove(stack: ItemStack) -> void:
	if items.has(stack):
		items.erase(stack)
		changed.emit()


## How many of `def` could go in: room in existing stacks plus one fresh stack if a spot is free.
## Only the first fresh stack counts - a full grid of rations is not this function's business.
func capacity_for(def: ItemDef) -> int:
	if not accepts(def):
		return 0
	var room := 0
	for it in items:
		if it.def == def:
			room += maxi(def.max_stack - it.count, 0)
	if not find_free(def.size).is_empty():
		room += def.max_stack
	return room


## Adds `count` of `def`: tops up existing stacks first, then one new stack in the first free
## spot. Returns how many were taken (0..count).
func add(def: ItemDef, count: int) -> int:
	if not accepts(def):
		return 0
	var left := count
	for it in items:
		if left <= 0:
			break
		if it.def == def and it.count < def.max_stack:
			var n := mini(def.max_stack - it.count, left)
			it.count += n
			left -= n
	if left > 0:
		var spot := find_free(def.size)
		if not spot.is_empty():
			var stack := ItemStack.new(def, mini(left, def.max_stack))
			left -= stack.count
			place(stack, spot["cell"], spot["rotated"])
			return count - left
	if left != count:
		changed.emit()
	return count - left


## Merges `stack` into the item at `cell` if it is the same stackable kind. Returns how many
## moved. Does not remove `stack` - the caller owns where it came from.
func merge_into(target: ItemStack, stack: ItemStack) -> int:
	if target == null or target == stack or target.def != stack.def or not target.def.stackable():
		return 0
	var n := mini(target.def.max_stack - target.count, stack.count)
	if n > 0:
		target.count += n
		stack.count -= n
		changed.emit()
	return n


## The layout as plain data, for undo: [[def, count, cell, rotated, contents], ...].
func snapshot() -> Array:
	var out: Array = []
	for it in items:
		out.append([it.def, it.count, it.cell, it.rotated, it.contents])
	return out


## Replaces every item with the ones in `snap` (from snapshot()). Fresh ItemStacks.
func restore(snap: Array) -> void:
	items.clear()
	for e: Array in snap:
		var s := ItemStack.new(e[0], e[1], e[4] if e.size() > 4 else null)
		s.cell = e[2]
		s.rotated = e[3]
		items.append(s)
	changed.emit()


## Sort order for items: category, then biggest area, then name.
static func sort_before(a: ItemStack, b: ItemStack) -> bool:
	return sort_key_before(a.def, a.footprint(), b.def, b.footprint())


static func sort_key_before(da: ItemDef, fa: Vector2i, db: ItemDef, fb: Vector2i) -> bool:
	if da.category_rank() != db.category_rank():
		return da.category_rank() < db.category_rank()
	var aa := fa.x * fa.y
	var ab := fb.x * fb.y
	if aa != ab:
		return aa > ab
	return da.display_name < db.display_name


## Merges partial stacks, then repacks everything with no gaps: category first, biggest first.
## False (grid untouched) if the repack would not fit - tidy packing can lose to the layout you
## had.
func sort_items() -> bool:
	var before := snapshot()
	# 1. Merge partial stacks of the same kind.
	var merged: Array[ItemStack] = []
	for it in items:
		var into: ItemStack = null
		if it.def.stackable():
			for m in merged:
				if m.def == it.def and m.count < m.def.max_stack:
					into = m
					break
		if into == null:
			merged.append(ItemStack.new(it.def, it.count, it.contents))
			continue
		var n := mini(into.def.max_stack - into.count, it.count)
		into.count += n
		if it.count - n > 0:
			merged.append(ItemStack.new(it.def, it.count - n))
	# 2. Repack in order.
	merged.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		return sort_key_before(a.def, a.def.size, b.def, b.def.size))
	items.clear()
	for s in merged:
		var spot := find_free(s.def.size)
		if spot.is_empty():
			restore(before)
			return false
		s.cell = spot["cell"]
		s.rotated = spot["rotated"]
		items.append(s)
	changed.emit()
	return true


## Takes `count` out of `stack` (kept in the grid) and returns it as a new ItemStack. Null if it
## would leave nothing behind or take nothing.
func split(stack: ItemStack, count: int) -> ItemStack:
	if stack == null or count <= 0 or count >= stack.count:
		return null
	stack.count -= count
	changed.emit()
	return ItemStack.new(stack.def, count)
