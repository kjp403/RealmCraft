shader_type canvas_item;
render_mode blend_mix;
// BLOOD AURA - SCREEN VIGNETTE. A dark red pulse around the edges of the OWNER'S
// screen while the Blood aura is worn.
//
// Two hard rules govern this file, both about not hurting the player wearing it:
//
//   ONLY THE OWNER   BloodVignette is mounted only when the wearer is the local
//                    player. A cosmetic that tinted a bystander's screen would
//                    let anyone standing next to you dim your game.
//   NEVER THE MIDDLE The centre is untouched at any pulse strength. This is a
//                    cosmetic worn for hours, and a full-screen red wash over the
//                    play area would fight every real damage and low-health cue
//                    the HUD has. Darkening only the corners reads as dread
//                    without ever competing with a gameplay signal.
//
// The pulse is slow (roughly a resting heartbeat) and shallow. If it is ever
// noticeable enough to draw the eye away from the fight, it is too strong.

uniform vec4 tint : source_color = vec4(0.32, 0.0, 0.02, 1.0);
// Peak alpha at the very corners. Kept low deliberately - see the header.
uniform float depth : hint_range(0.0, 0.6) = 0.30;
// Fraction of the screen radius that stays completely clear.
uniform float clear_radius : hint_range(0.1, 0.9) = 0.55;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Distance from screen centre, normalised so the corners sit near 1.
	vec2 centred = (UV - vec2(0.5)) * 2.0;
	// Squash x so the band hugs the frame on a wide screen instead of pinching in
	// at the sides on ultrawide and leaving the top and bottom bare.
	centred.x *= 0.82;
	float d = length(centred) / 1.32;

	float band = smoothstep(clear_radius, 1.0, d);
	// Square it: a linear ramp still darkens a lot of usable screen, while the
	// squared one keeps almost all of the falloff out in the corners.
	band *= band;

	// Heartbeat: a slow double-thump rather than a sine, so it reads as a pulse
	// and not as a fade in and out.
	float beat = pulse;
	float alpha = band * depth * (0.72 + 0.28 * beat);
	COLOR = vec4(tint.rgb, clamp(alpha, 0.0, 1.0));
}
