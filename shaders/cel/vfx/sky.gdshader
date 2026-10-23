shader_type sky;
render_mode use_half_res_pass;

// Sky Gradients
group_uniforms SkyGradients;
uniform vec3 day_bottom_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 day_top_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sunset_bottom_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 sunset_top_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 night_bottom_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 night_top_color : source_color = vec3(0.0, 0.0, 0.0);
group_uniforms;

// Horizon Stuff
group_uniforms Horizon;
uniform vec3 horizon_color_day : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 horizon_color_sunset : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 horizon_color_night : source_color = vec3(0.0, 0.8, 1.0);
uniform float horizon_falloff: hint_range(0.0, 1.0, 0.1);
group_uniforms;

// Sun Stuff
group_uniforms Sun;
uniform vec3 sun_col: source_color = vec3(1.0);
uniform float sun_size: hint_range(0.01, 1.0) = 1.0;
uniform float sun_blur: hint_range(0.01, 1.0) = 0.01;
group_uniforms;

// Moon Stuff
group_uniforms Moon;
uniform vec3 moon_col: source_color = vec3(1.0);
uniform float moon_size: hint_range(0.01, 1.0) = 1.0;
uniform float moon_crescent_offset: hint_range(-1.0, 1.0) = 0.5;
group_uniforms;

// Clouds Stuff
group_uniforms Clouds;
uniform sampler2D clouds_texture: filter_linear_mipmap;
uniform sampler2D clouds_distort_texture: filter_linear_mipmap;
uniform sampler2D clouds_noise_texture: filter_linear_mipmap;
uniform vec3 clouds_main_color: source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 clouds_edge_color: source_color = vec3(1.0, 1.0, 1.0);
uniform float clouds_speed: hint_range(0.0, 0.1, 0.01);
uniform float clouds_scale: hint_range(0.0, 1.0, 0.01);
uniform float clouds_cutoff: hint_range(0.0, 1.0, 0.01);
uniform float clouds_fuzziness: hint_range(0.0, 1.0, 0.01);
// RETRO's painted clouds (docs/specs/retro-look-pass-2.md). 0 = the clouds as they were. 1 = each
// cloud a flat soft-edged shape: clouds_main_color on top, clouds_shade_color below, where there
// is more cloud above the pixel.
uniform float clouds_paint: hint_range(0.0, 1.0) = 0.0;
uniform vec3 clouds_shade_color: source_color = vec3(0.6, 0.58, 0.72);
// Mip bias for the painted clouds' noise: blurs the wisps away so the shapes are broad.
uniform float clouds_paint_blur: hint_range(0.0, 6.0) = 3.0;
group_uniforms;

float cloud_density(vec2 sky_uv, float movement, float eye_y, float blur) {
	float base_noise = texture(clouds_texture, (sky_uv + movement) * clouds_scale, blur).r;
	float noise1 = texture(clouds_distort_texture, (sky_uv + base_noise + (movement * 0.75)) * clouds_scale, blur).r;
	float noise2 = texture(clouds_noise_texture, (sky_uv + noise1 + (movement * 0.25)) * clouds_scale, blur).r;
	return clamp(noise1 * noise2, 0.0, 1.0) * clamp(eye_y, 0.0, 1.0);
}

// Star Stuff
group_uniforms Stars;
uniform sampler2D stars_texture: filter_linear_mipmap;
uniform float stars_cutoff;
uniform float stars_speed: hint_range(0.0, 0.1);
group_uniforms;

