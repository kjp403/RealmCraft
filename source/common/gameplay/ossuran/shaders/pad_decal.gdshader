shader_type canvas_item;
// OSSURAN — PAD GROUND DECAL. Drawn UNDER a charge pad and wider than it, this
// is what stops the pads reading as stickers laid on the tiles.
//
// A pad looked pasted on for a specific reason: it was a perfect circle with a
// hard edge and nothing between it and the floor. Real ground-effects do not end
// — they FADE INTO the surface through damage the surface has taken. So this
// decal does the three things the pad itself cannot:
//
//   BURN     an irregular, noisy stain that eats into the floor and dies out
//            gradually, so there is no boundary anywhere for the eye to catch.
//   CRACKS   fissures radiating from the pad, splitting the tile grid. They are
//            what physically ties the effect to the ground: the pad is not ON
//            the floor, it has BROKEN the floor.
//   HEAT     as charge rises the cracks light from within, so the ground itself
//            joins in instead of the pad glowing alone on a dead surface.
//
// Deliberately blend_mix rather than an additive or multiply pass, because it
// has to do both jobs at once: a dark low-alpha wash DARKENS the floor for the
// burn, and a bright high-alpha line BRIGHTENS it for a lit crack. Splitting
// that into two nodes per pad would double the overdraw for no visual gain.
//
// The pad's own rim stays crisp and is drawn on top of this — that ring is the
// ward boundary players stand relative to, and softening it to help the blend
// would trade a gameplay read for a cosmetic one.

// 0-1 charge, mirrored from the pad by ChargePad._apply_visual.
uniform float charge : hint_range(0.0, 1.0) = 0.0;
// 0 while the pad is closed: the scar stays, the light in it does not.
uniform float active : hint_range(0.0, 1.0) = 0.0;
// 0 = EMBER (scorched stone, molten fissures).
// 1 = STORM (frost-shattered stone, lit blue-white).
uniform float variant : hint_range(0.0, 1.0) = 0.0;
// The decal's size in texels, for grid snapping.
uniform float decal_pixels = 176.0;
// Where the pad's own art ends, as a fraction of this decal's radius. The burn
// is strongest just outside it and fades to nothing by the rim.
uniform float pad_fraction : hint_range(0.1, 1.0) = 0.55;
// How many fissures radiate out.
uniform float crack_count = 11.0;

// Scorch: near-black, slightly warm. Frost-shatter: near-black, cold.
uniform vec3 burn_warm : source_color = vec3(0.08, 0.04, 0.03);
uniform vec3 burn_cold : source_color = vec3(0.05, 0.07, 0.11);
// Lit-crack colours per variant.
uniform vec3 lit_warm : source_color = vec3(1.0, 0.52, 0.16);
uniform vec3 lit_cold : source_color = vec3(0.62, 0.84, 1.0);

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
	vec2 snapped = (floor(UV * decal_pixels) + 0.5) / decal_pixels;
	vec2 centred = snapped - vec2(0.5);
	float radius = length(centred) * 2.0;
	float angle = (atan(centred.y, centred.x) + 3.14159265) / 6.28318530;

	vec3 burn = mix(burn_warm, burn_cold, variant);
	vec3 lit = mix(lit_warm, lit_cold, variant);

	// --- BURN. An irregular stain, densest at the pad's edge and feathering out.
	// The noise is added to the RADIUS rather than to the alpha, so the boundary
	// itself is ragged instead of a soft circle — a blurred circle still reads as
	// a circle, which is half of why the pads looked applied rather than burned.
	float ragged = radius + (fbm(centred * 7.0 + 3.3) - 0.5) * 0.30;
	float stain = (1.0 - smoothstep(pad_fraction * 0.7, 1.0, ragged));
	// Hollow out the middle: the pad's own art covers it, and stacking a stain
	// under it just muddies the shader that is supposed to be the focus.
	stain *= smoothstep(pad_fraction * 0.35, pad_fraction * 0.85, ragged);
	stain *= 0.75;

	// --- CRACKS. Fissures from under the pad, wandering as they travel out and
	// tapering to nothing — a crack of even width reads as a drawn spoke.
	float fissure = 0.0;  // the wide dark split
	float core = 0.0;     // the hairline at the bottom of it
	for (int i = 0; i < 12; i++) {
		if (float(i) >= crack_count) {
			break;
		}
		float fi = float(i);
		float seed = hash(vec2(fi, 4.0));
		float centre_angle = (fi + 0.5) / crack_count + seed * 0.05;
		// High-frequency wander so the fissure genuinely jinks as it travels.
		// A gentle curve reads as a drawn ray; stone splits in short straights.
		float wander = (vnoise(vec2(radius * 15.0, seed * 40.0)) - 0.5) * 0.085;
		float d = abs(fract(angle - centre_angle - wander + 0.5) - 0.5);
		// Each crack runs its own distance and thins as it goes.
		float reach = 0.58 + seed * 0.40;
		float run = smoothstep(pad_fraction * 0.28, pad_fraction * 0.55, radius)
			* (1.0 - smoothstep(reach - 0.22, reach, radius));
		// TWO widths, and this pairing is the whole fix. A single bright wedge
		// reads as a light ray fired out of the pad. A crack is a DARK SPLIT in
		// the stone that happens to have heat at the bottom of it, so the wide
		// band is the fissure itself and the hairline inside it is the glow.
		float wide = (3.4 / decal_pixels) / max(0.10, radius);
		float thin = (1.1 / decal_pixels) / max(0.10, radius);
		fissure = max(fissure, (1.0 - smoothstep(0.0, max(wide, 0.0005), d)) * run);
		core = max(core, (1.0 - smoothstep(0.0, max(thin, 0.0004), d)) * run);
	}

	// --- HEAT IN THE CRACKS. Cold, dark splits while the pad is closed; lit from
	// the bottom as it charges. This is what makes the ground feel involved in
	// the channel rather than merely stained by it.
	float glow = core * active * (0.15 + 0.85 * charge);

	// Compose: stain, then the fissure darkens the stone it splits, then the
	// heat sits in the bottom of the fissure.
	vec3 col = mix(burn, burn * 0.35, fissure);
	col = mix(col, lit, glow);
	float alpha = clamp(
		stain * 0.85 + fissure * 0.72 + glow * 0.55, 0.0, 1.0
	);

	// Nothing outside the disc, and the very edge is already at zero from the
	// smoothstep above, so there is no rim to see.
	alpha *= step(radius, 1.0);
	COLOR = vec4(col, alpha);
}
