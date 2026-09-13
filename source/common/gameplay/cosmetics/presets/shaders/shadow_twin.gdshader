shader_type canvas_item;
// SHADOW TWIN. Paints a sprite frame as a flat silhouette with a one-pixel lit
// rim just OUTSIDE its edge, and a slow band of light climbing through it.
//
// The rim samples the four neighbours of every transparent texel: if any of them
// is solid, this texel is the outline. That only works because the body frames
// have empty margin round the figure - which the 64 px player cells do - so the
// neighbour samples never reach into the next frame of the atlas.

uniform vec4 fill : source_color = vec4(0.10, 0.06, 0.18, 1.0);
uniform vec4 rim : source_color = vec4(0.62, 0.45, 1.0, 1.0);
uniform float alpha = 0.78;
uniform float sheen_speed = 0.45;

void fragment() {
	float a = step(0.5, texture(TEXTURE, UV).a);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float n = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
		+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).a
		+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float edge = step(0.5, n) * (1.0 - a);
	// A soft band sweeping up the body, in texel rows so it steps like pixel art.
	float row = floor(UV.y / px.y);
	float band = 0.5 + 0.5 * sin(row * 0.35 + TIME * sheen_speed * 6.2831);
	vec3 body = mix(fill.rgb, rim.rgb, 0.18 * band * band * band);
	vec3 col = mix(body, rim.rgb, edge);
	COLOR = vec4(col, max(a, edge) * alpha);
}
