shader_type canvas_item;
// OSSURAN — STORM PAD (pad 2). "Lightning sparks and jolts around the padded
// area in a crisp and smooth motion... something being conjured by the darkness
// of evil as it charges."
//
// The brief asks for two things that pull in opposite directions — CRISP jolts
// and SMOOTH conjuring — so they are given separate layers rather than averaged
// into one mushy effect:
//   DARK    a slow, smooth violet-black swirl that thickens with charge. This is
//           the "conjuring": continuous, patient, and it OWNS the motion budget.
//   BOLTS   arcs that do not move continuously at all. Their shape is reseeded on
//           a QUANTISED clock (floor(TIME * jolt_rate)), so each arc holds a
//           still pose and then snaps to a new one. That discontinuity is what
//           reads as electricity; a smoothly animated bolt reads as a ribbon.
//   RING    the ward boundary — the line that tells a player whether they are
//           inside the 75% protection. It is the one element that must never be
//           ambiguous, so it is drawn hard and last.
//
// Same pixel-art rules as ember_pad: snapped sampling and an indexed palette, so
// the bolts land on texel boundaries and the palette never blurs.

uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float active : hint_range(0.0, 1.0) = 0.0;
uniform float pad_pixels = 96.0;
// Jolts per second. The bolts hold still between these.
uniform float jolt_rate = 11.0;
// How far the arcs deviate from their ring, in UV.
uniform float jag : hint_range(0.0, 0.5) = 0.16;

const int PALETTE_STEPS = 6;
const vec3 PALETTE[6] = {
	vec3(0.03, 0.02, 0.07),  // the dark itself
	vec3(0.09, 0.06, 0.20),  // deep violet
	vec3(0.16, 0.16, 0.44),  // indigo
	vec3(0.22, 0.42, 0.86),  // conjured blue
	vec3(0.48, 0.78, 1.00),  // arc blue
	vec3(0.93, 0.98, 1.00)   // strike white
};

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		total += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 snapped = (floor(UV * pad_pixels) + 0.5) / pad_pixels;
	vec2 centred = snapped - vec2(0.5);
	float radius = length(centred) * 2.0;
	// atan gives -PI..PI; normalise to 0..1 so the noise wraps cleanly.
	float angle = (atan(centred.y, centred.x) + 3.14159265) / 6.28318530;

	// --- DARK: the smooth half. A slow swirl that fills in as it charges.
	// Deliberately kept mid-value, not near-black: the first pass pooled it so
	// deep that the pad read as a HOLE in the floor and swallowed its own
	// lightning. The dark is a medium the conjuring happens inside, so it has to
	// stay lit enough for the bolts to sit on top of it.
	float t = TIME * 0.16;
	vec2 q = centred * 4.0;
	vec2 warp = vec2(fbm(q + vec2(t, 0.0)), fbm(q - vec2(0.0, t) + 2.3));
	float dark = fbm(q * 1.3 + warp * 1.5);
	float body = clamp((0.92 - radius) * 2.2, 0.0, 1.0);
	float density = body * (0.34 + dark * 0.46) * mix(0.45, 1.0, charge);

	// --- BOLTS: the crisp half, and the half that has to READ. Two families:
	//
	//   SPOKES  jagged lines running from the centre out to the rim. This is the
	//           load-bearing one. Lightning drawn only as concentric rings (the
	//           first attempt) is indistinguishable from a decorative outline —
	//           radial spokes are what say "something is being conjured HERE and
	//           throwing power outward".
	//   ARCS    a partial ring that jumps between radii, layered under the
	//           spokes so the boundary crackles too.
	//
	// Both are reseeded on a QUANTISED clock (floor(TIME * jolt_rate)), so each
	// pose is held still and then snaps. That discontinuity is the electricity;
	// anything smoothly animated reads as a ribbon.
	float bolts = 0.0;

	const float SPOKES = 9.0;
	float tick = floor(TIME * jolt_rate);
	float sector = floor(angle * SPOKES);
	for (int s = -1; s <= 1; s++) {
		// Test the neighbouring sectors too, or a bolt that wobbles across a
		// sector boundary is clipped in half.
		float sec = sector + float(s);
		float seed = hash(vec2(sec, tick));
		// Only some spokes fire on any given tick — a full fan every frame is a
		// solid star, not lightning.
		if (seed < 0.42) {
			continue;
		}
		float centre_angle = (sec + 0.5) / SPOKES;
		// The bolt's angle deviates as it travels outward: that is the fork.
		float wob = (vnoise(vec2(radius * 11.0, seed * 60.0 + tick)) - 0.5) * jag * 0.9;
		float target = centre_angle + wob;
		// Wrapped angular distance, so a spoke crossing 0/1 is not cut.
		float d = abs(fract(angle - target + 0.5) - 0.5);
		// Angular width shrinks with radius so the bolt tapers instead of
		// fanning into a wedge.
		float width = (2.2 / pad_pixels) / max(0.12, radius);
		float line = 1.0 - smoothstep(0.0, width, d);
		// Fade out of the very centre and stop at the rim.
		line *= smoothstep(0.04, 0.30, radius) * (1.0 - smoothstep(0.88, 1.0, radius));
		bolts = max(bolts, line);
	}

	// Ring arcs, under the spokes.
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float rtick = floor(TIME * jolt_rate + fi * 3.77);
		float seed = hash(vec2(rtick, fi * 17.0));
		float ring = 0.46 + 0.34 * fract(seed * 7.31);
		float wobble = (vnoise(vec2(angle * 22.0 + seed * 40.0, rtick)) - 0.5) * jag;
		float hit = 1.0 - smoothstep(0.0, 2.4 / pad_pixels, abs(radius - ring - wobble));
		float arc_mask = step(0.40, vnoise(vec2(angle * 5.0 + seed * 20.0, rtick)));
		bolts = max(bolts, hit * arc_mask * 0.85);
	}

	// Bolts strengthen as the conjuring completes.
	bolts *= mix(0.45, 1.0, charge);
	// 1.5, not 1.9: at the higher weight every bolt pixel saturated into the
	// top (near-white) palette stop and the lightning came out monochrome. This
	// leaves the body of each bolt in the blue stops and lets only the hottest
	// core reach white, which is what makes it read as electricity rather than
	// as a white scribble.
	density += bolts * 1.5;

	// --- QUANTISE to the indexed palette (see ember_pad for the reasoning).
	float level = clamp(density, 0.0, 1.0) * float(PALETTE_STEPS - 1);
	int index = clamp(int(floor(level + 0.5)), 0, PALETTE_STEPS - 1);
	vec3 col = PALETTE[index];

	// --- RING: the ward boundary. Drawn last and hard, because this line is the
	// difference between taking 25% of a slam and taking all of it.
	float texel = 2.0 / pad_pixels;
	float rim = step(1.0 - texel * 2.0, radius) * step(radius, 1.0);
	col = mix(col, PALETTE[5], rim * (0.35 + 0.65 * charge));

	float alpha = clamp(max(max(density, bolts), rim * 0.9), 0.0, 1.0) * step(radius, 1.0);
	alpha *= mix(0.14, 1.0, active);

	COLOR = vec4(col, alpha);
}
