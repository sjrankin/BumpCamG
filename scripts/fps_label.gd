class_name FPSLabel
extends Label
## Frames-per-second readout for the upper-left corner, refreshed twice a second.

const REFRESH_SECONDS := 0.5

var _elapsed := 0.0


func _ready() -> void:
	position = Vector2(10.0, 8.0)
	modulate = Color(1.0, 1.0, 1.0, 0.8)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	text = "%d FPS" % roundi(Engine.get_frames_per_second())
