shader_type canvas_item;
// Title-text VFX only. Pulse + a shine band through the glyphs.
// Does NOT draw an aura or halo around the character.
// style: 0 gem, 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 ink
uniform vec4 glow_color : source_color = vec4(0.49, 0.75, 1.0, 1.0);
uniform float vip : hint_range(0.0, 1.0) = 0.0;
uniform float gold : hint_range(0.0, 1.0) = 0.0;
uniform float style : hint_range(0.0, 6.0) = 0.0;

void fragment() {
	vec4 tex = COLOR;
	if (tex.a < 0.04) {
		COLOR = tex;
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
	float band = 1.0 - smoothstep(0.0, mix(0.08, 0.14, vip), abs(UV.x - sweep));
	vec3 lit = tex.rgb * pulse + shine_col * band * shine_amt;
	lit = mix(lit, glow_color.rgb, 0.06 + 0.06 * vip);
	COLOR = vec4(lit, tex.a);
	}
}
