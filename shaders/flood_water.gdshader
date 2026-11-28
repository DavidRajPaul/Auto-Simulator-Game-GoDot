shader_type spatial;
// Monsoon flood water standing on the streets during a quest (scripts/world/QuestFlood.gd).
// One mesh for the whole flood: COLOR.r = how wet this spot is (0 at the dry edge, 1 standing
// water), COLOR.g = depth / 0.6 m. Muddy brown water that gets darker and more opaque as it gets
// deeper, rain-drop rings all over it (procedural cells, no textures), a slow drift, sky sheen at
// grazing angles, glossy enough to catch street lights and headlights, and a ragged foam line where
// it thins out at the kerbs. Drawn before other transparents so the street-light pools on the road
// still add their light over it (they read as reflections).
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec3 shallow_water : source_color = vec3(0.36, 0.31, 0.22);
uniform vec3 deep_water : source_color = vec3(0.17, 0.15, 0.11);
uniform vec3 sky_sheen : source_color = vec3(0.6, 0.63, 0.67);
uniform vec3 foam_colour : source_color = vec3(0.62, 0.57, 0.47);
uniform float ring_cell = 0.55;
uniform float ring_rate = 1.35;
uniform float rain = 1.0;
uniform vec2 drift = vec2(0.05, 0.12);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Height slope of the rain rings in one cell layer: each cell has one drop at a random spot
// whose ring spreads and fades over its cycle. One cell per layer (the ring stays inside its
// cell), so it is two hash lookups per layer: cheap enough for a budget phone.
vec2 rings(vec2 p, float t, float seed) {
	vec2 c = floor(p);
	float h = hash(c + seed);
	vec2 centre = c + 0.5 + (vec2(hash(c + seed + 3.1), h) - 0.5) * 0.4;
	float life = fract(t * (0.8 + 0.4 * h) + h);
	vec2 d = p - centre;
	float r = length(d);
	float band = r - life * 0.3;
	float wave = exp(-band * band * 260.0) * (1.0 - life) * (1.0 - life);
	return (r > 0.0001 ? d / r : vec2(0.0)) * wave * sin(band * 70.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wet = COLOR.r;
	float depth = clamp(COLOR.g, 0.0, 1.0);
	vec2 p = world_pos.xz;
	float t = TIME * ring_rate;
	vec2 slope = (rings(p / ring_cell, t, 0.0) + rings(p / (ring_cell * 1.7) + 13.0, t * 0.8, 5.0) * 0.6) * rain;
	// The slow, wind-pushed swell under the rings.
	vec2 q = p * 0.35 + drift * TIME;
	slope += vec2(noise(q) - noise(q + vec2(0.7, 0.0)), noise(q) - noise(q + vec2(0.0, 0.7))) * 0.35;
	NORMAL_MAP = normalize(vec3(0.5 - slope.x * 0.22, 0.5 - slope.y * 0.22, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
	vec3 water = mix(shallow_water, deep_water, smoothstep(0.05, 0.7, depth));
	// Grazing angles reflect the overcast sky: a flooded street looks silver down the road and
	// muddy brown at your feet. The rain rings break the sheen up.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	fres *= clamp(1.0 - length(slope) * 0.6, 0.4, 1.0);
	water = mix(water, sky_sheen, clamp(0.08 + fres * 0.85, 0.0, 0.9));
	// Ragged foam and scum where the sheet thins out at its edge.
	float edge = smoothstep(0.15, 0.45, wet) * (1.0 - smoothstep(0.45, 0.9, wet));
	float fleck = smoothstep(0.55, 0.8, noise(p * 3.2 + drift * TIME * 2.0));
	water = mix(water, foam_colour, edge * fleck * 0.6);
	ALBEDO = water;
	ROUGHNESS = 0.07 + edge * 0.3;
	SPECULAR = 0.65;
	METALLIC = 0.0;
	ALPHA = smoothstep(0.02, 0.55, wet) * mix(0.88, 0.97, smoothstep(0.0, 0.4, depth));
}
