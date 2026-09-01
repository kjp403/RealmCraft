shader_type canvas_item;
render_mode blend_mix;
// BLOOD AURA - POOL AND RIPPLES. A deep, dark crimson pool under the wearer with
// rings running outward across it.
//
// Blood is the one palette that must NOT be treated like the others. Every other
// aura here can be brightened until it glows; blood brightened goes pink and
// reads as a health pickup or a heal. So this shader is built the opposite way
// round to the toxic pool: the pool is DARK and nearly opaque, and the only light
// in it is a thin specular sheen on the ripple crests - the wet black-cherry look
// rather than a red lamp on the floor.
//
// The ripples are also slower and further apart than the sludge's. Fast tight
// rings read as boiling; blood should look thick and heavy, so the wave speed is
// roughly half and the amplitude is carried by the sheen rather than by hue.

uniform vec4 deep : source_color = vec4(0.20, 0.015, 0.03, 1.0);
uniform vec4 mid : source_color = vec4(0.52, 0.05, 0.07, 1.0);
uniform vec4 sheen : source_color = vec4(0.95, 0.35, 0.34, 1.0);
uniform float pool_pixels = 72.0;
uniform float speed = 1.0;
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
		p *= 2.13;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	float t = TIME * speed;
	vec2 snapped = (floor(UV * pool_pixels) + 0.5) / pool_pixels;
	vec2 centred = (snapped - vec2(0.5)) * 2.0;
	float radius = length(centred);

	// Slow surface churn - enough that the pool is not a frozen shape, far less
	// than the sludge, because blood should look viscous.
	float churn = fbm(centred * 2.4 + vec2(t * 0.09, -t * 0.07));

	// --- RIPPLES. Three rings travelling out on staggered phases, each fading as
	// it widens. Staggered rather than one repeating wave so the pool looks
	// disturbed continuously instead of pulsing on a metronome.
	float wave = 0.0;
	for (int i = 0; i < 3; i++) {
		float phase = fract(t * 0.34 + float(i) / 3.0);
		float ring = phase * 1.05;
		// The crest thins as it travels, like a real surface wave losing energy.
		float band = 1.0 - smoothstep(0.0, 0.09 + phase * 0.05, abs(radius - ring));
		wave = max(wave, band * (1.0 - phase));
	}

	float ragged = radius + (churn - 0.5) * 0.22;
	float mask = 1.0 - smoothstep(0.74, 0.99, ragged);
	if (mask <= 0.001) {
		discard;
	}

	// Body: dark in the middle where it is deepest, lighter at the shallow rim -
	// the reverse of a glow, and the reason it reads as depth rather than light.
	vec3 col = mix(deep.rgb, mid.rgb, smoothstep(0.15, 0.95, ragged) * (0.55 + churn * 0.45));
	// Specular only on the crests. Kept narrow: broad sheen turns the pool pink.
	col = mix(col, sheen.rgb, wave * 0.38);
	float rim = (1.0 - smoothstep(0.0, 0.13, abs(ragged - 0.83))) * mask;
	col = mix(col, mid.rgb * 1.25, rim * 0.5);

	float alpha = mask * (0.80 + 0.12 * churn) + wave * 0.10;
	COLOR = vec4(col, clamp(alpha * strength, 0.0, 1.0));
}
