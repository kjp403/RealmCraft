shader_type canvas_item;
render_mode blend_mix;
// TOXIC AURA - SLUDGE POOL. The floor layer: a pool of swirling toxic slop with a
// surface that bubbles and rings, laid flat under the wearer's feet.
//
// The old aura was a coloured ellipse outline. The three things that turn an
// outline into a POOL are all here, and each fixes a specific failure:
//
//   SWIRL   the body is domain-warped noise turning slowly around the centre, so
//           the surface has internal motion. A ring with a static fill reads as a
//           decal no matter how brightly it is coloured.
//   RINGS   waves travelling OUTWARD from the middle, riding over the swirl as
//           they pass. This is what says "liquid" rather than "green floor smoke".
//   BUBBLES discrete blobs that swell, get a bright rim, and pop. They are the
//           only element with a hard edge, and they carry the whole "this is
//           corrosive and alive" read.
//
// The rim is deliberately ragged and slightly brighter than the fill it holds in:
// a pool has a meniscus, and a clean edge is the thing that makes ground effects
// look pasted on (the same conclusion the Ossuran pad decal reached).

uniform vec4 deep : source_color = vec4(0.10, 0.28, 0.05, 1.0);
uniform vec4 surface : source_color = vec4(0.42, 0.85, 0.13, 1.0);
uniform vec4 bright : source_color = vec4(0.78, 1.0, 0.38, 1.0);
uniform float pool_pixels = 72.0;
uniform float speed = 1.0;
// Master opacity, so the preset can breathe the whole pool without touching hues.
uniform float strength : hint_range(0.0, 1.5) = 1.0;

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
		p *= 2.09;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	float t = TIME * speed;
	vec2 snapped = (floor(UV * pool_pixels) + 0.5) / pool_pixels;
	vec2 centred = (snapped - vec2(0.5)) * 2.0;
	float radius = length(centred);

	// --- SWIRL. Rotate the sample frame FASTER toward the middle, so the pool
	// shears the way a stirred liquid does instead of turning as one rigid disc.
	float spin = t * 0.55 + (1.0 - radius) * 1.35;
	float cs = cos(spin);
	float sn = sin(spin);
	vec2 turned = vec2(centred.x * cs - centred.y * sn, centred.x * sn + centred.y * cs);
	// Domain warp: noise displacing the lookup into more noise. One cheap way to
	// get slow-churning organic movement out of three octaves.
	vec2 warp = vec2(fbm(turned * 2.6 + t * 0.20), fbm(turned * 2.6 - t * 0.17)) - vec2(0.5);
	float body = fbm(turned * 3.1 + warp * 1.4);

	// --- RINGS. Waves running out from the centre, decaying as they widen.
	float wave = sin(radius * 13.0 - t * 2.3) * 0.5 + 0.5;
	wave *= smoothstep(0.05, 0.35, radius) * (1.0 - smoothstep(0.55, 1.0, radius));
	body += wave * 0.22;

	// --- POOL EDGE. Ragged radius (not a soft alpha) so the boundary is irregular.
	float ragged = radius + (body - 0.5) * 0.30;
	float mask = 1.0 - smoothstep(0.72, 0.98, ragged);
	if (mask <= 0.001) {
		discard;
	}

	// --- BUBBLES. Grid cells each running their own swell-and-pop on an offset
	// phase, so they never pulse together. A bubble is a filled blob with a bright
	// rim; the rim is the part that sells the surface tension.
	vec2 grid = turned * 4.2;
	vec2 cell = floor(grid);
	float seed = hash(cell);
	float phase = fract(t * (0.5 + seed * 0.6) + seed);
	// Swell over most of the cycle, then vanish - the pop is the abrupt end.
	float grow = smoothstep(0.0, 0.75, phase) * (1.0 - step(0.92, phase));
	vec2 offset = vec2(0.5 + (seed - 0.5) * 0.4, 0.5 + (hash(cell + vec2(3.7, 1.9)) - 0.5) * 0.4);
	vec2 local = fract(grid) - offset;
	float bd = length(local) / max(0.06, grow * 0.34);
	float bubble = 1.0 - smoothstep(0.75, 1.0, bd);
	float bubble_rim = (1.0 - smoothstep(0.10, 0.35, abs(bd - 0.85))) * grow;
	// Bubbles only live on the pool, and not right out at the ragged edge.
	float bubble_area = smoothstep(0.85, 0.55, ragged);
	bubble *= bubble_area;
	bubble_rim *= bubble_area;

	vec3 col = mix(deep.rgb, surface.rgb, clamp(body * 1.35, 0.0, 1.0));
	col = mix(col, surface.rgb * 0.75, bubble * 0.6);
	col = mix(col, bright.rgb, bubble_rim * 0.9);
	// Meniscus: the outer band is brighter and denser than the fill it holds in.
	float rim = (1.0 - smoothstep(0.0, 0.16, abs(ragged - 0.80))) * mask;
	col = mix(col, bright.rgb, rim * 0.45);

	float alpha = mask * (0.62 + 0.20 * body) + rim * 0.28 + bubble_rim * 0.35;
	COLOR = vec4(col, clamp(alpha * strength, 0.0, 1.0));
}
