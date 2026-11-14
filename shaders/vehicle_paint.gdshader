shader_type spatial;
// Chennai street vehicles from tools/art/make_chennai_vehicles.py: no texture, colours are
// vertex colours (linear), and the body panels carry vertex alpha 0. Each instance repaints
// exactly those panels: from INSTANCE_CUSTOM in a MultiMesh (parked rows, use_custom) or from
// the `paint` instance uniform (traffic). paint.a < 0.5 keeps the model's own silver.
// One material for every model and every colour, so a kerb of mixed colours is one draw call.
render_mode cull_back, specular_schlick_ggx;

uniform bool use_custom = false;
instance uniform vec4 paint = vec4(0.0);

varying vec4 v_paint;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	v_paint = use_custom ? INSTANCE_CUSTOM : paint;
}

void fragment() {
	float body = 1.0 - step(0.5, COLOR.a);
	vec3 c = COLOR.rgb;
	if (v_paint.a > 0.5) {
		c = mix(c, to_linear(v_paint.rgb), body);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.7, 0.42, body);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.6, body);
}
