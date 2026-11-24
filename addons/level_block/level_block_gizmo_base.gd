@tool
@abstract
extends EditorNode3DGizmoPlugin
## Draws hull edges + three face-drag handles for any [LevelBlockBase]. Dragging a
## handle grows that axis from the fixed front-bottom-right pivot corner, snapped
## to the block's [member LevelBlockBase.grid_step]. The outline and click-selection
## hull come from the block's own corner/index getters, so every shape reuses this.
##
## One subclass per shape, each overriding [method _has_gizmo] and
## [method _get_gizmo_name]: the engine's name is per-plugin, not per-node, so a
## single plugin could only ever show one label in View > Gizmos. A subclass per
## shape gives each its own toggle there.

const DragMath: GDScript = preload("res://addons/level_block/level_block_drag_math.gd")

var _handle_axes: PackedInt32Array = [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]
## Direction each axis grows from the pivot corner (+X, minY, +Z): -X, +Y, -Z.
var _growth_dirs: PackedVector3Array = [Vector3.LEFT, Vector3.UP, Vector3.FORWARD]
var _handle_labels: PackedStringArray = ["X", "Y", "Z"]

## How far the handle dots float off their face, in local units.
const HANDLE_OFFSET: float = 0.3
## Point sprite size in pixels for the handle dots.
const HANDLE_POINT_SIZE: float = 28.0

## Axis tints matching the editor gizmo colors (X red, Y green, Z blue).
var _axis_colors: PackedColorArray = [
	Color(0.96, 0.21, 0.32),
	Color(0.54, 0.84, 0.10),
	Color(0.16, 0.55, 0.96),
]
var _handle_materials: Array[StandardMaterial3D] = []
var _undo_redo: EditorUndoRedoManager
## Distance between the axis reading under the cursor and the extent at the
## moment of the grab, held for the rest of the drag so the block doesn't jump to
## meet the cursor on mouse-down. NAN until the drag takes its first reading.
var _drag_offset: float = NAN


