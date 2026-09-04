@tool
extends EditorScenePostImport

# Runs when assets/Mech_V1.glb is (re)imported.
#
# The Blender file exports every action it holds, and EXIA shares Setsuna's Rigify metarig bone
# names, so fourteen of her clips (RUN LOOP, DASH, SLIDE START ...) come across retargeted onto
# the mech. They play, and they produce nonsense on an 8.4 m machine five times her size.
#
# Everything not named MECH_* is dropped here rather than ignored at runtime, so the mech cannot
# be driven by one of them by accident and the editor's AnimationPlayer lists six clips instead
# of twenty. Fixing the export to only carry the mech's own actions would make this a no-op,
# which is the point: it is safe to keep either way. See docs/specs/exia-pilot.md.
const KEEP_PREFIX := "MECH_"

func _post_import(scene: Node) -> Node:
	for player in _animation_players(scene):
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			# Copied first: removing entries while walking the live list skips names.
			var names: Array = Array(library.get_animation_list())
			for animation_name in names:
				if not String(animation_name).begins_with(KEEP_PREFIX):
					library.remove_animation(animation_name)
	return scene

func _animation_players(node: Node) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	if node is AnimationPlayer:
		out.append(node as AnimationPlayer)
	for child in node.get_children():
		out.append_array(_animation_players(child))
	return out
