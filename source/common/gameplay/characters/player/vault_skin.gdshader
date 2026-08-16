shader_type canvas_item;
// Prestige skin recolor + a faint pulse/shine on the BODY SPRITE.
// Vault-only. Does not spawn an aura/halo cosmetic.
// style: 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 aether, 7 toxic
uniform vec4 tint : source_color = vec4(0.91, 0.75, 0.31, 1.0);
uniform float style : hint_range(1.0, 7.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 0.55;

vec3 _rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 _hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 1.0 / 3.0, 2.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = COLOR;
	if (tex.a < 0.04) {
		COLOR = tex;
		return;
	}
	float hue_shift = 0.02;
	float sat_mul = 1.12;
	float pulse_amt = 0.06;
	float pulse_spd = 1.8;
	float sweep_spd = 0.18;
	float shine_amt = 0.22;
	vec3 shine_col = tint.rgb;
	if (style > 0.5 && style < 1.5) {
		hue_shift = 0.04;
		sat_mul = 1.18;
		shine_col = vec3(1.0, 0.90, 0.45);
	} else if (style < 2.5) {
		hue_shift = -0.04;
		sat_mul = 1.22;
		pulse_spd = 1.5;
		shine_col = vec3(1.0, 0.50, 0.22);
	} else if (style < 3.5) {
		hue_shift = 0.72;
		sat_mul = 0.95;
		pulse_amt = 0.04;
		shine_amt = 0.14;
		shine_col = vec3(0.70, 0.55, 0.95);
	} else if (style < 4.5) {
		hue_shift = 0.06;
		sat_mul = 1.10;
		sweep_spd = 0.32;
		shine_amt = 0.34;
		shine_col = vec3(1.0, 0.96, 0.75);
	} else if (style < 5.5) {
		hue_shift = 0.55;
		sat_mul = 0.78;
		pulse_amt = 0.035;
		shine_amt = 0.12;
		shine_col = vec3(0.90, 0.94, 1.0);
	} else if (style < 6.5) {
		hue_shift = 0.48;
		sat_mul = 1.08;
		shine_col = vec3(0.70, 0.95, 0.98);
	} else {
		hue_shift = 0.28;
		sat_mul = 1.25;
		pulse_spd = 2.1;
		shine_col = vec3(0.55, 0.95, 0.45);
	}
	vec3 hsv = _rgb_to_hsv(tex.rgb);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * sat_mul, 0.0, 1.0);
	vec3 shifted = _hsv_to_rgb(hsv);
	vec3 dyed = mix(shifted, tint.rgb * (shifted.r + shifted.g + shifted.b) * 0.42, strength * 0.45);
	float pulse = 0.94 + pulse_amt * sin(TIME * pulse_spd);
	float sweep = fract(TIME * sweep_spd);
	float band = 1.0 - smoothstep(0.0, 0.10, abs(UV.x - sweep));
	vec3 lit = dyed * pulse + shine_col * band * shine_amt * strength;
	COLOR = vec4(lit, tex.a);
}
