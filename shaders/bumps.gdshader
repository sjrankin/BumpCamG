shader_type spatial;
render_mode cull_disabled;

// Draws every grid cell from one MultiMesh. Each instance is placed at its cell centre; this shader
// looks up that cell's colour in the reduced image, scales the shape and lifts it by the chosen
// "height" channel. No per-frame CPU work is needed.

uniform sampler2D grid_tex : filter_nearest, repeat_disable;
uniform ivec2 grid_dims = ivec2(64, 36);
uniform float cell_size = 0.25;
uniform float shape_size = 0.95;
uniform float height_amount = 2.0;
uniform int height_mode = 1;
uniform bool height_invert = false;
uniform bool hue_pointer = false;
uniform bool bar_mode = true;
uniform int color_mode = 0;
uniform float levels = 4.0;
uniform float metallic_amount = 0.0;
uniform float roughness_amount = 0.6;

varying vec3 cell_color;

vec3 srgb_to_linear(vec3 c) {
	vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
	vec3 lo = c / 12.92;
	return mix(hi, lo, vec3(1.0) - step(vec3(0.04045), c));
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float selected_value(vec3 c) {
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	if (height_mode == 1) { return luma; }
	if (height_mode == 2) { return c.r; }
	if (height_mode == 3) { return c.g; }
	if (height_mode == 4) { return c.b; }
	if (height_mode == 5) { return rgb_to_hsv(c).y; }
	if (height_mode == 6) { return rgb_to_hsv(c).x; }
	return 0.0;
}

// "None" stays flat; otherwise the chosen value is optionally inverted.
float height_value(vec3 c) {
	float v = clamp(selected_value(c), 0.0, 1.0);
	if (height_mode == 0) { return 0.0; }
	return height_invert ? 1.0 - v : v;
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec2 half_dims = (vec2(grid_dims) - 1.0) * 0.5;
	int cx = int(round(center.x / cell_size + half_dims.x));
	int cy = int(round(half_dims.y - center.y / cell_size));
	ivec2 cell = clamp(ivec2(cx, cy), ivec2(0), grid_dims - ivec2(1));

	vec3 c = texelFetch(grid_tex, cell, 0).rgb;
	if (color_mode == 1) {
		c = vec3(dot(c, vec3(0.299, 0.587, 0.114)));
	} else if (color_mode == 2) {
		c = floor(c * levels + 0.5) / levels;
	}
	float h = clamp(height_value(c), 0.0, 1.0) * height_amount;
	cell_color = srgb_to_linear(c);

	if (hue_pointer) {
		// Turn clockwise by the hue of the sampled colour (0 = up, a quarter turn = red-to-green).
		float angle = -rgb_to_hsv(texelFetch(grid_tex, cell, 0).rgb).x * 6.28318530718;
		mat2 turn = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
		VERTEX.xy = turn * VERTEX.xy;
		NORMAL.xy = turn * NORMAL.xy;
	}
	if (bar_mode) {
		VERTEX.xy *= cell_size * shape_size;
		VERTEX.z = (VERTEX.z + 0.5) * max(h, cell_size * 0.1);
	} else {
		VERTEX *= cell_size * shape_size;
		VERTEX.z += h;
	}
}

void fragment() {
	ALBEDO = cell_color;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
