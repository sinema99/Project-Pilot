class_name KnightPoses
extends RefCounted

# The Knight's key poses (docs/specs/knight-moveset.md). Same format as KnightBody.POSE: per bone,
# model-space rotations [axis, degrees] applied relative to the parent, in the rest frame (+X his
# left, +Y up, +Z his front). KnightBrain blends between them on eased curves.
#
# Reading the axes:
#   Spine/Chest/Head RIGHT +  = bow forward,        RIGHT - = arch back.
#   UpperLeg RIGHT -          = thigh forward,      LowerLeg RIGHT + = knee bends (shin back).
#   Foot RIGHT +              = toes point down.
#   LeftUpperArm  BACK -      = arm down,           BACK + = arm up.     UP - = arm forward.
#   RightUpperArm BACK +      = arm down,           BACK - = arm up.     UP + = arm forward.
#   A HANGING arm (BACK +-80 first) swings forward with RIGHT -, not UP.
#   Spine UP -                = his right shoulder turns back.

## The drawing's pose: dormant.
const DRAWING := KnightBody.POSE

## Floating: legs hang loose, toes down, arms low and a little out, head dipped.
const HOVER := {
	&"Hips": [[Vector3.RIGHT, 3.0]],
	&"Spine": [[Vector3.RIGHT, 4.0]],
	&"Chest": [[Vector3.RIGHT, 3.0]],
	&"Head": [[Vector3.RIGHT, 7.0]],
	&"LeftUpperArm": [[Vector3.BACK, -64.0], [Vector3.UP, -12.0]],
	&"LeftLowerArm": [[Vector3.UP, -22.0]],
	&"LeftHand": [[Vector3.BACK, -10.0]],
	&"RightUpperArm": [[Vector3.BACK, 64.0], [Vector3.UP, 12.0]],
	&"RightLowerArm": [[Vector3.UP, 22.0]],
	&"RightHand": [[Vector3.BACK, 10.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -8.0], [Vector3.BACK, -3.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 18.0]],
	&"LeftFoot": [[Vector3.RIGHT, 58.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, -3.0], [Vector3.BACK, 3.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 26.0]],
	&"RightFoot": [[Vector3.RIGHT, 60.0]],
}

## The wake: head up, chest open, arms flung wide and a little up.
const WAKE_SPREAD := {
	&"Hips": [[Vector3.RIGHT, -2.0]],
	&"Spine": [[Vector3.RIGHT, -6.0]],
	&"Chest": [[Vector3.RIGHT, -7.0]],
	&"Head": [[Vector3.RIGHT, -14.0]],
	&"LeftUpperArm": [[Vector3.BACK, 12.0], [Vector3.UP, 14.0]],
	&"LeftLowerArm": [[Vector3.UP, -8.0]],
	&"LeftHand": [[Vector3.BACK, 14.0]],
	&"RightUpperArm": [[Vector3.BACK, -12.0], [Vector3.UP, -14.0]],
	&"RightLowerArm": [[Vector3.UP, 8.0]],
	&"RightHand": [[Vector3.BACK, -14.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, 2.0], [Vector3.BACK, -4.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 10.0]],
	&"LeftFoot": [[Vector3.RIGHT, 64.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 4.0], [Vector3.BACK, 4.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 12.0]],
	&"RightFoot": [[Vector3.RIGHT, 64.0]],
}

## Laser windup 1: the right claw drawn back to his chest, right shoulder turned away.
const LASER_DRAW := {
	&"Hips": [[Vector3.UP, -8.0]],
	&"Spine": [[Vector3.UP, -14.0], [Vector3.RIGHT, 3.0]],
	&"Chest": [[Vector3.UP, -10.0]],
	&"Head": [[Vector3.UP, 18.0], [Vector3.RIGHT, 6.0]],
	&"RightUpperArm": [[Vector3.BACK, 38.0], [Vector3.UP, 62.0]],
	&"RightLowerArm": [[Vector3.UP, 112.0]],
	&"RightHand": [[Vector3.BACK, 20.0]],
	&"LeftUpperArm": [[Vector3.BACK, -58.0], [Vector3.UP, -24.0]],
	&"LeftLowerArm": [[Vector3.UP, -40.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -12.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 30.0]],
	&"LeftFoot": [[Vector3.RIGHT, 55.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 2.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 22.0]],
	&"RightFoot": [[Vector3.RIGHT, 60.0]],
}

