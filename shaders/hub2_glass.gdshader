shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, fog_disabled, shadows_disabled;

// The crane control room's windows (docs/specs/hub2-control-room.md): intact, dirty PS1 glass.
// A flat cold green-grey tint at ~7 % opacity (clear: the yard must read through it), grime that thickens toward the bottom edge of each
// pane, a few dirty streaks and one hard fake reflection band, all in dithered steps. Unshaded and
// double sided so it looks the same from the room and from the yard. COLOR.r = 0 at a pane's bottom
// edge, 1 at its top (written by Hub2ControlRoom when it builds the glass).

uniform vec3 tint : source_color = vec3(0.22, 0.42, 0.40);
uniform vec3 dirt : source_color = vec3(0.07, 0.08, 0.07);
uniform float base_alpha = 0.07;
uniform float levels = 6.0;

varying vec3 wpos;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = clamp(COLOR.r, 0.0, 1.0);
	float grime = pow(1.0 - up, 2.5);
	// Streaks: narrow columns that run down from the top and fade toward the bottom.
	float col_id = floor(wpos.z * 2.2);
	float streak = step(0.8, h(vec2(col_id, 3.0))) * (0.35 + 0.65 * h(vec2(col_id, 9.0)));
	streak *= smoothstep(0.0, 0.6, 1.0 - up * 0.5);
	// One hard diagonal reflection band, repeating every ~11 m along the pane.
	float d = fract((wpos.z * 0.22 + wpos.y * 0.5) * 0.5);
	float band = step(0.72, d) * step(d, 0.8);
	float a = base_alpha + grime * 0.16 + streak * 0.1 + band * 0.14;
	vec3 c = mix(tint, dirt, clamp(grime * 0.85 + streak * 0.5, 0.0, 1.0));
	c = mix(c, vec3(0.78, 0.86, 0.86), band * 0.6);
	// Dithered steps (PS1 transparency stipple).
	float t = bayer4(FRAGCOORD.xy);
	a = floor(a * levels + t) / levels;
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 0.45);
}
