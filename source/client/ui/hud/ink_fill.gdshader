shader_type canvas_item;
// "Ink in water" resource fill for the HUD bars (health / mana / prayer).
//
// The point is that a resource bar should look like a VOLUME OF FLUID, not a
// coloured rectangle: the body curls with slow domain-warped turbulence, it is
// denser at the bottom where the ink has settled and wispier at the top, and
// the front is a diffusing boundary rather than a straight cut. What keeps it
// from turning to mush is the leading edge — a hard bright core with a short
// bloom trailing behind it, so the eye is pulled straight to where the value
// actually is. That pairing is the whole design: fluid body, crisp front.
//
// The two cut corners (top-right, bottom-left) match the keybind tiles so the
// bars and the ability bar read as one instrument panel.

// Current value, 0-1. Driven from the ProgressBar by ink_fill.gd.
uniform float fill : hint_range(0.0, 1.0) = 1.0;
// Body gradient: deep is the settled ink, bright is where it thins out.
uniform vec4 ink_deep : source_color = vec4(0.04, 0.22, 0.07, 1.0);
uniform vec4 ink_bright : source_color = vec4(0.42, 0.95, 0.45, 1.0);
// The leading edge. Near-white reads as the meniscus catching the light.
uniform vec4 edge_color : source_color = vec4(0.88, 1.0, 0.90, 1.0);
// 0 turns the front off entirely — the health bar's damage chip is residue
// left behind, so it must NOT compete with the live bar for attention.
uniform float edge_glow : hint_range(0.0, 1.0) = 1.0;
uniform float flow_speed = 0.28;
// How far the front feathers, in UV. Wider = more diffuse, less readable.
uniform float bleed : hint_range(0.0, 0.2) = 0.045;
// Pixel size of the control, so the corner cut and the edge widths stay put
// whatever the bar is scaled to.
uniform vec2 rect_size = vec2(200.0, 15.0);
uniform float chamfer = 3.0;


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


// Three octaves is enough at 15px tall and keeps the domain warp below cost.
float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		total += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}


void fragment() {
	vec2 px = UV * rect_size;

	// Chamfered ends, matching hud_slot_box.gd: cut the top-right and
	// bottom-left corners, antialiased over one pixel.
	float top_right = (rect_size.x - px.x) + px.y;
	float bottom_left = px.x + (rect_size.y - px.y);
	float shape = min(
		smoothstep(chamfer - 1.0, chamfer + 0.5, top_right),
		smoothstep(chamfer - 1.0, chamfer + 0.5, bottom_left)
	);

	// Domain-warped turbulence: warping the sample point is what makes the
	// streaks CURL. Sampling the noise straight just scrolls a texture past.
	float t = TIME * flow_speed;
	vec2 q = vec2(UV.x * 5.0, UV.y * 2.2);
	vec2 warp = vec2(fbm(q + vec2(t, 0.0)), fbm(q + vec2(0.0, -t) + 4.7));
	float ink = fbm(q * 1.6 + warp * 1.4 + vec2(t * 0.5, 0.0));

	// The front wobbles with the same field, so body and boundary agree.
	float front = fill + (ink - 0.5) * bleed;
	float body = smoothstep(front, front - bleed * 1.2, UV.x);

	// Lit from above, like the keybind tiles: the fluid is brightest along the
	// top where the light catches it and deepens toward the bottom, which is
	// what gives a 15px strip any sense of volume at all.
	float density = clamp(ink * 1.05 + 0.12, 0.0, 1.0) * mix(1.0, 0.45, UV.y);
	vec3 col = mix(ink_deep.rgb, ink_bright.rgb, density);

	// Glass sheen on the top pixel — the "crisp" half of the brief.
	col += vec3(0.22) * smoothstep(1.5, 0.0, px.y);

	// Leading edge: hard core, short bloom BEHIND it only (max(d, 0.0)), so the
	// glow trails into the fluid instead of leaking into the empty track. Kept
	// deliberately thin — a fat white blob swallows the readout printed over it
	// and stops reading as a meniscus.
	float behind = (front - UV.x) * rect_size.x;
	float core = smoothstep(1.8, 0.0, abs(behind));
	float bloom = smoothstep(12.0, 0.0, max(behind, 0.0)) * 0.26;
	// Bloom tints toward the bright ink, only the core goes near-white.
	col = mix(col, ink_bright.rgb, clamp(bloom * edge_glow, 0.0, 1.0));
	col = mix(col, edge_color.rgb, clamp(core * 0.7 * edge_glow, 0.0, 1.0));

	// The core survives where the body has already faded, keeping the front
	// legible at a glance. Everything dies at fill 0 so an empty bar is empty.
	float alpha = max(body, core * 0.8 * edge_glow) * shape * ink_deep.a;
	COLOR = vec4(col, alpha * step(0.0005, fill));
}
