// Near street trees (scripts/world/StreetTrees.gd): the owner's textured model, one MultiMesh per
// species. Instance COLOR is the per-tree tint. Between fade_start and fade_end (horizontal distance
// from eye_pos to the tree's trunk) the model dissolves with a screen-space dither while the far
// impostor card (tree_impostor.gdshader) fills exactly the complementary pixels, so a tree never
// pops between the two (Nov 3 device test: the hard 60 m swap read as a glitch when driving up).
// eye_pos is the real camera, set by StreetTrees: CAMERA_POSITION_WORLD would be the light's
// camera in the shadow pass and dissolve every tree shadow.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 eye_pos = vec3(0.0);
uniform float fade_start = 50.0;
uniform float fade_end = 62.0;

varying float vis;

// Interleaved gradient noise: the same threshold per pixel in both tree shaders.
float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	// MODEL_MATRIX already holds the MultiMesh instance transform: column 3 is the trunk base.
	vec2 d = MODEL_MATRIX[3].xz - eye_pos.xz;
	vis = 1.0 - smoothstep(fade_start, fade_end, length(d));
}

void fragment() {
	if (vis < 0.999 && dither(FRAGCOORD.xy) >= vis) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * COLOR.rgb;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	ROUGHNESS = 1.0;
}
