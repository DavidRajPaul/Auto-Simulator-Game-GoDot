shader_type spatial;
// Side quest marker: flat ring + small gem. The gem (UV.x = 1) spins and bobs about its own axis.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

void vertex() {
	if (UV.x > 0.5) {
		float a = TIME * 1.6;
		float c = cos(a);
		float s = sin(a);
		VERTEX.xz = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xz;
		VERTEX.y += sin(TIME * 2.0) * 0.12;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