## Laser windup 2 / lock: the right arm thrust straight at pilot (the drawing's reach), left arm
## swept back for balance.
const LASER_THRUST := {
	&"Hips": [[Vector3.UP, 6.0]],
	&"Spine": [[Vector3.UP, 12.0], [Vector3.RIGHT, 4.0]],
	&"Chest": [[Vector3.UP, 8.0]],
	&"Head": [[Vector3.UP, -14.0], [Vector3.RIGHT, 4.0]],
	&"RightUpperArm": [[Vector3.BACK, 4.0], [Vector3.UP, 72.0]],
	&"RightLowerArm": [[Vector3.UP, 4.0]],
	&"RightHand": [[Vector3.BACK, -6.0]],
	&"LeftUpperArm": [[Vector3.BACK, -52.0], [Vector3.UP, 34.0]],
	&"LeftLowerArm": [[Vector3.UP, -18.0]],
	&"LeftHand": [[Vector3.BACK, -18.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, 6.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 30.0]],
	&"LeftFoot": [[Vector3.RIGHT, 62.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, -14.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 20.0]],
	&"RightFoot": [[Vector3.RIGHT, 56.0]],
}

## Laser fire: the recoil - torso thrown back, the arm kicked up, legs and robe whipping forward.
const LASER_RECOIL := {
	&"Hips": [[Vector3.UP, 4.0], [Vector3.RIGHT, -6.0]],
	&"Spine": [[Vector3.UP, 8.0], [Vector3.RIGHT, -10.0]],
	&"Chest": [[Vector3.UP, 4.0], [Vector3.RIGHT, -6.0]],
	&"Head": [[Vector3.UP, -10.0], [Vector3.RIGHT, -12.0]],
	&"RightUpperArm": [[Vector3.BACK, -22.0], [Vector3.UP, 64.0]],
	&"RightLowerArm": [[Vector3.UP, 28.0]],
	&"RightHand": [[Vector3.BACK, -22.0]],
	&"LeftUpperArm": [[Vector3.BACK, -40.0], [Vector3.UP, 40.0]],
	&"LeftLowerArm": [[Vector3.UP, -10.0]],
	&"LeftHand": [[Vector3.BACK, -24.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -28.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 14.0]],
	&"LeftFoot": [[Vector3.RIGHT, 50.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, -34.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 18.0]],
	&"RightFoot": [[Vector3.RIGHT, 50.0]],
}

## Laser recovery: spent - the arm dropped, shoulders and head sagging.
const LASER_SAG := {
	&"Hips": [[Vector3.RIGHT, 5.0]],
	&"Spine": [[Vector3.RIGHT, 12.0]],
	&"Chest": [[Vector3.RIGHT, 9.0]],
	&"Head": [[Vector3.RIGHT, 16.0]],
	&"RightUpperArm": [[Vector3.BACK, 74.0], [Vector3.UP, 16.0]],
	&"RightLowerArm": [[Vector3.UP, 12.0]],
	&"RightHand": [[Vector3.BACK, 16.0]],
	&"LeftUpperArm": [[Vector3.BACK, -72.0], [Vector3.UP, -8.0]],
	&"LeftLowerArm": [[Vector3.UP, -14.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -6.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 20.0]],
	&"LeftFoot": [[Vector3.RIGHT, 60.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, -2.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 24.0]],
	&"RightFoot": [[Vector3.RIGHT, 60.0]],
}

