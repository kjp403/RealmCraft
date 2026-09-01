shader_type canvas_item;
// Targeted palette swap for the Wayfarer: recolors ONLY the Scholar's blue robe
// into a magenta/pink palette and leaves every other pixel exactly as authored.
//
// Why a band swap and not `modulate`: modulate multiplies every channel, so a
// pink tint would also stain the face, the red sash, the gold trim and the black
// outline — the sprite turns into a pink blob and the silhouette stops reading.
// Sampling the four scholar_cataloguer sheets shows the art is a 17-colour
// indexed palette whose robe is exactly three blues:
//     #2569C4 (h .595 s .81 v .77)  light
//     #11407E (h .595 s .87 v .49)  mid
//     #0C2950 (h .596 s .85 v .31)  shadow
// and whose only other blue-ish pixels are DESATURATED greys (#2B3842 / #1C2328
// / #395062, s .30-.42). So "hue near .595 AND saturated" isolates the robe
// cleanly, and remapping through a value-keyed ramp keeps the original shading
// — the shadow fold stays a fold instead of flattening into one flat pink.
//
// GL Compatibility / web safe: plain arithmetic, no screen texture, no
// derivatives (see docs — hint_screen_texture is dead in 2D here).

// Hue band to capture, in turns. Default centres on the robe's .595.
uniform float hue_center : hint_range(0.0, 1.0) = 0.595;
uniform float hue_width : hint_range(0.0, 0.5) = 0.055;
// Saturation floor that separates the robe from the blue-grey leather/props.
uniform float min_sat : hint_range(0.0, 1.0) = 0.60;
// Source value range the robe occupies, mapped onto the ramp below.
uniform float val_low : hint_range(0.0, 1.0) = 0.26;
uniform float val_high : hint_range(0.0, 1.0) = 0.84;
// The replacement ramp, dark -> bright. Defaults are the requested pink palette,
// topping out at #FF1493 (deep pink) with a #FF69B4 (hot pink) highlight.
uniform vec3 robe_shadow : source_color = vec3(0.431, 0.043, 0.259); // #6E0B42
uniform vec3 robe_mid : source_color = vec3(0.761, 0.078, 0.435);    // #C2146F
uniform vec3 robe_light : source_color = vec3(1.0, 0.078, 0.576);    // #FF1493
uniform vec3 robe_hi : source_color = vec3(1.0, 0.412, 0.706);       // #FF69B4
// Blend against the original, so the effect can be dialled back or previewed.
uniform float strength : hint_range(0.0, 1.0) = 1.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Four-stop ramp: dark fold -> mid cloth -> lit cloth -> highlight.
vec3 ramp4(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.34) {
		return mix(a, b, t / 0.34);
	} else if (t < 0.67) {
		return mix(b, c, (t - 0.34) / 0.33);
	}
	return mix(c, d, (t - 0.67) / 0.33);
}

void fragment() {
	vec4 tex = COLOR; // texture sample * modulate, so modulate still layers on top
	if (tex.a < 0.04) {
		COLOR = tex;
	} else {
		vec3 hsv = rgb_to_hsv(tex.rgb);
		// Shortest distance around the hue wheel, so a band across the 0/1 seam
		// still works if this shader is reused for a red-robed NPC later.
		float dh = abs(fract(hsv.x - hue_center + 0.5) - 0.5);
		// Soft edges rather than a hard cutoff: nearest-neighbour art never
		// lands between palette entries, but a filtered/scaled draw can.
		float in_hue = 1.0 - smoothstep(hue_width * 0.75, hue_width, dh);
		float in_sat = smoothstep(min_sat - 0.12, min_sat, hsv.y);
		float mask = in_hue * in_sat * strength;

		float t = clamp((hsv.z - val_low) / max(val_high - val_low, 1.0e-4), 0.0, 1.0);
		vec3 dyed = ramp4(t, robe_shadow, robe_mid, robe_light, robe_hi);
		COLOR = vec4(mix(tex.rgb, dyed, mask), tex.a);
	}
}
