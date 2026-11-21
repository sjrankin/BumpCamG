class_name HeightField
extends RefCounted
## A smoothed CPU copy of the grid's surface heights, used to fly the camera over the relief.
## Cell (i, j) sits at x = (i - (columns - 1) / 2) * cell, y = ((rows - 1) / 2 - j) * cell.

const REGION_COLUMNS := 4
const REGION_ROWS := 3
## How far around the camera (scene units) no block top may reach it.
const CLEARANCE_RADIUS := 0.7

var columns := 0
var rows := 0
var cell := 1.0
var _values := PackedFloat32Array()
## The unsmoothed block tops, widened by the camera's body: the highest block within `radius` of each cell.
var _clearance := PackedFloat32Array()


func _init(column_count: int, row_count: int, cell_size: float, heights: PackedFloat32Array) -> void:
	columns = column_count
	rows = row_count
	cell = cell_size
	_values = heights
	_clearance = _max_filter(heights, ceili(CLEARANCE_RADIUS / cell))
	# Blocks make the raw heights jagged; blur so the camera glides rather than jitters.
	for pass_index in 2:
		_blur()


## Half the grid's extent in scene units.
func half_extent() -> Vector2:
	return Vector2(float(columns - 1), float(rows - 1)) * cell * 0.5


## Bilinear height at a scene position.
func height_at(position: Vector2) -> float:
	var half := half_extent()
	var fx := clampf(position.x / cell + float(columns - 1) * 0.5, 0.0, float(columns - 1))
	var fy := clampf(half.y / cell - position.y / cell, 0.0, float(rows - 1))
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, columns - 1)
	var y1 := mini(y0 + 1, rows - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(_at(x0, y0), _at(x1, y0), tx)
	var bottom := lerpf(_at(x0, y1), _at(x1, y1), tx)
	return lerpf(top, bottom, ty)


## Height the camera must stay above at a scene position: the tallest actual block top within
## CLEARANCE_RADIUS. Unlike `height_at`, this is not smoothed, so it never undershoots a block.
func clearance_at(position: Vector2) -> float:
	var half := half_extent()
	var x := clampi(roundi(position.x / cell + float(columns - 1) * 0.5), 0, columns - 1)
	var y := clampi(roundi(half.y / cell - position.y / cell), 0, rows - 1)
	return _clearance[y * columns + x]


## Regions (indices into the REGION_COLUMNS x REGION_ROWS split of the image) that the tour has
## not visited yet. `visited` is cleared once every region has had a turn.
func unvisited_regions(visited: Dictionary) -> Array[int]:
	if visited.size() >= REGION_COLUMNS * REGION_ROWS:
		visited.clear()
	var open: Array[int] = []
	for region in REGION_COLUMNS * REGION_ROWS:
		if not visited.has(region):
			open.append(region)
	return open


## The lowest (or highest) of a few random spots inside a region.
func best_spot_in(region: int, want_high: bool, rng: RandomNumberGenerator) -> Vector2:
	var half := half_extent() * 0.9
	var region_size := half * 2.0 / Vector2(REGION_COLUMNS, REGION_ROWS)
	var origin := -half + Vector2(region % REGION_COLUMNS, int(region / REGION_COLUMNS)) * region_size
	var best := origin + region_size * 0.5
	var best_height := -INF if want_high else INF
	for attempt in 10:
		var spot := origin + Vector2(rng.randf(), rng.randf()) * region_size
		var h := height_at(spot)
		if h > best_height if want_high else h < best_height:
			best = spot
			best_height = h
	return best


## Square max filter (separable) so each cell holds the tallest value within `radius` cells.
func _max_filter(source: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var across := PackedFloat32Array()
	across.resize(source.size())
	for y in rows:
		for x in columns:
			var top := -INF
			for k in range(maxi(x - radius, 0), mini(x + radius, columns - 1) + 1):
				top = maxf(top, source[y * columns + k])
			across[y * columns + x] = top
	var out := PackedFloat32Array()
	out.resize(source.size())
	for x in columns:
		for y in rows:
			var top := -INF
			for k in range(maxi(y - radius, 0), mini(y + radius, rows - 1) + 1):
				top = maxf(top, across[k * columns + x])
			out[y * columns + x] = top
	return out


func _at(x: int, y: int) -> float:
	return _values[y * columns + x]


func _blur() -> void:
	var out := PackedFloat32Array()
	out.resize(_values.size())
	for y in rows:
		for x in columns:
			var total := 0.0
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and nx < columns and ny >= 0 and ny < rows:
						total += _values[ny * columns + nx]
						count += 1
			out[y * columns + x] = total / float(count)
	_values = out
