// The arrival shot's clouds (scripts/cutscene/arrival_clouds.gd), spec R2-6. Three ways to make the
// shape, one look: a few big, smooth cel tones, lit from the sun's side (up and to the left, behind),
// the belly in shade, no speckle inside. Faded softly where a card meets anything behind it, so towers
// and peaks stand *in* the cloud instead of being cut by a line.
//   mode 0, heap: a cumulus of round lobes melted together (metaballs) along a flat base.
//   mode 1, plume: lobes rising up a leaning column, growing and thinning as they climb (steam).
//   mode 2, streak: wind-stretched noise (spindrift), soft and thin.
//   mode 3, sea: a level layer seen from above, a broad noise field with a billowed edge, lit by
//      its thickness; peaks rise out of it through the soft fade.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/cutscene/arrival_cloud.gdshaderinc"
