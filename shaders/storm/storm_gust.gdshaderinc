// The Ichi storm's gust curve, shared by the snow and the fog so a gust that speeds the flakes
// up is the same gust that closes the fog in. See docs/specs/ichi-snowstorm.md.
//
// Two incommensurate sines, so the gusts never repeat exactly. -1..1.

float storm_gust(float t, float period) {
	float w1 = TAU / period;
	float w2 = w1 * 0.61;
	return 0.6 * sin(w1 * t) + 0.4 * sin(w2 * t + 1.3);
}

// The integral of 1 + amount * storm_gust: distance travelled at unit mean speed. Keeping gusts
// in the displacement makes their derivative the gust speed, so streaks stretch with the wind.
float storm_gust_travel(float t, float period, float amount) {
	float w1 = TAU / period;
	float w2 = w1 * 0.61;
	return t + amount * (
		0.6 * (1.0 - cos(w1 * t)) / w1 + 0.4 * (cos(1.3) - cos(w2 * t + 1.3)) / w2);
}

// 0 between gusts, 1 at a gust's peak: drives the whiteout and the drift surge.
float storm_gust_peak(float t, float period) {
	return smoothstep(0.15, 0.75, storm_gust(t, period));
}

// The visibility right now: `clear` between gusts, `whiteout` at a gust's peak.
float storm_gust_wall(float t, float period, float clear, float whiteout) {
	return mix(clear, whiteout, storm_gust_peak(t, period));
}
