// Far street trees (scripts/world/StreetTrees.gd): VIEWS crossed cards per tree, all species in ONE
// MultiMesh. The atlas (tools/assets/bake_trees.py) has one row per species and one column per
// card; the mesh UVs address row 0 and INSTANCE_CUSTOM.x picks the species row. Instance COLOR
// is the same per-tree tint the near model gets. Normals point up (set in the mesh) so the cards
// take the sun like the top of a crown, at any yaw.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float rows = 5.0;

varying vec3 tint;

void vertex() {
	UV.y += INSTANCE_CUSTOM.x / rows;
	tint = COLOR.rgb;
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
