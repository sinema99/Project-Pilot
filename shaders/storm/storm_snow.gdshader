shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Wind-blown snow, entirely in the vertex shader: every flake is a quad whose position is a
// function of TIME, wrapped into a box centred on the camera, stretched along its velocity.
// No particle simulation. Gusts are in the displacement (its derivative is the gust speed), so
// the streak length follows the wind. See docs/specs/ichi-snowstorm.md.
//
// drift = true is the ground drift layer: the same flakes wrapped in XZ only, sat on the highest
// static surface under them (the roof map), blowing flat along the wind in snaking ribbons.
//
// Mesh contract (built by scripts/rendering/storm.gd): quad corners at (+-0.5, +-0.5, 0), UV.y runs
// along the quad (1 = head), COLOR.rgb = the flake's start position in the box (0..1),
// COLOR.a = a per-flake random.

#include "res://shaders/storm/storm_gust.gdshaderinc"
#include "res://shaders/storm/storm_torch.gdshaderinc"

uniform vec3 wind_dir = vec3(0.94, 0.0, 0.33);
uniform float wind_speed = 28.0;
uniform float gust_amount = 0.6;
uniform float gust_period = 8.0;
uniform float fall_ratio = 0.18;
uniform float box_size = 50.0;
uniform float flake_width = 0.05;
uniform float streak_time = 0.04;
uniform float opacity = 0.8;
uniform float visibility = 40.0;
uniform float gust_visibility = 25.0;
uniform vec3 near_tint : source_color = vec3(0.92, 0.95, 1.0);
uniform vec3 far_tint : source_color = vec3(0.80, 0.77, 0.86);

// Storm character (off by default; the flyover turns it on, docs/specs/cutscene-flyover.md "Dead
// city + storm"): flakes swing sideways in coherent S-lanes `lane_amount` metres either way over a
// `lane_size` wavelength along the wind, and their streaks follow the bend; `clump_chance` of them
// are clumps `clump_scale` wider with short streaks; `shade_chance` of them take `shade_color`.
uniform float lane_amount = 0.0;
uniform float lane_size = 30.0;
uniform float clump_chance = 0.0;
uniform float clump_scale = 3.0;
uniform float shade_chance = 0.0;
uniform vec3 shade_color : source_color = vec3(0.58, 0.6, 0.74);

// Drift layer: flakes hug the surface under them, up to drift_height above it.
uniform bool drift = false;
uniform float drift_height = 0.5;
// Drift opacity between gusts as a fraction of opacity; it surges to full at a gust's peak.
uniform float drift_calm = 0.4;

// Shelter: a top-down height map of the static level (storm_roof_bake.gdshader). A flake more than
// shelter_margin below the highest surface over it is under a roof and is not drawn.
uniform bool shelter_on = false;
uniform sampler2D roof_map : filter_nearest, repeat_disable;
// World XZ of the map's top-left corner (x min, z min) and its side length, in metres.
uniform vec3 roof_rect = vec3(0.0, 0.0, 1.0);
uniform float roof_y_min = 0.0;
uniform float roof_y_span = 1.0;
uniform float shelter_margin = 0.3;

varying float v_alpha;
varying vec3 v_tint;

// Height of the highest static surface over `xz`; `found` is false off the map or over nothing.
float roof_at(vec2 xz, out bool found) {
	found = false;
	if (!shelter_on) {
		return 0.0;
	}
	vec2 uv = (xz - roof_rect.xy) / roof_rect.z;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) {
		return 0.0;
	}
	vec4 roof = textureLod(roof_map, uv, 0.0);
	found = roof.a > 0.5;
	return roof_y_min + (round(roof.r * 255.0) + roof.g) / 255.0 * roof_y_span;
}

