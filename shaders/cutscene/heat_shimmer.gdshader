// Engine heat shimmer behind a nozzle (docs/specs/cutscene-flyover.md, "Speed lines + engine
// heat"): an open cone that redraws the screen behind it nudged by a drifting ripple. No colour of
// its own, no blur. The screen texture holds only the opaque pass (ground, building, sky, ship),
// so this draws BEFORE the storm fog (render_priority below -100): fog, snow and trails then go
// on over it undistorted, instead of the shimmer punching an unfogged hole through them.
//
// Mesh contract (built by scripts/cutscene/flyover.gd): the cone runs from the nozzle (local
// z = 0) back along -Z; UV.y = 0 at the nozzle, 1 at the far end.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// Peak nudge, as a fraction of the screen.
uniform float strength = 0.005;
// Shot time (set by the shot each frame), so a seek shows the same ripple.
uniform float shot_time = 0.0;
// Ripple size (m) and how fast it travels back out of the nozzle (m/s).
uniform float ripple_size = 0.7;
uniform float ripple_speed = 9.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float along = UV.y;
	// Eases in off the nozzle (no hard ring at its lip) and dies out by the far end. Held strong
	// through the middle: seen from behind, the far half is what spans the background.
	float fade = smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.5, 1.0, along));
	// Soft only right at the silhouette. The chase camera looks almost straight down the cone,
	// so its whole surface is near edge-on: a wider ramp fades nearly all of it out.
	float soft = smoothstep(0.0, 0.2, abs(dot(normalize(NORMAL), VIEW)));
	vec3 q = v_local / ripple_size + vec3(0.0, 0.0, shot_time * ripple_speed / ripple_size);
	vec2 n = vec2(noise3(q), noise3(q + vec3(17.3, 5.1, 9.7))) * 2.0 - 1.0;
	vec2 off = n * strength * fade * soft;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	// Where the nudge is zero the copy is the screen itself, so it can cover fully.
	ALPHA = 1.0;
}
