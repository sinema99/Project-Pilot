extends Node

# Autoload: press M anywhere in a running build to save a PNG of the whole
# window to res://screenshots/. Debug convenience - res:// is only writable when
# running from the editor / a debug build, which is exactly when you want this.
#
# Registered as the `Screenshot` autoload in project.godot.

const DIR := "res://screenshots"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_capture()


func _capture() -> void:
	# Wait for the frame to finish so the grab is never a half-drawn buffer.
	await RenderingServer.frame_post_draw

	var err := DirAccess.make_dir_recursive_absolute(DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("screenshot: could not create %s (%d)" % [DIR, err])
		return

	var image := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/shot_%s.png" % [DIR, stamp]
	err = image.save_png(path)
	if err == OK:
		print("screenshot saved: ", ProjectSettings.globalize_path(path))
	else:
		push_error("screenshot: save failed (%d) -> %s" % [err, path])
