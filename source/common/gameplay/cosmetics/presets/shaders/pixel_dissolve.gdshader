shader_type canvas_item;
render_mode blend_mix;
// CHRONO ECHO - PIXEL-BLOCK DISSOLVE. Eats an after-image away in square blocks
// instead of fading it, so a ghost comes apart into pixels rather than turning
// translucent and vanishing.
//
// Blocks are measured in TEXELS, not in UV. That is not a detail: the ghosts are
// drawn from SpriteFrames, whose frames are AtlasTexture regions, so UV spans the
// frame's slice of the atlas and not 0..1. Quantising UV directly would give a
// different block size for every skin depending on where its frame happens to sit
// in its sheet. UV / TEXTURE_PIXEL_SIZE is the texel coordinate, and quantising
// THAT gives the same physical block on every sprite in the game.
//
// Nothing is offset or displaced, however tempting. Sampling a neighbouring texel
// to make blocks drift apart would reach outside the frame's atlas region and
// pull in whatever animation frame is stored next to it.

// Block edge in source texels. 2 on 64 px art is a chunky, obviously-deliberate
// pixel; 1 reads as noise and 4 destroys the silhouette before it is recognised.
uniform float block_px = 2.0;
// 0 = whole ghost, 1 = fully gone.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);
// How hard the ghost is pushed toward the tint. 1.0 discards the sprite's own
// colours entirely, which is what keeps an after-image from being mistaken for a
// second player standing there.
uniform float tint_mix : hint_range(0.0, 1.0) = 0.82;
uniform float alpha : hint_range(0.0, 1.0) = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	// The sprite's own transparency still decides the silhouette - the dissolve
	// only removes from what was already there.
	if (src.a < 0.01) {
		discard;
	}

	vec2 texel = UV / TEXTURE_PIXEL_SIZE;
	vec2 block = floor(texel / max(block_px, 1.0));
	float roll = hash(block);

	// Each block has its own moment of death. Blocks with a low roll go first, so
	// the ghost erodes unevenly rather than thinning all over at once.
	if (roll < progress) {
		discard;
	}

	// A block flares just before it goes. Without this the dissolve is a silent
	// subtraction; with it, the eye is drawn to the edge that is coming apart.
	float doomed = smoothstep(0.14, 0.0, roll - progress);

	vec3 col = mix(src.rgb, tint.rgb, tint_mix);
	col = mix(col, vec3(1.0), doomed * 0.75);

	// Overall alpha holds steady and only drops at the very end. The dissolve is
	// supposed to do the disappearing; fading as well just makes it mush.
	float fade = 1.0 - smoothstep(0.75, 1.0, progress);
	COLOR = vec4(col, src.a * alpha * fade);
}
