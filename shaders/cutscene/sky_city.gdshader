// The descent shot's far mega sky city (docs/specs/mega-sky-city.md): flat silhouettes in the
// vertex colours DescentSkyCity bakes. Unshaded and fog-free, so lightning never touches it.
shader_type spatial;
// No depth write: the Storm's depth fog would turn it fog-white at 20 km; it reads as sky
// instead, and the ridges (drawn in the depth prepass) still hide what is behind them.
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, depth_draw_never;

void fragment() {
	ALBEDO = COLOR.rgb;
}
