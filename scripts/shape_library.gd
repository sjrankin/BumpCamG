class_name ShapeLibrary
extends RefCounted
## Builds the unit-sized meshes that are instanced once per grid cell.
##
## Every shape fits in a 1x1 cell and faces +Z (towards the camera). Flat shapes are single-sided
## polygons in the XY plane; "Blocks" is a unit box that the shader stretches into a bar.

const NAMES: Array[String] = [
	"Blocks", "Spheres", "Cones", "Pyramids", "Cylinders", "Rings",
	"Squares", "Circles", "Triangles", "Diamonds", "Hexagons", "Stars", "Hue Pointers", "Wireframe", "Filled Wireframe",
]

## Shapes built as prisms spanning z = -0.5..0.5, which the shader stretches into bars like Blocks.
const BAR_SHAPES: Array[String] = [
	"Blocks", "Rings", "Circles", "Triangles", "Diamonds", "Hexagons", "Stars", "Hue Pointers",
]

static var _cache: Dictionary = {}


## True for shapes that the shader stretches along Z instead of lifting.
static func is_bar(shape_name: String) -> bool:
	return shape_name in BAR_SHAPES


## True for shapes the shader turns to point along the colour's hue.
## True for the continuous wireframe, which has its own mesh and shader.
static func is_wireframe(shape_name: String) -> bool:
	return shape_name == "Wireframe"


## True for the wireframe whose cells are filled in.
static func is_filled_wireframe(shape_name: String) -> bool:
	return shape_name == "Filled Wireframe"


static func is_hue_pointer(shape_name: String) -> bool:
	return shape_name == "Hue Pointers"


static func make(shape_name: String) -> Mesh:
	if _cache.has(shape_name):
		return _cache[shape_name]
	var mesh: Mesh = _build(shape_name)
	_cache[shape_name] = mesh
	return mesh


static func _build(shape_name: String) -> Mesh:
	# Rotating +90 degrees about X turns the Y axis of Godot's primitives into +Z.
	var to_front := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	match shape_name:
		"Spheres":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 20
			sphere.rings = 10
			return sphere
		"Cones":
			return _rotated(_cylinder(0.0, 0.5, 24), to_front)
		"Pyramids":
			return _rotated(_cylinder(0.0, 0.5, 4), to_front * Basis(Vector3.UP, deg_to_rad(45.0)))
		"Cylinders":
			return _rotated(_cylinder(0.5, 0.5, 24), to_front)
		"Rings":
			return _prism(_ngon(32, 0.5, 0.0), true, _ngon(32, 0.3, 0.0))
		"Squares":
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			return quad
		"Circles":
			return _prism(_ngon(32, 0.5, 0.0), true)
		"Triangles":
			return _prism(_ngon(3, 0.5, PI / 2.0), false)
		"Diamonds":
			return _prism(_ngon(4, 0.5, 0.0), false)
		"Hexagons":
			return _prism(_ngon(6, 0.5, 0.0), false)
		"Stars":
			return _prism(_star(5, 0.5, 0.42, PI / 2.0), false)
		"Wireframe":
			# Two segments per cell: to the neighbour on the right and the one below. The shader reads
			# these vertex positions as neighbour offsets, not as geometry.
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_LINES)
			for end in [Vector3.ZERO, Vector3.RIGHT, Vector3.ZERO, Vector3.DOWN]:
				st.add_vertex(end)
			return st.commit()
		"Filled Wireframe":
			# Surface 0: two triangles per cell (COLOR.r = 1). Surface 1: the wires (COLOR.r = 0).
			# As for "Wireframe", the vertex positions are neighbour offsets read by the shader.
			var mesh := ArrayMesh.new()
			var fill := SurfaceTool.new()
			fill.begin(Mesh.PRIMITIVE_TRIANGLES)
			fill.set_color(Color(1, 0, 0))
			for corner in [Vector3.ZERO, Vector3.RIGHT, Vector3.DOWN, Vector3.RIGHT, Vector3(1, -1, 0), Vector3.DOWN]:
				fill.add_vertex(corner)
			fill.commit(mesh)
			var wires := SurfaceTool.new()
			wires.begin(Mesh.PRIMITIVE_LINES)
			wires.set_color(Color(0, 0, 0))
			for end in [Vector3.ZERO, Vector3.RIGHT, Vector3.ZERO, Vector3.DOWN]:
				wires.add_vertex(end)
			wires.commit(mesh)
			return mesh
		"Hue Pointers":
			# An arrowhead that points up at hue 0; the shader turns it clockwise by the hue.
			return _prism(PackedVector2Array([
				Vector2(0.0, 0.5), Vector2(-0.2, -0.5), Vector2(0.0, -0.36), Vector2(0.2, -0.5)]), false)
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			return box


