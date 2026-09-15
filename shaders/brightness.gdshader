shader_type canvas_item;

// Full-screen gamma lift. Lives on a ColorRect inside a CanvasLayer, same trick
// as shaders/pixelate.gdshader - it reads the finished frame and rewrites it.
//
// True gamma rather than an alpha wash: it lifts shadows instead of fogging the
// image toward grey, which matters because the cel pipeline puts a lot of
// information in near-black and the outline pass is pure black by definition.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float gamma = 1.0;

void fragment() {
	COLOR = vec4(pow(texture(screen_tex, SCREEN_UV).rgb, vec3(1.0 / gamma)), 1.0);
}
