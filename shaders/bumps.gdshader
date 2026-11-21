shader_type spatial;
render_mode cull_disabled;

// Draws every grid cell from one MultiMesh. Each instance is placed at its cell centre; this shader
// looks up that cell's colour in the reduced image, scales the shape and lifts it by the chosen
// "height" channel. No per-frame CPU work is needed.

#include "res://shaders/height.gdshaderinc"

uniform float shape_size = 0.95;
uniform bool hue_pointer = false;
uniform bool bar_mode = true;
uniform float metallic_amount = 0.0;
uniform float roughness_amount = 0.6;

varying vec3 cell_color;

void vertex() {
	ivec2 cell = cell_of(MODEL_MATRIX[3].xyz);
	vec3 c = cell_rgb(cell);
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
