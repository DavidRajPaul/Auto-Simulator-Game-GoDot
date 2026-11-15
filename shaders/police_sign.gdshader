// Police booth sign panels (scripts/world/TrafficPolice.gd): one MultiMesh of quads, each showing
// its part of assets/textures/police_signs.png (atlas rect in the instance custom data). The
// panels are printed flex: lit like paint by day, softly glowing at night from the booth's tube.
shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float night = 0.0;

varying vec4 rect;

void vertex() {
	rect = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 uv = mix(rect.xy, rect.zw, UV);
	vec3 c = texture(atlas, uv).rgb;
	ALBEDO = c;
	ROUGHNESS = 0.6;
	SPECULAR = 0.25;
	EMISSION = c * 0.3 * night; // the booth's tube light behind the flex
}
