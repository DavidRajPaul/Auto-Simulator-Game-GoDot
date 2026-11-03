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

varying vec3 mesh_pos;
varying float wear;

void vertex() {
	mesh_pos = VERTEX;
	vec3 p = (VERTEX - mesh_centre) / max(mesh_size, vec3(0.001));
	// Imported body faces +Z; the holder turns it to the driving direction.
	wear = max(max(panel_damage.x * smoothstep(0.05, 0.4, p.z), panel_damage.y * smoothstep(0.05, 0.4, -p.z)),
		max(panel_damage.z * smoothstep(0.05, 0.4, p.x), panel_damage.w * smoothstep(0.05, 0.4, -p.x)));
	float panel = texture(mask_tex, UV).r;
	VERTEX -= NORMAL * min(mesh_size.x, mesh_size.z) * 0.055 * wear * panel * (0.6 + 0.4 * sin(p.y * 31.0 + p.z * 17.0));
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
	if (stock_paint) { col = base; }
	float scratches = step(0.77, sin(mesh_pos.y * 1.3 + sin(mesh_pos.z * 0.21))) * step(0.35, wear);
	col = mix(col, vec3(0.16, 0.14, 0.12), body_m * wear * (0.25 + scratches * 0.6));
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
