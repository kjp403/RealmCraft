shader_type canvas_item;
render_mode blend_mix;
// SKILL MASTER TITLE TEXT. Eleven level-99 looks, selected by `fx`.
//
// Separate from title_vfx.gdshader on purpose. That one is a pulse and a shine
// band applied over whatever colour the label already is - the right shape for
// the supporter and premium sets, which are all "one colour, tastefully lit".
// These eleven each need their OWN gradient, so they need per-fragment control of
// hue rather than a modulation of an existing one, and folding both jobs into one
// shader would have meant a `mode` uniform gating two unrelated halves.
//
// THE OUTLINE MUST BE PASSED THROUGH, and this is the single most important
// thing in the file. Godot draws a Label's font outline as part of the SAME
// canvas item, not as a separate pass, so this shader receives the outline's
// fragments too. Repainting them with the gradient - which is what any shader
// that ignores the distinction does - means the dark backing set by
// TitleVfx.OUTLINE_COLOR is overwritten with bright title colour and the
// contrast guarantee silently evaporates. That is exactly how a bright title
// ends up unreadable over pale ground.
//
// Outline fragments are told apart by COLOUR: the glyph is drawn white
// (font_color) and the outline near-black, so anything close to `outline` is
// emitted unchanged. Robust because both ends are set by TitleVfx from the same
// constants this uniform is fed from.
//
// **UV IS NOT THE LABEL RECT.** This file used to say it was, and every one of
// the eleven looks below was written against that. It is wrong: a Label draws
// each glyph as its own quad textured from the FONT ATLAS, so `UV` is a
// coordinate into that atlas. UV.y measures near zero over every glyph of every
// title - verified by rendering it straight to screen - and UV.x tracks where a
// character sits in the atlas rather than where it sits in the word.
//
// What that cost: every vertical gradient here was DEAD, clamped to one end of
// its range, and every `sweep(uv.x, ...)` was travelling through atlas positions
// instead of through the word. The looks still read as deliberate, because
// per-glyph atlas variation passes for texture - which is exactly why this
// survived. It does not announce itself as a bug.
//
// `local` is the fix: a varying carrying VERTEX, the fragment's position in the
// LABEL's own coordinate space in pixels, divided by the label's size - which
// only GDScript knows, so it arrives as `rect_size`. TitleVfxPulse refreshes that
// uniform every frame because a Label resizes whenever its text changes.
//
// So NOW the header's original promise is true: a gradient down uv.y runs across
// the whole line of text (what "white-hot fading to red" wants) and a sweep along
// uv.x travels through the word left to right. Neither is per-letter, and at
// nameplate size that reads better anyway. Same treatment, same constants, as
// vip_title.gdshader - the two families sit on one nameplate and must not
// disagree about where the letters are.

uniform int fx : hint_range(0, 10) = 0;
// The catalog colour for this title. Every branch blends toward or away from it,
// so a palette edit in SkillMasterTitles moves the whole look without touching
// this file.
uniform vec4 base : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Seconds, driven from TitleVfxPulse rather than TIME: a Label does not redraw on
// its own, so TIME advances while the visible result does not. See that script.
uniform float t = 0.0;
// TitleVfx.OUTLINE_COLOR. Fragments matching it are the font outline and are
// emitted untouched - see the header.
uniform vec4 outline : source_color = vec4(0.043, 0.043, 0.063, 1.0);
// How close a fragment must be to `outline` to count as outline rather than
// glyph. Wide enough to survive font anti-aliasing on the outline's own edge,
// far narrower than the distance to any title's palette.
uniform float outline_tolerance : hint_range(0.0, 1.0) = 0.22;
// The label's laid-out size in its own units. Fed by TitleVfxPulse; see header.
uniform vec2 rect_size = vec2(1.0, 1.0);

// Position within the label, in the label's own pixels. See the header.
varying vec2 local;

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

