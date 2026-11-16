// Daylight through hub2's roof door (docs/specs/hub2-roof-door.md, rev 1): soft faked light shafts.
// The cards Hub2RoofDoor builds are only slices; every pixel asks one light FIELD how bright the air is
// at its point, so the slices agree and no card edge ever shows:
//   - lit where following the sun back up reaches the roof inside the sky gap (soft edges, metres wide);
//   - fades in just under the roof, then eases out to nothing by `reach` metres down;
//   - static soft streaks along the sun's slant (a function of where the ray crossed the roof);
//   - fades where a card meets a wall or floor (depth) and when a card is seen edge-on.
// Positions are in the door node's space: origin = middle of the opening on the roof plane, +Z along
// the shaft, the sun comes from +X.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

uniform vec3 tint : source_color = vec3(0.74, 0.86, 1.0);
// Brightness one card adds where the field is full (cards stack along a view ray).
uniform float strength = 0.03;
// Sky gap half size (x, z) and how many metres its edges blur over (x, z).
uniform vec2 gap = vec2(12.0, 32.0);
uniform vec2 feather = vec2(3.5, 6.0);
// Sideways metres per metre of fall (1 / tan(sun elevation)).
uniform float beam_shift = 0.466;
// Metres below the roof where the light has faded out.
uniform float reach = 51.0;
// Metres below the roof over which it fades in.
uniform float fade_in = 5.0;
// Streaks: 0 = even glow; how big the soft streak cells are (metres, x then z at the roof).
uniform float streak_amount = 0.55;
uniform vec2 streak_size = vec2(2.2, 5.0);
// Soft fade where a card cuts into a surface, metres.
uniform float contact_fade = 2.5;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

float hash2(vec2 c) {
	uvec2 q = uvec2(ivec2(c) + ivec2(8192));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h) / 4294967295.0;
}

float vnoise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float depth_below = -v_local.y;
	// Where this point's ray from the sun crossed the roof plane.
	vec2 at_roof = vec2(v_local.x + beam_shift * depth_below, v_local.z);
	vec2 inside = gap - abs(at_roof);
	float field = smoothstep(-feather.x * 0.5, feather.x * 0.5, inside.x) * smoothstep(-feather.y * 0.5, feather.y * 0.5, inside.y);
	// The west wall (x = -gap.x) stops the light; the card slips behind it, the depth fade softens that.
	float down = clamp(depth_below / reach, 0.0, 1.0);
	field *= smoothstep(-1.0, fade_in, depth_below) * pow(1.0 - down, 1.6);
	// Static streaks: constant along each ray, so they read as rays.
	vec2 sq = at_roof / streak_size;
	float n = vnoise(sq) * 0.65 + vnoise(sq * 2.3 + 17.0) * 0.35;
	field *= mix(1.0, smoothstep(0.15, 0.85, n) * 1.6, streak_amount);

	// Edge-on cards would show as bright lines.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	field *= smoothstep(0.08, 0.45, facing);

	// Soft contact with walls and floors.
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = scene.z / scene.w;
	field *= clamp((VERTEX.z - scene_z) / contact_fade, 0.0, 1.0);

	ALBEDO = tint * strength * field;
}
