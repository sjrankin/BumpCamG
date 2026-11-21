class_name ShapeLibrary
extends RefCounted
## Builds the unit-sized meshes that are instanced once per grid cell.
##
## Every shape fits in a 1x1 cell and faces +Z (towards the camera). Flat shapes are single-sided
## polygons in the XY plane; "Blocks" is a unit box that the shader stretches into a bar.

const NAMES: Array[String] = [
	"Blocks", "Spheres", "Cones", "Pyramids", "Cylinders", "Rings",
	"Squares", "Circles", "Triangles", "Diamonds", "Hexagons", "Stars",
]

static var _cache: Dictionary = {}


## True for shapes that the shader stretches along Z instead of lifting.
static func is_bar(shape_name: String) -> bool:
	return shape_name == "Blocks"


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
			var torus := TorusMesh.new()
			torus.inner_radius = 0.3
			torus.outer_radius = 0.5
			torus.rings = 24
			torus.ring_segments = 12
			return _rotated(torus, to_front)
		"Squares":
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			return quad
		"Circles":
			return _polygon(32, 1.0, 0.0)
		"Triangles":
			return _polygon(3, 1.0, PI / 2.0)
		"Diamonds":
			return _polygon(4, 1.0, 0.0)
		"Hexagons":
			return _polygon(6, 1.0, 0.0)
		"Stars":
			return _polygon(5, 0.42, PI / 2.0)
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


## A flat fan of triangles. `inner_ratio` below 1 alternates radii to make a star.
static func _polygon(points: int, inner_ratio: float, start_angle: float) -> ArrayMesh:
	var count := points * (2 if inner_ratio < 1.0 else 1)
	var ring: Array[Vector3] = []
	for k in count:
		var radius := 0.5
		if inner_ratio < 1.0 and k % 2 == 1:
			radius *= inner_ratio
		var angle := start_angle + TAU * float(k) / float(count)
		ring.append(Vector3(cos(angle), sin(angle), 0.0) * radius)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in count:
		_add_front_vertex(st, Vector3.ZERO)
		_add_front_vertex(st, ring[(k + 1) % count])
		_add_front_vertex(st, ring[k])
	return st.commit()


static func _add_front_vertex(st: SurfaceTool, position: Vector3) -> void:
	st.set_normal(Vector3.BACK)
	st.add_vertex(position)
