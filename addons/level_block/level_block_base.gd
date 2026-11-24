@tool
@abstract
class_name LevelBlockBase
extends Node3D
## Shared skeleton for corner-pivoted greybox primitives. Node origin sits at the
## front-bottom-right corner (+X, minY, +Z); the shape grows into -X, +Y, -Z from
## that grid-snappable corner. Mesh + collision are rebuilt procedurally from
## [member size], [member grid_step], [member material] and the collision flags,
## which are the only properties the scene file carries by default — set
## [member persist_geometry] to put the generated nodes in the file too.
##
## Subclasses supply geometry only: [method _new_mesh] / [method _new_shape] mint
## the child resources, [method _apply_geometry] sizes them, and the three
## corner/index getters feed the gizmo's outline and click-selection hull.

const MIN_SIZE: float = 0.05

# Names for the generated children. Left to the engine they come out as
# "@MeshInstance3D@4" — a per-session counter, so with persist_geometry on the
# same block would land in the scene file under a different name depending on
# which session authored it, taking every NodePath under it along.
const MESH_NAME: StringName = &"LevelBlockMesh"
const BODY_NAME: StringName = &"LevelBlockBody"
const SHAPE_NAME: StringName = &"LevelBlockShape"

## Bounding extents in local units. The shape spans [member size] on each axis.
## Each assignment snaps every component to [member grid_step] and floors it at one
## full step, so a block stays grid-aligned and never reaches zero extent. Changing
## [member grid_step] does not itself re-snap size — that would clobber an extent
## mid-edit — but the next size write does, and [method _ready] performs one on
## every scene load. So a size left below the step (e.g. after raising grid_step)
## re-aligns up the next time the scene is reopened.
@export var size: Vector3 = Vector3.ONE:
	set(value):
		if not is_node_ready():
			# Scene load applies exported properties in declaration order, and this
			# setter reads grid_step, which is declared after size — so at load time
			# grid_step is still its default. Snapping now would round against the
			# wrong step and corrupt the saved size. Store it raw; _ready snaps once
			# every property has loaded. (Assigning `size` inside its own setter
			# writes the backing field directly — GDScript doesn't re-enter the
			# setter here, same as the snap line below.)
			size = value
			return
		var step: Vector3 = Vector3.ONE * maxf(grid_step, MIN_SIZE)
		# Floor AFTER snapping: snapped() rounds anything under half a step down to
		# zero, which used to yield a zero-extent mesh and collision shape. One step
		# is the same floor the gizmo's drag handles enforce.
		size = value.snapped(step).max(step)
		_rebuild()
## Snap increment applied to [member size] (and used by the gizmo handles).
@export var grid_step: float = 1.0:
	set(value):
		grid_step = maxf(value, MIN_SIZE)
		_rebuild()
## Surface material for the greybox faces.
@export var material: Material = preload("res://addons/level_block/default_material.tres"):
	set(value):
		material = value
		# Parentage, not nullity: a child removed from the SceneTree dock stays
		# alive, and writing into it would edit a node the block no longer owns
		# while leaving the one it rebuilds untouched. The next rebuild re-resolves
		# the child and applies the value there.
		if _is_live_child(_mesh_instance, self):
			_mesh_instance.material_override = material
## Physics layer(s) the static body occupies. Set to your world/collision layer.
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if _is_live_child(_body, self): # see the note on material
			_body.collision_layer = collision_layer
## Physics layer(s) the static body scans. Static geometry usually scans nothing.
@export_flags_3d_physics var collision_mask: int = 0:
	set(value):
		collision_mask = value
		if _is_live_child(_body, self): # see the note on material
			_body.collision_mask = collision_mask
