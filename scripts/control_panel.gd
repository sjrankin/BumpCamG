class_name ControlPanel
extends PanelContainer
## The settings panel. It only edits the shared settings dictionary values by emitting `changed`;
## the main scene applies them.

signal changed(key: String, value: Variant)
signal source_selected(index: int)
signal open_image_requested
signal save_image_requested
signal reset_view_requested

const PANEL_WIDTH := 340.0

var _settings: Dictionary = {}
var _box: VBoxContainer
var _source_option: OptionButton
var _status: Label
var _content: Control
var _restore_button: Button


func setup(settings: Dictionary) -> void:
	_settings = settings
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	clip_contents = true

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	_content = margin
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	margin.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)

	_add_heading("Source")
	_source_option = OptionButton.new()
	_source_option.clip_text = true
	_source_option.fit_to_longest_item = false
	_source_option.custom_minimum_size.x = 120.0
	_source_option.item_selected.connect(func(index: int) -> void: source_selected.emit(index))
	_add_row("Input", _source_option)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 0.7, 0.4)
	_status.visible = false
	_box.add_child(_status)
	_add_check("Mirror camera", "mirror")
	_add_check("Flip vertical", "flip_y")
	var buttons := HBoxContainer.new()
	buttons.add_child(_make_button("Open Image…", func() -> void: open_image_requested.emit()))
	buttons.add_child(_make_button("Save Image…", func() -> void: save_image_requested.emit()))
	_box.add_child(buttons)

	_add_heading("Shapes")
	_add_option("Shape", "shape", ShapeLibrary.NAMES)
	_add_option("Columns", "columns", [16, 32, 48, 64, 96, 128, 192])
	_add_slider("Shape size", "shape_size", 0.2, 1.2, 0.01)
	_add_option("Height from", "height_mode", GridView.HEIGHT_MODES)
	_add_check("Invert height", "height_invert")
	_add_slider("Height", "height_amount", 0.0, 6.0, 0.05)

	_add_heading("Color")
	_add_option("Mode", "color_mode", GridView.COLOR_MODES)
	_add_slider("Levels", "levels", 2.0, 16.0, 1.0)
	_add_color("Background", "background")

	_add_heading("Lighting")
	_add_slider("Light", "light", 0.0, 3.0, 0.05)
	_add_slider("Metallic", "metallic", 0.0, 1.0, 0.01)
	_add_slider("Roughness", "roughness", 0.05, 1.0, 0.01)
	_add_check("Shadows", "shadows")

	_add_heading("View")
	_box.add_child(_make_button("Reset View (double-click)", func() -> void: reset_view_requested.emit()))
	var hint := Label.new()
	hint.text = "Drag: move the image. Shift or right drag: orbit.\nWheel or pinch: zoom.\nDrop an image on the window."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1.0
	hint.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(hint)
	_box.add_child(HSeparator.new())
	_box.add_child(_make_button("Minimize Controls", func() -> void: set_minimized(true)))

	_restore_button = _make_button("Show Controls", func() -> void: set_minimized(false))
	_restore_button.visible = false
	add_child(_restore_button)
	set_minimized(false)


## Collapses the panel to a single restore button in the upper right, or expands it again.
func set_minimized(minimized: bool) -> void:
	_content.visible = not minimized
	_restore_button.visible = minimized
	offset_top = 10.0
	offset_right = -10.0
	if minimized:
		offset_left = -150.0
		anchor_bottom = 0.0
		offset_bottom = 10.0 + _restore_button.get_combined_minimum_size().y + 12.0
	else:
		offset_left = -PANEL_WIDTH - 10.0
		anchor_bottom = 1.0
		offset_bottom = -10.0


## Fills the input list without emitting `source_selected`.
func set_sources(labels: Array[String], selected: int) -> void:
	_source_option.clear()
	for label in labels:
		_source_option.add_item(label)
	if selected >= 0 and selected < labels.size():
		_source_option.select(selected)


## Shows a warning under the input list; an empty string hides it.
func set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(0.75, 0.85, 1.0)
	_box.add_child(HSeparator.new())
	_box.add_child(label)


func _add_row(text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 100.0
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	_box.add_child(row)


func _add_option(text: String, key: String, values: Array) -> void:
	var option := OptionButton.new()
	option.clip_text = true
	option.fit_to_longest_item = false
	option.custom_minimum_size.x = 120.0
	for index in values.size():
		option.add_item(str(values[index]))
		if values[index] == _settings[key]:
			option.select(index)
	option.item_selected.connect(func(index: int) -> void: changed.emit(key, values[index]))
	_add_row(text, option)


func _add_slider(text: String, key: String, low: float, high: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(_settings[key])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 80.0
	var readout := Label.new()
	readout.custom_minimum_size.x = 36.0
	readout.text = String.num(slider.value, 2)
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = String.num(value, 2)
		changed.emit(key, value))
	row.add_child(slider)
	row.add_child(readout)
	_add_row(text, row)


func _add_check(text: String, key: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = bool(_settings[key])
	check.toggled.connect(func(on: bool) -> void: changed.emit(key, on))
	_box.add_child(check)


func _add_color(text: String, key: String) -> void:
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size.x = 120.0
	picker.color = _settings[key]
	picker.custom_minimum_size.y = 28.0
	picker.color_changed.connect(func(color: Color) -> void: changed.emit(key, color))
	_add_row(text, picker)


func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button
