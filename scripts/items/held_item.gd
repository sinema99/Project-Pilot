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

## The arm's pose at walking pace or slower, same format as hold_rotations. It blends into
## hold_rotations (the running pose) over the same walk-to-run range as the speed gate, so the
## revolver is held out wide standing still and trails behind in a sprint. Empty means
## hold_rotations at every pace (the staff).
@export var idle_rotations: Dictionary[StringName, Vector3] = {}

## The arm pose at full aim (right mouse held), same format. Blended over the hip pose by the
## gun's aim weight; empty means the hip pose stays. Guns only.
@export var aim_rotations: Dictionary[StringName, Vector3] = {}
## The same at the camera looking 40 degrees up and 40 down; the pose blends between the three by
## the camera's pitch, so the muzzle follows the view. Solved by tests/_probe_solve_aim.gd.
@export var aim_rotations_up: Dictionary[StringName, Vector3] = {}
@export var aim_rotations_down: Dictionary[StringName, Vector3] = {}

## The bladed aim stance: bone name -> yaw degrees about the skeleton's up axis, added on top of the
## animation at full aim (NEGATIVE turns his right shoulder back: positive yaws him to his left). Spine, chest and upper chest
## turn him; neck and head turn back so he still looks down the barrel. The aim arm poses are
## solved with this twist in place. Empty keeps the torso square (the revolver).
@export var aim_twist_deg: Dictionary[StringName, float] = {}

## Aim by placement + IK (scripts/items/aim_ik.gd) instead of the aim_rotations poses: the item goes
## where a shooter holds it and both arms reach their grips. The aim_rotations are ignored when on.
@export var aim_ik: bool = false
## IK numbers. `aim_anchor_item` is the ITEM-frame point (origin at the grip, -Z down the barrel)
## that gets pinned to his body: the middle of the rifle's butt plate, or a point on the revolver's
## barrel line. `aim_anchor_offset` is where on his body, (right, up, forward) metres from the right
## shoulder joint - or, with `aim_center`, from the midpoint of both shoulder joints - forward being
## toward the aim point. Never placed from the head. See docs/specs/pilot9-gun-aim.md.
@export var aim_anchor_item: Vector3 = Vector3.ZERO
@export var aim_anchor_offset: Vector3 = Vector3.ZERO
@export var aim_center: bool = false
## The left WRIST's frame on the gun, ITEM frame (hand bone: +Y down the fingers, +Z out of the palm).
@export var aim_left_hand: Transform3D = Transform3D.IDENTITY
## Which way each elbow bends, (right, up, forward) in his frame.
@export var aim_right_pole: Vector3 = Vector3(0.35, -1.0, 0.0)
@export var aim_left_pole: Vector3 = Vector3(-0.35, -1.0, 0.0)
## How much of the aim's up / down pitch his upper body takes (spine, chest, upper chest), 0..1.
@export var aim_bend: float = 1.0

## How the equip animation forms it in his hand. LENGTH stretches it along its own +Y out of the
## grip (the staff, a plain cylinder). UNIFORM grows the whole thing from the grip, glowing cyan
## and cooling to its colour (the revolver - a stretch would squash it). See
## docs/specs/pilot9-revolver.md.
enum Grow { LENGTH, UNIFORM }
@export var grow: Grow = Grow.LENGTH
## Whether the reflect spin may use it. Only the staff: with anything else drawn, left mouse
## does nothing.
@export var can_reflect: bool = false
## Hold the arm pose at every pace, idle and walk included, rather than only at running pace.
@export var hold_at_any_speed: bool = false
## AnimationTree states this item turns the hold off in, on top of the holder's own off list.
@export var hold_off_states: Array[StringName] = []
## Where it sits on his body while holstered (scripts/items/weapon_mounts.gd). Empty slot_bone means
## it is not shown when holstered (the staff). slot_origin is where the item's origin (the grip) goes,
## in skeleton space (+Y up, his left +X, his back faces -Z); slot_muzzle_dir is the way the barrel
## points and slot_top_dir the way the top of the gun faces, both skeleton space. The _bare set is
## used instead while he wears no backpack; a zero slot_bare_muzzle_dir means "same as slot_".
@export_group("Body slot")
@export var slot_bone: StringName = &""
@export var slot_origin: Vector3 = Vector3.ZERO
@export var slot_muzzle_dir: Vector3 = Vector3.UP
@export var slot_top_dir: Vector3 = Vector3.RIGHT
@export var slot_bare_origin: Vector3 = Vector3.ZERO
@export var slot_bare_muzzle_dir: Vector3 = Vector3.ZERO
@export var slot_bare_top_dir: Vector3 = Vector3.RIGHT
@export_group("")

## Set on a gun: its numbers. Null on everything else (the staff), which fires nothing.
@export var gun: GunDef
