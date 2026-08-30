shader_type canvas_item;
render_mode blend_mix;
// SOLAR ECLIPSE - THE UMBRA. The pitch-black disc under the wearer that the
// corona burns around.
//
// This is a separate quad from solar_corona.gdshader, and the split is forced by
// how blending works rather than by preference: a canvas item gets ONE blend
// mode, darkness can only be painted by blend_mix, and light only reads as light
// under blend_add. One shader trying to do both ends up either a grey disc with a
// yellow ring or a bright disc with no shadow at all. So the shadow is mixed on
// first and the corona is added on top of it.
//
// The disc is genuinely opaque in the middle. That matters: an eclipse is a HOLE,
// and every other floor effect in the set is translucent, so full opacity is the
// single cheapest thing that makes this one read as higher tier than the rest.

uniform vec4 shadow : source_color = vec4(0.01, 0.008, 0.02, 1.0);
uniform float umbra_pixels = 72.0;
uniform float speed = 1.0;
// How far past the black disc the darkness keeps spilling before it is gone.
uniform float penumbra : hint_range(0.0, 1.0) = 0.34;
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

void fragment() {
	float t = TIME * speed;
	vec2 snapped = (floor(UV * umbra_pixels) + 0.5) / umbra_pixels;
	vec2 centred = (snapped - vec2(0.5)) * 2.0;
	float radius = length(centred);
	if (radius > 1.0) {
		discard;
	}

	// The disc edge breathes very slightly - a perfectly static circle at full
	// opacity reads as a hole in the rendering rather than as an object.
	float breathe = 1.0 + 0.02 * sin(t * 0.8);
	float core = 0.58 * breathe;

	// UMBRA: hard and total. PENUMBRA: the shadow thinning outward, and it is
	// what stops the disc looking like a sticker cut out with scissors.
	float dark = 1.0 - smoothstep(core, core + penumbra, radius);
	// A little noise on the outer falloff only, so the boundary is uneven while
	// the middle stays absolutely solid.
	dark *= 0.92 + 0.08 * vnoise(centred * 5.0 + t * 0.1);
	dark = clamp(dark, 0.0, 1.0);
	// Re-solidify the core after the noise: the centre must be pure black.
	dark = max(dark, 1.0 - smoothstep(core * 0.85, core, radius));

	COLOR = vec4(shadow.rgb, clamp(dark * strength, 0.0, 1.0));
}
