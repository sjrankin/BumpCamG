class_name OrbitCamera
extends Node3D
## Orbit / pan / zoom camera. Drag = orbit, Command-drag, right or middle drag = move the image,
## wheel or pinch = zoom, trackpad scroll = pan, double-click = reset to the original framing.

## SceneKit's default implicit animation duration (SCNTransaction.animationDuration) is 0.25 s;
## the reset glide takes three times that, in seconds.
const RESET_DURATION := 0.75

## Tour settings (scene units; the image is 16 wide): length and approach/return glide in seconds,
## how far ahead the camera looks, height above the surface, constant flying speed per second,
## the smallest turning circle, the path sampling step, and how far along the path the camera looks
## ahead (and behind) for blocks to clear, which also sets how gently the altitude changes.
const TOUR_SECONDS := 240.0
const TOUR_APPROACH_SECONDS := 2.5
const TOUR_DISTANCE := 3.0
const TOUR_LIFT := 0.4
const TOUR_SPEED := 0.9
const TOUR_TURN_RADIUS := 3.5
const TOUR_STEP := 0.05
const TOUR_LOOKAHEAD := 3.0

var camera: Camera3D
var _reset_tween: Tween
var fit_size := Vector2(16.0, 9.0)

var _yaw := 0.0
var _pitch := 0.0
var _distance := 20.0
var _target := Vector3.ZERO
var _moved := false
## While gliding or touring the camera follows `_look` instead of the yaw/pitch orbit angles.
var _look := Basis.IDENTITY
var _use_look := false


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


