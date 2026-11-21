class_name GridView
extends Node3D
## One MultiMesh of shapes, one per grid cell, coloured and lifted entirely on the GPU.
##
## Pipeline: source texture (camera or image) -> `pixellate.gdshader` renders it at one pixel per
## cell into a tiny SubViewport -> `bumps.gdshader` reads that texture per instance.

signal grid_changed

const SCENE_WIDTH := 16.0
const HEIGHT_MODES: Array[String] = [
	"None", "Brightness", "Red", "Green", "Blue", "Saturation", "Hue",
]
const COLOR_MODES: Array[String] = ["Color", "Grayscale", "Posterized"]

var material: ShaderMaterial
var pass_material: ShaderMaterial
var columns := 64
var rows := 36
var shape_name := "Blocks"
var height_amount := 2.0

var _multimesh: MultiMesh
var _viewport: SubViewport
var _rect: ColorRect
var _source: Texture2D
var _aspect := 16.0 / 9.0
var _last_source_size := Vector2i.ZERO


func _ready() -> void:
	_build_pass()
	_build_instances()
	_rebuild_grid()
	set_shape(shape_name)


## Size of the whole grid in scene units, used to fit the camera.
func scene_size() -> Vector2:
	return Vector2(SCENE_WIDTH, float(rows) * SCENE_WIDTH / float(columns))


## `camera_mode`: 0 RGB, 1 packed YCbCr, 2 separate Y (texture) and CbCr (`chroma`) planes.
func set_source(texture: Texture2D, camera_mode := 0, chroma: Texture2D = null) -> void:
	_source = texture
	pass_material.set_shader_parameter("src", texture)
	pass_material.set_shader_parameter("src2", chroma if chroma != null else texture)
	pass_material.set_shader_parameter("cam_mode", camera_mode)
	pass_material.set_shader_parameter("has_mipmaps", not texture is CameraTexture)
	_last_source_size = Vector2i.ZERO
	_check_source_size()


func set_shape(new_shape: String) -> void:
	shape_name = new_shape
	if _multimesh == null:
		return
	_multimesh.mesh = ShapeLibrary.make(new_shape)
	material.set_shader_parameter("bar_mode", ShapeLibrary.is_bar(new_shape))


func set_columns(count: int) -> void:
	columns = maxi(count, 2)
	_rebuild_grid()
	grid_changed.emit()


func set_height_amount(amount: float) -> void:
	height_amount = amount
	material.set_shader_parameter("height_amount", amount)
	_update_bounds()


func _process(_delta: float) -> void:
	_check_source_size()


func _build_pass() -> void:
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(columns, rows)
	add_child(_viewport)
	_rect = ColorRect.new()
	pass_material = ShaderMaterial.new()
	pass_material.shader = load("res://shaders/pixellate.gdshader")
	_rect.material = pass_material
	_viewport.add_child(_rect)


func _build_instances() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/bumps.gdshader")
	material.set_shader_parameter("grid_tex", _viewport.get_texture())
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	instance.material_override = material
	add_child(instance)


## Lays out one instance per cell. The shader recovers the cell from the instance position.
func _rebuild_grid() -> void:
	rows = maxi(1, roundi(float(columns) / _aspect))
	var cell := SCENE_WIDTH / float(columns)
	_viewport.size = Vector2i(columns, rows)
	_rect.position = Vector2.ZERO
	_rect.size = Vector2(columns, rows)
	pass_material.set_shader_parameter("grid_size", Vector2(columns, rows))
	material.set_shader_parameter("grid_dims", Vector2i(columns, rows))
	material.set_shader_parameter("cell_size", cell)

	var count := columns * rows
	_multimesh.instance_count = count
	var buffer := PackedFloat32Array()
	buffer.resize(count * 12)
	var index := 0
	for j in rows:
		var y := (float(rows - 1) * 0.5 - float(j)) * cell
		for i in columns:
			var x := (float(i) - float(columns - 1) * 0.5) * cell
			var base := index * 12
			buffer[base] = 1.0
			buffer[base + 3] = x
			buffer[base + 5] = 1.0
			buffer[base + 7] = y
			buffer[base + 10] = 1.0
			index += 1
	_multimesh.buffer = buffer
	_update_bounds()


## The shader moves vertices, so the automatic bounds would cull the grid too early.
func _update_bounds() -> void:
	var size := scene_size()
	_multimesh.custom_aabb = AABB(
		Vector3(-size.x * 0.5 - 1.0, -size.y * 0.5 - 1.0, -2.0),
		Vector3(size.x + 2.0, size.y + 2.0, height_amount + 4.0))


## Cameras report their size only after the first frame, so this runs every frame.
func _check_source_size() -> void:
	if _source == null:
		return
	var size := Vector2i(_source.get_width(), _source.get_height())
	if size.x <= 0 or size.y <= 0 or size == _last_source_size:
		return
	_last_source_size = size
	pass_material.set_shader_parameter("src_size", Vector2(size))
	var new_aspect := float(size.x) / float(size.y)
	if absf(new_aspect - _aspect) > 0.001:
		_aspect = new_aspect
		_rebuild_grid()
		grid_changed.emit()
