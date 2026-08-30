shader_type canvas_item;
// Sweeping shine for a rare reward's slot background.
//
// The band is QUANTIZED into a few hard steps rather than left as a smooth
// gradient. A continuous falloff is the giveaway that a "pixel art" UI was built
// with vector tools — it produces hundreds of intermediate values across a
// handful of pixels. Stepping it keeps the shine on the same limited ramp the
// rest of the art uses, so it reads as animated pixel shading.
//
// Drives only the BACKGROUND of a slot; the item icon is drawn above it
// unshaded, so the sprite itself is never tinted or washed out.

// Shine colour. Fed the rarity tint so one shader serves every tier.
uniform vec4 shine_color : source_color = vec4(1.0, 0.86, 0.42, 1.0);
// Base fill under the shine.
uniform vec4 base_color : source_color = vec4(0.09, 0.10, 0.13, 1.0);
uniform float speed = 0.45;
// Half-width of the band in diagonal-UV space.
uniform float band_width = 0.22;
uniform float intensity = 0.85;
// Number of hard steps in the band. 3-4 reads as pixel art; higher smooths out.
uniform float steps = 4.0;

void fragment() {
	// Diagonal sweep: constant along the anti-diagonal, travelling with TIME.
	float diag = (UV.x + UV.y) * 0.5;
	float phase = fract(diag - TIME * speed);

	// Distance from the band centre, wrapped so the sweep is seamless.
	float d = abs(phase - 0.5);
	float band = clamp(1.0 - d / max(band_width, 0.001), 0.0, 1.0);

	// Quantize to hard steps — this is what keeps it pixel-art rather than a
	// smooth vector sheen.
	band = floor(band * steps) / steps;

	vec3 rgb = mix(base_color.rgb, shine_color.rgb, band * intensity);
	COLOR = vec4(rgb, base_color.a);
}
