shader_type spatial;
// Low-poly water for canals, ponds and temple tanks (mesh from tools/osm/build_water.py).
// Mobile-cheap: the mesh is a ~4 m triangle lattice; vertices bob on three slow sine waves and
// every triangle is shaded FLAT (normal from screen-space derivatives), which gives the faceted
// low-poly glitter. UV.x carries the distance to the bank: shallow -> deep colour, a soft foam
// band at the bank, and the shore vertices stay still so the water never pokes through walls.
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_colour : source_color = vec3(0.24, 0.52, 0.47);
uniform vec3 deep_colour : source_color = vec3(0.07, 0.25, 0.30);
uniform vec3 foam_colour : source_color = vec3(0.86, 0.92, 0.88);
uniform float deep_at_m = 9.0;
uniform float foam_m = 0.9;
uniform float wave_height = 0.11;
uniform float wave_speed = 0.6;
// 0 dry -> 1 monsoon: choppier, browner (run-off), set by WorldChunkStreamer with road wetness.
uniform float monsoon = 0.0;

varying float shore;
varying float wave;

float waves(vec2 p, float t) {
	float a = sin(dot(p, vec2(0.21, 0.13)) + t * 1.1);
	float b = sin(dot(p, vec2(-0.11, 0.27)) * 1.3 + t * 0.8);
	float c = sin(dot(p, vec2(0.33, -0.19)) * 0.7 + t * 1.6);
	return (a + b * 0.6 + c * 0.4) / 2.0;
}

void vertex() {
	shore = UV.x;
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float t = TIME * wave_speed * (1.0 + monsoon * 0.8);
	wave = waves(wp, t);
	// Banks stay put; the waves grow over the first ~3 m of water.
	VERTEX.y += wave * wave_height * (1.0 + monsoon) * smoothstep(0.3, 3.0, shore);
}

void fragment() {
	// Flat per-triangle normal: the low-poly facet look, no normal map needed.
	// (dFdy runs down the screen in Godot's view space, hence y then x for an outward normal.)
	vec3 n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	NORMAL = n.y < -0.2 ? -n : n;
	float depth = smoothstep(0.0, deep_at_m, shore);
	vec3 col = mix(shallow_colour, deep_colour, depth);
	col = mix(col, vec3(0.30, 0.27, 0.18), monsoon * 0.45);
	// Crest highlight on the facets that face the light most (stylised, not physical).
	col += vec3(0.06, 0.08, 0.07) * smoothstep(0.55, 0.95, wave);
	// Foam: a hard-edged band at the bank that breathes a little.
	float f = 1.0 - smoothstep(foam_m * (0.7 + 0.3 * sin(TIME * 1.3 + shore * 3.0)), foam_m * 1.25, shore);
	col = mix(col, foam_colour, f * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.6, f);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
