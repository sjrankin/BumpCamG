shader_type spatial;
render_mode unshaded, cull_disabled;

// A continuous wireframe over the grid. Every instance contributes two line segments, from its node
// to the next node to the right and the next one down. The mesh vertices encode which neighbour
// each end belongs to (x = columns to the right, y = rows down, negated); this shader lifts every
// end by its own cell's height, the same way the shapes are lifted, so the lines join up.

#include "res://shaders/height.gdshaderinc"

varying vec3 cell_color;

void vertex() {
	ivec2 cell = cell_of(MODEL_MATRIX[3].xyz);
	ivec2 step_to = ivec2(int(round(VERTEX.x)), -int(round(VERTEX.y)));
	ivec2 node = cell + step_to;
	// Nodes past the edge collapse onto this one, leaving a zero-length line.
	if (node.x < 0 || node.y < 0 || node.x >= grid_dims.x || node.y >= grid_dims.y) {
		node = cell;
		step_to = ivec2(0);
	}
	vec3 c = cell_rgb(node);
	cell_color = srgb_to_linear(c);
	float h = clamp(height_value(c), 0.0, 1.0) * height_amount;
	VERTEX = vec3(float(step_to.x), -float(step_to.y), 0.0) * cell_size;
	VERTEX.z = h;
}

void fragment() {
	ALBEDO = cell_color;
}
