// The arrival shot's cloud banks (spec R6-2): the heaps of arrival_cloud.gdshader, translucent as
// one sheet. They write depth and drop their thin edge, and ArrivalClouds draws them nearest first,
// so where heaps overlap only the front one shows.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled, fog_disabled;

#define FRONT_ONLY
#include "res://shaders/cutscene/arrival_cloud.gdshaderinc"
