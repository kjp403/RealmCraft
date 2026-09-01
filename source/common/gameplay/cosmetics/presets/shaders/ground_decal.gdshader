shader_type canvas_item;
render_mode blend_mix;
// COSMETIC TRAILS — FLOOR MARK. One shader, four variants, drawn on the tiles the
// wearer stepped on and dissolved away over its own short life.
//
// The marks DISSOLVE rather than fade. A fading decal keeps its silhouette all
// the way to zero, so a row of them reads as a row of ghost stamps of the same
// stencil; eating the shape away with noise means no two marks disappear the same
// way and the repeat stops being visible. It is also what a puddle drying and a
// scorch cooling actually look like.
//
// Everything is snapped to a texel grid to match the 64 px pixel-art bodies —
// smooth sub-pixel gradients on the floor next to hard-edged sprites is the exact
// mismatch that makes an effect look imported from another game.

// 0 SLUDGE   toxic: a thick irregular puddle with run-off lobes.
// 1 SPLATTER blood: an impact centre with droplets thrown along the step.
// 2 SCORCH   storm: a burn with a few embers still lit in it.
// 3 DUST     gold: loose glittering grains rather than a wet mark.
uniform int variant : hint_range(0, 3) = 0;
uniform vec4 tint : source_color = vec4(0.35, 0.85, 0.15, 1.0);
// 0 at birth, 1 at death. Driven from GroundDecal so a decal's own clock, not
// TIME, controls it — decals dropped a frame apart must not dissolve in lockstep.
uniform float age : hint_range(0.0, 1.0) = 0.0;
// Per-decal random, so two marks on the same tile are never the same shape.
uniform float rand = 0.0;
// Heading the wearer was moving in, for the variants that throw material along it.
uniform vec2 heading = vec2(1.0, 0.0);
uniform float decal_pixels = 24.0;

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
		p *= 2.11;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 snapped = (floor(UV * decal_pixels) + 0.5) / decal_pixels;
	vec2 centred = (snapped - vec2(0.5)) * 2.0;
	float radius = length(centred);
	vec2 seed = vec2(rand * 37.0, rand * 91.0);

	float mask = 0.0;
	vec3 col = tint.rgb;
	float glow = 0.0;

	if (variant == 0) {
		// SLUDGE. Ragged radius, not ragged alpha: a blurred circle still reads as
		// a circle, so the noise has to move the EDGE, not soften it.
		float ragged = radius + (fbm(centred * 3.4 + seed) - 0.5) * 0.55;
		mask = 1.0 - smoothstep(0.55, 0.92, ragged);
		// Densest in the MIDDLE and thinning to the rim, which is the way round a
		// puddle actually sits. Shading it the other way (dark centre, bright edge)
		// turns every drop into a ring, and a line of rings down a corridor is the
		// most obviously repeated thing a trail can leave behind.
		col = mix(tint.rgb, tint.rgb * 0.45, smoothstep(0.15, 0.9, ragged));
		// Wet highlight on the near edge — the read that says "liquid", not "stain".
		glow = (1.0 - smoothstep(0.30, 0.55, abs(ragged - 0.62))) * 0.5;
	} else if (variant == 1) {
		// SPLATTER. A squashed centre plus thrown droplets, biased DOWN-heading so
		// the spray follows the step instead of blooming symmetrically.
		vec2 along = normalize(heading + vec2(0.0001));
		float forward = dot(centred, along);
		vec2 skewed = centred - along * forward * 0.35;
		mask = 1.0 - smoothstep(0.28, 0.52, length(skewed));
		// Droplets: cell noise thresholded hard, thrown further along the heading.
		vec2 cell = centred * 4.5 - along * 1.2 + seed;
		float spots = hash(floor(cell));
		float drop = step(0.86, spots) * (1.0 - smoothstep(0.45, 1.0, radius));
		mask = max(mask, drop);
		col = tint.rgb * (0.7 + 0.3 * spots);
	} else if (variant == 2) {
		// SCORCH. Small, dark, irregular, with a couple of embers still alive in it
		// — the embers are what stop a footstep burn reading as a dirt smudge.
		float ragged = radius + (fbm(centred * 5.0 + seed) - 0.5) * 0.45;
		mask = (1.0 - smoothstep(0.35, 0.70, ragged)) * 0.85;
		col = tint.rgb * 0.25;
		float ember = step(0.93, hash(floor(centred * 6.0 + seed)));
		// Embers cool over the mark's life rather than surviving to the last frame.
		glow = ember * mask * (1.0 - age) * 1.4;
	} else {
		// DUST. No body at all, only grains — a solid disc of gold on the floor
		// reads as a spilled coin, which is a pickup, and must never be confused.
		vec2 cell = centred * 5.5 + seed;
		float grain = hash(floor(cell));
		mask = step(0.80, grain) * (1.0 - smoothstep(0.25, 1.0, radius));
		glow = mask * 0.9;
	}

	// DISSOLVE. The threshold climbs with age, so the noise field eats the mark
	// from its thinnest parts inward and the silhouette changes as it goes.
	float erosion = fbm(centred * 4.2 + seed.yx * 1.7);
	mask *= step(age * 1.15, erosion + (1.0 - age) * 0.35);
	// ...and a gentle overall fade underneath it, so the last few surviving specks
	// do not wink out at full opacity.
	mask *= 1.0 - smoothstep(0.65, 1.0, age);

	col = mix(col, mix(col, vec3(1.0), 0.65), glow);
	COLOR = vec4(col, clamp(mask * tint.a, 0.0, 1.0));
}
