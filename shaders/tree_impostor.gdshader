// Far street trees (scripts/world/StreetTrees.gd): VIEWS crossed cards per tree, all species in ONE
// MultiMesh. The atlas (tools/assets/bake_trees.py) has one row per species and one column per
// card; the mesh UVs address row 0 and INSTANCE_CUSTOM.x picks the species row. Instance COLOR
// is the same per-tree tint the near model gets. Normals point up (set in the mesh) so the cards
// take the sun like the top of a crown, at any yaw.
// Inside the fade band the cards draw exactly the pixels the near model (tree_near.gdshader)
// dissolves, with the same dither and distance, so the swap is a short cross-fade, not a pop.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float rows = 5.0;
uniform vec3 eye_pos = vec3(0.0);
uniform float fade_start = 50.0;
uniform float fade_end = 62.0;

varying vec3 tint;
varying float near_vis;

float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	UV.y += INSTANCE_CUSTOM.x / rows;
	tint = COLOR.rgb;
	vec2 d = MODEL_MATRIX[3].xz - eye_pos.xz;
	near_vis = 1.0 - smoothstep(fade_start, fade_end, length(d));
}

void fragment() {
	if (near_vis > 0.001 && dither(FRAGCOORD.xy) < near_vis) {
		discard;
	}
	vec4 c = texture(atlas, UV);
	// Mipmaps average leaf alpha with the gaps, so with a fixed 0.5 cut-off distant crowns thin out
	// and sparkle. Raise alpha with the mip level to keep their coverage (Golus, "anti-aliased
	// alpha test"). The LOD comes from the UV derivatives (textureQueryLod is not in GLES3).
	vec2 texel = UV * vec2(textureSize(atlas, 0));
	vec2 dx = dFdx(texel);
	vec2 dy = dFdy(texel);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALBEDO = c.rgb * tint;
	ALPHA = clamp(c.a * (1.0 + lod * 0.25), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
