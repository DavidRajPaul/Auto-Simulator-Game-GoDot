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
// Height of the model (model units), set by StreetTrees: how far up the tree a vertex is.
uniform float model_height = 8.0;
// Leaf cards with alpha (the CC BY trees, bake_cc_trees.py): cut at 0.5, in the shadow pass too.
uniform bool cutout = false;

// City wind (scripts/world/Wind.gd, project.godot [shader_globals]).
global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_gust;

varying float vis;
varying float leafy;

// Interleaved gradient noise: the same threshold per pixel in both tree shaders.
float dither(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	// MODEL_MATRIX already holds the MultiMesh instance transform: column 3 is the trunk base.
	vec2 d = MODEL_MATRIX[3].xz - eye_pos.xz;
	vis = 1.0 - smoothstep(fade_start, fade_end, length(d));
	// Wind (Nov 14): the whole tree leans and sways with the wind, more at the top (bend grows
	// with the square of height), each tree a little out of step; leaves flutter on top of that.
	// Identical in the shadow pass, so shadows sway with the tree. The far card leans the same.
	float h = clamp(VERTEX.y / max(model_height, 0.1), 0.0, 1.2);
	leafy = smoothstep(0.32, 0.6, h);
	float tree_h = model_height * length(MODEL_MATRIX[1].xyz);
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.131, 0.077));
	float push = wind_strength + 1.5 * wind_gust;
	float sway = tree_h * 0.03 * push * (0.7 + 0.3 * sin(TIME * (0.8 + wind_strength) + phase));
	vec3 w = vec3(wind_dir.x, 0.0, wind_dir.y);
	float flutter = 0.045 * push * leafy * sin(TIME * (5.0 + 3.0 * wind_gust) + dot(VERTEX, vec3(2.9, 1.7, 3.3)) + phase);
	vec3 disp = w * (sway * h * h + flutter) + vec3(0.0, flutter * 0.6 - sway * h * h * 0.12, 0.0);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * disp;
}

void fragment() {
	if (vis < 0.999 && dither(FRAGCOORD.xy) >= vis) {
		discard;
	}
	vec4 tex = texture(albedo_tex, UV);
	if (cutout) {
		// Mipmaps average thin leaves with the gaps around them, so with a fixed 0.5 cut the crown
		// goes bare a few metres away. Raise alpha with the mip level (as tree_impostor does).
		vec2 texel = UV * vec2(textureSize(albedo_tex, 0));
		vec2 ddx = dFdx(texel);
		vec2 ddy = dFdy(texel);
		float lod = max(0.0, 0.5 * log2(max(dot(ddx, ddx), dot(ddy, ddy))));
		if (tex.a * (1.0 + lod * 0.4) < 0.5) {
			discard;
		}
	}
	ALBEDO = tex.rgb * COLOR.rgb;
	// Sun through the leaves: a thin crown glows when lit from behind (as in real foliage).
	BACKLIGHT = ALBEDO * 0.35 * leafy;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	ROUGHNESS = 1.0;
}
