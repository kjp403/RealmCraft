shader_type canvas_item;
// POOL REFLECTION. Draws a (vertically flipped) sprite frame as a reflection in
// water: tinted toward the water colour, wobbled sideways in whole texel rows,
// and clipped to the pool ellipse.
//
// The clip works in the SPRITE'S LOCAL pixel space (passed down from vertex()),
// not in UV: body frames are AtlasTexture regions, so UV is a coordinate in the
// whole sheet and says nothing about where on the figure a fragment is.

uniform vec4 water : source_color = vec4(0.25, 0.55, 0.65, 1.0);
uniform float alpha = 0.4;
// Pool half-extents in local pixels, and its centre.
uniform vec2 pool_radius = vec2(26.0, 26.0);
uniform vec2 pool_centre = vec2(0.0, 4.0);
uniform float wobble_px = 0.6;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float row = floor(local_pos.y);
	float shift = sin(row * 0.9 + TIME * 3.0) * wobble_px;
	vec4 t = texture(TEXTURE, UV + vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0));
	vec2 d = (local_pos - pool_centre) / pool_radius;
	float inside = 1.0 - smoothstep(0.7, 1.0, length(d));
	// Fades with depth: the part of the figure farthest from the feet is faintest.
	float depth = 1.0 - clamp(abs(local_pos.y - pool_centre.y) / pool_radius.y, 0.0, 1.0);
	vec3 col = mix(t.rgb, water.rgb, 0.45);
	COLOR = vec4(col, t.a * alpha * inside * (0.35 + 0.65 * depth));
}
