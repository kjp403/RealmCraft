shader_type canvas_item;
render_mode blend_mix;
// VIP DONATION TITLE TEXT. Cast-metal lettering with a travelling polish sweep.
//
// A third title shader, and the split is the same one that already separates the
// other two. title_vfx.gdshader modulates a colour the label already has;
// skill_master_title.gdshader paints eleven bespoke gradients selected by an
// index. Neither shape fits here: the four VIP tiers all want the SAME treatment
// - a vertical metal ramp plus a specular band - differing only in the numbers.
// So this file has no branches at all. Every tier is a set of uniforms, fed from
// its VipTierProfile .tres, and adding a fifth tier is a new .tres and nothing
// else.
//
// THE OUTLINE MUST BE PASSED THROUGH. Godot draws a Label's font outline into
// this same canvas item, so those fragments arrive here too, and repainting them
// with the metal ramp overwrites the dark backing TitleVfx.OUTLINE_COLOR exists
// to provide. That backing is the only thing keeping a bright title readable
// over pale desert sand or snow. Outline fragments are told apart by colour: the
// glyph is drawn white and the outline near-black.
//
// **UV IS NOT THE LABEL RECT.** This is the one thing to know before editing
// anything below. A Label draws each glyph as its own quad textured from the
// FONT ATLAS, so `UV` here is a coordinate into that atlas - UV.y measures near
// zero over every glyph of every title, and UV.x wanders with where a character
// sits in the atlas rather than with where it sits in the word. A ramp written
// against UV.y is not subtle, it is DEAD: every fragment clamps to the same end
// of it and all four tiers render as their metal_high, which is near-white for
// three of them. That is exactly what the first capture of this looked like, and
// it reads as "the gradient is too subtle" rather than as a bug - which is why
// it is worth this many lines of comment.
//
// The fix is `local`, a varying carrying VERTEX - the fragment's position in the
// LABEL's own coordinate space, in pixels - divided by the label's size, which
// only GDScript knows and so arrives as `rect_size`. TitleVfxPulse refreshes that
// uniform every frame precisely because a Label resizes whenever its text
// changes.

// The vertical ramp, crown -> body -> base. See VipTierProfile.
uniform vec4 metal_high : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 metal_mid : source_color = vec4(0.80, 0.80, 0.80, 1.0);
uniform vec4 metal_low : source_color = vec4(0.40, 0.40, 0.40, 1.0);
uniform vec4 sheen : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// TitleVfx.OUTLINE_COLOR, or the tier's override. Fragments matching it are the
// font outline and are emitted untouched - see the header.
uniform vec4 outline : source_color = vec4(0.043, 0.043, 0.063, 1.0);
// How close a fragment must be to `outline` to count as outline rather than
// glyph. Wide enough to survive the outline's own anti-aliased edge, far
// narrower than the distance to any tier's metal.
uniform float outline_tolerance : hint_range(0.0, 1.0) = 0.22;
// The label's laid-out size in its own units. Fed by TitleVfxPulse; see header.
uniform vec2 rect_size = vec2(1.0, 1.0);

uniform float sweep_speed = 0.24;
uniform float sweep_width : hint_range(0.02, 0.4) = 0.10;
uniform float sheen_amount : hint_range(0.0, 1.2) = 0.45;
uniform float pulse_amount : hint_range(0.0, 0.4) = 0.08;
uniform float pulse_speed = 2.2;
uniform float grain : hint_range(0.0, 1.0) = 0.0;
uniform float prism : hint_range(0.0, 1.0) = 0.0;
// CUT STONE. Quantises the metal ramp into this many hard steps, so the letters
// read as faceted rather than moulded - the single biggest difference between
// "shiny blue text" and "text carved out of a gem". 0 leaves the ramp smooth,
// which is what every tier but Diamond wants: gold and silver are POURED.
uniform float facets : hint_range(0.0, 12.0) = 0.0;
// Dispersion. Tints the polish band through the spectrum instead of through
// `sheen`, which is what makes a diamond throw colour it does not have. Costs a
// three-channel fold per fragment and is off (0) everywhere else.
uniform float fire : hint_range(0.0, 1.0) = 0.0;
// A second, faster polish band crossing the first. 0 = off. Two glints at
// different speeds stop the sweep reading as a metronome, which is exactly how a
// single band on a short word reads once you have watched it for a few seconds.
uniform float sweep_speed2 = 0.0;
// Seconds, driven from TitleVfxPulse rather than TIME. A Label does not redraw
// on its own, so TIME advances while the visible result does not.
uniform float t = 0.0;

