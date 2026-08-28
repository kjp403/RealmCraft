shader_type canvas_item;
// OSSURAN — ENVIRONMENT SHIFT. The phase-3 turn from Kindled Forge to Thick Ice,
// driven by a single `freeze` uniform that OssuranArena tweens 0 -> 1.
//
// This is deliberately NOT a crossfade between two tints. A dissolve reads as a
// filter being applied to the room; what the moment wants is the room BEING
// TAKEN, so the frost CREEPS: it seeds at the edges of the arena and eats inward,
// because Ossuran smashes the floor and the cold spreads from the walls to where
// the players are standing. The mechanism is a noise field compared against a
// rising threshold that is biased by distance from the centre — so the same
// `freeze` value covers the rim long before it reaches the middle, and the last
// warm ground in the room is the ground around the boss.
//
// The layer this runs on carries NO collision and NO navigation (see
// OssuranArena._freeze_environment): it is pure overlay, so the walkable world
// and every live path are untouched by the transition.
//
// Pixel-art rules as in the pad shaders: snapped sampling, indexed palette. The
// frost edge in particular is quantised hard — creeping ice in pixel art has a
// stepped, crystalline boundary, not an airbrushed one.

// 0 = full forge, 1 = full ice. Tweened by the arena over FREEZE_LERP_S.
uniform float freeze : hint_range(0.0, 1.0) = 0.0;
// Overlay size in texels, for grid snapping.
uniform float world_pixels = 480.0;
// Peak opacity of the overlay at full freeze. Deliberately low: this wash sits
// ON TOP of an ice TILE layer that is already doing most of the work, and at
// 0.72 the two together painted the forge out completely and turned the room
// into a flat white snowfield. Ossuran freezes the foundry — you should still
// see the foundry under the ice.
uniform float max_opacity : hint_range(0.0, 1.0) = 0.42;
// Warm tint strength before the freeze begins.
uniform float ember_warmth : hint_range(0.0, 1.0) = 0.28;

const int PALETTE_STEPS = 5;
// Cold ramp: shadowed ice -> lit rime. Warm ramp is a single ember wash, since
// the forge floor art already carries its own colour.
const vec3 ICE_PALETTE[5] = {
	vec3(0.16, 0.26, 0.40),  // ice in shadow
	vec3(0.29, 0.46, 0.63),  // wet ice
	vec3(0.48, 0.68, 0.84),  // lit ice
	vec3(0.72, 0.88, 0.97),  // rime
	vec3(0.95, 0.99, 1.00)   // frost highlight
};
const vec3 EMBER_WASH = vec3(0.92, 0.42, 0.14);

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
		p *= 2.11;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 snapped = (floor(UV * world_pixels) + 0.5) / world_pixels;
	vec2 centred = snapped - vec2(0.5);
	// 0 at the centre of the arena, ~1 at the corners.
	float from_centre = clamp(length(centred) * 1.9, 0.0, 1.0);

	// --- THE CREEP. A static crystal field, thresholded by a front that rises
	// with `freeze` and is biased outward, so the rim ices over first.
	float crystal = fbm(snapped * 7.0);
	// Bias: at a given freeze, the edge needs a much lower noise value to ice
	// over than the centre does.
	float front = freeze * 1.55 - (1.0 - from_centre) * 0.55;
	float covered = clamp((front - crystal) * 4.0, 0.0, 1.0);

	// --- ICE SHADING. Faceted rather than smooth: a second, sharper noise gives
	// the plates their internal structure.
	float facet = fbm(snapped * 15.0 + crystal * 2.0);
	float shade = covered * (0.35 + facet * 0.85);
	// A bright rime line exactly at the advancing boundary, so the spread is
	// visible as it happens instead of only in its result.
	float edge = (1.0 - smoothstep(0.0, 0.16, abs(front - crystal))) * step(0.02, freeze);
	shade += edge * 0.75;

	// --- QUANTISE. The stepped boundary is the point: pixel-art ice has plates.
	float level = clamp(shade, 0.0, 1.0) * float(PALETTE_STEPS - 1);
	int index = clamp(int(floor(level + 0.5)), 0, PALETTE_STEPS - 1);
	vec3 ice = ICE_PALETTE[index];

	// --- FORGE SIDE. A slow ember wash that breathes, retreating as ice takes
	// the room. Multiplied by (1 - covered) so warmth survives only on ground
	// the frost has not reached — which is what makes the braziers read as the
	// last warm places.
	float breathe = 0.75 + 0.25 * vnoise(snapped * 3.0 + vec2(TIME * 0.11, 0.0));
	float warm = ember_warmth * breathe * (1.0 - covered) * (1.0 - freeze * 0.55);

	vec3 col = ice;
	float alpha = covered * max_opacity;

	// Where the frost has not arrived, the overlay is the ember wash instead.
	col = mix(EMBER_WASH, col, covered);
	alpha = max(alpha, warm);

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
