shader_type canvas_item;
// Title-text VFX only. Pulse + a shine band through the glyphs.
// Does NOT draw an aura or halo around the character.
// style: 0 gem, 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 ink
//
// **UV IS NOT THE LABEL RECT**, and the shine band below is the reason this file
// had to change. A Label draws each glyph as its own quad textured from the FONT
// ATLAS, so `UV` is a coordinate into that atlas rather than a position in the
// word - which meant the band was not travelling through the title at all, it was
// jumping between wherever each character happens to sit in the atlas. It still
// flickered, so it read as a shine and nobody caught it.
//
// `local` carries VERTEX - the fragment's position in the LABEL's own coordinate
// space, in pixels - and `rect_size` is the label's laid-out size, which only
// GDScript knows. TitleVfxPulse refreshes it every frame because a Label resizes
// whenever its text changes. Same fix, same plumbing, as the other two title
// shaders; all three now agree on what a horizontal sweep means.
uniform vec4 glow_color : source_color = vec4(0.49, 0.75, 1.0, 1.0);
uniform float vip : hint_range(0.0, 1.0) = 0.0;
uniform float gold : hint_range(0.0, 1.0) = 0.0;
uniform float style : hint_range(0.0, 6.0) = 0.0;
// TitleVfx.OUTLINE_COLOR. A Label's outline is drawn INSIDE this same canvas
// item, so without this test the pulse and the shine band land on the dark
// backing too - the band brightens it, the glow tints it, and the contrast the
// outline exists to provide is gone. See skill_master_title.gdshader's header.
uniform vec4 outline : source_color = vec4(0.043, 0.043, 0.063, 1.0);
uniform float outline_tolerance : hint_range(0.0, 1.0) = 0.22;
// The label's laid-out size in its own units. Fed by TitleVfxPulse; see header.
uniform vec2 rect_size = vec2(1.0, 1.0);

// Position within the label, in the label's own pixels. See the header.
varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 tex = COLOR;
	if (tex.a < 0.04 || distance(tex.rgb, outline.rgb) < outline_tolerance) {
		COLOR = tex; // transparent, or the dark outline - emit unchanged
	} else {
	float pulse_amt = mix(0.07, 0.16, vip);
	float pulse_spd = mix(2.0, 3.2, vip);
	float sweep_spd = mix(0.16, 0.30, vip);
	float shine_amt = mix(0.18, 0.48, vip);
	vec3 shine_col = vec3(1.0, 0.97, 0.92);
	float gold_on = gold;
	if (style > 0.5 && style < 1.5) {
		gold_on = 1.0;
		shine_col = vec3(1.0, 0.90, 0.45);
		pulse_spd = mix(1.6, 2.4, vip);
	} else if (style > 1.5 && style < 2.5) {
		shine_col = vec3(1.0, 0.55, 0.28);
		pulse_spd = 1.5;
		sweep_spd = 0.12;
		shine_amt *= 0.7;
	} else if (style > 2.5 && style < 3.5) {
		shine_col = vec3(0.70, 0.55, 0.95);
		pulse_amt *= 0.7;
		pulse_spd = 1.4;
		shine_amt *= 0.55;
	} else if (style > 3.5 && style < 4.5) {
		shine_col = vec3(1.0, 0.96, 0.75);
		sweep_spd = mix(0.28, 0.42, vip);
		shine_amt = mix(0.35, 0.62, vip);
	} else if (style > 4.5 && style < 5.5) {
		shine_col = vec3(0.90, 0.94, 1.0);
		pulse_amt *= 0.55;
		sweep_spd = 0.14;
		shine_amt *= 0.45;
	} else if (style > 5.5) {
		shine_col = vec3(0.70, 0.95, 0.98);
		pulse_spd = 1.8;
		shine_amt *= 0.6;
	}
	if (gold_on > 0.5) {
		shine_col = vec3(1.0, 0.90, 0.45);
	}
	float pulse = 0.90 + pulse_amt * sin(TIME * pulse_spd);
	float sweep = fract(TIME * sweep_spd);
	// Label space, not UV - see the header. This is the whole fix in this file.
	float across = clamp(local.x / max(rect_size.x, 1.0), 0.0, 1.0);
	float band = 1.0 - smoothstep(0.0, mix(0.08, 0.14, vip), abs(across - sweep));
	vec3 lit = tex.rgb * pulse + shine_col * band * shine_amt;
	lit = mix(lit, glow_color.rgb, 0.06 + 0.06 * vip);
	COLOR = vec4(lit, tex.a);
	}
}
