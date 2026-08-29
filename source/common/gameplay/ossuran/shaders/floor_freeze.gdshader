shader_type canvas_item;
// OSSURAN — FLOOR FREEZE. The phase-3 turn from Kindled Forge to Thick Ice,
// applied directly to the floor TileMapLayers and driven by one tweened uniform,
// `transition_progress`.
//
// ON THE LAYER, NOT OVER IT. The previous version was a full-rect overlay using
// `blend_mul`. That had to change for a hard reason: a blend_mul material does
// not draw its own item at all — it multiplies whatever is already in the
// framebuffer — so putting it ON the Ground layer would have erased the floor
// instead of frosting it. A material on the layer must therefore CROSS-FADE the
// texel it sampled, which is what this does, and it is strictly better:
//
//   * The frost is masked to real painted floor cells for free. The overlay was
//     a rectangle and bled over walls, props and the void at the room's edge.
//   * It can ADD blue. Multiply can only subtract, and the forge floor has
//     almost no blue channel — that limitation is why the old pass needed a
//     second additive node just to supply a hue. Computing the output colour
//     directly removes the whole problem, and the second node with it.
//   * One shader on two existing layers replaces three nodes and two shaders.
//
// HEAT RESISTS. Molten pixels are detected from the texel itself (warm and
// bright) and frost far less than cold stone does, so the lava channels and the
// glowing mortar stay lit while the slate around them ices over. That is a
// gameplay read as much as an art one: in phase 3 the warm things are the safe
// things, and they must never be frosted into the background.

// 0 = full forge, 1 = full ice. Tweened by EnvironmentTransitionManager.
uniform float transition_progress : hint_range(0.0, 1.0) = 0.0;

// World-space rect of the room that freezes: (x, y, width, height). Both rooms
// share one tilemap, so without this mask the summoning chamber would ice over
// at the same moment the arena does.
uniform vec4 arena_rect = vec4(32.0, 32.0, 704.0, 480.0);

// The frosted palette. `frost_deep` is the shadowed ice the sheet mostly is;
// `frost_lit` is the top of the ramp, reached only on facet edges and puddles.
uniform vec3 frost_deep : source_color = vec3(0.16, 0.26, 0.42);
uniform vec3 frost_lit : source_color = vec3(0.62, 0.80, 0.98);
// How far the frosted result is allowed to darken the original. 1.0 keeps the
// floor's own luminance, lower values sink it — the room must stay dim.
uniform float value_keep : hint_range(0.0, 1.0) = 0.92;
// Scale of the crystal facets, in cells per 100 world px. 2.0 puts a plate
// boundary roughly every 50px — about three tiles, which is the size that
// reads as cracked ice rather than as a stained-glass window. (It was 0.34,
// which spread two enormous cells across the whole room.)
uniform float facet_scale = 2.0;
// Pixels per world unit for snapping, so the pattern never crawls sub-pixel.
uniform float snap = 1.0;

varying vec2 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	)) * 43758.5453);
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

// Cellular noise. The GAP between nearest and second-nearest cell is near zero
// exactly on a plate boundary, which is what gives real crystal facets and the
// cracks between them — fbm alone produces clouds, and clouds are not ice.
vec2 voronoi(vec2 p) {
	vec2 base = floor(p);
	vec2 f = p - base;
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 offset = hash2(base + g);
			vec2 r = g + offset - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void vertex() {
	// UV on a TileMapLayer is the ATLAS coordinate, so it restarts inside every
	// tile — driving the noise from it would stamp the same 16px crystal into
	// every cell. World position is the only stable field to work in.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// Room mask. Outside the freezing room this shader is a pass-through, which
	// is also what every chamber tile on the same layer takes.
	//
	// Written as a BRANCH, not an early `return`: Godot's shading language does
	// not allow returning from fragment(), and the compile error it produces
	// silently empties the whole uniform list rather than naming the line.
	vec2 local = (world_pos - arena_rect.xy) / arena_rect.zw;
	float in_room =
		step(0.0, local.x) * step(local.x, 1.0) *
		step(0.0, local.y) * step(local.y, 1.0);
	vec3 out_rgb = base.rgb;

	if (in_room > 0.5 && transition_progress > 0.0) {
	vec2 p = floor(world_pos * snap) / snap;
	vec2 centred = local - vec2(0.5);
	float from_centre = clamp(length(centred) * 1.9, 0.0, 1.0);

	// --- THE CREEP. A static field thresholded by a front that rises with
	// progress and is biased outward, so the rim ices first and the last warm
	// ground in the room is the ground around the boss.
	float grain = fbm(p * 0.014);
	float front = transition_progress * 1.55 - (1.0 - from_centre) * 0.55;
	float covered = clamp((front - grain) * 4.0, 0.0, 1.0);

	// --- HEAT RESISTS. Warm, bright texels (lava, glowing mortar, embers) are
	// the room's remaining heat and must not be frosted into the background.
	float warmth = clamp((base.r - base.b) * 1.8, 0.0, 1.0) * base.r;
	covered *= 1.0 - warmth * warmth;

	// --- FACETS + PUDDLES.
	vec2 vor = voronoi(p * facet_scale * 0.01);
	float seam = 1.0 - smoothstep(0.0, 0.045, vor.y - vor.x);
	vec2 plate_id = floor(p * facet_scale * 0.01);
	float plate = vnoise(plate_id + 0.5);
	// Vary brightness PER PLATE EDGE. A uniformly lit web reads as a drawn
	// lattice laid on the floor; real ice catches light on some seams and not
	// others, and that unevenness is most of what sells it as a surface.
	float seam_lit = seam * mix(0.30, 1.0, hash(plate_id + 7.3));
	float pools = smoothstep(0.55, 0.86, fbm(p * 0.006 + 11.0));

	// --- THE FROSTED TEXEL. Built from the floor's own luminance so the slate's
	// grain, its tile seams and the light falling on it all survive the change;
	// only the hue and the value are re-authored.
	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float lit = clamp(
		luma * value_keep + plate * 0.07 + pools * 0.09 + seam_lit * 0.30, 0.0, 1.0
	);
	vec3 frosted = mix(frost_deep, frost_lit, lit);

	// --- RIME. A bright line exactly at the advancing boundary, so the spread is
	// visible while it happens. It retires once nothing is still moving.
	float edge = 1.0 - smoothstep(0.0, 0.12, abs(front - grain));
	float moving = smoothstep(0.02, 0.18, transition_progress)
		* (1.0 - smoothstep(0.82, 1.0, transition_progress));
	frosted += frost_lit * edge * moving * 0.45;

	out_rgb = mix(base.rgb, frosted, covered);
	}

	COLOR = vec4(out_rgb, base.a);
}
