shader_type sky;
// Chennai sky. Atmosphere.gd drives every uniform from the shift clock and the weather.
// Blue mornings over the Bay of Bengal, bright fair-weather cumulus, a soft pale horizon, and
// sunsets where the glow sits on the sun's side while the far sky stays blue. High cirrus takes
// the strongest reds because it catches sunlight above the low haze. Crepuscular rays ("Buddha
// rays") fan out when the sun is low behind cloud. The Northeast Monsoon closes it into overcast.
// Mobile: at most 6 samples of one seamless noise texture, sky pixels only. The environment
// takes neither ambient nor reflections from the sky, so no radiance cubemap is re-rendered for
// the moving clouds; the cubemap pass (if any) gets the gradient only.

uniform vec3 zenith_colour : source_color = vec3(0.10, 0.34, 0.74);
uniform vec3 mid_colour : source_color = vec3(0.29, 0.57, 0.91);
uniform vec3 horizon_sun : source_color = vec3(0.86, 0.91, 0.96);
uniform vec3 horizon_far : source_color = vec3(0.80, 0.89, 0.96);
uniform vec3 ground_colour : source_color = vec3(0.55, 0.53, 0.50);
uniform vec3 sun_glow_colour : source_color = vec3(1.0, 0.85, 0.6);
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.66, 0.73, 0.82);
uniform vec3 cirrus_colour : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0); // True sun: goes below the horizon, unlike the light.
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float coverage : hint_range(0.0, 1.0) = 0.38; // 0 clear .. 1 overcast
uniform float cirrus : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float base_dark : hint_range(0.0, 1.0) = 0.45; // How grey cumulus bases get.
uniform float low_sun : hint_range(0.0, 1.0) = 0.0; // 1 around sunrise and sunset.
uniform float rays : hint_range(0.0, 1.0) = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float wind_speed = 0.004;

