shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The light shafts in the descent shot (docs/specs/descent-composite.md row 4): soft slanted cards
// falling from the cloud break. UV.x runs across a card, UV.y from its top (0) to its foot (1).
// COLOR.r is the card's strength, COLOR.g its phase. Soft on every side: thin edges, the top tucked
// into the deck, the foot fading out and again where it meets the ground or a building.

uniform vec3 shaft_color : source_color = vec3(1.0, 0.957, 0.902);
uniform float energy = 0.5;
// Shot time: drives the slow breathing.
uniform float time = 0.0;
// Seconds per breath, and how deep it goes (0..1).
uniform float breath_period = 9.0;
uniform float breath_depth = 0.35;
// 0..1 lightning, pushed by the shot.
uniform float flash = 0.0;
uniform float flash_boost = 0.6;
// Metres over which the card fades where it meets the scene behind it.
uniform float surface_fade = 250.0;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float across = UV.x;
	float along = UV.y;
	float edge = smoothstep(0.0, 0.4, across) * smoothstep(1.0, 0.6, across);
	// A few soft streaks along the length, so it is not one flat band.
	float phase = COLOR.g;
	float streaks = 0.7 + 0.3 * sin(across * 19.0 + phase * 6.0) * sin(across * 7.0 - phase * 3.0);
	float ends = smoothstep(0.0, 0.18, along) * (1.0 - smoothstep(0.45, 1.0, along));
	float breath = 1.0 - breath_depth * (0.5 + 0.5 * sin(TAU * time / breath_period + phase * 2.3));

	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -p.z / p.w;
	float gap = clamp((scene_z - (-VERTEX.z)) / surface_fade, 0.0, 1.0);

	ALBEDO = shaft_color * energy * (1.0 + flash * flash_boost);
	ALPHA = clamp(COLOR.r * edge * streaks * ends * breath * gap, 0.0, 1.0);
}
