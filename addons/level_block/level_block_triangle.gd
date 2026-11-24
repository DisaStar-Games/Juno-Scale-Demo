@tool
@icon("res://addons/level_block/icon.svg")
class_name LevelBlockTriangle
extends LevelBlockBase
## Greybox ramp/wedge primitive — a right-triangular prism filling the same
## bounding box as a [LevelBlockCube] of equal [member LevelBlockBase.size].
##
## The slope's high edge sits at the pivot end (z = 0) at full height and falls
## away to zero at z = -size.z, so the ramp climbs toward +Z. Rotate the node on
## Y to face it elsewhere. See [LevelBlockBase] for the shared data and child
## lifecycle; this script carries only the wedge geometry.

## Cross-section is a triangle rather than a square, so the prism fills half its
## bounding box.
const VOLUME_FRACTION: float = 0.5


func _new_mesh() -> Mesh:
	return ArrayMesh.new()


func _new_shape() -> Shape3D:
	var hull: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	# Populated here rather than left to _apply_geometry: assigning a pointless
	# hull to a CollisionShape3D makes the physics server try to build it and log
	# "Failed to build convex hull" before the points ever arrive. Harmless, but
	# it lands in the user's output as a red error from an addon they just added.
	hull.points = get_corner_points()
	return hull


func _apply_geometry() -> void:
	var corners: PackedVector3Array = get_corner_points()
	# Vertices are authored in pivot space already, so unlike the cube (whose
	# BoxMesh is centre-origin) the children need no offset.
	_mesh_instance.position = Vector3.ZERO
	_shape.position = Vector3.ZERO
	var hull: ConvexPolygonShape3D = _shape.shape
	hull.points = corners
	var mesh: ArrayMesh = _mesh_instance.mesh
	mesh.clear_surfaces()
	_build_surface(mesh, corners, get_face_indices())


## Emits one flat-shaded surface. Normals are derived per triangle from the
## winding rather than authored, so the index table stays the single source of
## truth for which way a face points.
func _build_surface(mesh: ArrayMesh, corners: PackedVector3Array, tris: PackedInt32Array) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: int in range(0, tris.size(), 3):
		var v0: Vector3 = corners[tris[t]]
		var v1: Vector3 = corners[tris[t + 1]]
		var v2: Vector3 = corners[tris[t + 2]]
		# Godot front-faces are clockwise seen from outside, so the outward normal
		# is cross(v2 - v0, v1 - v0) — verified against BoxMesh's own arrays.
		var normal: Vector3 = (v2 - v0).cross(v1 - v0).normalized()
		# SurfaceTool holds normal state across add_vertex, so one write per face.
		st.set_normal(normal)
		st.set_uv(_planar_uv(normal, v0))
		st.add_vertex(v0)
		st.set_uv(_planar_uv(normal, v1))
		st.add_vertex(v1)
		st.set_uv(_planar_uv(normal, v2))
		st.add_vertex(v2)
	st.commit(mesh)


## Projects a vertex along the face's dominant axis, 1 UV unit per world unit, to
## match the grid material's "1 cell = 1 unit" reading at any size.
func _planar_uv(normal: Vector3, v: Vector3) -> Vector2:
	var a: Vector3 = normal.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector2(v.z, -v.y)
	if a.y >= a.z:
		return Vector2(v.x, v.z)
	return Vector2(v.x, -v.y)


## The 6 prism corners: a triangle at x = 0 and its copy at x = -size.x. Full
## height at z = 0, tapering to nothing at z = -size.z.
func get_corner_points() -> PackedVector3Array:
	var s: Vector3 = size
	return [
		Vector3(0, 0, 0), # 0 near, bottom, pivot end
		Vector3(0, s.y, 0), # 1 near, top, pivot end
		Vector3(0, 0, -s.z), # 2 near, bottom, far end
		Vector3(-s.x, 0, 0), # 3 far, bottom, pivot end
		Vector3(-s.x, s.y, 0), # 4 far, top, pivot end
		Vector3(-s.x, 0, -s.z), # 5 far, bottom, far end
	]


func get_edge_indices() -> PackedInt32Array:
	var edges: PackedInt32Array = []
	edges.append_array([0, 1, 1, 2, 2, 0]) # near triangle
	edges.append_array([3, 4, 4, 5, 5, 3]) # far triangle
	edges.append_array([0, 3, 1, 4, 2, 5]) # connecting the two
	return edges


func get_face_indices() -> PackedInt32Array:
	var tris: PackedInt32Array = []
	tris.append_array([0, 1, 2]) # near triangular side @ x=0
	tris.append_array([3, 5, 4]) # far triangular side @ x=-s.x
	tris.append_array([0, 3, 4, 0, 4, 1]) # vertical back @ z=0
	tris.append_array([0, 2, 5, 0, 5, 3]) # bottom @ y=0
	tris.append_array([1, 5, 2, 1, 4, 5]) # the slope
	return tris


## Anchors sit on the wedge itself: the far triangle's centroid, the high edge,
## and the far bottom edge. A cube's face centres would float free of the slope.
func get_handle_anchors() -> PackedVector3Array:
	var s: Vector3 = size
	return [
		Vector3(-s.x, s.y / 3.0, -s.z / 3.0), # -X face, triangle centroid
		Vector3(-s.x * 0.5, s.y, 0), # +Y, midpoint of the high edge
		Vector3(-s.x * 0.5, 0, -s.z), # -Z, midpoint of the far bottom edge
	]
