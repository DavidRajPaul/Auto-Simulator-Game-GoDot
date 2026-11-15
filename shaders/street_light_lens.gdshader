// A street lamp seen from the road at night (scripts/world/StreetLights.gd): the LED lens and the
// glow it makes in Chennai's humid air, one camera-facing card per lamp, added on top.
// Far lamps keep a minimum size on screen so a line of lights runs down the road into the haze.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float on = 0.0;
uniform float wet = 0.0;
uniform float halo_m = 1.7;       // glow radius near the lamp (m)
uniform float halo_frac = 0.02;   // far away the halo is at least this share of the distance
uniform float lens_frac = 0.004;  // and the lens at least ~3 px across on a phone

varying float size;
varying float core;
varying float far;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	vec3 centre = MODEL_MATRIX[3].xyz;
	float d = length(CAMERA_POSITION_WORLD - centre);
	size = max(halo_m * (1.0 + 0.6 * wet), d * halo_frac * (1.0 + 0.5 * wet));
	core = clamp(max(0.28, d * lens_frac) / size, 0.02, 0.45); // the lens is ~0.5 m across
	far = smoothstep(60.0, 450.0, d);
	// Billboard: the card faces the camera, sized in world metres.
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = centre + (right * VERTEX.x + up * VERTEX.y) * size * 2.0;
	// Lamps face down: from below the lens is bright, from above it hides in the housing.
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	vec3 tint = custom.rgb;
	float lens = smoothstep(core, core * 0.4, r) * 4.0;
	// Bloom round the lens (tight) and the haze it lights (wide); both scale with the card.
	float rc = r / max(core, 0.001);
	float glow = exp(-rc * rc * 0.15) * 0.75 + exp(-r * r * 3.0) * (0.22 + 0.3 * wet);
	// Distance and humidity soften the lens into the glow.
	float a = (lens * (1.0 - 0.5 * far) + glow) * custom.a * on;
	ALBEDO = tint * a * mix(1.0, 0.75, far);
}
