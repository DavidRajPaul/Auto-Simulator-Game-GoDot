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

varying vec2 cell;
varying vec3 paint;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
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
