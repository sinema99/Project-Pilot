@tool
extends EditorScenePostImport

# Runs when assets/setsuna.glb is (re)imported.
#
# Setsuna's blend exports every action it holds, and only some of them are hers. Two kinds of
# stowaway ride along:
#
#   - **The mech's clips.** EXIA shares Setsuna's Rigify metarig bone names, so every `MECH.*`
#     action is exported retargeted onto her - the mirror image of what scripts/mech_import.gd
#     cleans off the mech.
#   - **`PLACEHOLDER*`.** Dead actions the user could not delete in Blender and renamed instead,
#     as of the 2026-09-03 SETSUNA.glb export. Most are collapsed to a single keyframe; at least
#     one (`PLACEHOLDER.011`) still carries a full second of real motion. None of them are hers.
#
# So this is an allow-list, not a drop-list: anything not named below is removed at import, the
# `has_animation()` guards through scripts/player.gd go false, and the move it belongs to falls
# back to the locomotion clips instead of playing garbage. Nothing at runtime knows a clip is
# missing.
#
# **Every clip of hers is prefixed `SET ` (for Setsuna) as of the 2026-09-03 SETSUNA.glb
# export** - that prefix is the user's marker for "this action belongs to Setsuna", so a new
# clip that does not carry it is a stowaway until they say otherwise.
#
# **To re-enable a clip, add its name here** - that is the whole switch.
const KEEP := [
	"SET IDLE",
	"SET RUN LOOP",
	# The crouch. Three clips, and all three are *static poses* rather than cycles - nothing in
	# any of them moves over its own second. LEFT and RIGHT are the crouch leaning to one side and
	# the plain one is the upright crouch between them, so the crouch is built by blending the
	# three in the tree off how hard she is turning rather than by playing a cycle.
	# See docs/specs/setsuna-animation-tree.md.
	"SET CROUCH LOOP",
	"SET CROUCH LOOP LEFT",
	"SET CROUCH LOOP RIGHT",
	# The airborne cycle - it loops for as long as she is off the ground. The wind-up and the
	# landing clips it used to sit between (`Jump.start` / `Jump.end`) were deleted in Blender
	# for this export; the tree's crossfades do that job now.
	"SET JUMP LOOP",
	# The walk-off-a-ledge cycle. Its first and last frames are ~29 degrees apart, so it does not
	# loop seamlessly; player.gd ping-pongs it rather than looping it, which hides that.
	"SET Falling",
	# Speed-scaled into DASH_TIME by player.gd, through the DASH state's TimeScale. The sustain
	# clip it used to hand over to (`DASH.loop`) is gone with this export.
	"SET DASH",
	# The climb into EXIA - 2.0 s, and the only clip here that is not locomotion. It is a
	# scripted move rather than a state: mech.gd starts it, waits it out, and only then boots
	# the machine up, and the animation tree is switched off for the whole sequence.
	# See docs/specs/exia-pilot.md.
	"SET embark",
]

func _post_import(scene: Node) -> Node:
	for player in _animation_players(scene):
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			# Copied first: removing entries while walking the live list skips names.
			var names: Array = Array(library.get_animation_list())
			for animation_name in names:
				if not KEEP.has(String(animation_name)):
					library.remove_animation(animation_name)
	return scene

func _animation_players(node: Node) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		out.append(node as AnimationPlayer)
	for child in node.get_children():
		out.append_array(_animation_players(child))
	return out
