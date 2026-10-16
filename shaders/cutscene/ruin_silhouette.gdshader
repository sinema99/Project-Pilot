shader_type spatial;
// The ruined room around the descent shot's camera (docs/specs/cutscene-descent.md rows 39-45):
// flat near-black, unlit and unfogged. During lightning a cool rim lights the faces seen edge-on,
// stronger on the ones turned toward the storm (up-left on screen).
render_mode unshaded, fog_disabled, cull_back, shadows_disabled;

uniform vec3 ink : source_color = vec3(0.039, 0.051, 0.071);
uniform vec3 rim_color : source_color = vec3(0.55, 0.88, 0.95);
// 0..~1.5: how lit the storm is right now (set every frame from the shot's flashes and bolts).
uniform float flash = 0.0;
uniform float rim_energy = 1.0;
// The rim starts on faces turned this far from the lens (0 = facing it, 1 = edge-on): the flat
// fronts never light, the sides and the round edges of pipe and wires do.
uniform float rim_start = 0.35;
// View-space direction (xy) toward the storm.
uniform vec2 storm_dir = vec2(-0.6, 0.8);

void fragment() {
	float edge = smoothstep(rim_start, 0.9, 1.0 - abs(dot(NORMAL, VIEW)));
	float side = 0.0;
	if (length(NORMAL.xy) > 1e-4) {
		side = dot(normalize(NORMAL.xy), normalize(storm_dir));
	}
	float facing = mix(0.4, 1.0, smoothstep(-0.3, 0.8, side));
	ALBEDO = ink + rim_color * flash * rim_energy * edge * facing;
}
