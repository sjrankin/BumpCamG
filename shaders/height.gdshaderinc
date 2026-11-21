// Shared by the shape and wireframe shaders: reads a cell's colour from the reduced image and turns
// it into a height, so both draw the same relief.

uniform sampler2D grid_tex : filter_nearest, repeat_disable;
uniform ivec2 grid_dims = ivec2(64, 36);
uniform float cell_size = 0.25;
uniform float height_amount = 2.0;
uniform int height_mode = 1;
uniform bool height_invert = false;
uniform int color_mode = 0;
uniform float levels = 4.0;

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

// The grid cell an instance sits in, from its centre position.
ivec2 cell_of(vec3 center) {
	vec2 half_dims = (vec2(grid_dims) - 1.0) * 0.5;
	int cx = int(round(center.x / cell_size + half_dims.x));
	int cy = int(round(half_dims.y - center.y / cell_size));
	return clamp(ivec2(cx, cy), ivec2(0), grid_dims - ivec2(1));
}

// The cell's colour after the colour mode (grayscale / posterized) has been applied.
vec3 cell_rgb(ivec2 cell) {
	vec3 c = texelFetch(grid_tex, cell, 0).rgb;
	if (color_mode == 1) {
		c = vec3(dot(c, vec3(0.299, 0.587, 0.114)));
	} else if (color_mode == 2) {
		c = floor(c * levels + 0.5) / levels;
	}
	return c;
}

// Height of a node (clamped to the grid), in scene units.
float node_height(ivec2 node) {
	ivec2 n = clamp(node, ivec2(0), grid_dims - ivec2(1));
	return clamp(height_value(cell_rgb(n)), 0.0, 1.0) * height_amount;
}
