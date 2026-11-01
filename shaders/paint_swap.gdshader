shader_type spatial;
// Per-instance recolour of a textured model (PaintSwap.gd): the texels close to `src_colour`
// (hue within `hue_tol`, saturation >= `min_sat`, inside `rect` in UV) are moved in HSV so that
// `src_colour` becomes the paint colour: hue rotated, saturation and value scaled. Folds,
// shading, stripes and prints survive; skin, hair, tyres, chrome and glass are untouched.
// Paint comes from an instance uniform (MeshInstance3D, skinned too) or, for MultiMesh, from
// INSTANCE_CUSTOM (use_custom). paint.a < 0.5 = the model's own colours. One draw call, as before.
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 src_colour : source_color = vec3(1.0, 0.8, 0.0);
uniform float hue_tol = 0.08;   // 0..0.5 of the colour wheel
uniform float min_sat = 0.25;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0); // u0, v0, u1, v1
uniform bool use_custom = false;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
instance uniform vec4 paint = vec4(0.0);

varying vec4 v_paint;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-6)), d / (q.x + 1e-6), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	v_paint = use_custom ? INSTANCE_CUSTOM : paint;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 c = t.rgb;
	if (v_paint.a > 0.5) {
		float in_rect = step(rect.x, UV.x) * step(rect.y, UV.y) * step(UV.x, rect.z) * step(UV.y, rect.w);
		vec3 h = rgb2hsv(c);
		vec3 s0 = rgb2hsv(src_colour);
		vec3 p = rgb2hsv(v_paint.rgb);
		float dh = abs(fract(h.x - s0.x + 0.5) - 0.5);
		float m = in_rect * (1.0 - smoothstep(hue_tol, hue_tol + 0.03, dh)) * smoothstep(min_sat * 0.7, min_sat, h.y);
		vec3 nh = vec3(fract(h.x + p.x - s0.x),
			clamp(h.y * p.y / max(s0.y, 0.02), 0.0, 1.0),
			clamp(h.z * p.z / max(s0.z, 0.02), 0.0, 1.0));
		c = mix(c, hsv2rgb(nh), m);
	}
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