## Whether the generated mesh and static body are written into the scene file.
##
## Off (the default), they exist only once this script has run: they stay out of
## the SceneTree dock, out of the [code].tscn[/code], and out of the reach of
## anything that reads the file rather than the running tree. On, they become
## ordinary owned nodes — visible and selectable in the dock, addable to groups,
## saved with the scene — while the block stays fully editable, because the
## rebuild adopts them by their meta tag instead of spawning a second set.
##
## Turn it on when something outside this addon has to see the geometry as nodes:
## a [NavigationMesh] baking in Group Explicit mode (which reads only the tagged
## nodes themselves, never their children), a tool that parses the scene file, or
## simply wanting the collider visible while debugging. Everything that walks the
## live tree — navmesh baking in its default Root Node Children mode, [LightmapGI],
## [OccluderInstance3D], glTF export — already sees the geometry with this off.
##
## Costs scene-file size: the mesh and hull resources are written out per block,
## several times the block's own handful of properties, and a rebuild re-mints
## them on load anyway. Worth it where something needs the nodes, not by default.
##
## Editor-only: ownership means nothing at runtime, where the children are always
## rebuilt. Requires the block to belong to the scene being edited — a block
## inside an instanced sub-scene belongs to that sub-scene, and only persists when
## the sub-scene itself is the open one.
@export var persist_geometry: bool = false:
	set(value):
		persist_geometry = value
		_apply_persistence()
		update_configuration_warnings()

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
# The exact resources last minted into the children, held so a rebuild can tell
# the ones this block made from ones dropped into the inspector slots that
# persist_geometry exposes. Identity rather than class: _new_mesh() on the wedge
# returns a bare ArrayMesh, the most generic mesh there is, so a class test would
# read any ArrayMesh a user dropped as the block's own and clear its surfaces.
# Null until the first mint, and reset by a @tool reload along with the refs.
var _minted_mesh: Mesh
var _minted_shape: Shape3D


## Snaps size against the now-loaded grid_step and builds the procedural children.
## A subclass overriding _ready MUST call super._ready(), or the block loads with
## an unsnapped size and no mesh or collision.
func _ready() -> void:
	# Now that grid_step has loaded, run size through the setter's ready path — it
	# snaps against the correct step and builds the children. The doc on `size`
	# counts _ready as one of its "size writes"; this is that write.
	size = size


## Editor-only setter used by the gizmo to grow one axis from the fixed corner.
func set_axis_size(axis: int, value: float) -> void:
	var new_size: Vector3 = size
	new_size[axis] = value
	size = new_size

# --- Subclass geometry hooks -------------------------------------------------
# @abstract: a subclass that omits any of these fails to parse, so an incomplete
# shape can never reach a user's project.


## Mints the mesh resource this shape draws into. One fresh instance per call.
@abstract func _new_mesh() -> Mesh


## Mints the collision shape resource. One fresh instance per call.
@abstract func _new_shape() -> Shape3D


## Resizes the child mesh + shape to [member size] and places them relative to
## the corner pivot. Called only with both children present and non-null.
@abstract func _apply_geometry() -> void


## Vertices of the shape's hull in local space, pivot at the origin. Indexed by
## [method get_edge_indices] and [method get_face_indices].
@abstract func get_corner_points() -> PackedVector3Array


## Vertex index pairs for the gizmo's wireframe outline.
@abstract func get_edge_indices() -> PackedInt32Array


## Vertex index triples for the gizmo's click-selection hull. Wound clockwise as
## seen from outside, which is Godot's front-facing convention.
@abstract func get_face_indices() -> PackedInt32Array


## Where the three drag handles sit, in X, Y, Z order, before the gizmo floats
## them off the surface. Per-shape because a box's face centres land inside a
## wedge's sloped face — the handle would hang in mid-air.
##
## Each anchor's components on the OTHER two axes must not depend on its own
## axis. The drag rebuilds its measuring line every motion from the live anchor,
## taking the part of it perpendicular to the axis being dragged; if that part
## moves as the axis grows, the line slides out from under the cursor mid-drag.
## Both shapes satisfy this — every anchor's perpendicular part is a fraction of
## the other two extents — but a new shape has to be checked against it.
@abstract func get_handle_anchors() -> PackedVector3Array

# --- Child lifecycle ---------------------------------------------------------


func _get_configuration_warnings() -> PackedStringArray:
	if persist_geometry and _edited_scene_root() == null:
		# The declared return type converts the literal; no constructor wrapper.
		return [
			(
				"persist_geometry is on, but this block does not belong to the scene "
				+ "being edited, so its geometry will not be saved. Open the scene "
				+ "that owns this block to persist it."
			)
		]
	return []


