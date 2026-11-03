shader_type spatial;
// Player-auto glass (AutoRickshawModel), replacing the file's blinn1 material (dark tint, alpha
// 0.24, rough). Part ids in UV2.x (tools/assets/bake_auto_parts.py): 1 / 2 mirror glass, 3
// windshield, 4 rear glass. Visible crash damage (Nov 3):
//   crack 0..1 on the windshield, grown from crack_origin (MESH x/y, cm) over crack_reach:
//     > 0     a chip and short radial cracks
//     > 0.35  a spider web: radial cracks + cell borders (Voronoi) out to the reach
//     > 0.8   shattered: milky safety glass, a few cells knocked out
//   a broken mirror's glass is hidden with the housing (see auto_paint.gdshader).
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 glass_colour : source_color = vec4(0.025, 0.025, 0.025, 0.24);
uniform float roughness = 0.92;
uniform float crack = 0.0;
uniform vec2 crack_origin = vec2(0.0, 136.0);
uniform float crack_reach = 70.0;
uniform bool mirror_l_broken = false;
uniform bool mirror_r_broken = false;

varying vec3 mesh_pos;
varying float part;

void vertex() {
	mesh_pos = VERTEX;
	part = UV2.x;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi cell border (x) and the cell's id hash (y).
vec2 voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec2(md, hash2(n + mg).x);
}

void fragment() {
	if ((mirror_l_broken && abs(part - 1.0) < 0.5) || (mirror_r_broken && abs(part - 2.0) < 0.5)) {
		discard;
	}
	vec3 col = glass_colour.rgb;
	float alpha = glass_colour.a;
	float rough = roughness;
	if (crack > 0.001 && abs(part - 3.0) < 0.5) {
		vec2 q = mesh_pos.xy - crack_origin;
		float r = length(q);
		float reach = crack_reach * clamp(0.15 + crack, 0.0, 1.0);
		float inside = 1.0 - smoothstep(reach * 0.85, reach, r);
		float ang = atan(q.y, q.x);
		// Radial cracks: thin, wobbling lines whose number grows with the damage.
		float spokes = mix(5.0, 11.0, crack);
		float wob = sin(r * 0.35 + ang * 3.0) * 0.12;
		float sp = abs(fract((ang / 6.2832) * spokes + wob + 0.5) - 0.5) * r;
		float radial = 1.0 - smoothstep(0.0, 0.25 + fwidth(sp) * 1.5, sp);
		// Cell borders (the web), only once the crack has spread.
		vec2 ve = voronoi_edge(q / mix(9.0, 5.0, crack));
		float web = (1.0 - smoothstep(0.0, 0.05 + fwidth(ve.x) * 1.5, ve.x)) * smoothstep(0.35, 0.55, crack);
		// The chip at the impact point.
		float chip = 1.0 - smoothstep(1.2, 2.5, r);
		float lines = clamp(max(max(radial, web), chip), 0.0, 1.0) * inside;
		// Shattered: milky, crazed glass and a few cells knocked out.
		float shatter = smoothstep(0.8, 1.0, crack) * inside;
		if (shatter > 0.5 && ve.y < 0.18 * shatter && r > 3.0) {
			discard;
		}
		col = mix(col, vec3(0.72, 0.74, 0.74), max(lines * 0.9, shatter * 0.55));
		alpha = max(alpha, max(lines * 0.85, shatter * 0.7));
		rough = mix(rough, 1.0, max(lines, shatter));
	}
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
