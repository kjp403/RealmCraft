shader_type canvas_item;
render_mode blend_add;
// GALAXY AURA - ACCRETION DISK. The floor layer: a black core with logarithmic
// spiral arms of indigo and violet dust winding into it.
//
// blend_add, unlike the other two pool shaders, and that choice is the look. A
// galaxy is light suspended in a void: mixing it would paint a purple disc ONTO
// the floor tiles, while adding it lets the tiles show through the gaps between
// the arms and makes the dark lanes genuinely dark. The trade is that the core
// cannot be painted black - nothing additive can darken - so the "void" is made
// by simply emitting nothing there, and the hole reads as black against the
// bright inner rim around it.
//
// The arms are logarithmic (angle offset by the log of radius), which is the
// actual shape of a spiral galaxy and the reason they keep winding convincingly
// at every radius. Arms drawn as fixed angular wedges just look like a fan blade.

uniform vec4 dust : source_color = vec4(0.28, 0.14, 0.62, 1.0);
uniform vec4 arm : source_color = vec4(0.55, 0.32, 0.95, 1.0);
uniform vec4 core : source_color = vec4(0.78, 0.72, 1.0, 1.0);
uniform float disk_pixels = 80.0;
uniform float speed = 1.0;
uniform float arms = 2.0;
uniform float strength : hint_range(0.0, 1.5) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	vec2 snapped = (floor(UV * disk_pixels) + 0.5) / disk_pixels;
	vec2 centred = (snapped - vec2(0.5)) * 2.0;
	float radius = length(centred);
	if (radius > 1.0) {
		discard;
	}
	float angle = atan(centred.y, centred.x);

	// Differential rotation: inner material laps outer material, so the arms wind
	// tighter over time exactly as a real disc shears. A single global spin makes
	// the whole thing look like a rotating sticker.
	float shear = t * (0.65 + 0.55 / max(0.18, radius));
	// Logarithmic spiral. log(radius) is what curves the arm rather than fanning it.
	float wind = angle * arms + log(max(radius, 0.04)) * 3.4 + shear;
	float spiral = 0.5 + 0.5 * sin(wind);
	// Sharpen: broad sine arms read as a soft pinwheel, not as dust lanes.
	spiral = pow(spiral, 2.6);

	// Dust grain along the arms so they are not smooth ribbons of colour.
	float grain = vnoise(vec2(wind * 1.7, radius * 9.0)) * 0.55 + 0.45;

	// The VOID. Emit nothing inside the hole; the falloff outside it is what the
	// eye reads as the event horizon.
	float hole = smoothstep(0.10, 0.30, radius);
	// Outer edge dissolves into space rather than ending.
	float outer = 1.0 - smoothstep(0.62, 1.0, radius);
	float density = spiral * grain * hole * outer;

	// Hot inner rim just outside the hole - the brightest thing in the effect and
	// the anchor that makes the dark middle read as deliberate.
	float rim = (1.0 - smoothstep(0.0, 0.14, abs(radius - 0.30))) * outer;

	vec3 col = mix(dust.rgb, arm.rgb, clamp(spiral * 1.4, 0.0, 1.0));
	col = mix(col, core.rgb, rim * 0.8);

	float alpha = clamp(density * 0.85 + rim * 0.55, 0.0, 1.0);
	// Premultiplied: an additive pass wants colour scaled by its own coverage, or
	// the dark gaps between arms still deposit full-brightness dust on the floor.
	COLOR = vec4(col * alpha, alpha * strength);
}
