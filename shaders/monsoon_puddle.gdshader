shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Cheap procedural ripples on waterlogged Chennai roads.
// No screen-space reflections, normal textures or fluid solver.
uniform vec4 muddy_water : source_color = vec4(0.31, 0.29, 0.24, 0.8);
uniform float ripple_scale : hint_range(0.1, 12.0) = 3.0;
uniform float ripple_speed : hint_range(0.0, 4.0) = 1.2;
uniform float ripple_strength : hint_range(0.0, 0.4) = 0.12;

void fragment() {
    vec2 p = UV * ripple_scale * 8.0;
    float a = sin(length(p - vec2(2.0, 3.0)) * 2.4 - TIME * ripple_speed * 5.0);
    float b = sin(length(p - vec2(8.0, 6.0)) * 2.1 - TIME * ripple_speed * 4.1);
    float wave = (a + b) * 0.5;
    ALBEDO = muddy_water.rgb * (0.94 + wave * ripple_strength);
    ROUGHNESS = 0.19;
    METALLIC = 0.03;
    SPECULAR = 0.55;
    NORMAL_MAP = vec3(0.5 + 0.08 * a, 0.5 + 0.08 * b, 1.0);
    NORMAL_MAP_DEPTH = 0.35;
    ALPHA = muddy_water.a;
}
