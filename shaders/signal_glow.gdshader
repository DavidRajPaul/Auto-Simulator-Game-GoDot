// Chennai LED signal pole (ChennaiTrafficManager signal posts): everything on the post that lights up,
// in one opaque, unshaded surface, so the whole pole changes colour like the city's new LED poles.
// Per post (instance uniforms, no extra material): `lit` 0 red / 1 amber / 2 green, `seconds` left
// on the countdown. Vertex colour alpha = part: 0..2 lens (red, amber, green), 3 LED strip on the
// pole and the arm (glows in the current colour), 4 countdown face (UV 0..1, two 7-segment digits).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

instance uniform float lit = 0.0;
instance uniform float seconds = 0.0;

varying float part;

const int SEGS[10] = int[](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);

void vertex() {
	part = COLOR.a * 8.0;
}

vec3 light_colour(float l) {
	if (l < 0.5) {
		return vec3(1.0, 0.07, 0.04);
	}
	if (l < 1.5) {
		return vec3(1.0, 0.52, 0.02);
	}
	return vec3(0.06, 1.0, 0.38);
}

float in_rect(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
}

// 1 on a lit segment, 0.5 on a dark one, 0 off the digit. p in the digit cell, 0..1, y up.
float seven_seg(vec2 p, int d) {
	float t = 0.15;
	float g = 0.03;
	float lit_seg = 0.0;
	float any_seg = 0.0;
	for (int s = 0; s < 7; s++) {
		vec2 lo;
		vec2 hi;
		if (s == 0) { lo = vec2(t, 1.0 - t); hi = vec2(1.0 - t, 1.0); }
		else if (s == 1) { lo = vec2(1.0 - t, 0.5 + g); hi = vec2(1.0, 1.0 - g); }
		else if (s == 2) { lo = vec2(1.0 - t, g); hi = vec2(1.0, 0.5 - g); }
		else if (s == 3) { lo = vec2(t, 0.0); hi = vec2(1.0 - t, t); }
		else if (s == 4) { lo = vec2(0.0, g); hi = vec2(t, 0.5 - g); }
		else if (s == 5) { lo = vec2(0.0, 0.5 + g); hi = vec2(t, 1.0 - g); }
		else { lo = vec2(t, 0.5 - t * 0.5); hi = vec2(1.0 - t, 0.5 + t * 0.5); }
		float r = in_rect(p, lo, hi);
		any_seg = max(any_seg, r);
		if (((SEGS[d] >> s) & 1) == 1) {
			lit_seg = max(lit_seg, r);
		}
	}
	return max(lit_seg, any_seg * 0.5 * (1.0 - lit_seg));
}

void fragment() {
	float pid = floor(part + 0.5);
	vec3 now = light_colour(lit);
	vec3 col = COLOR.rgb;
	if (pid < 2.5) {
		// Lens: a dense grid of LEDs behind tinted glass, like the real heads.
		vec3 lens = light_colour(pid);
		vec2 q = UV - 0.5;
		float r = length(q) * 2.0;
		float dots = smoothstep(0.42, 0.22, length(fract(UV * 11.0) - 0.5));
		if (abs(pid - lit) < 0.5) {
			col = lens * (0.8 + 0.45 * dots) * (1.05 - 0.2 * r);
		} else {
			col = lens * (0.05 + 0.04 * dots);
		}
	} else if (pid < 3.5) {
		// LED strip along the pole and arm: the whole post wears the current colour.
		col = now * (0.9 + 0.1 * sin(UV.y * 60.0));
	} else if (pid < 4.5) {
		int s = int(clamp(ceil(seconds), 0.0, 99.0));
		vec2 p = UV;
		float on = 0.0;
		if (s > 0) {
			if (p.x < 0.5) {
				on = s >= 10 ? seven_seg(vec2((p.x - 0.08) / 0.34, (p.y - 0.12) / 0.76), s / 10) : 0.0;
			} else {
				on = seven_seg(vec2((p.x - 0.58) / 0.34, (p.y - 0.12) / 0.76), s % 10);
			}
		}
		col = on > 0.75 ? now : (on > 0.25 ? now * 0.07 : vec3(0.015));
	}
	ALBEDO = col;
}
