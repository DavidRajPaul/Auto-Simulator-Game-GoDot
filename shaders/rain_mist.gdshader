shader_type spatial;
// Tyre spray (RainSplashes.gd): soft, round, faint mist puffs on CPUParticles3D. Nov 14 owner
// report: the old spray was untextured quads that flew back into the chase camera and filled the
// screen with white boxes. Each puff is a round soft blob, lit by the scene, and it fades out
// before it gets close to the lens.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform float opacity = 0.13;

varying float cam_fade;

void vertex() {
	// Face the camera (particle billboard, keeping the particle's own scale).
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
	vec3 world = MODEL_MATRIX[3].xyz;
	cam_fade = smoothstep(4.0, 7.5, distance(world, CAMERA_POSITION_WORLD));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float blob = exp(-r * r * 3.0) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = vec3(0.78, 0.8, 0.83);
	ROUGHNESS = 1.0;
	ALPHA = clamp(blob * opacity * COLOR.a * cam_fade, 0.0, 1.0);
}
