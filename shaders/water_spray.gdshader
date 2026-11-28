shader_type spatial;
// Spray thrown up by the player auto's wheels in standing water (AutoRickshawController): wheel
// spray and the bow wave pushed out from the front wheel in a flood. Each particle is a soft,
// round, slightly lumpy blob of muddy water (no texture, no square edges: the Nov 14 "white boxes"
// report), lit by the scene so it is grey in rain and dark at night, faded out close to the lens
// so it never fills the chase camera. COLOR.a (from the particle colour ramp) fades it over life.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec3 water_colour : source_color = vec3(0.72, 0.7, 0.64);
uniform float opacity = 0.42;

varying float cam_fade;

void vertex() {
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
	cam_fade = smoothstep(1.6, 3.2, distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD));
}

void fragment() {
	vec2 d = UV - 0.5;
	float a = atan(d.y, d.x);
	// A lumpy edge: a splash of drops, not a disc.
	float edge = 0.44 + 0.025 * sin(a * 3.0 + COLOR.r * 31.0) + 0.015 * sin(a * 5.0 + COLOR.g * 17.0);
	float r = length(d);
	float blob = 1.0 - smoothstep(edge * 0.25, edge, r);
	float core = 1.0 - smoothstep(0.0, edge * 0.7, r);
	ALBEDO = water_colour * (0.85 + 0.25 * core);
	ROUGHNESS = 0.4;
	ALPHA = clamp(blob * opacity * COLOR.a * cam_fade, 0.0, 1.0);
}
