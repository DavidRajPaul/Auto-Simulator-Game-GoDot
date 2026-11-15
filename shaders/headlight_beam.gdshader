// The auto's headlight on the road ahead, as a lit patch (scripts/world/Atmosphere.gd). Used where
// a real SpotLight3D is too costly: on the GL Compatibility renderer every object a light touches
// is drawn again, which put night driving over the 150 draw-call budget. Quad 2 × 2 units, laid on
// the road in front of the auto; local -Z points ahead. Illuminance from a lamp ~0.6 m up:
// E ∝ h / r³ near the auto, a beam cone ±16°, and a soft cut-off at ~30 m.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float energy = 1.0;
uniform vec3 tint = vec3(1.0, 0.95, 0.82);

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	// Quad spans x ±1 (→ ±9 m) and z ±1 (→ 0 … 32 m ahead) once scaled by its node.
	float ahead = (1.0 - local.z) * 16.0; // metres from the lamp
	float side = local.x * 9.0;
	float ang = atan(abs(side), max(ahead, 0.1));
	float cone = 1.0 - smoothstep(0.2, 0.34, ang);
	float h = 0.6;
	float r2 = ahead * ahead + side * side + h * h;
	float e = h / pow(r2, 1.5) * 18.0 + 1.8 / (1.0 + r2 * 0.02);
	e *= smoothstep(0.0, 2.5, ahead) * (1.0 - smoothstep(24.0, 32.0, ahead));
	ALBEDO = tint * cone * min(e, 1.6) * 0.18 * energy;
}
