shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_add;
// Pilot's meshes write stencil 1 while the menu is up: the beam is skipped there, so his head
// reads as in front of the projection.
stencil_mode read, compare_not_equal, 1;

// The projection cone from the visor to the panel's corners. UV.y runs 0 at the emitter to 1 at
// the panel. Flares on the open, then holds a faint resting level while the menu is up.

uniform vec3 tint : source_color = vec3(0.25, 0.95, 0.9);
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float along = UV.y;
	float streaks = 0.5 + 0.5 * sin(UV.x * 40.0 + along * 6.0 - TIME * 6.0);
	float body = mix(0.55, 0.12, along);
	ALBEDO = tint * (body + streaks * 0.25);
	// Brightest at the head, faintest where it reaches the menu's edges.
	ALPHA = strength * (0.35 + 0.65 * (1.0 - along * 0.6)) * mix(1.0, 0.4, along);
}
