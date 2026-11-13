shader_type spatial;
// Chennai facades from one 8×8 atlas (assets/textures/facade_atlas.png). One draw call per chunk.
//   UV  = repeating bay/floor coordinates (u: window bays along the wall, v: floors from the ground)
//   UV2 = atlas cell (column, row) for this quad
//   COLOR = the building's paint; atlas alpha says where paint applies (plaster) vs. fixed colours.
// At night the glow atlas lights windows, shop interiors and signboards.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow : source_color, filter_linear_mipmap, repeat_disable;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cells = vec2(8.0, 8.0);
// Atlas width in pixels: the mip level is capped so far walls never blend neighbouring cells.
uniform float atlas_px = 2048.0;
const float MAX_TEXELS_PER_PIXEL = 4.0;
// Shift clock 0–24 (WorldChunkStreamer). Push-cart shops carry open-only / closed-only parts:
// UV2.y = atlas row + 100 * gate (gate 1 = open part, 2 = closed part), UV = 0.3 + open hour,
// 0.5 + close hour (close may pass 24; open == close = shut all day). The wrong part collapses to
// a point. The gate must NOT be read from UV: roof UVs are world metres / 6 and run into the
// hundreds, so a UV test caught real roofs and stretched them across the sky.
uniform float clock_hour = 12.0;

varying vec2 cell;
varying vec3 paint;
varying float ground_dirt;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	cell = UV2;
	if (UV2.y > 50.0) {
		float gate = floor(UV2.y / 100.0);
		cell.y = UV2.y - gate * 100.0;
		float open_h = floor(UV.x);
		float close_h = floor(UV.y);
		bool is_open = (clock_hour >= open_h && clock_hour < close_h) || (clock_hour + 24.0 >= open_h && clock_hour + 24.0 < close_h);
		if (is_open != (gate < 1.5)) {
			VERTEX = vec3(0.0);
		}
	}
	// Soften the palette a touch: sun-bleached Chennai paint, not fresh poster colours.
	paint = mix(srgb_to_linear(COLOR.rgb), vec3(0.75), 0.18);
	// Road dust and rain splash: painted plaster darkens over its first metre above the ground.
	ground_dirt = 1.0 - smoothstep(0.0, 1.3, (MODEL_MATRIX * vec4(VERTEX, 1.0)).y);
}

void fragment() {
	// Keep a 2% gutter so bilinear filtering never bleeds into the neighbouring cell,
	// and take mip derivatives from the continuous UV (fract() would cause seams).
	vec2 f = clamp(vec2(fract(UV.x), 1.0 - fract(UV.y)), 0.02, 0.98);
	vec2 auv = (cell + f) / cells;
	vec2 dx = dFdx(UV) / cells;
	vec2 dy = dFdy(UV) / cells;
	float reach = max(length(dx), length(dy)) * atlas_px;
	if (reach > MAX_TEXELS_PER_PIXEL) {
		dx *= MAX_TEXELS_PER_PIXEL / reach;
		dy *= MAX_TEXELS_PER_PIXEL / reach;
	}
	vec4 t = textureGrad(atlas, auv, dx, dy);
	ALBEDO = mix(t.rgb, t.rgb * paint * (1.0 - 0.16 * ground_dirt), t.a);
	ROUGHNESS = mix(0.35, 0.92, t.a);
	SPECULAR = 0.3;
	EMISSION = textureGrad(glow, auv, dx, dy).rgb * night * 1.4;
}
