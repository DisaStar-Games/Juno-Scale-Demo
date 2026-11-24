class_name Player
extends CharacterBody3D
## Simple test player: walk, sprint, jump. Speeds, jump and capsule size match back-on-track.

@export_group("Look")
@export var mouse_sensitivity := 0.0025

@export_group("Speeds")
@export var walk_speed := 4.0
@export var sprint_speed := 6.5

@export_group("Ground movement")
@export var ground_accel := 40.0
@export var ground_decel := 45.0

@export_group("Jump")
@export var jump_height := 1.6
@export var time_to_peak := 0.35
@export var fall_gravity_multiplier := 1.3
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Air control")
@export var air_speed_cap := 7.0
@export var air_accel := 25.0

@onready var gravity: float = (2.0 * jump_height) / (time_to_peak * time_to_peak)
@onready var jump_velocity: float = gravity * time_to_peak
@onready var head: Node3D = $Head
@onready var pitch: Node3D = $Head/Pitch

var wish_dir := Vector3.ZERO
var coyote_timer := 0.0
var jump_buffer_timer := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.5
	floor_constant_speed = true
	floor_stop_on_slope = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		pitch.rotation.x = clampf(
			pitch.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()

	var i := Input.get_vector("left", "right", "forward", "back")
	wish_dir = (head.global_basis * Vector3(i.x, 0.0, i.y)).normalized()

	coyote_timer = maxf(coyote_timer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	if is_on_floor():
		var sprinting := Input.is_action_pressed("sprint") and wish_dir != Vector3.ZERO
		_accelerate(sprint_speed if sprinting else walk_speed, delta)
	else:
		_air_steer(delta)

	if jump_buffer_timer > 0.0 and (is_on_floor() or coyote_timer > 0.0):
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# Falling or released jump early => stronger gravity (short hop + snappy fall)
	var g := gravity
	if velocity.y < 0.0 or not Input.is_action_pressed("jump"):
		g *= fall_gravity_multiplier
	velocity.y -= g * delta

	move_and_slide()

	# Walked off a ledge (not jumped): start the coyote window
	if was_on_floor and not is_on_floor() and velocity.y <= 0.0:
		coyote_timer = coyote_time


func _accelerate(target_speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ground_accel if wish_dir != Vector3.ZERO else ground_decel
	horizontal = horizontal.move_toward(wish_dir * target_speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


# Adds speed along wish_dir only up to a cap, never kills existing momentum
func _air_steer(delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var limit := maxf(horizontal.length(), air_speed_cap)
	horizontal += wish_dir * air_accel * delta
	if horizontal.length() > limit:
		horizontal = horizontal.normalized() * limit
	velocity.x = horizontal.x
	velocity.z = horizontal.z
