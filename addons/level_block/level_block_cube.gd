@tool
@icon("res://addons/level_block/icon.svg")
class_name LevelBlockCube
extends LevelBlockBase
## Greybox box primitive. Spans [member LevelBlockBase.size] on each axis from the
## corner pivot at the node origin, growing into -X, +Y, -Z. See
## [LevelBlockBase] for the shared data and child lifecycle; this script carries
## only the box geometry.


func _new_mesh() -> Mesh:
	return BoxMesh.new()


func _new_shape() -> Shape3D:
	return BoxShape3D.new()


func _apply_geometry() -> void:
	var box_mesh: BoxMesh = _mesh_instance.mesh
	box_mesh.size = size
	var box_shape: BoxShape3D = _shape.shape
	box_shape.size = size
	# BoxMesh/BoxShape3D are center-origin. Offset so the node origin lands on the
	# front-bottom-right corner (+X, minY, +Z); block grows into -X, +Y, -Z.
	var center: Vector3 = Vector3(-size.x * 0.5, size.y * 0.5, -size.z * 0.5)
	_mesh_instance.position = center
	_shape.position = center


## The 8 box corners. Box spans x:[-s.x,0] y:[0,s.y] z:[-s.z,0]; pivot at (0,0,0).
func get_corner_points() -> PackedVector3Array:
	var s: Vector3 = size
	return [
		Vector3(0, 0, 0),
		Vector3(-s.x, 0, 0),
		Vector3(-s.x, 0, -s.z),
		Vector3(0, 0, -s.z),
		Vector3(0, s.y, 0),
		Vector3(-s.x, s.y, 0),
		Vector3(-s.x, s.y, -s.z),
		Vector3(0, s.y, -s.z),
	]


func get_edge_indices() -> PackedInt32Array:
	# Appended in short labelled groups: the formatter explodes any array literal
	# that doesn't fit on one line, and 24 indices one-per-line is unreadable.
	var edges: PackedInt32Array = []
	edges.append_array([0, 1, 1, 2, 2, 3, 3, 0]) # bottom
	edges.append_array([4, 5, 5, 6, 6, 7, 7, 4]) # top
	edges.append_array([0, 4, 1, 5, 2, 6, 3, 7]) # verticals
	return edges


## Centre of each face opposite the pivot.
func get_handle_anchors() -> PackedVector3Array:
	var s: Vector3 = size
	return [
		Vector3(-s.x, s.y * 0.5, -s.z * 0.5), # -X face
		Vector3(-s.x * 0.5, s.y, -s.z * 0.5), # +Y face
		Vector3(-s.x * 0.5, s.y * 0.5, -s.z), # -Z face
	]


func get_face_indices() -> PackedInt32Array:
	# Wound clockwise seen from outside, per LevelBlockBase.get_face_indices.
	var tris: PackedInt32Array = []
	tris.append_array([0, 2, 1, 0, 3, 2]) # bottom
	tris.append_array([4, 5, 6, 4, 6, 7]) # top
	tris.append_array([0, 1, 5, 0, 5, 4]) # side -X..0 @ z=0
	tris.append_array([1, 2, 6, 1, 6, 5]) # side @ x=-s.x
	tris.append_array([2, 3, 7, 2, 7, 6]) # side @ z=-s.z
	tris.append_array([3, 0, 4, 3, 4, 7]) # side @ x=0
	return tris
