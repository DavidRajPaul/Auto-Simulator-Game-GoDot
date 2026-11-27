shader_type spatial;
// Napier Bridge LED lighting at night (owner photos, Nov 27: green, violet, blue and red arches,
// their colours mirrored in the Cooum). Mesh from LandmarkKit.napier_lights: vertex alpha =
// arch group (0, .25, .5, .75) + .125 for the reflection streaks on the water. Additive and
// unshaded, so the whole bridge's lighting is one draw call and no real lights.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float on = 1.0;
uniform float cycle_s = 6.0;

vec3 palette(int i) {
	if (i == 0) return vec3(0.10, 1.00, 0.32);   // green
	if (i == 1) return vec3(0.62, 0.22, 1.00);   // violet
	if (i == 2) return vec3(0.18, 0.42, 1.00);   // blue
	return vec3(1.00, 0.16, 0.22);               // red
}

void fragment() {
	float g = COLOR.a * 4.0 + 0.01;
	float group = floor(g);
	bool reflection = fract(g) > 0.4;
	float t = TIME / cycle_s;
	float step_t = floor(t);
	int i = int(mod(group + step_t, 4.0));
	int j = int(mod(group + step_t + 1.0, 4.0));
	vec3 c = mix(palette(i), palette(j), smoothstep(0.75, 1.0, fract(t)));
	float shimmer = reflection ? 0.55 + 0.45 * sin(TIME * 2.3 + VERTEX.x * 0.7 + VERTEX.z * 0.4) : 1.0;
	ALBEDO = c * (reflection ? 0.32 : 0.95) * shimmer * on;
}
