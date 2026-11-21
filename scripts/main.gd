extends Node3D
## BumpCamG: renders a camera feed or image as a grid of lit 3D shapes.
##
## Command line (after `--`): --image=PATH --shape=NAME --height=MODE --columns=N
## --orbit=YAW,PITCH --shot=OUT.png (save the window and quit) --shot-ui (keep the panel in the shot).

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULTS := {
	"shape": "Blocks",
	"height_mode": "Brightness",
	"height_invert": false,
	"height_amount": 2.0,
	"columns": 64,
	"shape_size": 0.95,
	"color_mode": "Color",
	"levels": 4.0,
	"metallic": 0.0,
	"roughness": 0.6,
	"light": 1.0,
	"shadows": true,
	"mirror": true,
	"flip_y": false,
	"background": Color.BLACK,
	"source_kind": "camera",
	"image_path": "",
}

var settings: Dictionary = DEFAULTS.duplicate()

var _grid: GridView
var _rig: OrbitCamera
var _light: DirectionalLight3D
var _environment: Environment
var _panel: ControlPanel
var _layer: CanvasLayer
var _open_dialog: FileDialog
var _save_dialog: FileDialog

var _sources: Array[Dictionary] = []
var _source_kind := "demo"
var _demo_texture: ImageTexture
var _image_texture: ImageTexture
var _image_name := ""
var _camera_texture: CameraTexture
var _chroma_texture: CameraTexture
var _camera_datatype := -1
var _camera_wait := 0.0
var _camera_retry := 0.0
var _notice := ""
var _notice_time := 0.0
var _active_feed: CameraFeed
var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	_load_settings()
	_apply_command_line_settings()
	_build_scene()
	_build_ui()
	_apply_all()
	get_window().files_dropped.connect(_on_files_dropped)
	_demo_texture = _make_demo_texture()
	_start_initial_source()
	if _args.has("shot"):
		_take_command_line_shot()


# MARK: Setup

func _build_scene() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	_environment.ambient_light_energy = 0.45
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-25.0, 18.0, 0.0)
	_light.directional_shadow_max_distance = 80.0
	add_child(_light)

	_grid = GridView.new()
	add_child(_grid)
	_rig = OrbitCamera.new()
	add_child(_rig)
	_rig.camera.current = true
	_grid.grid_changed.connect(_on_grid_changed)


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_panel = ControlPanel.new()
	_layer.add_child(_panel)
	_panel.setup(settings)
	_panel.changed.connect(_on_setting_changed)
	_panel.source_selected.connect(_select_source)
	_panel.open_image_requested.connect(_show_open_dialog)
	_panel.save_image_requested.connect(_show_save_dialog)
	_panel.reset_view_requested.connect(_rig.reset_view_animated)

	_open_dialog = FileDialog.new()
	_open_dialog.use_native_dialog = true
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.exr", "Images")
	_open_dialog.file_selected.connect(_load_image_file)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.use_native_dialog = true
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.png", "PNG image")
	_save_dialog.add_filter("*.jpg", "JPEG image")
	_save_dialog.current_file = "BumpCamG.png"
	_save_dialog.file_selected.connect(func(path: String) -> void: capture(path))
	add_child(_save_dialog)


func _parse_args() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var parts := argument.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return parsed


func _apply_command_line_settings() -> void:
	if _args.has("shape"):
		settings["shape"] = _args["shape"]
	if _args.has("height"):
		settings["height_mode"] = _args["height"]
	if _args.has("invert-height"):
		settings["height_invert"] = true
	if _args.has("columns"):
		settings["columns"] = int(_args["columns"])
	if _args.has("mode"):
		settings["color_mode"] = _args["mode"]


# MARK: Settings

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key in DEFAULTS:
		if config.has_section_key("settings", key):
			var value: Variant = config.get_value("settings", key)
			if typeof(value) == typeof(DEFAULTS[key]):
				settings[key] = value
	# "Inverse Brightness" was replaced by Brightness plus the Invert option.
	if settings["height_mode"] == "Inverse Brightness":
		settings["height_mode"] = "Brightness"
		settings["height_invert"] = true


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings:
		config.set_value("settings", key, settings[key])
	config.save(SETTINGS_PATH)


func _on_setting_changed(key: String, value: Variant) -> void:
	settings[key] = value
	_apply(key)
	_save_settings()


func _apply_all() -> void:
	for key in settings:
		_apply(key)


