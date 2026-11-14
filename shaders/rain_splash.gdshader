shader_type spatial;
// Raindrops hitting the ground round the camera (RainSplashes.gd): ONE MultiMesh, no texture.
// Every instance is a splash that repeats every `period` seconds at a new random spot within
// `radius` m of the camera (a hash of its index and cycle), so the ground fizzes everywhere with
// no CPU work. Each splash is a small ring spreading on the ground (UV.y < 0.5) and a crown of
// spray thrown up on two crossed cards (UV.y > 0.5). Wind leans the spray.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, world_vertex_coords;

uniform float intensity = 1.0;
uniform float radius = 22.0;
uniform float period = 0.42;
uniform float ground_y = 0.06;
uniform vec3 centre = vec3(0.0);
global uniform vec2 wind_dir;
global uniform float wind_strength;

varying float t;
varying float part;
varying vec2 uv;

float h11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	float id = float(INSTANCE_ID);
	float phase = h11(id + 0.37) * period;
	float cyc = floor((TIME + phase) / period);
	t = fract((TIME + phase) / period);
	// Square-root radius spreads the splashes evenly over the disc.
	float r = sqrt(h11(id * 7.13 + cyc * 3.71)) * radius;
	float a = h11(id * 1.91 + cyc * 9.17) * 6.2831853;
	vec3 at = vec3(centre.x + cos(a) * r, ground_y + 0.012, centre.z + sin(a) * r);
	part = step(0.5, UV.y);
	uv = UV;
	float size = mix(0.05, 0.24, t) * (part < 0.5 ? 1.0 : 0.0) + (part > 0.5 ? 0.12 : 0.0);
	vec3 v = VERTEX * size;
	if (part > 0.5) {
		// Spray: rises and falls once per cycle, leaning with the wind.
		v.y = VERTEX.y * 0.17 * sin(min(t * 1.6, 1.0) * 3.14159);
		v.xz += wind_dir * v.y * wind_strength * 0.8;
	}
	VERTEX = at + v; // world space (world_vertex_coords; the MultiMesh transforms are identity)
}

void fragment() {
	float a;
	if (part < 0.5) {
		vec2 q = vec2(uv.x * 2.0 - 1.0, uv.y * 4.0 - 1.0);
		float rr = length(q);
		a = smoothstep(0.55, 0.78, rr) * (1.0 - smoothstep(0.86, 1.0, rr)) * (1.0 - t * t);
	} else {
		vec2 q = vec2(uv.x * 2.0 - 1.0, (uv.y - 0.5) * 2.0);
		// A few thin droplets fanning out of the crown.
		float rays = abs(sin(q.x * 9.0)) ;
		a = smoothstep(0.65, 0.95, rays) * (1.0 - q.y) * (1.0 - smoothstep(0.6, 1.0, t)) * 0.8;
	}
	ALBEDO = vec3(0.9, 0.93, 0.97);
	ALPHA = clamp(a * 0.95 * intensity, 0.0, 1.0);
}