const vec3 MOON_DIR = vec3(-0.29, 0.77, -0.57);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 sun = normalize(sun_dir);
	vec2 sun_flat = normalize(sun.xz + vec2(0.0001));
	// 0 facing away from the sun .. 1 facing it, around the horizon.
	float toward = 0.5 + 0.5 * dot(normalize(d.xz + vec2(0.0001)), sun_flat);
	float sd = max(dot(d, sun), 0.0);
	float h = max(up, 0.0);

	vec3 horizon = mix(horizon_far, horizon_sun, pow(toward, 2.2));
	vec3 col = mix(horizon, mid_colour, smoothstep(0.0, 0.3, pow(h, 0.8)));
	col = mix(col, zenith_colour, smoothstep(0.14, 0.8, h));
	if (up < 0.0) {
		col = mix(horizon, ground_colour, smoothstep(0.0, 0.25, -up));
	}
	// Twilight: the earth's shadow rises opposite the sun as a blue band under a pink one.
	col = mix(col, zenith_colour * 1.5, low_sun * (1.0 - toward) * (1.0 - smoothstep(0.0, 0.1, h)) * 0.55);
	// The sunset glow climbs the sky on the sun's side.
	col = mix(col, horizon_sun, low_sun * pow(toward, 5.0) * (1.0 - smoothstep(0.03, 0.5, h)) * 0.75);

	float sun_up = smoothstep(-0.03, 0.03, sun.y) * (1.0 - overcast);
	float above = smoothstep(-0.01, 0.01, up);
	col += sun_glow_colour * (pow(sd, 10.0) * 0.28 + pow(sd, 90.0) * 0.5) * (1.0 - night) * (1.0 - overcast * 0.9);
	col += mix(vec3(1.0, 0.97, 0.88), sun_glow_colour * 1.4, low_sun) * smoothstep(0.9993, 0.9997, sd) * sun_up * above * 1.8;

	if (!AT_CUBEMAP_PASS && up > 0.0) {
		vec2 wind = vec2(1.0, 0.35) * TIME * wind_speed;
		if (night > 0.01) {
			vec2 sp = floor(d.xz / max(d.y, 0.05) * 180.0);
			float s = step(0.9975, hash(sp)) * smoothstep(0.15, 0.5, up) * night * (1.0 - coverage);
			col += vec3(s);
			float md = max(dot(d, MOON_DIR), 0.0);
			col += vec3(0.92, 0.94, 1.0) * (smoothstep(0.9994, 0.9996, md) * 1.1 + pow(md, 300.0) * 0.12) * night * (1.0 - coverage * 0.7);
		}
		// Crepuscular rays: light and shadow fans around a low sun.
		if (rays > 0.01) {
			vec3 side = normalize(cross(sun, vec3(0.0, 1.0, 0.0)));
			float angle = atan(dot(d, side), d.y - sun.y);
			float beam = texture(cloud_noise, vec2(angle * 0.22 + 0.37, 0.31 + TIME * 0.0015)).r;
			beam = smoothstep(0.42, 0.66, beam);
			col = mix(col, col * (0.88 + beam * 0.24) + sun_glow_colour * beam * 0.13, rays * pow(sd, 3.0));
		}
		// Cumulus on a flat layer: uv grows toward the horizon, so they flatten into the haze.
		vec2 uv = d.xz / (up + 0.22) * 0.24;
		float body = texture(cloud_noise, uv + wind).r;
		float n = body * 0.66 + texture(cloud_noise, uv * 2.7 - wind * 1.6).r * 0.24
			+ texture(cloud_noise, uv * 7.3 + wind * 2.4).r * 0.1;
		// High cirrus: fine wisps in the gaps between cumulus, first to redden, last to fade.
		if (cirrus > 0.01) {
			vec2 hi = d.xz / (up + 0.55);
			hi = vec2(hi.x * 0.86 + hi.y * 0.5, hi.y * 0.86 - hi.x * 0.5);
			float streak = texture(cloud_noise, hi * vec2(1.9, 0.2) + wind * 0.5).r;
			float wisp = smoothstep(0.66 - cirrus * 0.16, 0.86, streak) * smoothstep(0.04, 0.3, up);
			wisp *= smoothstep(0.58, 0.36, body) * (0.5 + cirrus * 0.5);
			col = mix(col, cirrus_colour + sun_glow_colour * pow(sd, 3.0) * 0.3 * (1.0 - night), wisp * mix(0.24, 0.95, low_sun) * (1.0 - overcast));
		}
		// Blending the octaves squeezes the noise toward 0.5: stretch it back out.
		n = clamp((n - 0.5) * 2.1 + 0.5, 0.0, 1.0);
		float edge = 1.0 - coverage;
		float c = smoothstep(edge - 0.02, edge + 0.2, n);
		if (c > 0.0) {
			// Sample toward the sun: where the cloud thins that way, this side faces the light.
			float toward_light = texture(cloud_noise, uv + wind + sun_flat * 0.02).r;
			float facing = clamp((body - toward_light) * 9.0 + 0.55, 0.0, 1.0);
			float thick = smoothstep(edge + 0.04, edge + 0.42, n);
			float shade = clamp(thick * base_dark * 1.5 + (1.0 - facing) * 0.55, 0.0, 1.0);
			// A low sun lights clouds on its own side and leaves the far side in shadow.
			shade = mix(shade, clamp(shade + (0.55 - toward) * 0.9, 0.0, 1.0), low_sun);
			// Monsoon deck: one closed layer with soft dark rolls, no bright gaps.
			shade = mix(shade, 0.35 + (1.0 - n) * 0.5, overcast);
			vec3 cc = mix(cloud_lit, cloud_shade, shade);
			cc += sun_glow_colour * pow(sd, 5.0) * (1.0 - thick) * 0.55 * (1.0 - night) * (1.0 - overcast);
			// Distant clouds sink into the horizon air.
			cc = mix(horizon, cc, smoothstep(0.015, 0.2, up) * 0.6 + 0.4);
			col = mix(col, cc, mix(c, 1.0, overcast) * smoothstep(0.0, 0.1, up) * cloud_alpha);
		}
	}
	COLOR = col;
}
