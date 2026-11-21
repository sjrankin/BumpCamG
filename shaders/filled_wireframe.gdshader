shader_type spatial;
render_mode cull_disabled;

// A wireframe whose cells are filled in. Each instance draws the quad between its node and the
// three nodes to the right and below (two triangles, COLOR.r = 1) plus the two wire segments along
// its top and left edges (COLOR.r = 0). The vertex positions encode which neighbour each corner
// belongs to, as in `wireframe.gdshader`. Corners take their node's colour, so the fill blends
// smoothly from node to node; the wires are a darker shade of the same colour.

#include "res://shaders/height.gdshaderinc"

uniform float metallic_amount = 0.0;
uniform float roughness_amount = 0.6;

varying vec3 cell_color;
varying float is_fill;

void vertex() {
	ivec2 cell = cell_of(MODEL_MATRIX[3].xyz);
	ivec2 step_to = ivec2(int(round(VERTEX.x)), -int(round(VERTEX.y)));
	ivec2 node = cell + step_to;
	if (node.x < 0 || node.y < 0 || node.x >= grid_dims.x || node.y >= grid_dims.y) {
		node = cell;
		step_to = ivec2(0);
	}
	vec3 c = cell_rgb(node);
	cell_color = srgb_to_linear(c);
	is_fill = COLOR.r;

	// Slope of the relief at this node, for lighting.
	float dx = (node_height(node + ivec2(1, 0)) - node_height(node - ivec2(1, 0))) / (2.0 * cell_size);
	float dy = (node_height(node - ivec2(0, 1)) - node_height(node + ivec2(0, 1))) / (2.0 * cell_size);
	NORMAL = normalize(vec3(-dx, -dy, 1.0));

	float h = node_height(node);
	VERTEX = vec3(float(step_to.x), -float(step_to.y), 0.0) * cell_size;
	// Lift the wires a hair so they are not swallowed by the fill beneath them.
	VERTEX.z = h + (1.0 - COLOR.r) * cell_size * 0.03;
}

void fragment() {
	if (is_fill > 0.5) {
		ALBEDO = cell_color;
		METALLIC = metallic_amount;
		ROUGHNESS = roughness_amount;
	} else {
		ALBEDO = vec3(0.0);
		EMISSION = cell_color * 0.35;
	}
}
