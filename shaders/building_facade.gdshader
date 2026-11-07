shader_type spatial;
// Chennai facades from one 8×4 atlas (assets/textures/facade_atlas.png). One draw call per chunk.
//   UV  = repeating bay/floor coordinates (u: window bays along the wall, v: floors from the ground)
//   UV2 = atlas cell (column, row) for this quad
//   COLOR = the building's paint; atlas alpha says where paint applies (plaster) vs. fixed colours.
// At night the glow atlas lights windows, shop interiors and signboards.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow : source_color, filter_linear_mipmap, repeat_disable;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec2 cells = vec2(8.0, 4.0);
// Shift clock 0–24 (WorldChunkStreamer). Push-cart shops carry open-only / closed-only parts:
// UV.x = 0.3 + 100 * gate + open hour, UV.y = 0.5 + close hour (gate 1 = open part, 2 = closed
// part; close may pass 24; open == close = shut all day). The wrong part collapses to a point.
uniform float clock_hour = 12.0;

varying vec2 cell;
varying vec3 paint;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	if (UV.x > 50.0) {
		float gate = floor(UV.x / 100.0);
		float open_h = floor(UV.x) - gate * 100.0;
		float close_h = floor(UV.y);
		bool is_open = (clock_hour >= open_h && clock_hour < close_h) || (clock_hour + 24.0 >= open_h && clock_hour + 24.0 < close_h);
		if (is_open != (gate < 1.5)) {
			VERTEX = vec3(0.0);
		}
	}
	cell = UV2;
	// Soften the palette a touch: sun-bleached Chennai paint, not fresh poster colours.
	paint = mix(srgb_to_linear(COLOR.rgb), vec3(0.75), 0.18);
}

void fragment() {
	// Keep a 1.5% gutter so bilinear filtering never bleeds into the neighbouring cell,
	// and take mip derivatives from the continuous UV (fract() would cause seams).
	vec2 f = clamp(vec2(fract(UV.x), 1.0 - fract(UV.y)), 0.015, 0.985);
	vec2 auv = (cell + f) / cells;
	vec2 dx = dFdx(UV) / cells;
	vec2 dy = dFdy(UV) / cells;
	vec4 t = textureGrad(atlas, auv, dx, dy);
	ALBEDO = mix(t.rgb, t.rgb * paint, t.a);
	ROUGHNESS = mix(0.35, 0.92, t.a);
	SPECULAR = 0.3;
	EMISSION = textureGrad(glow, auv, dx, dy).rgb * night * 1.4;
}
