class_name OrbitCamera
extends Node3D
## Orbit / pan / zoom camera. Drag = orbit, right or middle drag = pan, wheel or pinch = zoom,
## trackpad scroll = pan, double-click = reset to the original framing.

## SceneKit's default implicit animation duration (SCNTransaction.animationDuration), in seconds.
const SCENEKIT_DEFAULT_DURATION := 0.25

var camera: Camera3D
var _reset_tween: Tween
var fit_size := Vector2(16.0, 9.0)

var _yaw := 0.0
var _pitch := 0.0
var _distance := 20.0
var _target := Vector3.ZERO
var _moved := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.far = 500.0
	add_child(camera)
	get_viewport().size_changed.connect(_on_viewport_resized)
	reset_view()


## Frames the whole grid face-on, as it was when the source was loaded.
func reset_view() -> void:
	_stop_reset_tween()
	var home := _home_pose()
	_yaw = home.yaw
	_pitch = home.pitch
	_target = home.target
	_distance = home.distance
	_moved = false
	_apply()


## Glides back to the original framing over SceneKit's default animation duration.
func reset_view_animated() -> void:
	_stop_reset_tween()
	var home := _home_pose()
	var from_yaw := _yaw
	# Take the shortest way round to the home yaw.
	var to_yaw := from_yaw + wrapf(-from_yaw, -PI, PI)
	var from_pitch := _pitch
	var from_target := _target
	var from_distance := _distance
	_moved = false
	_reset_tween = create_tween()
	_reset_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)  # SceneKit's default timing is ease-in/out
	_reset_tween.tween_method(func(t: float) -> void:
		_yaw = lerpf(from_yaw, to_yaw, t)
		_pitch = lerpf(from_pitch, home.pitch, t)
		_target = from_target.lerp(home.target, t)
		_distance = lerpf(from_distance, home.distance, t)
		_apply(), 0.0, 1.0, SCENEKIT_DEFAULT_DURATION)
	_reset_tween.finished.connect(reset_view)  # snap to exact home values at the end


func _home_pose() -> Dictionary:
	var half_tan := tan(deg_to_rad(camera.fov) * 0.5)
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	return {
		"yaw": 0.0,
		"pitch": 0.0,
		"target": Vector3(0.0, 0.0, 0.5),
		"distance": maxf(fit_size.y * 0.5 / half_tan, fit_size.x * 0.5 / (half_tan * aspect)) * 1.1,
	}


func _stop_reset_tween() -> void:
	if _reset_tween != null and _reset_tween.is_valid():
		_reset_tween.kill()
	_reset_tween = null


## Refits only if the user has not moved the camera themselves.
func refit() -> void:
	if not _moved:
		reset_view()


func set_orbit_degrees(yaw_degrees: float, pitch_degrees: float) -> void:
	_stop_reset_tween()
	_yaw = deg_to_rad(yaw_degrees)
	_pitch = deg_to_rad(pitch_degrees)
	_moved = true
	_apply()


func _apply() -> void:
	position = _target
	basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	camera.position = Vector3(0.0, 0.0, _distance)


func _on_viewport_resized() -> void:
	refit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
		elif button.button_index == MOUSE_BUTTON_LEFT and button.double_click:
			reset_view_animated()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_stop_reset_tween()
			_yaw -= motion.relative.x * 0.005
			_pitch = clampf(_pitch - motion.relative.y * 0.005, -1.5, 1.5)
			_moved = true
			_apply()
		elif motion.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			_pan(motion.relative)
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
	elif event is InputEventPanGesture:
		_pan(-(event as InputEventPanGesture).delta * 8.0)


func _zoom(factor: float) -> void:
	_stop_reset_tween()
	_distance = clampf(_distance * factor, 1.0, 200.0)
	_moved = true
	_apply()


func _pan(relative: Vector2) -> void:
	_stop_reset_tween()
	var view_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var scale := 2.0 * _distance * tan(deg_to_rad(camera.fov) * 0.5) / view_height
	_target += (-basis.x * relative.x + basis.y * relative.y) * scale
	_moved = true
	_apply()
