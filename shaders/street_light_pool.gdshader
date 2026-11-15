// The pool of light a street lamp throws on the road at night (scripts/world/StreetLights.gd).
// One flat quad per lamp, 2 h across × 3 h along the road (h = fitting height), added on top of
// the lit scene. Illuminance from a point source at height h on the ground below it:
//   E = I(γ) · cos γ / r² = I(γ) · h / r³  →  E / E0 = I(γ)/I0 · (1 + a² + b²)^-1.5
// with a, b the across / along offsets in units of h. I(γ) follows a road-lighting optic that
// throws light up and down the road (it peaks ~60° off vertical along the road and is cut off
// past ~75°), which is what draws the long bright ovals of a lit road at night.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float on = 0.0;        // dusk → night (StreetLights.lit)
uniform float wet = 0.0;       // raining: puddled asphalt mirrors the lamp towards the camera
uniform float strength = 0.42; // nadir brightness of a 9 m lamp on asphalt (calibrated in shots)

varying vec2 ab;      // across, along offset / h
varying float h;
varying vec3 world;
varying vec3 centre;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	h = length(MODEL_MATRIX[0].xyz) * 0.5;
	ab = vec2(VERTEX.x * 2.0, VERTEX.z * 3.0);
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	centre = MODEL_MATRIX[3].xyz;
}

void fragment() {
	float r2 = 1.0 + ab.x * ab.x + ab.y * ab.y;
	float cos3 = pow(r2, -1.5);
	// Road optic: more intensity along the road, less across it; cut off near the horizon.
	float along = abs(ab.y);
	float optic = 1.0 + 1.1 * smoothstep(0.3, 1.7, along) * exp(-ab.x * ab.x * 0.5);
	optic *= 1.0 - smoothstep(2.2, 2.95, along);
	optic *= 1.0 - smoothstep(1.4, 1.95, abs(ab.x));
	float e = cos3 * optic;
	// Asphalt is dark and rough: the light it gives back is soft and slightly warm-grey.
	vec3 tint = custom.rgb;
	float k = custom.a * strength * (81.0 / (h * h)) * 0.012 * h * h; // normalised to a 9 m pole
	vec3 light = tint * e * k;
	// Wet road: a narrow bright streak from the lamp's foot towards the viewer.
	if (wet > 0.0) {
		vec2 to_cam = CAMERA_POSITION_WORLD.xz - centre.xz;
		float dc = length(to_cam);
		vec2 dir = to_cam / max(dc, 0.001);
		vec2 rel = world.xz - centre.xz;
		float s = dot(rel, dir);
		float t = abs(rel.x * dir.y - rel.y * dir.x);
		float streak = exp(-t * t / (0.08 * h)) * smoothstep(-0.5, 1.0, s) * exp(-max(s, 0.0) / (2.2 * h));
		light += tint * streak * wet * k * 1.6;
		light *= 1.0 + 0.25 * wet;
	}
	ALBEDO = light * on;
}
