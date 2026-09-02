shader_type canvas_item;
// Animated shine for high-tier gear: a highlight sweep across the sprite plus a
// slow twinkle, with an optional hue cycle for iridescent metals (Astralite).
// Applied at runtime from Item.shimmer_* / MineableNodeResource.shimmer_* — the
// art itself stays flat so inventory icons keep their contrast.

uniform vec4 shimmer_tint : source_color = vec4(1.0, 0.95, 0.72, 1.0);
uniform float shimmer_strength : hint_range(0.0, 2.0) = 0.6;
uniform float shimmer_speed : hint_range(0.1, 4.0) = 1.0;
uniform bool shimmer_iridescent = false;
// Static offset into the cycle, in seconds. Lets preview tooling grab a chosen
// phase, and lets two copies of the same prop glint out of step.
uniform float shimmer_phase = 0.0;

vec3 hue_shift(vec3 color, float amount) {
	const vec3 k = vec3(0.57735);
	float c = cos(amount);
	return color * c + cross(k, color) * sin(amount) + k * dot(k, color) * (1.0 - c);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = tex;
	} else {
		vec3 rgb = tex.rgb;
		float t = (TIME + shimmer_phase) * shimmer_speed;
		if (shimmer_iridescent) {
			rgb = clamp(hue_shift(rgb, sin(t * 0.6 + (UV.x + UV.y) * 3.0) * 0.5), 0.0, 1.0);
		}
		// diagonal highlight sweep
		float band = fract(t * 0.25) * 2.0 - 0.5;
		float sweep = exp(-pow((UV.x * 0.5 + UV.y * 0.5) - band, 2.0) * 26.0);
		// twinkle, biased to the already-bright faces so shadows stay dark
		float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
		float twinkle = (0.5 + 0.5 * sin(t * 2.2 + (UV.x * 17.0 + UV.y * 11.0))) * smoothstep(0.55, 0.95, lum);
		rgb = mix(rgb, shimmer_tint.rgb, clamp(sweep * 0.55 * shimmer_strength, 0.0, 1.0));
		rgb += shimmer_tint.rgb * (sweep * 0.45 + twinkle * 0.30) * shimmer_strength;
		COLOR = vec4(clamp(rgb, 0.0, 1.0), tex.a);
	}
}
