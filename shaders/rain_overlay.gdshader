shader_type canvas_item;
// Screen-space monsoon rain: slanted streaks, windscreen drops and a wiper arm (cockpit).
// One full-screen draw call; all uniforms driven by scripts/world/MonsoonFX.gd.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float drops : hint_range(0.0, 1.0) = 0.0;
uniform float wiper_angle = -2.0; // radians from vertical; |angle| > 1.6 hides the arm
uniform float cockpit = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float streaks(vec2 uv, float density, float speed, float seed) {
	vec2 st = vec2(uv.x * density + uv.y * density * 0.12, uv.y * 2.5 - TIME * speed);
	vec2 cell = floor(st);
	vec2 f = fract(st);
	float h = hash(cell + seed);
	float len = 0.25 + 0.3 * hash(cell + seed + 4.0);
	float on = step(0.9, h);
	float y = smoothstep(0.0, 0.05, f.y) * (1.0 - smoothstep(len * 0.6, len, f.y));
	float x = 1.0 - smoothstep(0.03, 0.1, abs(f.x - 0.5));
	return on * x * y;
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float s = streaks(uv, 70.0, 5.5, 0.0) * 0.8 + streaks(uv, 120.0, 7.0, 13.0) * 0.5;
	float a = s * 0.28 * intensity;
	vec3 col = vec3(0.82, 0.86, 0.9);

	// Windscreen drops (cockpit only).
	vec2 dg = uv * vec2(aspect * 11.0, 11.0);
	vec2 dc = floor(dg);
	vec2 df = fract(dg) - 0.5;
	vec2 off = vec2(hash(dc + 1.7), hash(dc + 5.3)) - 0.5;
	float r = 0.1 + 0.16 * hash(dc + 9.1);
	float d = length(df - off * 0.55);
	float drop = (1.0 - smoothstep(r * 0.65, r, d)) * step(1.0 - drops, hash(dc + 3.1));
	float rim = smoothstep(r * 0.45, r * 0.8, d) * drop;
	a += (drop * 0.07 + rim * 0.16) * cockpit * intensity;

	// Wiper arm pivoting at the bottom centre of the windscreen.
	vec2 p = (uv - vec2(0.5, 1.02)) * vec2(aspect, 1.0);
	vec2 dir = vec2(sin(wiper_angle), -cos(wiper_angle));
	float along = dot(p, dir);
	float across = abs(p.x * dir.y - p.y * dir.x);
	float arm = step(0.0, along) * (1.0 - step(0.62, along)) * (1.0 - smoothstep(0.004, 0.008, across));
	arm *= cockpit * step(abs(wiper_angle), 1.6);
	col = mix(col, vec3(0.05), arm);
	a = max(a, arm * 0.95);
	COLOR = vec4(col, a);
}
