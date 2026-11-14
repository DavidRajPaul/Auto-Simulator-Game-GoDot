// Roads, footpaths, paved plots and the open ground: one material, one draw call per chunk.
// The mesh carries a colour per vertex and the surface kind in UV.x; the look comes from
// assets/textures/ground_detail.png (tools/art/make_ground_detail.py): four grey detail maps in
// one texture (R asphalt, G pavers, B concrete, A wear), sampled in world space so nothing
// stretches and chunks join without a seam.
//   kind 0 asphalt (road, junction)   1 footpath pavers   2 road paint
//        3 cement forecourt           4 paver frontage    5 bare ground
// Two lookups per pixel (one with `rich` off, the Low graphics preset).
// UV.y is the road's condition (WorldChunkStreamer.road_condition, a slow world-space noise):
// below ~0.45 a clean road, above it a dusty one (sand drifted in from the kerbs), above ~0.6 a
// broken one with potholes. Potholes are a small procedural noise (no lookup), evaluated only on
// broken stretches; in rain they fill with water.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform float wet = 0.0;
uniform bool rich = true;
// The ground plane has no per-vertex data: it sets its kind and colour here.
uniform float fixed_kind = -1.0;
uniform vec3 fixed_colour : source_color = vec3(0.5, 0.46, 0.4);
// Asphalt showing through worn paint.
uniform vec3 asphalt_colour : source_color = vec3(0.31, 0.31, 0.32);

varying vec2 wpos;
varying float kind;
varying vec3 tint;
varying float cond;

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	kind = fixed_kind >= 0.0 ? fixed_kind : UV.x;
	tint = fixed_kind >= 0.0 ? fixed_colour : srgb_to_linear(COLOR.rgb);
	cond = fixed_kind >= 0.0 ? 0.0 : UV.y;
}

void fragment() {
	float k = floor(kind + 0.5);
	// Detail scale by material: blocks are 20 cm, aggregate is fine, cement is broad.
	float tile = (k == 1.0 || k == 4.0) ? 1.6 : ((k == 0.0 || k == 2.0) ? 3.2 : 4.0);
	vec4 d = texture(detail, wpos / tile);
	float wear = 0.4;
	if (rich) {
		// Rotated, so repair patches never line up with a road or repeat along it.
		wear = texture(detail, mat2(vec2(0.848, 0.53), vec2(-0.53, 0.848)) * wpos / 53.0).a;
	}
	vec3 col = tint;
	float rough = 0.95;
	float hole = 0.0;
	if (k == 0.0 || k == 2.0) {
		vec3 base = (k == 0.0) ? tint : asphalt_colour;
		// Chennai asphalt is sun-bleached mid-grey, not fresh black.
		vec3 road = base * 2.0 * (0.6 + 0.8 * d.r);
		// Sun-bleached stretches, then fresh repair patches and a trench scar, both darker and smoother.
		road = mix(road, road * 1.35 + 0.012, smoothstep(0.3, 0.6, wear) * (1.0 - step(0.74, wear)));
		float patch = step(0.87, wear);
		float trench = step(0.74, wear) * (1.0 - patch);
		road = mix(road, base * 1.05 * (0.85 + 0.3 * d.r), patch);
		road = mix(road, base * 1.3 * (0.8 + 0.4 * d.r), trench);
		// Dusty roads: sand and grit drifted over the asphalt, thickest in blotches.
		float dusty = smoothstep(0.45, 0.6, cond);
		float drift = dusty * smoothstep(0.38, 0.62, d.b * 0.45 + wear * 0.65);
		road = mix(road, vec3(0.43, 0.37, 0.28) * (0.75 + 0.5 * d.r), drift * 0.62 * (1.0 - wet * 0.5));
		// Broken roads: potholes with a pale crumbled rim; puddles when it rains.
		float broken = smoothstep(0.6, 0.7, cond) * (1.0 - patch);
		if (broken > 0.01) {
			float n = vnoise(wpos * 0.9) * 0.7 + vnoise(wpos * 2.3 + 7.0) * 0.3 + (d.r - 0.5) * 0.1;
			float limit = 0.2 + 0.12 * broken;
			hole = 1.0 - smoothstep(limit - 0.035, limit, n);
			float rim = (1.0 - smoothstep(limit, limit + 0.06, n)) * (1.0 - hole);
			road = mix(road, road * 1.3 + vec3(0.05, 0.045, 0.035), rim * 0.7);
			road = mix(road, vec3(0.14, 0.12, 0.1) * (0.5 + 1.1 * d.r), hole);
		}
		col = road;
		if (k == 2.0) {
			// Thermoplastic paint, chipped where the aggregate stands proud and gone over repairs.
			float keep = smoothstep(0.30, 0.46, 1.0 - d.r * 0.55 - wear * 0.45) * (1.0 - patch) * (1.0 - hole) * (1.0 - 0.5 * drift);
			col = mix(road, tint * (0.8 + 0.3 * d.g), keep * 0.92);
		}
	} else if (k == 1.0 || k == 4.0) {
		col = tint * (0.55 + 0.9 * d.g);
		// Footpath stretches relaid in red blocks.
		if (k == 1.0) {
			col = mix(col, col * vec3(1.25, 0.82, 0.72), smoothstep(0.53, 0.57, wear) * (1.0 - step(0.74, wear)) * 0.5);
		}
		rough = 0.9;
	} else if (k == 3.0) {
		col = tint * (0.7 + 0.6 * d.b);
		vec2 j = abs(fract(wpos / 3.0) - 0.5);           // expansion joints every 3 m
		col *= 1.0 - 0.28 * step(0.493, max(j.x, j.y));
		col *= mix(1.0, 0.8, smoothstep(0.42, 0.62, wear));  // damp, shaded corners
		rough = 0.88;
	} else {
		col = tint * (0.6 + 0.8 * (d.b * 0.5 + d.r * 0.5));
		col = mix(col, col * vec3(0.78, 0.76, 0.72), smoothstep(0.3, 0.6, wear));
	}
	// A pothole in the rain is a brown puddle: darker and mirror-smooth.
	float puddle = hole * wet;
	ALBEDO = mix(col * mix(1.0, 0.78, wet), vec3(0.2, 0.17, 0.13), puddle * 0.8);
	ROUGHNESS = mix(mix(rough, 0.3, wet), 0.06, puddle);
	SPECULAR = mix(0.5, 0.9, wet);
}
