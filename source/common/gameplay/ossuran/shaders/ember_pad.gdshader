shader_type canvas_item;
// OSSURAN — EMBER PAD (pad 1). "Glowing red like ink mixed with water, with
// flames and kindled coal."
//
// Three layers stacked, all of them driven by ONE domain-warped noise field so
// they agree with each other instead of sliding past one another:
//   INK    a slow, curling body that bleeds outward from the centre as the pad
//          charges — the ink is being dropped into still water, so it blooms.
//   COAL   a sparse high-frequency speck layer that only lights where the ink is
//          already dense, flickering on its own clock. This is what reads as
//          "kindled" rather than "painted red".
//   RIM    a hard boundary ring, always crisp, so the pad's edge is a place you
//          can stand on or off. Fluid inside, hard edge — the same pairing the
//          HUD's ink_fill uses.
//
// PIXEL-ART DISCIPLINE (the part that makes this belong in the game rather than
// look like a modern gradient pasted on top):
//   1. Every sample is taken on a SNAPPED grid (`pad_pixels`), so the noise
//      moves in whole texels and never shimmers with sub-pixel crawl.
//   2. The final colour is an INDEXED PALETTE LOOKUP, not a lerp. Density is
//      quantised into PALETTE_STEPS bands and each band emits one authored
//      colour, so palette boundaries stay hard the way hand-drawn pixel art
//      does. A smooth mix() here would blur exactly the edges the art style is
//      made of.

// 0-1 charge, driven by ChargePad._apply_visual.
uniform float charge : hint_range(0.0, 1.0) = 0.0;
// 0 while the pad is closed — everything fades out and the pad reads as inert.
uniform float active : hint_range(0.0, 1.0) = 0.0;
// The pad's on-screen size in texels. Sampling is snapped to this grid.
uniform float pad_pixels = 96.0;
uniform float flow_speed = 0.22;
// How hard the coal specks flicker (0 = steady embers).
uniform float coal_flicker : hint_range(0.0, 1.0) = 0.65;

// Authored ramp, ash -> white-hot. Indexed, never interpolated.
const int PALETTE_STEPS = 6;
const vec3 PALETTE[6] = {
	vec3(0.08, 0.04, 0.05),  // cold ash — the unlit pad stone
	vec3(0.31, 0.05, 0.05),  // dried blood, the first hint of ink
	vec3(0.58, 0.10, 0.06),  // deep ember
	vec3(0.83, 0.25, 0.07),  // burning orange
	vec3(1.00, 0.51, 0.13),  // kindled coal
	vec3(1.00, 0.87, 0.56)   // white-hot core
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
	for (int i = 0; i < 4; i++) {
		total += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	// 1. SNAP. Everything downstream samples this, so the whole effect animates
	//    in whole texels — no sub-pixel crawl against the tileset.
	vec2 snapped = (floor(UV * pad_pixels) + 0.5) / pad_pixels;

	vec2 centred = snapped - vec2(0.5);
	float radius = length(centred) * 2.0;   // 0 at centre, 1 at the pad's edge

	float t = TIME * flow_speed;

	// 2. INK BODY. Warping the sample point (rather than scrolling it) is what
	//    makes the ink CURL into the water instead of sliding across it.
	vec2 q = centred * 5.5;
	vec2 warp = vec2(fbm(q + vec2(t, 0.0)), fbm(q + vec2(0.0, -t) + 4.7));
	float ink = fbm(q * 1.5 + warp * 1.7 + vec2(t * 0.4, 0.0));

	// The ink front advances from the centre outward with charge. The noise
	// perturbs the front so the boundary is a diffusing bleed, not a clean disc.
	float front = charge * 1.15 + (ink - 0.5) * 0.42;
	float body = clamp((front - radius) * 2.6, 0.0, 1.0);

	// 3. DENSITY. Hotter toward the centre and wherever the ink piled up.
	float density = body * (ink * 0.85 + 0.35) * mix(0.55, 1.25, 1.0 - radius);

	// 4. COAL. Sparse specks on their own fast clock, only inside dense ink.
	//    floor() on a coarse grid keeps them BLOCKY — a coal is a lit texel.
	vec2 coal_cell = floor(snapped * pad_pixels * 0.5);
	float speck = hash(coal_cell);
	float flicker = mix(1.0, 0.45 + 0.55 * vnoise(coal_cell + vec2(TIME * 3.1, 0.0)), coal_flicker);
	float coal = step(0.955, speck) * flicker * body;
	density += coal * 0.9;

	// 5. QUANTISE TO THE PALETTE. This is the pixel-art step: bucket the density
	//    into discrete bands and emit one authored colour per band, so the result
	//    has hard palette edges instead of a continuous ramp.
	float level = clamp(density, 0.0, 1.0) * float(PALETTE_STEPS - 1);
	int index = int(floor(level + 0.5));
	index = clamp(index, 0, PALETTE_STEPS - 1);
	vec3 col = PALETTE[index];

	// 6. RIM. A hard two-texel ring at the pad's edge, brightening as it charges,
	//    so the standable area is unambiguous even when the ink is still thin.
	float texel = 2.0 / pad_pixels;
	float rim = step(1.0 - texel * 2.0, radius) * step(radius, 1.0);
	col = mix(col, PALETTE[4], rim * (0.45 + 0.55 * charge));

	// Alpha: the ink body, the rim, and nothing outside the disc.
	float alpha = clamp(max(body, rim * 0.85), 0.0, 1.0) * step(radius, 1.0);
	// A closed pad shows only the faintest cold stone ring.
	alpha *= mix(0.18, 1.0, active);

	COLOR = vec4(col, alpha);
}
