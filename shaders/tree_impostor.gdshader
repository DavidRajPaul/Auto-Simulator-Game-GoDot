// Distant trees share one billboard batch. Each seeded tree yaw selects a fixed atlas view.
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
varying vec2 atlas_uv;
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
	// ax comes from the tree's seeded placement rotation, independent of the camera.
	float angle = atan(ax.z, ax.x);
	float column = floor(angle * views / 3.14159265 + 0.5);
	atlas_uv = view_uv(column, qx * 0.5 + 0.5, qy, INSTANCE_CUSTOM.x);
	tint = COLOR.rgb;
	vec2 d = origin.xz - eye_pos.xz;
	near_vis = 1.0 - smoothstep(fade_start, fade_end, length(d));
}

void fragment() {
	if (near_vis > 0.001 && fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) < near_vis) {
		discard;
	}
	vec4 c = texture(atlas, atlas_uv);
	// Mipmaps average leaf alpha with the gaps, so with a fixed 0.5 cut-off distant crowns thin out
	// and sparkle. Raise alpha with the mip level to keep their coverage (Golus, "anti-aliased
	// alpha test"). The LOD comes from the UV derivatives (textureQueryLod is not in GLES3).
	vec2 texel = atlas_uv * vec2(textureSize(atlas, 0));
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