## Builds (or refreshes) the child mesh + collision. Idempotent.
func _rebuild() -> void:
	if not is_node_ready():
		return
	_ensure_children()
	_apply_geometry()
	update_gizmos()


## Creates the children once, then hands them to [method _apply_persistence],
## which decides via [member persist_geometry] whether they reach the .tscn. On a
## @tool script reload the instance vars reset but the children persist, so we
## re-adopt the meta-tagged survivors instead of spawning duplicates — the same
## adoption that picks up children loaded from a scene saved with persistence on.
func _ensure_children() -> void:
	_ensure_mesh()
	_ensure_body()
	_ensure_shape()
	_body.collision_layer = collision_layer
	_body.collision_mask = collision_mask
	_apply_persistence()


## Resolves [member _mesh_instance] — adopting the tagged survivor if there is
## one, minting the node if there is not — and leaves it holding a mesh of the
## class [method _apply_geometry] expects.
func _ensure_mesh() -> void:
	if not _is_live_child(_mesh_instance, self):
		_mesh_instance = null
	var adopted: bool = false
	if _mesh_instance == null:
		_mesh_instance = _find_proc_child(self, &"_lb_mesh") as MeshInstance3D
		adopted = _mesh_instance != null
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.set_meta(&"_lb_mesh", true)
		_mesh_instance.name = MESH_NAME
		add_child(_mesh_instance)
	# Re-minted on adoption whatever it holds, because a duplicated block arrives
	# sharing the original's mesh — duplicate() copies resource *references*, and
	# resizing one block would resize its copies. Re-minted again whenever the mesh
	# is not the one this block last made, which persist_geometry newly allows: the
	# node is in the dock, so its mesh is an inspector slot, and anything dropped
	# there either fails _apply_geometry on the type or — worse, because it is
	# silent — gets resized and cleared as though the block had authored it.
	# _minted_mesh null is the untouched state — a fresh node or a @tool reload —
	# and has to be tested for its own sake: the node's mesh is null there too, and
	# null == null would read as a match and leave the block with no mesh at all.
	if adopted or _minted_mesh == null or _mesh_instance.mesh != _minted_mesh:
		_minted_mesh = _new_mesh()
		_mesh_instance.mesh = _minted_mesh
	_mesh_instance.material_override = material
	_release_surplus(self, &"_lb_mesh", _mesh_instance)
	_assert_name(_mesh_instance, MESH_NAME)


## Resolves [member _body], adopting the tagged survivor or minting one.
func _ensure_body() -> void:
	if not _is_live_child(_body, self):
		_body = null
	if _body == null:
		_body = _find_proc_child(self, &"_lb_body") as StaticBody3D
	if _body == null:
		_body = StaticBody3D.new()
		_body.set_meta(&"_lb_body", true)
		_body.name = BODY_NAME
		add_child(_body)
	_release_surplus(self, &"_lb_body", _body)
	_assert_name(_body, BODY_NAME)


## Resolves [member _shape]. Looked up under the body by tag rather than by
## position, and separately from the body itself: the two are only born together,
## either can be deleted from the dock on its own once persist_geometry has made
## them visible there, and the body is a normal node a user may have parented
## something else under.
func _ensure_shape() -> void:
	if not _is_live_child(_shape, _body):
		_shape = null
	var adopted: bool = false
	if _shape == null:
		_shape = _find_proc_child(_body, &"_lb_shape") as CollisionShape3D
		if _shape == null:
			_shape = _adoptable_untagged_shape(_body)
		adopted = _shape != null
		if adopted:
			_shape.set_meta(&"_lb_shape", true)
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.set_meta(&"_lb_shape", true)
		_shape.name = SHAPE_NAME
		_body.add_child(_shape)
	if adopted or _minted_shape == null or _shape.shape != _minted_shape:
		_minted_shape = _new_shape() # same three reasons as the mesh
		_shape.shape = _minted_shape
	_release_surplus(_body, &"_lb_shape", _shape)
	_assert_name(_shape, SHAPE_NAME)


