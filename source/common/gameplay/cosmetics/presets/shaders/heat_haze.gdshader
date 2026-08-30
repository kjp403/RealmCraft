shader_type canvas_item;
render_mode blend_mix;
// EMBERFROST AURA - HEAT DISTORTION over the ember half of the ring.
//
// This is the ONE shader in the cosmetic set that reads the screen behind it, and
// that is not free: sampling hint_screen_texture forces a back-buffer copy for
// the canvas item using it, every frame, for every wearer on screen. That is
// affordable for a handful of players in a town and is not affordable on the web
// export, so AuraEmberfrostPreset swaps this for heat_shimmer.gdshader there. If
// a crowd ever becomes a problem on desktop too, that same swap is the lever.
//
// The distortion is deliberately VERTICALLY biased and rises with height: hot air
// climbs, so the wobble has to travel up and grow as it goes. A uniform
// omnidirectional ripple reads as underwater, not as heat.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Peak offset in UV units. Tiny on purpose: legible distortion at this sprite
// scale is a couple of pixels, and more turns the body behind it to mush.
uniform float amount : hint_range(0.0, 0.02) = 0.006;
uniform float speed = 1.0;
uniform float haze_pixels = 40.0;
// Warm tint added on top of the refraction, so the air over the embers also
// LOOKS hot rather than merely moving.
uniform vec4 glow : source_color = vec4(1.0, 0.55, 0.18, 1.0);

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

	// Envelope: strongest low and in the middle, gone by the edges, so the effect
	// has no boundary for the eye to catch.
	float rise = 1.0 - snapped.y;          // 1 at the bottom (over the embers)
	float sides = 1.0 - smoothstep(0.25, 0.5, abs(snapped.x - 0.5));
	float top = 1.0 - smoothstep(0.45, 1.0, rise);
	float envelope = sides * clamp(rise, 0.0, 1.0) * (0.35 + 0.65 * top);
	if (envelope <= 0.002) {
		discard;
	}

	// Cells stretched horizontally and scrolled UP, so the pattern is columns of
	// rising air rather than a drifting blob field.
	float wobble = vnoise(vec2(snapped.x * 7.0, snapped.y * 3.0 + t * 1.6)) - 0.5;
	float wobble2 = vnoise(vec2(snapped.x * 13.0 - 4.0, snapped.y * 5.0 + t * 2.4)) - 0.5;
	// Amplitude grows with height: the plume widens as it leaves the heat source.
	float climb = 0.35 + 0.65 * (1.0 - rise);
	vec2 offset = vec2(wobble * 1.0 + wobble2 * 0.5, wobble2 * 0.35) * amount * envelope * climb;

	vec4 behind = texture(screen_tex, SCREEN_UV + offset);
	// Add heat colour in proportion to how hard this pixel is bending - the parts
	// that shimmer most are the parts closest to the fire.
	float heat = envelope * (0.35 + abs(wobble) * 1.3);
	vec3 col = behind.rgb + glow.rgb * heat * 0.16;
	COLOR = vec4(col, 1.0);
}
