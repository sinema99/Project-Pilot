// The tredge's staff light as the storm sees it: the flakes near it take its colour, and the fog
// glows warm round it. Driven by globals that scripts/staff_light.gd sets (project.godot
// [shader_globals]); storm_torch.x is 0 whenever there is no light, so nothing changes then.
// See docs/specs/pilot9-tredge.md, "Staff light".

global uniform vec3 storm_torch_pos;
global uniform vec4 storm_torch_color;
// x = strength (the fade times the flicker), y = how far the flakes take its colour (m),
// z = the fog glow's radius (m).
global uniform vec3 storm_torch;
global uniform float storm_torch_fog;

// 0..1: how much of the light's colour a flake at `world` takes.
float storm_torch_flake(vec3 world) {
	if (storm_torch.x <= 0.0) {
		return 0.0;
	}
	float d = length(world - storm_torch_pos);
	float k = 1.0 - smoothstep(0.0, max(storm_torch.y, 0.001), d);
	return clamp(storm_torch.x * k * k, 0.0, 1.0);
}

// 0..1: the warm haze along a view ray from the camera (view space, at the origin) in direction
// `dir`, stopping at `surface` metres, from a light at view-space `light`. The haze is brightest
// where the ray passes closest to the light, and a surface in front of the light cuts it off.
float storm_torch_haze(vec3 dir, float surface, vec3 light) {
	if (storm_torch.x <= 0.0) {
		return 0.0;
	}
	float t = clamp(dot(light, dir), 0.0, surface);
	float d = length(light - dir * t);
	float r = max(storm_torch.z, 0.001);
	return clamp(storm_torch.x * storm_torch_fog * exp(-(d * d) / (r * r)), 0.0, 0.85);
}