static func _cylinder(top_radius: float, bottom_radius: float, segments: int) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = 1.0
	cylinder.radial_segments = segments
	cylinder.rings = 1
	return cylinder


static func _rotated(mesh: Mesh, basis: Basis) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.append_from(mesh, 0, Transform3D(basis, Vector3.ZERO))
	return st.commit()


## Regular polygon outline, counter-clockwise, `radius` from the centre.
static func _ngon(points: int, radius: float, start_angle: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for k in points:
		var angle := start_angle + TAU * float(k) / float(points)
		outline.append(Vector2(cos(angle), sin(angle)) * radius)
	return outline


## Star outline alternating between `outer` and `outer * inner_ratio`.
static func _star(points: int, outer: float, inner_ratio: float, start_angle: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for k in points * 2:
		var radius := outer if k % 2 == 0 else outer * inner_ratio
		var angle := start_angle + TAU * float(k) / float(points * 2)
		outline.append(Vector2(cos(angle), sin(angle)) * radius)
	return outline


## Extrudes a counter-clockwise outline (star-shaped about the origin) from z = -0.5 to 0.5. A `hole`
## with the same point count makes a ring. `smooth` shades the side walls as a curved surface.
## Godot treats clockwise triangles as front-facing.
static func _prism(outline: PackedVector2Array, smooth: bool, hole := PackedVector2Array()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := outline.size()
	var has_hole := not hole.is_empty()
	for k in count:
		var n := (k + 1) % count
		var a := outline[k]
		var b := outline[n]
		var ia := hole[k] if has_hole else Vector2.ZERO
		var ib := hole[n] if has_hole else Vector2.ZERO
		# Front (+Z) and back (-Z) caps.
		if has_hole:
			_tri(st, Vector3(a.x, a.y, 0.5), Vector3(ia.x, ia.y, 0.5), Vector3(ib.x, ib.y, 0.5), Vector3.BACK)
			_tri(st, Vector3(a.x, a.y, 0.5), Vector3(ib.x, ib.y, 0.5), Vector3(b.x, b.y, 0.5), Vector3.BACK)
			_tri(st, Vector3(a.x, a.y, -0.5), Vector3(ib.x, ib.y, -0.5), Vector3(ia.x, ia.y, -0.5), Vector3.FORWARD)
			_tri(st, Vector3(a.x, a.y, -0.5), Vector3(b.x, b.y, -0.5), Vector3(ib.x, ib.y, -0.5), Vector3.FORWARD)
		else:
			_tri(st, Vector3(0.0, 0.0, 0.5), Vector3(b.x, b.y, 0.5), Vector3(a.x, a.y, 0.5), Vector3.BACK)
			_tri(st, Vector3(0.0, 0.0, -0.5), Vector3(a.x, a.y, -0.5), Vector3(b.x, b.y, -0.5), Vector3.FORWARD)
		# Outer wall.
		var edge := b - a
		var flat := Vector3(edge.y, -edge.x, 0.0).normalized()
		_wall(st, a, b, flat, a.normalized() if smooth else flat, b.normalized() if smooth else flat)
		# Inner wall of a ring faces the centre.
		if has_hole:
			var inner_edge := ib - ia
			var inward := Vector3(-inner_edge.y, inner_edge.x, 0.0).normalized()
			_wall(st, ib, ia, inward, ib.normalized() * -1.0, ia.normalized() * -1.0)
	return st.commit()


## One side wall from `a` to `b` (counter-clockwise as seen from outside the wall's normal side).
static func _wall(st: SurfaceTool, a: Vector2, b: Vector2, flat: Vector3, normal_a: Variant, normal_b: Variant) -> void:
	var na: Vector3 = normal_a if normal_a is Vector3 else Vector3(normal_a.x, normal_a.y, 0.0)
	var nb: Vector3 = normal_b if normal_b is Vector3 else Vector3(normal_b.x, normal_b.y, 0.0)
	var af := Vector3(a.x, a.y, 0.5)
	var bf := Vector3(b.x, b.y, 0.5)
	var bb := Vector3(b.x, b.y, -0.5)
	var ab := Vector3(a.x, a.y, -0.5)
	_vert(st, af, na)
	_vert(st, bf, nb)
	_vert(st, bb, nb)
	_vert(st, af, na)
	_vert(st, bb, nb)
	_vert(st, ab, na)


static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, normal: Vector3) -> void:
	_vert(st, p0, normal)
	_vert(st, p1, normal)
	_vert(st, p2, normal)


static func _vert(st: SurfaceTool, position: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(position)
