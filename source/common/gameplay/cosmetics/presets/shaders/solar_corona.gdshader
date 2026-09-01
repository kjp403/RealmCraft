shader_type canvas_item;
render_mode blend_add;
// SOLAR ECLIPSE - THE CORONA. The blazing ring of light around the umbra, laid
// over eclipse_umbra.gdshader (see that file for why they are two quads).
//
// A corona is not a glowing ring. It is millions of streamers of plasma leaving
// the surface along magnetic field lines, which is why a real eclipse photograph
// has a RAGGED, spiky halo rather than a smooth annulus. So the light here is
// built from angular streamers of varying length and brightness, not from a
// radial gradient - and the streamers wander over time, because a static spike
// pattern reads as a drawn sun icon.
//
// Two frequency bands do the work: a slow, wide band that gives the halo its
// overall lopsided shape (a real corona is never symmetrical), and a fast, fine
// band that gives it the hairline detail. Either alone looks wrong - the wide
// band alone is a blob, the fine band alone is a fringe.

uniform vec4 inner : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform vec4 outer : source_color = vec4(1.0, 0.55, 0.10, 1.0);
uniform float corona_pixels = 88.0;
uniform float speed = 1.0;
// Where the umbra ends and the light begins. Must match the umbra's core.
uniform float ring : hint_range(0.1, 0.9) = 0.58;
uniform float strength : hint_range(0.0, 2.0) = 1.0;

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

void fragment() {
	float t = TIME * speed;
	vec2 snapped = (floor(UV * corona_pixels) + 0.5) / corona_pixels;
	vec2 centred = (snapped - vec2(0.5)) * 2.0;
	float radius = length(centred);
	if (radius > 1.0 || radius < ring * 0.7) {
		discard;
	}
	// 0..1 around the disc. Sampling noise on this wraps at the seam, so both
	// bands are sampled on a CIRCLE in noise space instead (cos/sin below).
	float angle = atan(centred.y, centred.x);
	vec2 on_circle = vec2(cos(angle), sin(angle));

	// WIDE band: the lopsided overall shape, drifting slowly.
	float wide = vnoise(on_circle * 2.4 + vec2(t * 0.09, -t * 0.07));
	// FINE band: hairline streamers, moving faster and in the other direction so
	// the two never lock into a pattern.
	float fine = vnoise(on_circle * 11.0 - vec2(t * 0.22, t * 0.17));
	// Sharpened: streamers need gaps between them, and a plain sum has none.
	float streamer = pow(clamp(wide * 0.65 + fine * 0.45, 0.0, 1.0), 2.1);

	// Each streamer reaches its own distance. This is the whole silhouette.
	float reach = ring + 0.10 + streamer * 0.42;
	float body = 1.0 - smoothstep(ring, reach, radius);
	// Hot rim hugging the umbra: the corona is brightest where it leaves the
	// surface, and this is what makes the black disc look BACKLIT rather than
	// like a hole punched in a glow.
	float rim = 1.0 - smoothstep(ring, ring + 0.09, radius);

	// Colour by distance travelled, not by streamer strength: plasma cools as it
	// climbs, so the near light is white and the far light is deep orange.
	float climb = clamp((radius - ring) / 0.5, 0.0, 1.0);
	vec3 col = mix(inner.rgb, outer.rgb, climb);

	float alpha = clamp(body * (0.30 + 0.70 * streamer) + rim * 0.85, 0.0, 1.0);
	// Premultiplied, like the accretion disk: an additive pass must scale colour
	// by its own coverage or the gaps between streamers still deposit full light.
	COLOR = vec4(col * alpha, alpha * strength);
}
