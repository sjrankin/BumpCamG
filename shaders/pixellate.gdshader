shader_type canvas_item;

// Reduces the source image (still or camera) to one pixel per grid cell by averaging a block of
// samples. The result is rendered into a small SubViewport whose texture drives the 3D shader.

const int TAPS = 6;

uniform sampler2D src : filter_linear_mipmap, repeat_disable;
uniform sampler2D src2 : filter_linear, repeat_disable;
// 0 = RGB, 1 = packed YCbCr in one texture, 2 = Y in src and CbCr in src2 (macOS cameras).
uniform int cam_mode = 0;
uniform bool has_mipmaps = true;
uniform vec2 src_size = vec2(1.0);
uniform vec2 grid_size = vec2(64.0, 36.0);
uniform bool flip_x = false;
uniform bool flip_y = false;

void fragment() {
	vec2 cell_uv = 1.0 / grid_size;
	// Mip level that makes each tap already cover about 1/TAPS of a cell.
	float lod = has_mipmaps ? max(log2(src_size.x / grid_size.x / float(TAPS)), 0.0) : 0.0;
	vec3 sum = vec3(0.0);
	for (int y = 0; y < TAPS; y++) {
		for (int x = 0; x < TAPS; x++) {
			vec2 o = (vec2(float(x), float(y)) + 0.5) / float(TAPS) - 0.5;
			vec2 s = UV + o * cell_uv;
			if (flip_x) { s.x = 1.0 - s.x; }
			if (flip_y) { s.y = 1.0 - s.y; }
			vec3 t = textureLod(src, s, lod).rgb;
			if (cam_mode == 2) {
				vec2 cc = texture(src2, s).rg - 0.5;
				t = vec3(t.r + 1.402 * cc.y, t.r - 0.344 * cc.x - 0.714 * cc.y, t.r + 1.772 * cc.x);
			} else if (cam_mode == 1) {
				t = vec3(t.r + 1.402 * (t.b - 0.5), t.r - 0.344 * (t.g - 0.5) - 0.714 * (t.b - 0.5), t.r + 1.772 * (t.g - 0.5));
			}
			sum += clamp(t, 0.0, 1.0);
		}
	}
	COLOR = vec4(sum / float(TAPS * TAPS), 1.0);
}
