shader_type sky;
// Chennai sky (Atmosphere.gd drives every uniform from the shift clock and the weather).
// Coastal Tamil Nadu look: a bright humid haze band on the horizon, deeper blue overhead,
// drifting fair-weather cumulus with sunlit tops and grey bases; the Northeast Monsoon closes
// it into a low slate overcast; dusk turns the haze orange/pink; stars at night.
// Mobile: one seamless noise texture sampled 3 times on a cloud plane, sky pixels only. The
// environment takes neither ambient nor reflections from the sky, so no radiance cubemap is
// re-rendered for the moving clouds; the cubemap pass (if any) gets the gradient only.

uniform vec3 zenith_colour : source_color = vec3(0.26, 0.48, 0.80);
uniform vec3 horizon_colour : source_color = vec3(0.86, 0.85, 0.80);
uniform vec3 ground_colour : source_color = vec3(0.55, 0.53, 0.50);
uniform vec3 sun_glow_colour : source_color = vec3(1.0, 0.85, 0.6);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.66, 0.74);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float coverage : hint_range(0.0, 1.0) = 0.38; // 0 clear .. 1 overcast
uniform float cloud_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float haze : hint_range(0.0, 1.0) = 0.55;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float wind_speed = 0.004;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	// Haze band: humid coastal air keeps the lower sky milky white.
	float t = pow(max(up, 0.0), mix(0.55, 0.9, haze));
	vec3 col = mix(horizon_colour, zenith_colour, t);
	if (up < 0.0) {
		col = mix(horizon_colour, ground_colour, smoothstep(0.0, 0.25, -up));
	}
	// Sun glow (no hard disc: the haze softens it).
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float sd = max(dot(d, sun_dir), 0.0);
	col += sun_glow_colour * (pow(sd, 8.0) * 0.25 + pow(sd, 256.0) * 1.2) * (1.0 - night) * (1.0 - coverage * 0.8);

	if (!AT_CUBEMAP_PASS && up > 0.0) {
		// Stars, only on clear nights, above the haze.
		if (night > 0.01) {
			vec2 sp = floor(d.xz / max(d.y, 0.05) * 180.0);
			float s = step(0.9975, hash(sp)) * smoothstep(0.15, 0.5, up) * night * (1.0 - coverage);
			col += vec3(s);
		}
		// Clouds on a flat layer: uv grows toward the horizon, so they flatten into the haze.
		vec2 uv = d.xz / (up + 0.12) * 0.13;
		vec2 wind = vec2(1.0, 0.35) * TIME * wind_speed;
		float n = texture(cloud_noise, uv + wind).r * 0.6
			+ texture(cloud_noise, uv * 2.3 - wind * 1.7).r * 0.28
			+ texture(cloud_noise, uv * 5.1 + wind * 2.9).r * 0.12;
		// Averaging three octaves squeezes the noise toward 0.5: stretch it back out.
		n = clamp((n - 0.5) * 1.9 + 0.5, 0.0, 1.0);
		float edge = 1.0 - coverage;
		float c = smoothstep(edge - 0.06, edge + 0.16, n);
		// Fade out at the horizon (into haze) and thin at the zenith for depth.
		c *= smoothstep(0.0, 0.18, up) * cloud_alpha;
		// Lighting: thicker parts and the side away from the sun are darker.
		float thick = smoothstep(edge, edge + 0.35, n);
		float lit = clamp(0.55 + 0.45 * dot(normalize(vec3(d.x, 0.0, d.z) + 0.0001), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 0.0001)), 0.0, 1.0);
		vec3 cc = mix(cloud_lit, cloud_shade, thick * 0.75 + (1.0 - lit) * 0.25);
		cc += sun_glow_colour * pow(sd, 6.0) * 0.35 * (1.0 - night);
		col = mix(col, cc, c);
	}
	COLOR = col;
}
