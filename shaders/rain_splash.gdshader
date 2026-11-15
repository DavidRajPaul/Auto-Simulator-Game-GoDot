shader_type spatial;
// Raindrops hitting the ground round the camera (RainSplashes.gd): ONE MultiMesh, no texture.
// Every instance is a splash that repeats every `period` seconds at a new random spot within
// `radius` m of the camera (a hash of its index and cycle), so the ground fizzes everywhere with
// no CPU work. Nov 14 owner report ("the rain is very bad", white rings everywhere): a real drop
// splash is tiny and over in a tenth of a second. Each one is now a faint ring a few centimetres
// wide that lives for the first third of its cycle, plus a small crown of droplets; both are LIT,
// so at night they only show where a light falls on the road.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords, specular_disabled;

uniform float intensity = 1.0;
uniform float radius = 12.0;
uniform float period = 0.5;
uniform float life = 0.32; // share of the cycle the splash is visible
uniform float ground_y = 0.06;
uniform vec3 centre = vec3(0.0);
global uniform vec2 wind_dir;
global uniform float wind_strength;

varying float t;
varying float part;
varying vec2 uv;
varying float fade;

float h11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	float id = float(INSTANCE_ID);
	float phase = h11(id + 0.37) * period;
	float cyc = floor((TIME + phase) / period);
	t = fract((TIME + phase) / period) / life;
	// Square-root radius spreads the splashes evenly over the disc.
	float r = sqrt(h11(id * 7.13 + cyc * 3.71)) * radius;
	float a = h11(id * 1.91 + cyc * 9.17) * 6.2831853;
	vec3 at = vec3(centre.x + cos(a) * r, ground_y + 0.01, centre.z + sin(a) * r);
	part = step(0.5, UV.y);
	uv = UV;
	float tt = clamp(t, 0.0, 1.0);
	float size = part < 0.5 ? mix(0.015, 0.075, sqrt(tt)) : 0.035;
	vec3 v = VERTEX * size;
	if (part > 0.5) {
		// Crown: a few droplets thrown up a few centimetres and falling back.
		v.y = VERTEX.y * 0.06 * sin(min(tt * 1.3, 1.0) * 3.14159);
		v.xz += wind_dir * v.y * wind_strength * 0.6;
	}
	VERTEX = at + v; // world space (world_vertex_coords; the MultiMesh transforms are identity)
	NORMAL = vec3(0.0, 1.0, 0.0);
	fade = (1.0 - step(1.0, t)) * (1.0 - smoothstep(0.7, 1.0, r / radius));
}

void fragment() {
	float tt = clamp(t, 0.0, 1.0);
	float a;
	if (part < 0.5) {
		vec2 q = vec2(uv.x * 2.0 - 1.0, uv.y * 4.0 - 1.0);
		float rr = length(q);
		a = smoothstep(0.7, 0.85, rr) * (1.0 - smoothstep(0.9, 1.0, rr)) * (1.0 - tt);
	} else {
		vec2 q = vec2(uv.x * 2.0 - 1.0, (uv.y - 0.5) * 2.0);
		float drops = step(0.92, abs(sin(q.x * 7.0 + q.y * 3.0)));
		a = drops * (1.0 - q.y) * (1.0 - tt) * 0.7;
	}
	ALBEDO = vec3(0.7, 0.74, 0.78);
	ROUGHNESS = 0.2;
	ALPHA = clamp(a * 0.55 * fade * intensity, 0.0, 1.0);
}
