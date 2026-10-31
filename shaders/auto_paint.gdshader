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
uniform float canopy_min_y = 96.0;
uniform float canopy_max_x = 68.0;

varying vec3 mesh_pos;

void vertex() {
	mesh_pos = VERTEX;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
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
	ALBEDO = col;
	if (has_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = mix(clamp(orm.g * roughness_scale, 0.0, 1.0), 0.85, canopy_m);
		METALLIC = orm.b * (1.0 - canopy_m);
	} else {
		ROUGHNESS = 0.6;
	}
	// The canopy samples an empty (black) region of the normal map too: a (0,0,0) normal lights
	// it as permanent shadow, invisible while the canvas is black. Use the mesh normal there.
	if (has_normal && canopy_m < 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