void vertex() {
	float r = COLOR.a;
	float t = TIME;
	float speed = wind_speed * (1.0 + gust_amount * storm_gust(t, gust_period));
	float travelled = wind_speed * storm_gust_travel(t, gust_period, gust_amount);
	float peak = storm_gust_peak(t, gust_period);

	vec3 wind = normalize(vec3(wind_dir.x, 0.0, wind_dir.z));
	vec3 flow = wind + vec3(0.0, drift ? 0.0 : -fall_ratio, 0.0);
	float per_flake = 0.85 + 0.3 * r;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 p = COLOR.rgb * box_size + flow * travelled * per_flake;
	vec3 rel = mod(p - cam + vec3(box_size * 0.5), vec3(box_size)) - vec3(box_size * 0.5);
	// A little eddy so the field is not one rigid sheet.
	rel += 0.3 * vec3(sin(t * 2.1 + r * 40.0), 0.5 * sin(t * 1.7 + r * 70.0), cos(t * 1.9 + r * 55.0));
	vec3 center = cam + rel;

	float size = 1.0;
	float ribbon = 1.0;
	float lane_slope = 0.0;
	vec3 lane_across = vec3(0.0);
	if (drift) {
		// Snake sideways as the flake travels, coherently, so neighbours form a stream.
		vec3 across_wind = vec3(-wind.z, 0.0, wind.x);
		float s = dot(center.xz, wind.xz);
		float q = dot(center.xz, across_wind.xz);
		center += across_wind * 0.6 * sin(s * 0.3 - t * 1.5 + q * 0.4);
		bool found;
		float ground = roof_at(center.xz, found);
		// Low and dense near the surface, thinning upward.
		float h = fract(r * 31.0);
		center.y = ground + 0.04 + h * h * drift_height;
		// No surface under it (or no map yet, as headless): no drift.
		size = found ? 1.0 : 0.0;
		// Ribbons: bands across the wind that wander slowly, so the drift streams, not sheets.
		ribbon = smoothstep(0.25, 0.85, 0.5 + 0.5 * sin(q * 0.9 + 0.8 * sin(s * 0.15 - t * 0.7)));
		rel = center - cam;
	} else {
		if (lane_amount > 0.0) {
			vec3 across_wind = vec3(-wind.z, 0.0, wind.x);
			float k = TAU / lane_size;
			float phase = dot(center.xz, wind.xz) * k + dot(center.xz, across_wind.xz) * k * 0.45;
			center += across_wind * lane_amount * sin(phase);
			// Moving along the wind at `speed` through the lane: the sideways speed is the slope.
			lane_slope = lane_amount * k * cos(phase);
			lane_across = across_wind;
			rel = center - cam;
		}
		bool found;
		float roof_y = roof_at(center.xz, found);
		// A sheltered flake collapses to a point: no area, nothing drawn.
		size = found && center.y < roof_y - shelter_margin ? 0.0 : 1.0;
	}

	vec3 vel = (flow + lane_across * lane_slope) * speed * per_flake;
	vec3 along = normalize(vel);
	vec3 to_cam = normalize(cam - center);
	vec3 side = cross(along, to_cam);
	side = length(side) < 0.001 ? cross(along, vec3(0.0, 0.0, 1.0)) : side;
	side = normalize(side);
	float len = length(vel) * streak_time * (0.7 + 0.6 * r);
	float width = flake_width * (0.6 + 0.8 * fract(r * 17.0));
	if (fract(r * 53.0) < clump_chance) {
		width *= clump_scale;
		len *= 0.35;
	}
	vec3 world = center + (along * (UV.y - 0.5) * len + side * VERTEX.x * width) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);

	float vis = storm_gust_wall(t, gust_period, visibility, gust_visibility);
	float dist = length(rel);
	float t_dist = clamp(dist / vis, 0.0, 1.0);
	// Drift wraps in XZ only; its height follows the ground, not the box.
	float edge = (drift ? max(abs(rel.x), abs(rel.z))
		: max(max(abs(rel.x), abs(rel.y)), abs(rel.z))) / (box_size * 0.5);
	float wrap_fade = 1.0 - smoothstep(0.75, 1.0, edge);
	float near_fade = smoothstep(0.6, 2.5, dist);
	float fog = 1.0 - exp(-3.9 * t_dist * t_dist);
	float surge = drift ? mix(drift_calm, 1.0, peak) : 1.0;
	v_alpha = opacity * wrap_fade * near_fade * (1.0 - fog) * ribbon * surge;
	v_tint = mix(near_tint, far_tint, smoothstep(0.05, 1.0, t_dist));
	if (fract(r * 91.0) < shade_chance) {
		v_tint = mix(v_tint, shade_color, 0.7);
	}
	// The staff light: flakes near it take its colour and brighten (storm_torch.gdshaderinc).
	float torch = storm_torch_flake(center);
	v_tint = mix(v_tint, storm_torch_color.rgb, torch);
	v_alpha = min(v_alpha * (1.0 + 0.5 * torch), 1.0);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float shape = pow(1.0 - across, 1.6) * (0.1 + 0.9 * UV.y) * (1.0 - smoothstep(0.8, 1.0, UV.y));
	ALBEDO = v_tint;
	ALPHA = clamp(v_alpha * shape, 0.0, 1.0);
}
