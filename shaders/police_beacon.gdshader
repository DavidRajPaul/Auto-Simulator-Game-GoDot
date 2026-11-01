shader_type spatial;
// Police jeep roof light bar (bolero_police.glb surface "Beacon"): the left lamp flashes red,
// the right lamp blue, in a quick double-flash that alternates sides, like Chennai patrol
// jeeps. Unshaded + emissive so it reads at noon and glows at night. One draw call.
render_mode unshaded, cull_back;

uniform float rate = 1.6; // cycles per second
varying float side;

void vertex() {
	side = VERTEX.x;
}

float flashes(float t) {
	// Two short flashes in the first half of the cycle.
	float f = fract(t);
	return step(f, 0.12) + step(0.2, f) * step(f, 0.32);
}

void fragment() {
	float t = TIME * rate;
	float on = side < 0.0 ? flashes(t) : flashes(t + 0.5);
	vec3 lamp = COLOR.rgb;
	ALBEDO = lamp * mix(0.35, 2.4, clamp(on, 0.0, 1.0));
}