// A bright band travelling left to right along the word. Shared by every look
// that needs a shimmer, at different speeds and widths.
float sweep(float x, float speed, float width, float phase) {
	float head = fract(t * speed + phase);
	return 1.0 - smoothstep(0.0, width, abs(x - head));
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 tex = COLOR;
	if (tex.a < 0.04 || distance(tex.rgb, outline.rgb) < outline_tolerance) {
		// Transparent, or the dark outline backing the glyph. Straight through.
		COLOR = tex;
	} else {
		vec2 uv = local / max(rect_size, vec2(1.0, 1.0));
		// Vertical gradients are remapped onto the GLYPH BAND rather than the
		// label rect. A Label centres its line vertically with padding above and
		// below, so the letters only occupy the middle of its height - running a
		// gradient over the full 0..1 spends part of its range on empty space and
		// delivers a washed-out sliver of itself to the text. This stretches the
		// interesting part over the rows that actually have glyphs in them.
		uv.y = clamp((uv.y - 0.22) / 0.56, 0.0, 1.0);
		vec3 col = tex.rgb * base.rgb;
		float alpha = tex.a;

		if (fx == 0) {
			// MASTER MINER - rugged stone with a gold shimmer running through it.
			// The grain is sampled on a stretched noise field so it reads as
			// bedding planes in rock rather than as television static.
			float grain = vnoise(vec2(uv.x * 26.0, uv.y * 5.0));
			vec3 stone = mix(vec3(0.42, 0.39, 0.36), vec3(0.78, 0.74, 0.68), grain);
			col = mix(stone, base.rgb, 0.45);
			// The ore seam. Narrow and slow: gold in stone is a vein, not a wash.
			float vein = sweep(uv.x, 0.20, 0.13, 0.0);
			col = mix(col, vec3(1.0, 0.85, 0.42), vein * 0.85);
		} else if (fx == 1) {
			// FORGE MASTER - white-hot at the top cooling to deep red at the
			// bottom, which is the direction heat actually leaves a billet.
			float heat = 1.0 - uv.y;
			col = mix(vec3(0.55, 0.05, 0.02), vec3(1.0, 0.55, 0.15), smoothstep(0.15, 0.75, heat));
			col = mix(col, vec3(1.0, 0.97, 0.90), smoothstep(0.72, 1.0, heat));
			// Heat wave on the TOP boundary only. Displacing the gradient's
			// sample rather than the glyph keeps the letterform crisp - warping
			// the text itself at this size just makes it unreadable.
			float wave = sin(uv.x * 22.0 + t * 3.4) * 0.5 + 0.5;
			col += vec3(0.45, 0.20, 0.04) * wave * smoothstep(0.55, 1.0, heat) * 0.5;
		} else if (fx == 2) {
			// DEEP SEA LEGEND - cyan surface into deep blue, with caustics.
			col = mix(vec3(0.05, 0.20, 0.55), vec3(0.35, 0.90, 1.0), 1.0 - uv.y);
			// Two counter-drifting wave fields multiplied together: the product
			// is what makes the bright cells wander and pinch like real caustics.
			float a = sin((uv.x * 13.0 + uv.y * 5.0) + t * 1.7);
			float b = sin((uv.x * 9.0 - uv.y * 7.0) - t * 1.1);
			float caustic = pow(clamp(a * b, 0.0, 1.0), 2.0);
			col += vec3(0.55, 0.95, 1.0) * caustic * 0.55;
		} else if (fx == 3) {
			// CULINARY KING - warm golden brown with a soft inner glow. The glow
			// is strongest in the middle band of the line so the letters look lit
			// from within rather than edge-lit.
			col = mix(vec3(0.45, 0.26, 0.09), base.rgb, smoothstep(0.0, 0.9, 1.0 - abs(uv.y - 0.5) * 2.0));
			col += vec3(1.0, 0.78, 0.35) * (1.0 - abs(uv.y - 0.45) * 2.0) * 0.22;
		} else if (fx == 4) {
			// GRAND ARTISAN - polished marble. Veining, then a hard silver
			// specular line that travels: polish is a moving highlight, and a
			// static one just looks like a lighter stripe.
			float vein = vnoise(vec2(uv.x * 7.0 + uv.y * 2.0, uv.y * 3.0));
			col = mix(vec3(0.80, 0.82, 0.86), vec3(0.98, 0.99, 1.0), vein);
			col = mix(col, vec3(0.55, 0.58, 0.66), smoothstep(0.55, 0.85, vein) * 0.5);
			col += vec3(1.0) * sweep(uv.x, 0.26, 0.05, 0.0) * 0.65;
		} else if (fx == 5) {
			// TIMBER LORD - oak. Grain rings run ALONG the text, tight and
			// irregular, and the darker latewood bands are what read as wood
			// rather than as a brown gradient.
			float rings = vnoise(vec2(uv.x * 4.0, uv.y * 30.0));
			col = mix(vec3(0.36, 0.22, 0.09), vec3(0.78, 0.56, 0.28), rings);
			col = mix(col, base.rgb, 0.35);
		} else if (fx == 6) {
			// ARCH-BOTANIST - high-visibility emerald with light climbing it, so
			// the colour reads as growth rather than as a flat green fill.
			col = mix(vec3(0.06, 0.42, 0.20), vec3(0.45, 1.0, 0.55), smoothstep(0.1, 0.9, 1.0 - uv.y));
			float climb = fract(uv.y * 2.0 + t * 0.35);
			col += vec3(0.55, 1.0, 0.45) * pow(1.0 - abs(climb - 0.5) * 2.0, 5.0) * 0.30;
		} else if (fx == 7) {
			// MASTER FLETCHER - white and crimson, split by a feather barb
			// pattern. High-frequency diagonal stripes, because a feather's vane
			// is a comb, not a gradient.
			float barb = sin(uv.x * 52.0 + uv.y * 12.0) * 0.5 + 0.5;
			col = mix(vec3(0.72, 0.08, 0.14), vec3(1.0, 0.96, 0.95), smoothstep(0.35, 0.65, barb));
			// The shot: a fast, thin streak straight through the word.
			col += vec3(1.0) * sweep(uv.x, 0.75, 0.035, 0.0) * 0.8;
		} else if (fx == 8) {
			// GRAND ALCHEMIST - potion purple, boiling. Cells rise and wrap, so
			// the surface churns upward continuously.
			float boil = vnoise(vec2(uv.x * 12.0, uv.y * 8.0 - t * 1.6));
			col = mix(vec3(0.28, 0.06, 0.45), vec3(0.72, 0.35, 1.0), boil);
			// Neon-green rim INSIDE the glyph edge. This is a chemical tell, and
			// it is separate from the dark contrast outline behind the glyph.
			float edge = smoothstep(0.30, 0.05, tex.a);
			col = mix(col, vec3(0.45, 1.0, 0.35), edge * 0.85);
		} else if (fx == 9) {
			// SLAYER MASTER - a straight vertical gradient, bone at the top of the
			// glyph band into dark blood at the bottom. uv.y is already remapped
			// onto that band above, so the full range lands on the letters.
			//
			// The waterline noise only ragges the BOUNDARY, not the endpoints: the
			// two colours are exact so the title matches its catalog swatch and its
			// crimson outline, while the transition between them still looks
			// absorbed rather than printed.
			float edge = 0.55 + (vnoise(vec2(uv.x * 16.0, t * 0.35)) - 0.5) * 0.18;
			col = mix(
				vec3(0.878, 0.839, 0.765), // #E0D6C3
				vec3(0.545, 0.0, 0.0),     // #8B0000
				smoothstep(edge - 0.42, edge + 0.42, uv.y)
			);
		} else {
			// HIGH PRIEST - divine white and gold, brightest at the centre line
			// and blooming. Kept just under blowout: the dark outline is what
			// holds this one together on a bright map, and if the glyph interior
			// goes pure white the letterform is gone.
			float halo = 1.0 - abs(uv.y - 0.5) * 2.0;
			// Radiant gold (#FFD700) at the edges of the glyph band, burning to a
			// white core along its centre line. The core is pushed harder than the
			// old cream mix (pow 2.4 rather than 1.6) so the white stays a narrow
			// filament instead of flooding the letterform.
			col = mix(
				vec3(1.0, 0.843, 0.0),  // #FFD700
				vec3(1.0, 1.0, 1.0),    // white core
				pow(clamp(halo, 0.0, 1.0), 2.4)
			);
			col += vec3(1.0, 0.90, 0.50) * sweep(uv.x, 0.18, 0.16, 0.0) * 0.30;
		}

		// Shared gentle breath so no title is completely static, even the ones
		// whose look has no motion of its own.
		col *= 0.94 + 0.06 * sin(t * 2.1);
		COLOR = vec4(col, alpha);
	}
}