func _apply(key: String) -> void:
	var value: Variant = settings[key]
	match key:
		"shape":
			_grid.set_shape(str(value))
		"height_mode":
			_grid.material.set_shader_parameter("height_mode", GridView.HEIGHT_MODES.find(str(value)))
		"height_invert":
			_grid.material.set_shader_parameter("height_invert", bool(value))
		"height_amount":
			_grid.set_height_amount(float(value))
		"columns":
			_grid.set_columns(int(value))
		"shape_size":
			_grid.material.set_shader_parameter("shape_size", float(value))
		"color_mode":
			_grid.material.set_shader_parameter("color_mode", GridView.COLOR_MODES.find(str(value)))
		"levels":
			_grid.material.set_shader_parameter("levels", float(value))
		"metallic":
			_grid.material.set_shader_parameter("metallic_amount", float(value))
		"roughness":
			_grid.material.set_shader_parameter("roughness_amount", float(value))
		"light":
			_light.light_energy = float(value)
		"shadows":
			_light.shadow_enabled = bool(value)
		"mirror", "flip_y":
			_update_flips()
		"background":
			_environment.background_color = value


func _update_flips() -> void:
	_grid.pass_material.set_shader_parameter("flip_x", bool(settings["mirror"]) and _source_kind == "camera")
	_grid.pass_material.set_shader_parameter("flip_y", bool(settings["flip_y"]))


func _on_grid_changed() -> void:
	_rig.fit_size = _grid.scene_size()
	_rig.refit()


# MARK: Sources

func _start_initial_source() -> void:
	if _args.has("image"):
		if _load_image_file(str(_args["image"])):
			if _args.has("orbit"):
				var parts := str(_args["orbit"]).split(",")
				if parts.size() == 2:
					_rig.set_orbit_degrees(float(parts[0]), float(parts[1]))
			return
	_use_demo()
	# Always watch for cameras so they appear in the Input list, whatever source was used last.
	CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)
	CameraServer.monitoring_feeds = true
	var saved_path := str(settings["image_path"])
	if settings["source_kind"] == "image" and FileAccess.file_exists(saved_path):
		_load_image_file(saved_path)


func _on_camera_feeds_updated() -> void:
	if _active_feed == null and settings["source_kind"] == "camera":
		var feeds := CameraServer.feeds()
		if not feeds.is_empty():
			_start_camera(feeds[0])
			return
	_refresh_sources()


func _select_source(index: int) -> void:
	if index < 0 or index >= _sources.size():
		return
	var source := _sources[index]
	match source["kind"]:
		"demo":
			_use_demo()
		"image":
			_stop_camera()
			_use_texture(_image_texture, "image")
		"camera":
			_start_camera(source["feed"] as CameraFeed)
	settings["source_kind"] = _source_kind
	_save_settings()


func _use_demo() -> void:
	_stop_camera()
	_use_texture(_demo_texture, "demo")


func _use_texture(texture: Texture2D, kind: String) -> void:
	_source_kind = kind
	_grid.set_source(texture)
	_update_flips()
	_refresh_sources()


func _start_camera(feed: CameraFeed) -> void:
	_stop_camera()
	feed.feed_is_active = true
	_camera_texture = CameraTexture.new()
	_camera_texture.camera_feed_id = feed.get_id()
	_camera_texture.camera_is_active = true
	_chroma_texture = null
	_camera_datatype = -1
	_camera_wait = 0.0
	_camera_retry = 0.0
	_active_feed = feed
	_use_texture(_camera_texture, "camera")


func _process(delta: float) -> void:
	_watch_camera(delta)
	_configure_camera_format()


## Godot refuses to activate a camera until macOS grants access, and then shows a placeholder
## texture. Keep retrying and tell the user why nothing is happening.
func _watch_camera(delta: float) -> void:
	_notice_time = maxf(_notice_time - delta, 0.0)
	if _active_feed == null:
		_panel.set_status(_notice if _notice_time > 0.0 else "")
		return
	if _active_feed.feed_is_active:
		_camera_wait = 0.0
		_panel.set_status(_notice if _notice_time > 0.0 else "")
		return
	_camera_wait += delta
	# Retry sparingly: starting a capture session blocks, so doing it every frame freezes the app.
	_camera_retry += delta
	if _camera_wait > 2.0 and _camera_retry > 3.0:
		_camera_retry = 0.0
		_active_feed.feed_is_active = true
	if _camera_wait > 2.5:
		_panel.set_status("The camera did not start. Allow camera access for this app in System Settings > Privacy & Security > Camera, then reselect the camera.")


