shader_type spatial;
render_mode cull_disabled;
uniform vec4 ocean_blue : source_color = vec4(0.03, 0.24, 0.38, 1.0);
void fragment() {
  vec2 p = UV * 35.0;
  float a = sin(p.x * 2.0 + TIME * 1.4 + sin(p.y * 0.7));
  float b = sin(p.y * 2.5 - TIME * 1.1);
  float wave = 0.5 + 0.25 * a + 0.25 * b;
  ALBEDO = mix(ocean_blue.rgb, vec3(0.25, 0.62, 0.72), wave);
  ALBEDO = mix(ALBEDO, vec3(0.83, 0.91, 0.90), smoothstep(0.88, 0.99, wave) * 0.65);
  ROUGHNESS = 0.32;
}
