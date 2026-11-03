shader_type spatial;
// Player-auto repaint (AutoRickshawModel). Body: mask_tex.r (tools/assets/make_auto_paint_mask.py,
// the yellow panels of the texture) takes the target colour scaled by each texel's brightness
// relative to stock yellow, so shading and stickers survive. Canopy: dark, unsaturated texels
// above canopy_min_y inside |x| < canopy_max_x in MESH space (the roof canvas samples a black
// texture area shared with other parts, so it cannot be told apart in UV space). Wheels,
// chrome, seat, mirrors and chassis keep their original texture.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform vec3 body_colour : source_color = vec3(0.98, 0.76, 0.02);
uniform vec3 canopy_colour : source_color = vec3(0.07, 0.07, 0.07);
uniform vec3 body_stock : source_color = vec3(0.987, 0.856, 0.0);
uniform vec3 canopy_stock : source_color = vec3(0.13, 0.13, 0.13);
uniform float roughness_scale = 1.0;
// The file's metallicFactor (0 for the player auto). Its ORM texture has metallic = 1 everywhere,
// which glTF multiplies by this factor; reading orm.b alone made the whole body chrome, and chrome
// with no sky reflections renders black in shade (Nov 3 device test).
uniform float metallic_scale = 0.0;
uniform float canopy_min_y = 96.0;
uniform float canopy_max_x = 68.0;
uniform bool stock_paint = false;
uniform vec4 panel_damage = vec4(0.0);
uniform vec3 mesh_centre = vec3(0.0);
uniform vec3 mesh_size = vec3(1.0);
// Visible crash damage (Nov 3). Part ids are baked into UV2.x by tools/assets/bake_auto_parts.py:
// 0 body, 1 left mirror, 2 right mirror, 3 windshield, 4 rear glass, 5 headlamp.
// dents: up to 8 impact points in MESH space (the file's units, cm), w = strength 0..1. Each pushes
// the body in towards the auto's centre line over dent_radius, bends the normal so the dent reads
// in the light, and scrapes the paint to bare grey metal at its centre.
uniform vec4 dents[8];
uniform int dent_count = 0;
uniform float dent_radius = 34.0;
uniform float dent_depth = 13.0;
uniform bool mirror_l_broken = false;
uniform bool mirror_r_broken = false;
uniform float lamp_broken = 0.0;

varying vec3 mesh_pos;
varying float wear;
varying float part;
varying float dent_f;

void vertex() {
	mesh_pos = VERTEX;
	part = UV2.x;
	vec3 p = (VERTEX - mesh_centre) / max(mesh_size, vec3(0.001));
	// Imported body faces +Z; the holder turns it to the driving direction.
	wear = max(max(panel_damage.x * smoothstep(0.05, 0.4, p.z), panel_damage.y * smoothstep(0.05, 0.4, -p.z)),
		max(panel_damage.z * smoothstep(0.05, 0.4, p.x), panel_damage.w * smoothstep(0.05, 0.4, -p.x)));
	dent_f = 0.0;
	if (part < 0.5) {
		vec3 push = vec3(0.0);
		vec3 bend = vec3(0.0);
		for (int i = 0; i < dent_count; i++) {
			vec4 dn = dents[i];
			float r = dent_radius * (0.75 + 0.5 * dn.w);
			float d = distance(VERTEX, dn.xyz);
			float k = 1.0 - smoothstep(0.0, r, d);
			float f = dn.w * k * k;
			// Inwards = towards the centre line at the dent's height (never through the floor).
			vec3 inward = normalize(vec3(mesh_centre.x - dn.x, 0.0, mesh_centre.z - dn.z) + vec3(0.0001));
			push += inward * f;
			// Slope of the dent: tilt the normal away from the dent centre on its rim.
			bend += normalize(VERTEX - dn.xyz + vec3(0.0001)) * dn.w * k * (1.0 - k) * 2.0;
			dent_f = max(dent_f, f);
		}
		VERTEX += push * dent_depth;
		NORMAL = normalize(NORMAL - bend * 1.7);
	}
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Value noise (smooth, irregular) for scraped paint.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	// A broken mirror is gone (housing, arm and glass all carry its id).
	if ((mirror_l_broken && abs(part - 1.0) < 0.5) || (mirror_r_broken && abs(part - 2.0) < 0.5)) {
		discard;
	}
	vec3 base = texture(albedo_tex, UV).rgb;
	float body_m = texture(mask_tex, UV).r;
	float sat = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
	float canopy_m = step(canopy_min_y, mesh_pos.y) * step(abs(mesh_pos.x), canopy_max_x)
		* step(luma(base), 0.42) * step(sat, 0.15) * (1.0 - body_m);
	float kb = clamp(luma(base) / max(luma(body_stock), 0.001), 0.0, 1.4);
	// The canvas is near-black in the texture: keep only a gentle shading variation.
	float kc = clamp(0.85 + (luma(base) - luma(canopy_stock)) * 1.5, 0.65, 1.15);
	vec3 col = mix(base, body_colour * kb, body_m);
	col = mix(col, canopy_colour * kc, canopy_m);
	if (stock_paint) { col = base; }
	// Road grime on worn panels (the old full-panel scratch stripes read as banding: Nov 3).
	col = mix(col, col * 0.7, body_m * wear * 0.35);
	// Dents: a darker crease on the rim, paint scraped to bare grey metal in irregular patches at
	// the centre (noise, not stripes), with fine scratches through it.
	float rim = dent_f * (1.0 - dent_f) * 4.0;
	col *= 1.0 - 0.35 * rim;
	float n = vnoise(mesh_pos * 0.22) * 0.65 + vnoise(mesh_pos * 0.9) * 0.35;
	float bare = smoothstep(0.3, 0.7, dent_f) * smoothstep(0.62 - 0.35 * dent_f, 0.7 - 0.35 * dent_f, n);
	float fine = step(0.92, fract((mesh_pos.x + mesh_pos.y * 0.6) * 0.45 + n * 2.0)) * smoothstep(0.2, 0.5, dent_f);
	col = mix(col, vec3(0.5, 0.5, 0.48), clamp(bare + fine * 0.6, 0.0, 1.0));
	// Smashed headlamp: dark glass with a white crack.
	if (abs(part - 5.0) < 0.5 && lamp_broken > 0.0) {
		float crack = step(0.93, abs(sin(atan(mesh_pos.y - 56.0, mesh_pos.x) * 5.0 + mesh_pos.y * 0.4)));
		col = mix(col, mix(vec3(0.05), vec3(0.8), crack), lamp_broken);
	}
	ALBEDO = col;
	if (has_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = mix(clamp(orm.g * roughness_scale, 0.0, 1.0), 0.85, canopy_m);
		METALLIC = orm.b * metallic_scale * (1.0 - canopy_m);
	} else {
		ROUGHNESS = 0.6;
	}
	// The canopy samples an empty (black) region of the normal map too: a (0,0,0) normal lights
	// it as permanent shadow, invisible while the canvas is black. Use the mesh normal there.
	if (has_normal && canopy_m < 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
