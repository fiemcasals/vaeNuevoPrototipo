extends Node3D

@export var vehicle: VehicleBody3D = null
@export var follow_speed: float = 3.0
@export var cam_height: float = 2.0
@export var cam_distance: float = 5.0

func _ready() -> void:
	$ThirdPerson.spring_length = cam_distance
	$ThirdPerson.position.y = cam_height
	# Snap to vehicle on start so it doesn't sweep from origin
	global_position = vehicle.global_position
	global_rotation.y = vehicle.global_rotation.y

func _physics_process(delta: float) -> void:
	global_position = vehicle.global_position

	# Slerp only the Y rotation (yaw) toward the vehicle's yaw
	var target_yaw = vehicle.global_rotation.y
	var current_yaw = global_rotation.y

	global_rotation.y = lerp_angle(current_yaw, target_yaw, follow_speed * delta)
