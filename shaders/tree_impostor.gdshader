// Far street trees (scripts/world/StreetTrees.gd): ONE upright card per tree that turns to face the
// camera, all species in ONE MultiMesh. The atlas (tools/assets/bake_trees.py) has one row per
// species and one column per baked view; view k looks along d(k) = (sin, 0, -cos)(PI k / views) in
// the tree's own (unyawed) space with screen-right a(k) = (cos, 0, sin)(PI k / views). The card
// picks the two baked views either side of the real view direction and blends them, and uses the
// mirror image for the far half of the circle (seen from behind, a view is its own mirror).
// INSTANCE_CUSTOM.x picks the species row; instance COLOR is the per-tree tint the near model gets.
//
// Nov 4 device test ("tree glitch still there"): the old 4 crossed cards were lit by straight-up
// normals (full sun), so every tree was a pale flat blob until 56 m and then turned into the dark
// self-shadowed model; seen edge-on a card was a thin bright slab; and 4 overlapping alpha-tested
// cards cost 4x overdraw. Now: one card, the silhouette from the matching view, lit and toned to
// match the near model (card_tone / normal tilt calibrated against tree_near renders).
//
// Inside the fade band the card draws exactly the pixels the near model (tree_near.gdshader)
// dissolves, with the same dither and distance, so the swap is a short cross-fade, not a pop.
shader_type spatial;
render_mode cull_disabled, specular_disabled, skip_vertex_transform;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float rows = 5.0;
uniform float views = 4.0;
uniform vec3 eye_pos = vec3(0.0);
uniform float fade_start = 50.0;
uniform float fade_end = 62.0;
// Albedo scale and how far the normal leans from facing the camera towards the sky: together they
// make a card as bright as the lit, self-shadowed model it stands in for.
uniform float card_tone = 0.75;
uniform float sky_lean = 0.45;

varying vec3 tint;
varying float near_vis;
varying vec2 uv_a;
varying vec2 uv_b;
varying float view_mix;
varying vec3 card_normal;

// Atlas UV for baked view column `c` (0 .. 2 views - 1; the upper half are mirrored views).
vec2 view_uv(float c, float u, float y, float row) {
	float col = mod(c, 2.0 * views);
	float mirrored = step(views, col);
	col -= mirrored * views;
	float img_u = mix(u, 1.0 - u, mirrored);
	// Keep half a texel off the cell edges so the neighbour column never bleeds in.
	img_u = clamp(img_u, 0.004, 0.996);
	return vec2((col + img_u) / views, (1.0 - y + row) / rows);
}

void vertex() {
	// The card mesh is one quad: x in [-1, 1] across, y in [0, 1] up (StreetTrees._impostor_mesh).
	float qx = VERTEX.x;
	float qy = VERTEX.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float radius = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 ax = MODEL_MATRIX[0].xyz / max(radius, 1e-4);
	vec3 az = normalize(MODEL_MATRIX[2].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec2 to = origin.xz - cam.xz;
	float len = length(to);
	vec2 v = len > 1e-3 ? to / len : vec2(0.0, -1.0);
	vec3 dir = vec3(v.x, 0.0, v.y);
	// Upright billboard: right = cross(view dir, up), the baked views' screen-right convention.
	vec3 right = vec3(-v.y, 0.0, v.x);
	vec3 world = origin + right * (qx * radius) + vec3(0.0, qy * height, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	vec3 n = normalize(-dir + vec3(0.0, sky_lean * 2.0, 0.0));
	card_normal = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = card_normal;
	// View angle in the tree's own space -> the two nearest baked views and the blend between.
	float theta = atan(dot(dir, ax), -dot(dir, az));
	theta = theta < 0.0 ? theta + 6.2831853 : theta;
	float f = theta / (3.14159265 / views);
	float k = floor(f);
	view_mix = f - k;
	float u = qx * 0.5 + 0.5;
	uv_a = view_uv(k, u, qy, INSTANCE_CUSTOM.x);
	uv_b = view_uv(k + 1.0, u, qy, INSTANCE_CUSTOM.x);
	tint = COLOR.rgb;
	vec2 d = origin.xz - eye_pos.xz;
	near_vis = 1.0 - smoothstep(fade_start, fade_end, length(d));
}

void fragment() {
	if (near_vis > 0.001 && fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) < near_vis) {
		discard;
	}
	vec4 c = mix(texture(atlas, uv_a), texture(atlas, uv_b), view_mix);
	// Mipmaps average leaf alpha with the gaps, so with a fixed 0.5 cut-off distant crowns thin out
	// and sparkle. Raise alpha with the mip level to keep their coverage (Golus, "anti-aliased
	// alpha test"). The LOD comes from the UV derivatives (textureQueryLod is not in GLES3).
	vec2 texel = uv_a * vec2(textureSize(atlas, 0));
	vec2 dx = dFdx(texel);
	vec2 dy = dFdy(texel);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALBEDO = c.rgb * tint * card_tone;
	ALPHA = clamp(c.a * (1.0 + lod * 0.25), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Set here, not only in vertex(): with cull_disabled Godot flips the normal of a back face, and
	// which side of the billboard faces the camera is arbitrary - a flipped card went dark brown.
	NORMAL = card_normal;
	ROUGHNESS = 1.0;
}
