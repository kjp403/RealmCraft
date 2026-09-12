shader_type canvas_item;
render_mode blend_mix;
// COLOUR-MATCHED TITLE TEXT. Eight shop looks, selected by `fx`.
//
// A THIRD TITLE SHADER, and the reason is the palette rather than the effect.
// title_vfx.gdshader modulates whatever colour the label already is, and
// skill_master_title.gdshader hard-codes eleven earned gradients. These eight are
// neither: every colour here arrives as a uniform from [CosmeticThemes], because
// the same hex also paints an aura and a body dye and the three must not drift.
// Folding them into either neighbour would have meant a palette living half in a
// uniform and half in GLSL literals - which is exactly the drift this set exists
// to avoid. So: no colour constants in this file. Anything coloured comes from
// `core`, `accent`, `pale` or `deep`, and the branches only decide how they move.
//
// THE OUTLINE MUST BE PASSED THROUGH. Godot draws a Label's font outline in this
// same canvas item, so this shader receives its fragments too; repainting them
// overwrites the dark backing TitleVfx.OUTLINE_COLOR exists to be, and a bright
// title over pale ground stops being readable. Fragments near `outline` are
// emitted untouched. Same rule, same uniforms, as the other two title shaders.
//
// UV IS NOT THE LABEL RECT. A Label textures each glyph from the FONT ATLAS, so
// UV is an atlas coordinate and says nothing about where a fragment sits in the
// word. `local` carries VERTEX - label space, in pixels - and `rect_size` is the
// laid-out size, which only GDScript knows. See skill_master_title.gdshader's
// header for the full account; all three title shaders agree on this.
//
// PIXEL ART. Gradients and sweeps are evaluated on `px`, the fragment's label
// position snapped to whole pixels, so a ramp lands as pixel bands rather than as
// a smooth smear over 64px art. The label itself is filtered NEAREST by TitleVfx.

uniform int fx : hint_range(0, 7) = 0;
// The theme's dye colour. THE colour the title is.
uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The theme's second dye - ember over crimson, cyan over frost, gold over violet.
uniform vec4 accent : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// core lightened / darkened, by CosmeticThemes. Highlights and shadow.
uniform vec4 pale : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Seconds, driven from TitleVfxPulse rather than TIME: a Label does not redraw on
// its own, so TIME advances while the visible result does not. See that script.
uniform float t = 0.0;
// TitleVfx.OUTLINE_COLOR, and how close a fragment must be to it to count as
// outline rather than glyph. See the header.
uniform vec4 outline : source_color = vec4(0.043, 0.043, 0.063, 1.0);
uniform float outline_tolerance : hint_range(0.0, 1.0) = 0.22;
// The label's laid-out size in its own units. Fed by TitleVfxPulse; see header.
uniform vec2 rect_size = vec2(1.0, 1.0);

// Position within the label, in the label's own pixels. See the header.
varying vec2 local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A bright band travelling left to right along the word. Shared by every look
// that needs a shimmer, at different speeds and widths.
float sweep(float x, float speed, float width, float phase) {
	float head = fract(t * speed + phase);
	return 1.0 - smoothstep(0.0, width, abs(x - head));
}