## Points the generated children's owner at the edited scene, or clears it, to
## match [member persist_geometry]. A node serializes into a scene only if it is
## owned by that scene's root, so this one field is the whole difference between
## geometry that lives in the file and geometry that lives only in this script.
##
## No-op outside the editor and for a block that isn't part of the edited scene;
## [method _get_configuration_warnings] is what tells the user about the latter,
## since a checkbox that reads on while nothing gets saved is otherwise silent.
func _apply_persistence() -> void:
	if not persist_geometry:
		# Released whatever is still ours, without first requiring all three to be
		# — a child gone from the dock is no reason to leave its siblings owned,
		# which would keep writing them into the file with the box unticked until
		# some later edit happened to run this again.
		_set_geometry_owner(null)
		return
	var scene_root: Node = _edited_scene_root()
	if scene_root == null:
		# No scene to belong to. Deliberately leaves the current owner alone
		# rather than clearing it: opening a scene runs _ready before the editor
		# has finished designating the edited root, and clearing here would strip
		# the ownership that was just loaded from the file.
		return
	_set_geometry_owner(scene_root)


## The scene root that would own this block's geometry, or null if there is none
## to own it.
##
## Membership is tested through [member Node.owner] rather than ancestry: a block
## inside an instanced sub-scene IS a descendant of the edited root, but belongs
## to the sub-scene, and the packer drops geometry owned by anything else. Its
## geometry can only be persisted by opening the sub-scene itself.
func _edited_scene_root() -> Node:
	if not is_inside_tree():
		return null
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == self or owner == scene_root:
		return scene_root
	return null


## Assigns [param target] as owner of each generated node still attached where
## this block put it. Guarded per child rather than for the set: assigning an
## owner to a node outside the block errors, and one child gone from the dock
## must not decide the other two's ownership. [method _ensure_children] resolves
## the missing one and calls back here.
func _set_geometry_owner(target: Node) -> void:
	_set_owner_if_live(_mesh_instance, self, target)
	if not _is_live_child(_body, self):
		# The shape hangs off the body, so a detached body takes its shape out of
		# the block's reach too. Claiming the shape anyway either errors outright
		# or — worse, when the body was dragged elsewhere in the same scene rather
		# than deleted — quietly succeeds, leaving the block owning a node sitting
		# under someone else's.
		return
	_set_owner_if_live(_body, self, target)
	_set_owner_if_live(_shape, _body, target)


## Gives [param child] to [param target] if it is still parented to
## [param parent]. Skips the write when the owner already matches: a rebuild runs
## on every motion event of a handle drag, and this is otherwise a setter call per
## child per frame for a value that has not changed.
static func _set_owner_if_live(child: Variant, parent: Variant, target: Node) -> void:
	if not _is_live_child(child, parent):
		return
	var node: Node = child
	if node.owner != target:
		node.owner = target


## Returns the child of [param parent] carrying [param meta_key], or null.
## Bounded scan.
static func _find_proc_child(parent: Node, meta_key: StringName) -> Node:
	for child: Node in parent.get_children():
		if child.has_meta(meta_key):
			return child
	return null


## Returns an untagged [CollisionShape3D] that this addon plainly made itself, or
## null. Adopting one means retagging it, replacing its resource and moving it
## onto the pivot, so the test has to be one a collider added through the dock
## cannot pass. A collider parented by a script can still pass it — nothing
## distinguishes one of those from a pre-tag build's own child.
##
## Serves only blocks built before the [code]_lb_shape[/code] tag existed — an
## addon updated underneath an open editor, reaching here through the @tool script
## reload that follows. Three conditions, none of them sufficient alone: the body
## has no other child, the node still carries an engine-assigned name (they begin
## with [code]@[/code]), and nothing owns it.
##
## The name alone would not do. The engine also renames on a *collision*, and the
## name it collides with is one this addon puts in front of the user — a collider
## the user adds and names [code]LevelBlockShape[/code] lands as
## [code]@CollisionShape3D@4[/code] and would read as ours. Ownership is what
## separates them: a node added through the dock belongs to the edited scene,
## while a pre-tag build never owned the children it made. Anything failing the
## test is left alone and a second, correctly tagged shape built beside it, which
## the next scene reload resolves.
static func _adoptable_untagged_shape(body: Node) -> CollisionShape3D:
	if body.get_child_count() != 1:
		return null
	var only: CollisionShape3D = body.get_child(0) as CollisionShape3D
	if only == null or not only.name.begins_with("@") or only.owner != null:
		return null
	return only


