shader_type canvas_item;
// Pixel-art palette swap, not a tint wash.
// Keeps outlines, faces, leather, tusks/beards, and cyan eye-glints.
// Armor and cloth remap through a 4-stop ramp so the sprite still reads.
// style: 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 aether, 7 toxic,
// 8 crimson, 9 frost, 10 verdant, 11 sapphire, 12 rose, 13 obsidian,
// 14 copper, 15 ghost, 16 amber
uniform vec4 tint : source_color = vec4(0.94, 0.78, 0.29, 1.0);
uniform float style : hint_range(1.0, 16.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float keep_flesh : hint_range(0.0, 1.0) = 1.0;

vec3 _rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 _ramp4(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.33) {
		return mix(a, b, t / 0.33);
	} else if (t < 0.66) {
		return mix(b, c, (t - 0.33) / 0.33);
	}
	return mix(c, d, (t - 0.66) / 0.34);
}

void fragment() {
	vec4 tex = COLOR;
	if (tex.a < 0.04) {
		COLOR = tex;
	} else {
		vec3 orig = tex.rgb;
		vec3 hsv = _rgb_to_hsv(orig);
		float hue = hsv.x;
		float sat = hsv.y;
		float luma = dot(orig, vec3(0.299, 0.587, 0.114));

		float keep = 0.0;
		if (luma < 0.16 && sat < 0.42) {
			keep = 1.0;
		}
		if (keep_flesh > 0.5 && hue > 0.018 && hue < 0.11 && sat > 0.16 && sat < 0.72 && luma > 0.28 && luma < 0.82) {
			keep = 1.0;
		}
		if (luma > 0.82 && sat < 0.22) {
			keep = 1.0;
		}
		if (hue > 0.045 && hue < 0.12 && sat > 0.32 && sat < 0.88 && luma > 0.20 && luma < 0.62) {
			keep = 1.0;
		}
		if (hue > 0.48 && hue < 0.56 && sat > 0.72 && luma > 0.62) {
			keep = 1.0;
		}

		vec3 shadow = vec3(0.22, 0.12, 0.04);
		vec3 midc = vec3(0.72, 0.48, 0.10);
		vec3 light = vec3(0.93, 0.74, 0.22);
		vec3 hi = vec3(1.0, 0.94, 0.70);
		vec3 accent = vec3(0.72, 0.22, 0.16);
		vec3 shine = vec3(1.0, 0.90, 0.55);
		float pulse_amt = 0.0;
		float pulse_spd = 1.8;
		if (style > 1.5 && style < 2.5) {
			shadow = vec3(0.08, 0.03, 0.02);
			midc = vec3(0.42, 0.09, 0.05);
			light = vec3(0.88, 0.28, 0.08);
			hi = vec3(1.0, 0.78, 0.42);
			accent = vec3(1.0, 0.82, 0.38);
			shine = vec3(1.0, 0.55, 0.18);
			pulse_amt = 0.07;
			pulse_spd = 2.2;
		} else if (style > 2.5 && style < 3.5) {
			shadow = vec3(0.05, 0.03, 0.08);
			midc = vec3(0.23, 0.14, 0.38);
			light = vec3(0.48, 0.38, 0.78);
			hi = vec3(0.86, 0.78, 1.0);
			accent = vec3(1.0, 0.50, 0.82);
			shine = vec3(0.78, 0.62, 1.0);
			pulse_amt = 0.04;
		} else if (style > 3.5 && style < 4.5) {
			shadow = vec3(0.06, 0.08, 0.16);
			midc = vec3(0.16, 0.22, 0.44);
			light = vec3(0.78, 0.66, 0.28);
			hi = vec3(1.0, 0.94, 0.75);
			accent = vec3(0.95, 0.82, 0.40);
			shine = vec3(1.0, 0.95, 0.72);
		} else if (style > 4.5 && style < 5.5) {
			shadow = vec3(0.05, 0.08, 0.11);
			midc = vec3(0.16, 0.25, 0.35);
			light = vec3(0.53, 0.64, 0.74);
			hi = vec3(0.91, 0.95, 1.0);
			accent = vec3(0.75, 0.56, 1.0);
			shine = vec3(0.88, 0.94, 1.0);
		} else if (style > 5.5 && style < 6.5) {
			shadow = vec3(0.03, 0.14, 0.18);
			midc = vec3(0.06, 0.48, 0.55);
			light = vec3(0.22, 0.86, 0.90);
			hi = vec3(0.82, 1.0, 1.0);
			accent = vec3(0.88, 0.32, 0.62);
			shine = vec3(0.45, 0.95, 1.0);
		} else if (style > 6.5 && style < 7.5) {
			shadow = vec3(0.03, 0.06, 0.03);
			midc = vec3(0.11, 0.34, 0.09);
			light = vec3(0.41, 0.88, 0.25);
			hi = vec3(0.85, 1.0, 0.53);
			accent = vec3(0.82, 1.0, 0.25);
			shine = vec3(0.45, 1.0, 0.32);
			pulse_amt = 0.05;
			pulse_spd = 2.5;
		} else if (style > 7.5 && style < 8.5) {
			shadow = vec3(0.14, 0.02, 0.04);
			midc = vec3(0.55, 0.08, 0.12);
			light = vec3(0.88, 0.20, 0.24);
			hi = vec3(1.0, 0.62, 0.58);
			accent = vec3(1.0, 0.40, 0.30);
			shine = vec3(1.0, 0.45, 0.40);
		} else if (style > 8.5 && style < 9.5) {
			shadow = vec3(0.10, 0.16, 0.22);
			midc = vec3(0.42, 0.62, 0.78);
			light = vec3(0.78, 0.90, 1.0);
			hi = vec3(0.96, 0.99, 1.0);
			accent = vec3(0.55, 0.82, 1.0);
			shine = vec3(0.85, 0.95, 1.0);
		} else if (style > 9.5 && style < 10.5) {
			shadow = vec3(0.04, 0.10, 0.04);
			midc = vec3(0.12, 0.38, 0.16);
			light = vec3(0.28, 0.70, 0.38);
			hi = vec3(0.72, 0.95, 0.58);
			accent = vec3(0.55, 0.90, 0.30);
			shine = vec3(0.55, 1.0, 0.45);
		} else if (style > 10.5 && style < 11.5) {
			shadow = vec3(0.04, 0.08, 0.22);
			midc = vec3(0.10, 0.28, 0.72);
			light = vec3(0.28, 0.52, 1.0);
			hi = vec3(0.72, 0.84, 1.0);
			accent = vec3(0.40, 0.70, 1.0);
			shine = vec3(0.55, 0.75, 1.0);
		} else if (style > 11.5 && style < 12.5) {
			shadow = vec3(0.22, 0.06, 0.12);
			midc = vec3(0.72, 0.28, 0.42);
			light = vec3(0.95, 0.52, 0.68);
			hi = vec3(1.0, 0.82, 0.88);
			accent = vec3(1.0, 0.45, 0.62);
			shine = vec3(1.0, 0.70, 0.82);
		} else if (style > 12.5 && style < 13.5) {
			shadow = vec3(0.04, 0.04, 0.06);
			midc = vec3(0.14, 0.14, 0.18);
			light = vec3(0.38, 0.40, 0.48);
			hi = vec3(0.78, 0.80, 0.88);
			accent = vec3(0.70, 0.72, 0.82);
			shine = vec3(0.90, 0.92, 1.0);
		} else if (style > 13.5 && style < 14.5) {
			shadow = vec3(0.16, 0.07, 0.03);
			midc = vec3(0.55, 0.28, 0.10);
			light = vec3(0.82, 0.48, 0.22);
			hi = vec3(1.0, 0.78, 0.50);
			accent = vec3(0.90, 0.40, 0.18);
			shine = vec3(1.0, 0.72, 0.40);
		} else if (style > 14.5 && style < 15.5) {
			shadow = vec3(0.16, 0.16, 0.18);
			midc = vec3(0.42, 0.44, 0.48);
			light = vec3(0.72, 0.74, 0.78);
			hi = vec3(0.92, 0.93, 0.95);
			accent = vec3(0.80, 0.84, 0.90);
			shine = vec3(0.95, 0.96, 1.0);
		} else if (style > 15.5) {
			shadow = vec3(0.22, 0.10, 0.02);
			midc = vec3(0.78, 0.40, 0.08);
			light = vec3(1.0, 0.68, 0.22);
			hi = vec3(1.0, 0.90, 0.55);
			accent = vec3(1.0, 0.55, 0.20);
			shine = vec3(1.0, 0.80, 0.40);
		}

		float q = clamp((luma - 0.10) / 0.80, 0.0, 1.0);
		vec3 dyed;
		if (hue > 0.84 && hue < 0.95 && sat > 0.58 && luma > 0.32 && luma < 0.78) {
			dyed = mix(shadow, accent, q);
		} else {
			dyed = _ramp4(q, shadow, midc, light, hi);
		}

		float pulse = 1.0 + pulse_amt * sin(TIME * pulse_spd);
		dyed *= pulse;
		float spec = smoothstep(0.58, 0.92, luma) * (0.05 + 0.07 * (0.5 + 0.5 * sin(TIME * 1.7)));
		dyed += shine * spec;

		vec3 outc = mix(orig, mix(orig, dyed, strength), 1.0 - keep);
		COLOR = vec4(outc, tex.a);
	}
}
