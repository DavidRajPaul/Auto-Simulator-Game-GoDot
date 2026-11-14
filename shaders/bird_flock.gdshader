shader_type spatial;
// Crows, pigeons and kites over the street (BirdFlock.gd): ONE MultiMesh, no texture.
// Each instance's transform is the centre of its circle; INSTANCE_CUSTOM = (radius m,
// angular speed rad/s, phase rad, flap rate Hz). The vertex shader flies the bird round the
// circle (nose along the tangent), banks it into the turn and flaps the wings: UV.x is how far
// out along the wing a vertex sits (0 body, 1 tip). Colour per bird from INSTANCE COLOR.
render_mode cull_disabled, specular_disabled;

varying vec3 v_col;

void vertex() {
	float r = INSTANCE_CUSTOM.x;
	float w = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
	float rate = INSTANCE_CUSTOM.w;
	float a = phase + w * TIME;
	// Flap: flapping birds beat steadily, kites (rate < 0.5) glide with a slow wobble.
	float beat = sin(TIME * rate * 6.2831 + phase * 7.0);
	float glide = step(0.5, rate) * smoothstep(-0.2, 0.6, sin(TIME * 0.35 + phase));
	float flap = mix(0.18 * sin(TIME * 1.3 + phase), beat * 0.75, step(0.5, rate) * (1.0 - glide * 0.85));
	vec3 v = VERTEX;
	v.y += flap * abs(v.x) * UV.x;
	// Bank into the turn, then face along the circle's tangent.
	float bank = -0.35 * sign(w);
	v = vec3(v.x * cos(bank) - v.y * sin(bank), v.x * sin(bank) + v.y * cos(bank), v.z);
	vec3 fwd = vec3(-sin(a), 0.0, cos(a)) * sign(w);
	vec3 side = vec3(fwd.z, 0.0, -fwd.x);
	v = side * v.x + vec3(0.0, v.y, 0.0) + fwd * v.z;
	v += vec3(cos(a) * r, 0.6 * sin(TIME * 0.4 + phase), sin(a) * r);
	VERTEX = v;
	v_col = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.9;
}