## Whether [param child] is still a live child of [param parent].
##
## Checked in place of a plain null test because deleting a node from the
## SceneTree dock removes it from the tree but keeps it alive for undo — which
## persist_geometry newly makes reachable, since that is what puts these nodes in
## the dock at all. The reference stays non-null, so a block that trusted it would
## never rebuild the child, run the rest of the session without it, and log an
## error every frame of a drag trying to re-own a node it no longer parents.
## Both parameters are deliberately untyped. A reference to a freed node does not
## satisfy a [Node] parameter — the call fails on the argument's type before the
## body runs, because a freed object no longer reports a class — and a freed node
## is one of the two states this is here to catch. That holds for the parent as
## much as the child: [code]_is_live_child(_shape, _body)[/code] passes one
## generated child in as the other's parent, and a freed body would take the whole
## rebuild down from the argument list.
static func _is_live_child(child: Variant, parent: Variant) -> bool:
	if not is_instance_valid(child) or not is_instance_valid(parent):
		return false
	var node: Node = child
	return node.get_parent() == parent


## Disowns any child of [param parent] carrying [param meta_key] other than
## [param keeper]: the tag comes off and, with it, any claim on the scene file.
##
## A block can end up holding two tagged children of a kind without ever having
## made two. Deleting one from the dock and undoing brings the original back
## beside the replacement the rebuild had already minted; duplicating one with
## Ctrl+D copies its metadata along with it. Whichever the tag search then finds
## first is the one the block keeps updating, and the other used to sit there
## owned — packed into the [code].tscn[/code] as a permanent duplicate collider
## or mesh that nothing ever resized again.
##
## Untagged and disowned rather than freed. The surplus node reached this state
## through the user's own undo or duplicate, so it is theirs to remove, and the
## editor's undo history holds a reference to it that freeing would dangle.
static func _release_surplus(parent: Node, meta_key: StringName, keeper: Node) -> void:
	for child: Node in parent.get_children():
		if child == keeper or not child.has_meta(meta_key):
			continue
		_untag(child)
		# A surplus body brings its own tagged shape with it, and that shape is not
		# a child of anything this pass walks. Left alone it stays a tagged collider
		# that would be adopted again the moment its body came back under a block.
		for grandchild: Node in child.get_children():
			_untag(grandchild)


## Strips every tag this addon marks its own children with, and nothing else:
## the node keeps its name, its owner, its place in the tree and its resources.
##
## Ownership in particular stays. Clearing it would drop the node out of the
## SceneTree dock, leaving something that still renders but cannot be selected or
## deleted — and an untagged node is an ordinary node, which is exactly what a
## user's undo or Ctrl+D made it.
##
## The node becomes ordinary; its resources do not. A duplicate copies resource
## properties by reference, so a released copy goes on sharing the mesh or hull
## the block still resizes, and follows its size until someone gives it one of
## its own. That is [method Node.duplicate] behaving as documented, not something
## this addon can undo without editing a node it has just disclaimed.
static func _untag(node: Node) -> void:
	if node.has_meta(&"_lb_mesh"):
		node.remove_meta(&"_lb_mesh")
	if node.has_meta(&"_lb_body"):
		node.remove_meta(&"_lb_body")
	if node.has_meta(&"_lb_shape"):
		node.remove_meta(&"_lb_shape")


## Restores [param wanted] on a generated child that came back engine-named.
##
## The names are set at mint, which is not enough to keep them: [method add_child]
## resolves a clash by renaming, so a block whose own name was taken — by a user's
## node, or by a copy of its own that an undo restored — ends up carrying
## [code]@MeshInstance3D@4[/code]. That name holds a per-session counter, and with
## [member persist_geometry] on it goes into the scene file, so the same block
## lands under a different name depending on which session saved it.
##
## Only engine names are corrected. A clash that resolved to [code]LevelBlockMesh2[/code]
## is stable across sessions and belongs to whatever took the name first; rewriting
## it every rebuild would fight the user for a name they are entitled to.
static func _assert_name(node: Node, wanted: StringName) -> void:
	if node.name.begins_with("@"):
		node.name = wanted