// Hue rotation about the luminance axis. The prism's whole trick, and cheaper
// than a round trip through HSV for something evaluated per fragment.
vec3 spin_hue(vec3 c, float turns) {
	// Rodrigues rotation about the grey axis: hue moves, luminance does not. A
	// round trip through HSV would do the same job and cost two branchy
	// conversions per fragment for a colour that is already in gamut.
	vec3 axis = vec3(0.57735, 0.57735, 0.57735);
	float a = turns * 6.2831853;
	float cs = cos(a);
	return c * cs + cross(axis, c) * sin(a) + axis * dot(axis, c) * (1.0 - cs);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 tex = COLOR;
	// An early `return` here would be the natural way to write this and is a
	// COMPILE ERROR in Godot's shading language - `return` is not allowed in
	// fragment(). Hence the else arm wrapping the whole body, the same shape
	// title_vfx.gdshader and skill_master_title.gdshader use.
	if (tex.a < 0.04 || distance(tex.rgb, outline.rgb) < outline_tolerance) {
		// Transparent, or the dark outline backing the glyph. Straight through.
		COLOR = tex;
	} else {
		// Whole label pixels, so every ramp below bands on pixel boundaries.
		vec2 px = floor(local);
		vec2 uv = px / max(rect_size, vec2(1.0, 1.0));
		// Vertical gradients are remapped onto the GLYPH BAND rather than the label
		// rect: a Label centres its line with padding above and below, so a 0..1 ramp
		// spends most of its range on empty space. Same remap the mastery shader uses.
		float band = clamp((uv.y - 0.22) / 0.56, 0.0, 1.0);
		vec3 col = core.rgb;
		float alpha = tex.a;

		if (fx == 0) {
			// CRIMSON WARLORD - a forge pulse. The whole word breathes between deep
			// and pale, and a slow ember wash rises through the letters, so the glow
			// looks like heat coming UP off them rather than a light switching on.
			float beat = 0.5 + 0.5 * sin(t * 2.1);
			float rise = fract(band * 1.2 - t * 0.35);
			float heat = smoothstep(0.55, 1.0, rise) * 0.45;
			// Floor at 0.62 rather than 0.45: the trough of the beat used to take the
			// word most of the way to `deep`, and a title that goes nearly black twice
			// a second reads as a flicker fault rather than as a forge.
			col = mix(deep.rgb, core.rgb, 0.62 + 0.30 * beat);
			col = mix(col, accent.rgb, heat);
			col += pale.rgb * sweep(uv.x, 0.13, 0.09, 0.0) * 0.30;
		} else if (fx == 1) {
			// ARCANE MAGUS - lit from inside. Deep at the rim, core through the
			// middle, with a slow inner swell. The brightness is spent on the CENTRE
			// of the glyph band rather than on a sweep, which is what makes it read as
			// glow rather than as polish.
			float centre = 1.0 - abs(band - 0.5) * 2.0;
			float swell = 0.62 + 0.38 * sin(t * 1.15);
			col = mix(deep.rgb, core.rgb, 0.35 + 0.65 * centre);
			col += pale.rgb * centre * centre * 0.35 * swell;
			// One narrow gold thread crossing the word, so the accent dye is present
			// in the text and not only in the sigils orbiting it.
			col = mix(col, accent.rgb, sweep(uv.x, 0.07, 0.05, 0.4) * 0.35);
		} else if (fx == 2) {
			// GLACIAL SOVEREIGN - cut ice. The ramp is QUANTISED into hard steps
			// (facets) instead of poured smoothly, which is the whole difference
			// between ice and pale blue paint, and a rare glint travels across it.
			float facets = floor(band * 5.0) / 4.0;
			col = mix(core.rgb, accent.rgb, facets * 0.7);
			col = mix(col, pale.rgb, 0.25);
			// Vertical fracture lines, frozen in place per column so they read as
			// cracks in the letter rather than as noise crawling over it.
			float crack = step(0.93, hash(vec2(floor(px.x), 3.0)));
			col = mix(col, pale.rgb, crack * 0.5);
			col += pale.rgb * sweep(uv.x, 0.09, 0.05, 0.0) * 0.55;
		} else if (fx == 3) {
			// VERDANT WARDEN - soft emerald shine. The quietest of the eight on
			// purpose: this is the one a player wears for a whole session, so it gets
			// a gentle top-lit ramp and a wide, slow polish instead of a glint.
			col = mix(core.rgb, pale.rgb, (1.0 - band) * 0.5);
			col = mix(col, accent.rgb, 0.18 + 0.10 * sin(t * 0.9));
			col += pale.rgb * sweep(uv.x, 0.11, 0.16, 0.0) * 0.22;
		} else if (fx == 4) {
			// AETHER STORM - electric static. Brightness jitters per COLUMN and per
			// tenth of a second, so the word crackles without any letter moving; a
			// moving glyph reads as a rendering fault, a flickering one reads as
			// charge. Every few seconds the whole word takes a cyan strike.
			float step_t = floor(t * 9.0);
			float jitter = hash(vec2(floor(px.x) * 0.37, step_t));
			col = mix(core.rgb, accent.rgb, 0.25 + 0.55 * jitter);
			col = mix(deep.rgb, col, 0.55 + 0.45 * jitter);
			float strike = smoothstep(0.86, 1.0, hash(vec2(floor(t * 1.7), 11.0)));
			col = mix(col, pale.rgb, strike * (0.35 + 0.4 * jitter));
		} else if (fx == 5) {
			// LOTUS WEAVER - a soft bloom. Nearly the same shape as ARCANE and
			// deliberately softer: no hard accent thread, a wider centre, a slower
			// breath. The two sit next to each other in the shop and have to read as
			// "lit from within, warm" against "lit from within, cold".
			float centre = 1.0 - abs(band - 0.5) * 2.0;
			float breath = 0.7 + 0.3 * sin(t * 0.8);
			col = mix(core.rgb, pale.rgb, centre * 0.55 * breath);
			col = mix(col, accent.rgb, smoothstep(0.7, 1.0, band) * 0.30);
			col += pale.rgb * sweep(uv.x, 0.08, 0.18, 0.2) * 0.16;
		} else if (fx == 6) {
			// ALCHEMICAL EXARCH - struck gold. The highest contrast in the set: a
			// full deep-to-pale ramp down the glyph band with a rim of pale at the
			// very bottom, which is what makes cast metal read as cast, plus a narrow
			// fast glint. Loud by design; it is the gold flex.
			float ramp = smoothstep(0.0, 0.85, band);
			col = mix(pale.rgb, core.rgb, ramp);
			col = mix(col, deep.rgb, smoothstep(0.72, 1.0, band) * 0.75);
			col = mix(col, pale.rgb, smoothstep(0.94, 1.0, band));
			col = mix(col, accent.rgb, 0.18);
			col += pale.rgb * sweep(uv.x, 0.22, 0.045, 0.0) * 0.85;
		} else {
			// IRIDESCENT ASPECT - white light through a prism. The hue scrolls
			// smoothly ALONG THE WORD, so at any moment the title is a gradient of
			// every dye rather than one flashing colour; flashing is what a cheap
			// rainbow does and it is unreadable at nameplate size.
			float turns = uv.x * 0.75 - t * 0.11;
			col = spin_hue(core.rgb, turns);
			col = mix(col, spin_hue(accent.rgb, turns), 0.35);
			// Only a touch of pale: this is the one title whose whole job is colour,
			// and washing it toward white is exactly how a rainbow ends up grey.
			col = mix(col, pale.rgb, (1.0 - band) * 0.14);
			col += vec3(1.0) * sweep(uv.x, 0.19, 0.05, 0.0) * 0.40;
		}


		COLOR = vec4(col * tex.rgb, alpha);
	}
}