## Missile windup: both arms swept up over his head, back arched, legs trailing.
const MISSILE_RAISE := {
	&"Hips": [[Vector3.RIGHT, -4.0]],
	&"Spine": [[Vector3.RIGHT, -10.0]],
	&"Chest": [[Vector3.RIGHT, -10.0]],
	&"Head": [[Vector3.RIGHT, -18.0]],
	&"LeftUpperArm": [[Vector3.BACK, 66.0], [Vector3.UP, -14.0]],
	&"LeftLowerArm": [[Vector3.UP, -20.0]],
	&"LeftHand": [[Vector3.BACK, 10.0]],
	&"RightUpperArm": [[Vector3.BACK, -66.0], [Vector3.UP, 14.0]],
	&"RightLowerArm": [[Vector3.UP, 20.0]],
	&"RightHand": [[Vector3.BACK, -10.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, 8.0], [Vector3.BACK, -3.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 30.0]],
	&"LeftFoot": [[Vector3.RIGHT, 64.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 12.0], [Vector3.BACK, 3.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 34.0]],
	&"RightFoot": [[Vector3.RIGHT, 64.0]],
}

## Missile launch: the arms snapped higher and wider, head thrown back, claws flared.
const MISSILE_SNAP := {
	&"Hips": [[Vector3.RIGHT, -6.0]],
	&"Spine": [[Vector3.RIGHT, -14.0]],
	&"Chest": [[Vector3.RIGHT, -12.0]],
	&"Head": [[Vector3.RIGHT, -26.0]],
	&"LeftUpperArm": [[Vector3.BACK, 84.0], [Vector3.UP, 6.0]],
	&"LeftLowerArm": [[Vector3.UP, -6.0]],
	&"LeftHand": [[Vector3.BACK, 26.0]],
	&"RightUpperArm": [[Vector3.BACK, -84.0], [Vector3.UP, -6.0]],
	&"RightLowerArm": [[Vector3.UP, 6.0]],
	&"RightHand": [[Vector3.BACK, -26.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, 12.0], [Vector3.BACK, -5.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 22.0]],
	&"LeftFoot": [[Vector3.RIGHT, 66.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 16.0], [Vector3.BACK, 5.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 26.0]],
	&"RightFoot": [[Vector3.RIGHT, 66.0]],
}

## Smash rise: claws gathered high overhead, knees tucked.
const SMASH_GATHER := {
	&"Hips": [[Vector3.RIGHT, -2.0]],
	&"Spine": [[Vector3.RIGHT, -8.0]],
	&"Chest": [[Vector3.RIGHT, -6.0]],
	&"Head": [[Vector3.RIGHT, 4.0]],
	&"LeftUpperArm": [[Vector3.BACK, 70.0], [Vector3.UP, -30.0]],
	&"LeftLowerArm": [[Vector3.UP, -48.0]],
	&"LeftHand": [[Vector3.BACK, 16.0]],
	&"RightUpperArm": [[Vector3.BACK, -70.0], [Vector3.UP, 30.0]],
	&"RightLowerArm": [[Vector3.UP, 48.0]],
	&"RightHand": [[Vector3.BACK, -16.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -46.0], [Vector3.BACK, -4.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 76.0]],
	&"LeftFoot": [[Vector3.RIGHT, 50.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, -40.0], [Vector3.BACK, 4.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 80.0]],
	&"RightFoot": [[Vector3.RIGHT, 50.0]],
}

## Smash mark: curled forward over the ring, claws still up, looking down at pilot.
const SMASH_CURL := {
	&"Hips": [[Vector3.RIGHT, 10.0]],
	&"Spine": [[Vector3.RIGHT, 18.0]],
	&"Chest": [[Vector3.RIGHT, 14.0]],
	&"Head": [[Vector3.RIGHT, 22.0]],
	&"LeftUpperArm": [[Vector3.BACK, 52.0], [Vector3.UP, -48.0]],
	&"LeftLowerArm": [[Vector3.UP, -56.0]],
	&"LeftHand": [[Vector3.BACK, 20.0]],
	&"RightUpperArm": [[Vector3.BACK, -52.0], [Vector3.UP, 48.0]],
	&"RightLowerArm": [[Vector3.UP, 56.0]],
	&"RightHand": [[Vector3.BACK, -20.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, -54.0], [Vector3.BACK, -4.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 88.0]],
	&"LeftFoot": [[Vector3.RIGHT, 50.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, -50.0], [Vector3.BACK, 4.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 90.0]],
	&"RightFoot": [[Vector3.RIGHT, 50.0]],
}