## Cameras report their pixel format only once frames arrive. Many (macOS) deliver separate Y and
## CbCr planes, which need a second texture and a colour conversion in the shader.
func _configure_camera_format() -> void:
	if _active_feed == null:
		return
	var datatype := _active_feed.get_datatype()
	if datatype == _camera_datatype or datatype == CameraFeed.FEED_NOIMAGE:
		return
	_camera_datatype = datatype
	print("BumpCamG: camera data type ", datatype)
	match datatype:
		CameraFeed.FEED_YCBCR_SEP:
			_camera_texture.which_feed = CameraServer.FEED_Y_IMAGE
			_chroma_texture = CameraTexture.new()
			_chroma_texture.camera_feed_id = _active_feed.get_id()
			_chroma_texture.which_feed = CameraServer.FEED_CBCR_IMAGE
			_chroma_texture.camera_is_active = true
			_grid.set_source(_camera_texture, 2, _chroma_texture)
		CameraFeed.FEED_YCBCR:
			_grid.set_source(_camera_texture, 1)
		_:
			_grid.set_source(_camera_texture, 0)


func _stop_camera() -> void:
	if _active_feed != null:
		_active_feed.feed_is_active = false
	_active_feed = null
	_camera_texture = null
	_chroma_texture = null


func _refresh_sources() -> void:
	_sources.clear()
	var labels: Array[String] = []
	var selected := 0
	_sources.append({"kind": "demo"})
	labels.append("Demo pattern")
	if _image_texture != null:
		_sources.append({"kind": "image"})
		labels.append("Image: " + _image_name)
		if _source_kind == "image":
			selected = labels.size() - 1
	var feeds: Array = CameraServer.feeds() if CameraServer.monitoring_feeds else []
	for feed: CameraFeed in feeds:
		_sources.append({"kind": "camera", "feed": feed})
		labels.append(feed.get_name())
		if feed == _active_feed:
			selected = labels.size() - 1
	_panel.set_sources(labels, selected)


func _on_files_dropped(files: PackedStringArray) -> void:
	print("BumpCamG: dropped ", files)
	_notice = "Dropped %s" % ", ".join(Array(files).map(func(f: String) -> String: return f.get_file()))
	_notice_time = 4.0
	for path in files:
		if _load_image_file(path):
			return


func _load_image_file(path: String) -> bool:
	var image := ImageLoader.load_image(path)
	if image == null:
		push_warning("BumpCamG: could not load image %s" % path)
		_notice = "Could not open %s" % path.get_file()
		_notice_time = 5.0
		return false
	var longest := maxi(image.get_width(), image.get_height())
	if longest > 4096:
		var factor := 4096.0 / float(longest)
		image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor), Image.INTERPOLATE_BILINEAR)
	image.generate_mipmaps()
	_image_texture = ImageTexture.create_from_image(image)
	_image_name = path.get_file()
	if not _args.has("image"):
		settings["image_path"] = path
	_stop_camera()
	_use_texture(_image_texture, "image")
	if not _args.has("image"):
		settings["source_kind"] = "image"
		_save_settings()
	return true


## A colourful gradient with a bright disc so the shapes have something to show before a camera starts.
func _make_demo_texture() -> ImageTexture:
	var width := 320
	var height := 180
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	for y in height:
		for x in width:
			var u := float(x) / float(width)
			var v := float(y) / float(height)
			var color := Color(
				0.5 + 0.5 * sin(u * 7.0 + v * 3.0),
				0.5 + 0.5 * sin(u * 4.0 - v * 6.0 + 2.0),
				0.5 + 0.5 * sin(u * 2.0 + v * 9.0 + 4.0))
			var offset := Vector2(u - 0.5, (v - 0.5) * 0.5625)
			var disc := 1.0 - smoothstep(0.18, 0.2, offset.length())
			image.set_pixel(x, y, color.lerp(Color.WHITE, disc))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# MARK: Dialogs and capture

func _show_open_dialog() -> void:
	_open_dialog.popup_centered_ratio(0.7)


func _show_save_dialog() -> void:
	_save_dialog.popup_centered_ratio(0.7)


## Saves the 3D view (without the settings panel) as PNG or JPEG.
func capture(path: String, hide_ui := true) -> Error:
	var was_visible := _layer.visible
	if hide_ui:
		_layer.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_layer.visible = was_visible
	if path.get_extension().to_lower() in ["jpg", "jpeg"]:
		return image.save_jpg(path, 0.92)
	return image.save_png(path)


func _take_command_line_shot() -> void:
	await get_tree().create_timer(float(_args.get("delay", "1.5"))).timeout
	var error := await capture(str(_args["shot"]), not _args.has("shot-ui"))
	if error != OK:
		push_error("BumpCamG: could not save screenshot (%s)" % error_string(error))
	get_tree().quit()