// Position within the label, in the label's own pixels. See the header.
varying vec2 local;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One edge of the polish band. Split out because the prismatic tiers evaluate it
// three times at slightly different offsets to fan the sweep into colour.
float band(float axis, float centre) {
	return 1.0 - smoothstep(0.0, sweep_width, abs(axis - centre));
}

// Hue -> RGB, the cheap fold. Full-saturation spectrum; the caller mixes it back
// toward `sheen` by `fire` rather than using it neat, because a title that goes
// full rainbow stops reading as a gem and starts reading as a party.
vec3 spectrum(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
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
		// Remap onto the GLYPH BAND rather than the whole label. A Label reserves
		// ascent and descent room around its line, so the letters occupy only the
		// middle of its height - a ramp run over the full 0..1 spends part of its
		// range on empty space and delivers a washed-out sliver of itself to the
		// text.
		float v = clamp((uv.y - 0.22) / 0.56, 0.0, 1.0);

		// Cast metal. A narrow bright crown, the tier's own colour through the
		// body, a dark base, then a rim of the crown colour caught along the very
		// bottom edge - that bottom catch-light is what separates chiselled
		// lettering from a flat vertical fade.
		//
		// The crown is narrow ON PURPOSE. Every tier's metal_high is near-white by
		// definition, so a wide crown paints most of the letters white and Diamond,
		// Platinum and Silver become the same title with different sparkles.
		// Facet the ramp BEFORE sampling it, so the steps land as flat planes of
		// colour with hard edges between them. Quantising the output instead would
		// posterise a smooth gradient, which looks like a colour-depth bug rather
		// than like a cut surface. `v` itself stays smooth below - the sweep has to
		// travel continuously across the facets, not jump between them.
		float mv = v;
		if (facets >= 1.0) {
			mv = floor(v * facets) / max(facets - 1.0, 1.0);
		}
		vec3 metal = mix(metal_high.rgb, metal_mid.rgb, smoothstep(0.0, 0.26, mv));
		metal = mix(metal, metal_low.rgb, smoothstep(0.40, 0.92, mv));
		// The rim is narrow for the mirrored reason: widening it eats back into the
		// run of metal_low above and the ramp collapses to a flat mid tone.
		metal = mix(metal, metal_high.rgb, smoothstep(0.93, 1.0, mv) * 0.55);

		// Tarnish. Quantised to whole label pixels rather than sampled per fragment
		// so it reads as pitting in the metal at pixel-art scale instead of as
		// television static under the nameplate's heavy downscale.
		if (grain > 0.001) {
			float n = hash21(floor(local));
			metal *= 1.0 - grain * 0.42 * n;
		}

		// Slow breath through the whole word.
		metal *= 1.0 - pulse_amount + pulse_amount * sin(t * pulse_speed);

		// The polish sweep. Slightly diagonal - a band travelling dead horizontal
		// across a line of text reads as a scanline, tilting it reads as light
		// moving over a surface.
		float axis = uv.x * 0.84 + v * 0.16;
		float centre = fract(t * sweep_speed);
		vec3 spec = vec3(band(axis, centre));
		if (prism > 0.001) {
			// Refraction, faked. The renderer is GL Compatibility, where
			// hint_screen_texture samples solid black, so there is no real
			// screen-space refraction available in 2D here at any price. Fanning
			// the band's channels apart gives the prismatic edge additively, which
			// is the whole trick.
			float split = prism * 0.045;
			spec = vec3(band(axis, centre + split), spec.g, band(axis, centre - split));
		}
		if (sweep_speed2 > 0.001) {
			// Offset half a cycle so the two bands cross mid-word rather than
			// chasing each other off the same edge.
			spec += vec3(band(axis, fract(t * sweep_speed2 + 0.5))) * 0.75;
		}

		// The band's colour. `fire` walks it through the spectrum along the word
		// and over time, so a facet catches green where its neighbour caught
		// violet - which is the read that separates cut stone from polished metal.
		vec3 spec_col = sheen.rgb;
		if (fire > 0.001) {
			spec_col = mix(sheen.rgb, spectrum(fract(axis * 1.6 + t * 0.11)), fire);
		}

		vec3 lit = metal * tex.rgb + spec_col * spec * sheen_amount;
		COLOR = vec4(lit, tex.a);
	}
}
