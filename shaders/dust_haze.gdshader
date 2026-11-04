// Procedural road-dust haze for WindDustFX (Nov 4 device test: the Kenney sprite puffs and
// streaks read as cartoon). No texture: each CPUParticles3D quad is a soft, billowing patch of
// dust whose shape is 3 octaves of value noise, scrolled slowly so it rolls instead of sliding.
// Mobile budget: a handful of quads for ~3 s at a time, no depth texture, no screen reads;
// particles fade out before they get close to the camera so they never fill the screen.
// Lit (one directional + ambient) so the dust darkens at dusk instead of glowing.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

uniform vec3 dust_colour : source_color = vec3(0.70, 0.63, 0.50);
uniform float opacity = 0.62;
uniform float near_fade_start = 3.0;
uniform float near_fade_end = 9.0;

varying float seed;
varying float age;

void vertex() {
	// Upright billboard around the particle centre (dust hangs low; tilting with the view makes it
	// look like a sticker on the camera), keeping the particle's scale.
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = cross(right, up);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mat4 world = mat4(vec4(right * sx, 0.0), vec4(up * sy, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// CPUParticles3D: custom.x = random angle (a free per-particle seed), custom.y = age 0..1.
	seed = INSTANCE_CUSTOM.x;
	age = INSTANCE_CUSTOM.y;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	// Wider than tall, heavier at the bottom: dust lifts off the road, it does not float.
	float r = length(vec2(c.x, (c.y + 0.25) * 1.35));
	float shape = 1.0 - smoothstep(0.35, 1.0, r);
	vec2 p = UV * vec2(2.2, 1.6) + vec2(seed * 3.7, seed * 1.3) + vec2(-TIME * 0.18, TIME * 0.05);
	float n = vnoise(p) * 0.55 + vnoise(p * 2.1 + 5.2) * 0.3 + vnoise(p * 4.3 + 9.7) * 0.15;
	float wisps = smoothstep(0.12, 0.66, n);
	float dist = -VERTEX.z;
	float near = smoothstep(near_fade_start, near_fade_end, dist);
	ALBEDO = dust_colour * (0.92 + 0.16 * n) * COLOR.rgb;
	ALPHA = clamp(shape * wisps * opacity * COLOR.a * near, 0.0, 1.0);
	// Half facing the camera, half facing the sky: lit from any sun angle, never a black card.
	NORMAL = normalize(vec3(0.0, 0.0, 1.0) + (VIEW_MATRIX * vec4(0.0, 1.5, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
