shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// A powered 90s terminal screen in hub2 (docs/specs/hub2-storage.md): scrolling garbage text in
// chunky stepped pixels, a blinking cursor, scanlines and a flicker. Green or amber per screen,
// picked by a hash of where the screen is. Unshaded so AIRFRAME leaves it alone.

uniform vec2 grid = vec2(28.0, 14.0);        // characters across, rows down
uniform float scroll_speed = 0.6;            // rows per second
uniform vec3 green : source_color = vec3(0.35, 1.0, 0.45);
uniform vec3 amber : source_color = vec3(1.0, 0.68, 0.2);
uniform float brightness = 1.4;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 cell_id = floor(wpos * 0.5);
	float seed = h(cell_id.xz + cell_id.y * 17.0);
	vec3 tint = seed < 0.6 ? green : amber;
	float t = TIME * scroll_speed * (0.6 + seed);
	vec2 uv = UV;
	vec2 cell = uv * grid;
	vec2 ci = floor(cell);
	float row = ci.y + floor(t);
	// Each row has a random length of text; some rows blank.
	float len = floor(h(vec2(row, seed * 91.0)) * grid.x);
	float on = 0.0;
	if (ci.x < len && h(vec2(row * 3.1, seed)) > 0.15) {
		vec2 px = floor(fract(cell) * vec2(4.0, 6.0));
		if (px.x < 3.0 && px.y > 0.0) {
			on = step(0.5, h(vec2(ci.x * 7.0 + px.x + row * 13.0, px.y + seed * 31.0)));
		}
	}
	// Cursor on the last row.
	if (ci.y == grid.y - 1.0) {
		on = 0.0;
		if (ci.x == 2.0 && fract(TIME * 1.1 + seed) < 0.5) {
			on = 1.0;
		}
	}
	float scan = 0.75 + 0.25 * step(0.5, fract(uv.y * grid.y * 3.0));
	float flick = 0.9 + 0.1 * step(0.5, h(vec2(floor(TIME * 12.0), seed)));
	vec3 c = tint * (0.08 + on * 0.92) * scan * flick * brightness;
	ALBEDO = c;
}
