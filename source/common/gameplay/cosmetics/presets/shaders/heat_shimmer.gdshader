shader_type canvas_item;
render_mode blend_add;
// EMBERFROST AURA - HEAT SHIMMER, the web-export stand-in for heat_haze.gdshader.
//
// Same envelope and the same rising-column noise, but it ADDS warm light instead
// of refracting what is behind it. No sampler2D means no back-buffer copy, which
// is the entire reason this file exists - see the heat_haze header.
//
// It is not as good and is not meant to be: refraction bends the body behind the
// aura, and nothing additive can do that. What it does keep is the motion cue -
// warm bands climbing and thinning - which is most of what sells "hot air" at a
// glance, so the two variants read as the same effect at different fidelities.

uniform float speed = 1.0;
uniform float haze_pixels = 40.0;
uniform vec4 glow : source_color = vec4(1.0, 0.55, 0.18, 1.0);
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
	vec2 snapped = (floor(UV * haze_pixels) + 0.5) / haze_pixels;

	float rise = 1.0 - snapped.y;
	float sides = 1.0 - smoothstep(0.25, 0.5, abs(snapped.x - 0.5));
	float top = 1.0 - smoothstep(0.45, 1.0, rise);
	float envelope = sides * clamp(rise, 0.0, 1.0) * (0.35 + 0.65 * top);
	if (envelope <= 0.002) {
		discard;
	}

	float wobble = vnoise(vec2(snapped.x * 7.0, snapped.y * 3.0 + t * 1.6));
	float wobble2 = vnoise(vec2(snapped.x * 13.0 - 4.0, snapped.y * 5.0 + t * 2.4));
	// Bands, not a wash: contrast between the columns is what reads as movement.
	float bands = pow(clamp(wobble * 0.65 + wobble2 * 0.35, 0.0, 1.0), 2.2);

	float alpha = bands * envelope * 0.30 * strength;
	COLOR = vec4(glow.rgb * alpha, alpha);
}
