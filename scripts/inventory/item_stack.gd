class_name ItemStack
extends RefCounted

# One copy of an item (or a stack of them) and where it sits in a grid. `cell` is its top-left
# cell; `rotated` swaps W and H. See docs/specs/inventory.md.

var def: ItemDef
var count := 1
var cell := Vector2i.ZERO
var rotated := false
## A container's own grid (a backpack's 6 x 4), null for everything else. Made empty with the
## stack; whoever moves a container moves this with it. See docs/specs/pilot9-backpack.md.
var contents: ItemGrid = null


func _init(item_def: ItemDef = null, item_count: int = 1, item_contents: ItemGrid = null) -> void:
	def = item_def
	count = item_count
	if def != null and def.is_container():
		contents = item_contents if item_contents != null else ItemGrid.make_container(def.container_size)


## Cells it covers, W x H, with rotation applied.
func footprint() -> Vector2i:
	return footprint_of(def.size if def != null else Vector2i.ONE, rotated)


func rect() -> Rect2i:
	return Rect2i(cell, footprint())


static func footprint_of(size: Vector2i, is_rotated: bool) -> Vector2i:
	return Vector2i(size.y, size.x) if is_rotated else size
