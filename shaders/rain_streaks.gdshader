shader_type spatial;
// Falling rain round the camera (RainSplashes.gd, Nov 14 owner report: "the rain is very bad").
// ONE MultiMesh of thin streaks: each instance is a drop seen with the eye's ~1/30 s blur, a
// thin line a few tenths of a metre long. Drops live in a world-anchored grid that wraps round
// the camera, so driving through the rain moves you through it (it never follows the camera).
// The streaks are LIT: dark against the sky by day, catching the headlights and street lights
// at night and flashing with the lightning, which is what makes rain read as rain.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords, specular_disabled;

uniform float intensity = 1.0;
uniform float radius = 16.0;
uniform float height = 12.0;
uniform float fall_speed = 9.0;
uniform float streak_m = 0.55;
uniform vec3 centre = vec3(0.0);
uniform float ground_y = 0.06;
global uniform vec2 wind_dir;
global uniform float wind_strength;

varying float fade;
varying float along;
varying float across;

float h11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	float id = float(INSTANCE_ID);
	// A fixed spot in a 2R x 2R tile, wrapped round the camera: world-anchored rain.
	vec2 seed = vec2(h11(id + 0.13), h11(id * 1.37 + 4.1)) * radius * 2.0;
	vec2 rel = mod(seed - centre.xz, radius * 2.0) - radius;
	float speed = fall_speed * mix(0.85, 1.15, h11(id * 3.3));
	float top = centre.y + height * 0.6;
	float y = top - mod(TIME * speed + h11(id * 7.7) * height, height);
	vec3 slant = normalize(vec3(wind_dir.x * wind_strength * 0.35, -1.0, wind_dir.y * wind_strength * 0.35));
	vec3 base = vec3(centre.x + rel.x, y, centre.z + rel.y);
	vec3 to_cam = CAMERA_POSITION_WORLD - base;
	float dist = length(to_cam);
	vec3 side = normalize(cross(slant, to_cam / max(dist, 0.001)));
	// Never thinner than ~1.3 px, or far drops shimmer.
	float width = max(0.006, dist * 0.0016);
	along = UV.y;
	across = UV.x * 2.0 - 1.0;
	VERTEX = base + side * (UV.x - 0.5) * width - slant * UV.y * streak_m;
	NORMAL = normalize(to_cam);
	// Fade the closest (they'd smear across the lens), the far edge of the disc, and anything
	// that has reached the ground.
	float r = length(rel) / radius;
	fade = smoothstep(0.6, 2.0, dist) * (1.0 - smoothstep(0.75, 1.0, r)) * step(ground_y, y);
}

void fragment() {
	float core = 1.0 - smoothstep(0.2, 1.0, abs(across));
	float tail = smoothstep(0.0, 0.25, along) * (1.0 - smoothstep(0.75, 1.0, along));
	ALBEDO = vec3(0.62, 0.66, 0.7);
	ROUGHNESS = 0.3;
	BACKLIGHT = vec3(0.7);
	ALPHA = clamp(core * tail * fade * 0.6 * intensity, 0.0, 1.0);
}