func _init(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	create_material("edges", Color(0.4, 0.8, 1.0))
	# create_handle_material()'s materials aren't retrievable via get_material(),
	# so build per-axis point materials directly and keep refs. A solid white
	# disc (tinted per axis) reads cleaner than the hollow editor ring icon.
	var dot_tex: Texture2D = _make_dot_texture()
	for axis: int in 3:
		_handle_materials.append(_make_handle_material(_axis_colors[axis], dot_tex))


## Solid white anti-aliased disc, tinted at draw time by the handle material.
func _make_dot_texture() -> ImageTexture:
	var dim: int = 64
	var center: Vector2 = Vector2(dim, dim) * 0.5
	var radius: float = dim * 0.5 - 1.0
	var img: Image = Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	for y: int in dim:
		for x: int in dim:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha: float = clampf(radius - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


## Unshaded point sprite tinted per axis, drawn on top of geometry (no depth
## test) so the dots always stay visible, using the editor handle icon.
func _make_handle_material(color: Color, tex: Texture2D) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.use_point_size = true
	mat.point_size = HANDLE_POINT_SIZE
	mat.albedo_color = color
	mat.albedo_texture = tex
	return mat


## Which node type this gizmo attaches to. @abstract rather than a broad
## [code]node is LevelBlockBase[/code] default: an inherited broad match would let a
## new shape's gizmo silently claim every other shape too, doubling their handles
## and making drags ambiguous. Forcing the override makes that unrepresentable.
@abstract func _has_gizmo(node: Node3D) -> bool


## Label for this shape's entry in View > Gizmos. The engine asks the plugin, not
## the node, which is why each shape needs its own plugin subclass.
@abstract func _get_gizmo_name() -> String


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var block: LevelBlockBase = gizmo.get_node_3d() as LevelBlockBase
	if block == null:
		return
	var corners: PackedVector3Array = block.get_corner_points()
	gizmo.add_lines(_edge_lines(corners, block.get_edge_indices()), get_material("edges", gizmo))
	# Collision triangles make the whole shape click-selectable in the viewport —
	# the procedural mesh child is non-owned, so it can't forward selection.
	gizmo.add_collision_triangles(_selection_mesh(corners, block.get_face_indices()))
	var points: PackedVector3Array = _handle_points(block)
	for axis: int in 3:
		gizmo.add_handles([points[axis]], _handle_materials[axis], [axis])


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return "Size %s" % _handle_labels[handle_id]


## Opens a drag. This is the only hook the editor fires exactly once per grab,
## and it fires before the first [method _set_handle], so it is where the offset
## latch from the previous drag gets cleared.
func _begin_handle_action(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> void:
	_drag_offset = NAN


## Pure read. The editor calls this once at mouse-down for the value it hands
## back to [method _commit_handle], then again after every [method _set_handle]
## to refresh the viewport readout — so anything latched here would be re-latched
## against the size the drag itself had just written, pinning the block at the
## size it started with.
func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var block: LevelBlockBase = gizmo.get_node_3d() as LevelBlockBase
	if block == null:
		return 0.0
	return block.size[_handle_axes[handle_id]]


func _set_handle(
	gizmo: EditorNode3DGizmo,
	handle_id: int,
	_secondary: bool,
	camera: Camera3D,
	screen_pos: Vector2,
) -> void:
	var block: LevelBlockBase = gizmo.get_node_3d() as LevelBlockBase
	if block == null:
		return
	var axis: int = _handle_axes[handle_id]
	var reading: float = DragMath.read_axis(
		block.global_transform,
		_growth_dirs[handle_id],
		block.get_handle_anchors()[axis],
		camera,
		screen_pos,
	)
	if is_nan(reading):
		# No usable reading this frame (see DragMath.MIN_DRAG_SINE). Hold the
		# current size: acting on the degenerate reading is what used to collapse
		# the block to one step the moment the camera lined up with the axis.
		return
	if is_nan(_drag_offset):
		# First reading of this drag, so block.size is still the pre-drag extent.
		# Anchor to it so grabbing the handle doesn't itself resize the block —
		# the dot floats HANDLE_OFFSET clear of the face, and an absolute reading
		# would snap that gap away on mouse-down.
		_drag_offset = block.size[axis] - reading
	var step: float = maxf(block.grid_step, LevelBlockBase.MIN_SIZE)
	block.set_axis_size(axis, DragMath.snap_extent(reading, _drag_offset, step))


func _commit_handle(
	gizmo: EditorNode3DGizmo,
	handle_id: int,
	_secondary: bool,
	restore: Variant,
	cancel: bool,
) -> void:
	var block: LevelBlockBase = gizmo.get_node_3d() as LevelBlockBase
	if block == null:
		return
	var axis: int = _handle_axes[handle_id]
	# Closes the drag from this end too: a _set_handle arriving without a grab
	# before it should read absolute rather than inherit this drag's offset.
	_drag_offset = NAN
	if cancel:
		block.set_axis_size(axis, float(restore))
		return
	# restore is the value _get_handle_value returned at mouse-down, which the
	# editor captured once and held — the only pre-drag extent still available
	# here, since block.size has been written on every motion since.
	var before: Vector3 = block.size
	before[axis] = float(restore)
	_undo_redo.create_action("Resize Level Block")
	_undo_redo.add_do_property(block, &"size", block.size)
	_undo_redo.add_undo_property(block, &"size", before)
	_undo_redo.commit_action(false)


func _edge_lines(corners: PackedVector3Array, edges: PackedInt32Array) -> PackedVector3Array:
	var lines: PackedVector3Array = []
	for i: int in edges:
		lines.append(corners[i])
	return lines


## The block's solid hull as a TriangleMesh for viewport click-selection.
func _selection_mesh(corners: PackedVector3Array, tris: PackedInt32Array) -> TriangleMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in tris:
		st.add_vertex(corners[i])
	return st.commit().generate_triangle_mesh()


## The shape's own anchors, floated out along each growth direction so the dots
## stand clear of the surface.
func _handle_points(block: LevelBlockBase) -> PackedVector3Array:
	var points: PackedVector3Array = block.get_handle_anchors()
	for axis: int in 3:
		points[axis] += _growth_dirs[axis] * HANDLE_OFFSET
	return points