void sky() {
	vec2 sky_uv = EYEDIR.xz / EYEDIR.y;
	
	float day_amount = clamp(LIGHT0_DIRECTION.y, 0.0, 1.0);
	vec3 gradient_day = mix(day_bottom_color, day_top_color, clamp(EYEDIR.y, 0.0, 1.0)) * day_amount;
	float sunset_amount = clamp(1.0 - abs(LIGHT0_DIRECTION.y), 0.0, 1.0);
	vec3 gradient_sunset = mix(sunset_bottom_color, sunset_top_color, clamp(EYEDIR.y, 0.0, 1.0)) * sunset_amount;
	float night_amount = clamp(-LIGHT0_DIRECTION.y, 0.0, 1.0);
	vec3 gradient_night = mix(night_bottom_color, night_top_color, clamp(EYEDIR.y, 0.0, 1.0)) * night_amount;
	vec3 sky_gradients = gradient_day + gradient_sunset + gradient_night;
	
	float horizon = 1.0 - abs(EYEDIR.y + horizon_falloff);
	vec3 horizon_glow_amount_day = clamp(horizon * clamp(LIGHT0_DIRECTION.y, 0.0, 1.0), 0.0, 1.0) * horizon_color_day;
	vec3 horizon_glow_amount_sunset = clamp(horizon * clamp(1.0 - abs(LIGHT0_DIRECTION.y), 0.0, 1.0), 0.0, 1.0) * horizon_color_sunset;
	vec3 horizon_glow_night = clamp(horizon * clamp(-LIGHT0_DIRECTION.y, 0.0, 1.0), 0.0, 1.0) * horizon_color_night;
	vec3 horizon_glow = horizon_glow_amount_day + horizon_glow_amount_sunset + horizon_glow_night;
	
	float sun_distance = distance(EYEDIR.xyz, LIGHT0_DIRECTION);
	float sun_power = 1.0 - clamp(sun_distance / sun_size, 0.0, 1.0);
	float sun_disc = clamp(sun_power / sun_blur, sun_power, 1.0);
	vec3 sun = sun_col * sun_disc;
	
	float moon_distance = distance(EYEDIR.xyz, -LIGHT0_DIRECTION);
	float moon_power = 1.0 - clamp(moon_distance / moon_size, 0.0, 1.0);
	float moon_disc = clamp(moon_power / 0.01, moon_power, 1.0);
	float moon_crescent_distance = distance(vec3(EYEDIR.x + moon_crescent_offset, EYEDIR.yz), -LIGHT0_DIRECTION);
	float moon_crescent_power = 1.0 - clamp(moon_crescent_distance / moon_size, 0.0, 1.0);
	float moon_crescent_disc = clamp(moon_crescent_power / 0.01, moon_crescent_power, 1.0);
	vec3 moon_crescent = moon_col * moon_crescent_disc;
	vec3 moon = clamp( (moon_col * moon_disc) - moon_crescent, 0.0 , 1.0);
	
	float clouds_movement = TIME * clouds_speed * 0.5;
	float clouds_noise_value = cloud_density(sky_uv, clouds_movement, EYEDIR.y, 0.0);
	float clouds_value = clamp(smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzziness, clouds_noise_value), 0.0, 1.0);
	vec3 clouds = mix(clouds_edge_color,  clouds_main_color , clouds_value) * clouds_value;
	if (clouds_paint > 0.0) {
		// One broad flat shape with a narrow soft edge, then the shade: sample the cloud a little
		// toward the horizon; where that is already clear sky, this pixel is the cloud's underside.
		float broad = cloud_density(sky_uv, clouds_movement, EYEDIR.y, clouds_paint_blur);
		float shape = smoothstep(clouds_cutoff, clouds_cutoff + 0.02, broad);
		vec3 down_dir = normalize(vec3(EYEDIR.x, max(EYEDIR.y - 0.03, 0.01), EYEDIR.z));
		float below = cloud_density(down_dir.xz / down_dir.y, clouds_movement, down_dir.y, clouds_paint_blur);
		float shade = 1.0 - smoothstep(clouds_cutoff - 0.01, clouds_cutoff + 0.02, below);
		vec3 painted = mix(clouds_main_color, clouds_shade_color, shade) * shape;
		clouds = mix(clouds, painted, clouds_paint);
		clouds_value = mix(clouds_value, shape, clouds_paint);
	}
	float clouds_negative = 1.0 - clouds_value;
	
	vec3 stars = texture(stars_texture, sky_uv + (stars_speed * TIME)).rgb;
	stars *= clamp(-LIGHT0_DIRECTION.y, 0.0, 1.0);
	stars = step(stars_cutoff, stars);

	vec3 sun_moon = sun + moon;
	sun_moon = clamp(sun_moon * clouds_negative, 0.0, 1.0);
	
	sky_gradients = clamp(sky_gradients * clouds_negative, 0.0, 1.0);
	
	vec3 sky = horizon_glow + sky_gradients + sun_moon + stars + clouds;

	COLOR = sky;
}
