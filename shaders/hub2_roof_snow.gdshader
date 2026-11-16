// Falling snow in hub2's roof-door column (docs/specs/hub2-roof-door.md). Every flake is a camera-facing
// square quad, positioned entirely here from TIME: it falls slowly, wraps at the bottom of the column,
// sways a little. Flakes inside the daylight beams are bright, the rest dim grey, and they sink into the
// fog colour the deeper they fall. No simulation, no lighting.
//
// Mesh contract (Hub2RoofDoor._build_flakes): VERTEX = the flake's start position in the node's space,
// UV = the quad corner (+-0.5), COLOR.r = size in metres, COLOR.g = phase 0..1, COLOR.b = speed factor.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_opaque;

uniform float fall_speed = 1.2;
uniform float sway = 0.9;
// Node-space y of the top of the column, and how far it runs before a flake wraps.
uniform float column_top = 2.2;
uniform float column_height = 152.0;
// The sky gap in node space: x0, z0, x1, z1.
uniform vec4 gap = vec4(-12.0, -32.0, 12.0, 32.0);
// Sideways travel of a beam per metre of fall.
uniform float beam_shift = 0.4663;
uniform float dark_begin = -50.0;
uniform float dark_end = -150.0;
uniform vec3 lit_color : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 dim_color : source_color = vec3(0.30, 0.34, 0.40);
uniform vec3 fog_tint : source_color = vec3(0.075, 0.14, 0.19);

varying vec3 v_col;

void vertex() {
	vec3 p = VERTEX;
	float phase = COLOR.g;
	p.y = column_top - mod(column_top - p.y + TIME * fall_speed * COLOR.b, column_height);
	p.x += sway * sin(TIME * 0.55 + phase * 6.2831 + p.y * 0.05);
	p.z += sway * 0.7 * cos(TIME * 0.43 + phase * 11.0);
	float x_top = p.x + beam_shift * (0.0 - p.y);
	bool in_beam = x_top > gap.x && x_top < gap.z && p.z > gap.y && p.z < gap.w;
	float depth = clamp((p.y - dark_end) / (dark_begin - dark_end), 0.0, 1.0);
	v_col = mix(fog_tint, in_beam ? lit_color : dim_color, depth);
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	mv.xy += UV * COLOR.r;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	ALBEDO = v_col;
}
