@tool
extends RefCounted
## Pure geometry behind the gizmo's face-drag handles: where along a growth axis
## the cursor points, and what extent that snaps to. Split out of
## level_block_gizmo_base.gd because [EditorNode3DGizmoPlugin] cannot be
## instantiated outside the editor, which put this math out of reach of the
## headless test suite while it lived there.
##
## Static only — never instantiated. Deliberately carries no [code]class_name[/code]:
## it is addon plumbing, not something a user project should find in autocomplete.

## Smallest sine of the angle between the mouse ray and the dragged axis that
## still yields a usable reading. Sighting down an axis leaves the position along
## it undetermined, and the reading degrades continuously as you approach that —
## so the cutoff sits well clear of it (0.15 ~= 8.6 degrees) and the caller holds
## the current value inside that cone rather than acting on noise.
const MIN_DRAG_SINE: float = 0.15
## Shortest basis column that still inverts. A block scaled to zero on any axis
## has no local space to read a drag in.
const MIN_BASIS_COLUMN: float = 0.000001
## Smallest ratio of basis determinant to the product of its column lengths that
## still inverts — 1.0 for an orthogonal basis, 0 once the columns are coplanar.
## Long columns can still be near-singular if the basis is sheared, which the
## column check alone would pass.
const MIN_BASIS_CONDITION: float = 0.0001


## Distance along [param growth_dir] that the cursor points at, in the local
## space of [param xform], measured from the base of the handle sitting at
## [param anchor]. [param growth_dir] must be unit length — it is projected
## against twice without normalising, so a scaled one misreads both the drag line
## and the conditioning measure, quietly and by its own length. Returns NAN when
## the mouse ray runs too close to that axis for
## the reading to mean anything — see [constant MIN_DRAG_SINE]. Callers hold the
## extent they have on NAN; treating it as a number is what used to collapse a
## block to one grid step the moment the camera lined up with the dragged axis.
static func read_axis(
	xform: Transform3D,
	growth_dir: Vector3,
	anchor: Vector3,
	camera: Camera3D,
	screen_pos: Vector2,
) -> float:
	# A zeroed scale component makes affine_inverse() fail. It doesn't return NAN,
	# it returns the basis un-inverted, so the reading would come back a finite,
	# plausible, wrong number that sails through every check below.
	#
	# Measured against the column lengths rather than the determinant alone: the
	# determinant is the product of the three scales, so a fixed cutoff on it is
	# cubic in scale — a block scaled uniformly to 0.01 has a determinant of 1e-06
	# and would stop answering drags entirely, with nothing to say why. Both terms
	# below are scale-free.
	var basis: Basis = xform.basis
	var lengths: Vector3 = Vector3(basis.x.length(), basis.y.length(), basis.z.length())
	if lengths[lengths.min_axis_index()] < MIN_BASIS_COLUMN:
		return NAN
	var orthogonal_determinant: float = lengths.x * lengths.y * lengths.z
	if absf(basis.determinant()) < MIN_BASIS_CONDITION * orthogonal_determinant:
		return NAN
	var inv: Transform3D = xform.affine_inverse()
	var ray_from: Vector3 = inv * camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = (inv.basis * camera.project_ray_normal(screen_pos)).normalized()
	# The drag line runs along growth_dir through the handle's own perpendicular
	# offset, not through the pivot: the X handle sits at half the block's Y and
	# Z, and measuring against a line through the origin instead biases every
	# oblique reading by that offset.
	var base: Vector3 = anchor - growth_dir * growth_dir.dot(anchor)
	# Intersect the ray with the plane that holds the drag line and faces the
	# camera as squarely as the axis allows. |perp| is the sine of the angle
	# between ray and axis, so it doubles as the conditioning measure: the whole
	# construction degenerates exactly as it approaches zero.
	var perp: Vector3 = ray_dir - growth_dir * growth_dir.dot(ray_dir)
	if perp.length() < MIN_DRAG_SINE:
		return NAN
	var hit: Variant = Plane(perp.normalized(), base).intersects_ray(ray_from, ray_dir)
	if hit == null:
		# Ray points away from the plane. Only reachable behind the near plane in
		# practice, but the drag holds rather than guessing.
		return NAN
	# base sits on the plane by construction and carries no component along
	# growth_dir, so the hit projects onto the axis directly.
	var point: Vector3 = hit
	return growth_dir.dot(point)


## The extent a [param reading] lands on: shifted by the drag's [param offset],
## rounded to [param step], and floored at one full step — the same floor
## [member LevelBlockBase.size] enforces, so the two can't disagree.
static func snap_extent(reading: float, offset: float, step: float) -> float:
	return maxf(roundf((reading + offset) / step) * step, step)