## A stately, low flight along the image's plane, like a glider skimming terrain: the camera
## rides just above the surface at a constant, unhurried speed, rising over high areas and
## settling into low ones, arcing round in wide turns (never reversing) from region to region
## until every part of the image has been visited, for `TOUR_SECONDS`. Then it glides back to the
## original framing. Any manual camera input, or a double-click, ends the tour.
func start_tour(field: HeightField) -> void:
	var from_basis := basis
	_stop_reset_tween()
	_moved = true
	var route := _plan_route(field)
	var points: PackedVector2Array = route.points
	var headings: PackedFloat32Array = route.headings
	var altitudes: PackedFloat32Array = route.altitudes
	var last := points.size() - 1

	var from_target := _target
	var from_distance := _distance
	var first_target := _tour_target(points[0], headings[0], altitudes[0])
	var first_basis := _tour_basis(headings[0])
	_reset_tween = create_tween()
	_reset_tween.tween_method(func(t: float) -> void:
		_target = from_target.lerp(first_target, t)
		_distance = lerpf(from_distance, TOUR_DISTANCE, t)
		_look = Basis(Quaternion(from_basis).slerp(Quaternion(first_basis), t))
		_use_look = true
		_apply(), 0.0, 1.0, TOUR_APPROACH_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# One linear sweep along the route, so the speed never changes, whatever the turns.
	_reset_tween.tween_method(func(t: float) -> void:
		var position_along := t * float(last)
		var i := mini(int(position_along), last - 1)
		var f := position_along - float(i)
		var xy := points[i].lerp(points[i + 1], f)
		var course := lerp_angle(headings[i], headings[i + 1], f)
		_target = _tour_target(xy, course, lerpf(altitudes[i], altitudes[i + 1], f))
		_look = _tour_basis(course)
		_use_look = true
		_distance = TOUR_DISTANCE
		_apply(), 0.0, 1.0, TOUR_SECONDS)
	_reset_tween.tween_callback(reset_view_animated.bind(TOUR_APPROACH_SECONDS))


## Plans the whole flight as a dense path (`points`, with the `headings` and `altitudes` at each),
## spaced evenly so that walking along it is constant speed. The path is steered like a vehicle with
## a minimum turning radius, so course changes are wide arcs rather than reversals.
func _plan_route(field: HeightField) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var visited := {}
	var points := PackedVector2Array()
	var headings := PackedFloat32Array()
	var total_length := TOUR_SPEED * TOUR_SECONDS
	var max_turn := TOUR_STEP / TOUR_TURN_RADIUS
	var turn_ease := max_turn * 0.02  # change in turn rate per step
	var turn_rate := 0.0
	var want_high := true
	var bounds := field.half_extent() * 0.95

	var position := field.best_spot_in(field.unvisited_regions(visited)[0], false, rng)
	var heading := rng.randf_range(-PI, PI)
	points.append(position)
	headings.append(heading)
	while float(points.size()) * TOUR_STEP < total_length:
		# Choose the next destination: one in a region not yet visited, that an arc can actually reach
		# (not inside either turning circle, which would leave the camera circling it), preferring
		# the gentlest turn.
		var best_spot := Vector2.ZERO
		var best_region := -1
		var best_score := INF
		var open := field.unvisited_regions(visited)
		open.shuffle()
		for region in open:
			var spot := field.best_spot_in(region, want_high, rng)
			var score := absf(wrapf((spot - position).angle() - heading, -PI, PI))
			if not _reachable(position, heading, spot):
				score += 100.0 - minf(position.distance_to(spot), 50.0)  # least-bad if none is reachable
			if score < best_score:
				best_score = score
				best_spot = spot
				best_region = region
			# A reachable one that does not need a sharp turn is good enough.
			if score < PI * 0.5:
				break
		visited[best_region] = true
		want_high = not want_high
		# Steer towards it. The turn rate itself ramps up and down gently, so a change of course is
		# a smooth arc that eases in and out, never a snap. Abandon a destination if the camera has
		# swung through most of a circle without reaching it, rather than circling on.
		var turned := 0.0
		while position.distance_to(best_spot) > 1.0 and turned < PI * 1.5 \
				and float(points.size()) * TOUR_STEP < total_length:
			var wanted := (best_spot - position).angle()
			# Never fly off the image: if the turn ahead would leave it, curve back towards the middle.
			var lookahead := position + Vector2(cos(heading), sin(heading)) * TOUR_TURN_RADIUS * 2.0
			if absf(lookahead.x) > bounds.x or absf(lookahead.y) > bounds.y:
				wanted = (-position).angle()
			var difference := wrapf(wanted - heading, -PI, PI)
			# The fastest turn that can still ease to a stop on the wanted course.
			var desired := signf(difference) * minf(max_turn, sqrt(2.0 * turn_ease * absf(difference)))
			turn_rate = move_toward(turn_rate, desired, turn_ease)
			heading += turn_rate
			turned += absf(turn_rate)
			position += Vector2(cos(heading), sin(heading)) * TOUR_STEP
			points.append(position)
			headings.append(heading)

	# Altitude: the camera must clear every block top near it. Take the highest requirement within a
	# wide window along the path (so it starts climbing well before an obstacle), then blur it. The
	# blur is narrower than the window, so the smoothed line can never dip below what is needed.
	var count := points.size()
	var needed := PackedFloat32Array()
	needed.resize(count)
	for i in count:
		needed[i] = field.clearance_at(points[i]) + TOUR_LIFT
	var window := int(TOUR_LOOKAHEAD / TOUR_STEP)
	var altitudes := PackedFloat32Array()
	altitudes.resize(count)
	for i in count:
		var top := -INF
		for k in range(maxi(i - window, 0), mini(i + window, count - 1) + 1):
			top = maxf(top, needed[k])
		altitudes[i] = top
	var blur_radius := window / 3
	for pass_index in 3:
		altitudes = _box_blur(altitudes, blur_radius)
	return {"points": points, "headings": headings, "altitudes": altitudes}


## True if an arc of the camera's turning circle can reach `spot`: it must lie outside both circles
## the camera could be turning along (with a little margin for the gentle ramp into a turn).
func _reachable(position: Vector2, heading: float, spot: Vector2) -> bool:
	var radius := TOUR_TURN_RADIUS * 1.3
	var side := Vector2(-sin(heading), cos(heading)) * radius
	return spot.distance_to(position + side) > radius and spot.distance_to(position - side) > radius


static func _box_blur(values: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var count := values.size()
	var out := PackedFloat32Array()
	out.resize(count)
	var running := 0.0
	var lo := 0
	var hi := -1
	for i in count:
		var want_hi := mini(i + radius, count - 1)
		while hi < want_hi:
			hi += 1
			running += values[hi]
		var want_lo := maxi(i - radius, 0)
		while lo < want_lo:
			running -= values[lo]
			lo += 1
		out[i] = running / float(hi - lo + 1)
	return out


## Looks along `heading` within the image plane, with +Z (the relief's up) as screen up.
func _tour_basis(heading: float) -> Basis:
	return Basis.looking_at(Vector3(cos(heading), sin(heading), 0.0), Vector3.BACK)


## The rig's position for a camera at `xy` and `altitude`: the camera sits `_distance` behind the
## rig along the heading.
func _tour_target(xy: Vector2, heading: float, altitude: float) -> Vector3:
	var ahead := Vector2(cos(heading), sin(heading)) * TOUR_DISTANCE
	return Vector3(xy.x + ahead.x, xy.y + ahead.y, altitude)


## Glides back to the original framing over `RESET_DURATION`.
func reset_view_animated(duration := RESET_DURATION) -> void:
	var from_basis := basis
	_stop_reset_tween()
	var home := _home_pose()
	var home_basis := Basis.from_euler(Vector3(home.pitch, home.yaw, 0.0))
	var from_target := _target
	var from_distance := _distance
	_moved = false
	_reset_tween = create_tween()
	_reset_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)  # SceneKit's default timing is ease-in/out
	_reset_tween.tween_method(func(t: float) -> void:
		_look = Basis(Quaternion(from_basis).slerp(Quaternion(home_basis), t))
		_use_look = true
		_target = from_target.lerp(home.target, t)
		_distance = lerpf(from_distance, home.distance, t)
		_apply(), 0.0, 1.0, duration)
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


## Stops any glide or tour. If the camera was mid-animation, the manual orbit carries on from
## the direction it was facing.
func _stop_reset_tween() -> void:
	if _reset_tween != null and _reset_tween.is_valid():
		_reset_tween.kill()
	_reset_tween = null
	if _use_look:
		var euler := _look.get_euler()
		_pitch = euler.x
		_yaw = euler.y
		_use_look = false


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
	basis = _look if _use_look else Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
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
		var dragging := motion.button_mask & MOUSE_BUTTON_MASK_LEFT and motion.meta_pressed
		if dragging:
			_pan(motion.relative)
		elif motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
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