## Smash dive: head-down and claws first, both arms driven straight down the dive, legs streaming
## up behind. (A hanging arm swings forward about RIGHT, not UP: BACK -85 drops it along the body,
## then RIGHT - swings it forward of the pitched torso.)
const SMASH_DIVE := {
	&"Hips": [[Vector3.RIGHT, 48.0]],
	&"Spine": [[Vector3.RIGHT, 12.0]],
	&"Chest": [[Vector3.RIGHT, 8.0]],
	&"Head": [[Vector3.RIGHT, -26.0]],
	&"LeftUpperArm": [[Vector3.BACK, -82.0], [Vector3.RIGHT, -78.0]],
	&"LeftLowerArm": [[Vector3.RIGHT, -6.0]],
	&"LeftHand": [[Vector3.BACK, -20.0]],
	&"RightUpperArm": [[Vector3.BACK, 82.0], [Vector3.RIGHT, -78.0]],
	&"RightLowerArm": [[Vector3.RIGHT, -6.0]],
	&"RightHand": [[Vector3.BACK, 20.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, 14.0], [Vector3.BACK, -6.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 30.0]],
	&"LeftFoot": [[Vector3.RIGHT, 70.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 20.0], [Vector3.BACK, 6.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 22.0]],
	&"RightFoot": [[Vector3.RIGHT, 70.0]],
}

## Smash stuck: hunched far over, arms straight down with the claws buried in the floor in front of
## him, head up at pilot, legs folded back behind (he floats, nothing under his knees).
const SMASH_STUCK := {
	&"Hips": [[Vector3.RIGHT, 40.0]],
	&"Spine": [[Vector3.RIGHT, 14.0]],
	&"Chest": [[Vector3.RIGHT, 8.0]],
	&"Head": [[Vector3.RIGHT, -34.0]],
	&"LeftUpperArm": [[Vector3.BACK, -80.0], [Vector3.RIGHT, -54.0], [Vector3.UP, -8.0]],
	&"LeftLowerArm": [[Vector3.RIGHT, -12.0]],
	&"LeftHand": [[Vector3.BACK, -30.0]],
	&"RightUpperArm": [[Vector3.BACK, 80.0], [Vector3.RIGHT, -54.0], [Vector3.UP, 8.0]],
	&"RightLowerArm": [[Vector3.RIGHT, -12.0]],
	&"RightHand": [[Vector3.BACK, 30.0]],
	&"LeftUpperLeg": [[Vector3.RIGHT, 6.0], [Vector3.BACK, -8.0]],
	&"LeftLowerLeg": [[Vector3.RIGHT, 78.0]],
	&"LeftFoot": [[Vector3.RIGHT, 40.0]],
	&"RightUpperLeg": [[Vector3.RIGHT, 12.0], [Vector3.BACK, 8.0]],
	&"RightLowerLeg": [[Vector3.RIGHT, 70.0]],
	&"RightFoot": [[Vector3.RIGHT, 40.0]],
}

## Every pose by name (the brain solves them all once).
const ALL := {
	&"drawing": DRAWING, &"hover": HOVER, &"wake": WAKE_SPREAD,
	&"laser_draw": LASER_DRAW, &"laser_thrust": LASER_THRUST, &"laser_recoil": LASER_RECOIL,
	&"laser_sag": LASER_SAG, &"missile_raise": MISSILE_RAISE, &"missile_snap": MISSILE_SNAP,
	&"smash_gather": SMASH_GATHER, &"smash_curl": SMASH_CURL, &"smash_dive": SMASH_DIVE,
	&"smash_stuck": SMASH_STUCK,
}
