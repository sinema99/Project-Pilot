class_name Hub2DressingBaked
extends Node3D

# The runtime form of hub2's storage dressing (docs/specs/hub2-load-time.md): scenes/hub2_dressing.tscn,
# written by tools/bake_hub2_dressing.gd from the editable source scenes/hub2_dressing_src.tscn.
# A few merged chunk meshes + a few static bodies of box shapes, instead of ~2,500 nodes that each
# built a mesh. Edit the SOURCE scene (or re-run tools/gen_hub2_dressing.gd), then re-run the bake.

## Light pools of the baked lit lamps: each [Vector4(x, y, z, radius), Vector4(r, g, b, strength)].
@export var lamps: Array = []


## What Hub2LampPools reads in place of Hub2Prop lamps.
func lamp_entries() -> Array:
	return lamps
