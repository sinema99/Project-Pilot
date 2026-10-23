## One thing pilot9 can carry: what it looks like, where it sits in the hand, and the arm pose he
## holds it with. pilot9 only ever knows "the current HeldItem" - a new staff is a
## new .tres, never new code. See docs/specs/pilot9-held-item.md.
class_name HeldItem
extends Resource

## The visual. Instanced once per set_item() into the hand socket, hidden while holstered.
@export var scene: PackedScene
## The instance's transform under the hand socket (RightHand's bone frame), lining its grip up
## with his fist. RightHand's frame: +X along the knuckles' forward, +Y out along the fingers,
## +Z out of the palm (all at rest - the T-pose).
@export var hand_offset: Transform3D = Transform3D.IDENTITY
## The right arm's hold while this is drawn and he is running: bone name -> rotation in degrees
## (Euler, YXZ - the order Basis.get_euler() gives), parent-relative like a Blender pose bone.
## Only rotations, and only the bones in scripts/items/item_holder.gd's ARM_BONES. Authored here
## rather than as a clip so it can be tuned live in the remote inspector while the game runs.
## Empty means no arm override: the item still moves to his hand and the arm does whatever the
## move's clip says.
@export var hold_rotations: Dictionary[StringName, Vector3] = {}
