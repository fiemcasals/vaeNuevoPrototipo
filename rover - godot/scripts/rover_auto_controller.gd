extends Node
class_name RoverAutoController

@export var rover: VehicleBody3D
@export var navigation: NavigationSystem
@export var arrival_threshold: float = 1.5
@export var max_speed: float = 15.0
@export var rotation_speed: float = 5.0

var is_active: bool = false
var target_position: Vector3 = Vector3.ZERO

signal navigation_started
signal navigation_stopped
signal waypoint_reached

func _ready():
	set_physics_process(false)
	# Cargar configuración desde RoverConfig
	if RoverConfig:
		max_speed = RoverConfig.velocidad_maxima * 0.3  # Convertir a unidades de Godot

func start():
	if navigation and navigation.current_path.size() > 0:
		is_active = true
		set_physics_process(true)
		if rover:
			rover.auto_controlled = true
		navigation_started.emit()
		print("AutoController started")

func stop():
	is_active = false
	set_physics_process(false)
	if rover:
		rover.auto_controlled = false
		rover.engine_force = 0
		rover.brake = 10.0
	navigation_stopped.emit()
	print("AutoController stopped")

func _physics_process(delta: float):
	if not is_active or not rover or not navigation:
		return
	
	target_position = navigation.get_current_target()
	
	if target_position == Vector3.ZERO:
		stop()
		return
	
	var distance_to_target = _get_horizontal_distance(rover.global_position, target_position)
	var distance_to_final = _get_distance_to_final_target()
	
	if distance_to_target < arrival_threshold:
		waypoint_reached.emit()
		if not navigation.advance_to_next_waypoint():
			stop()
			return
		target_position = navigation.get_current_target()
		distance_to_final = _get_distance_to_final_target()
	
	_rotate_towards_target(delta)
	_drive_forward(distance_to_final)

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	var diff = to - from
	diff.y = 0
	return diff.length()

func _get_distance_to_final_target() -> float:
	if navigation.current_path.size() == 0:
		return 0.0
	var final_cell = navigation.current_path[navigation.current_path.size() - 1]
	var final_pos = navigation.grid_to_world(final_cell)
	return _get_horizontal_distance(rover.global_position, final_pos)

func _rotate_towards_target(delta: float):
	var to_target = target_position - rover.global_position
	to_target.y = 0
	
	if to_target.length() < 0.1:
		return
	
	var target_angle = atan2(to_target.x, to_target.z)
	var current_angle = rover.rotation.y
	
	var angle_diff = target_angle - current_angle
	
	while angle_diff > PI:
		angle_diff -= 2 * PI
	while angle_diff < -PI:
		angle_diff += 2 * PI
	
	rover.rotation.y += angle_diff * rotation_speed * delta

func _drive_forward(distance_to_final: float):
	var speed = rover.linear_velocity.length()
	
	var in_mud = rover.mud_zones.size() > 0
	var current_max_speed = 5.0 if in_mud else max_speed
	var engine_multiplier = 0.3 if in_mud else 1.0
	var current_power = RoverConfig.torque if RoverConfig else 300.0
	
	var target_speed = current_max_speed
	var braking_distance = 12.0
	
	if distance_to_final < braking_distance:
		var speed_factor = distance_to_final / braking_distance
		target_speed = current_max_speed * speed_factor * speed_factor
	
	target_speed = max(target_speed, 0.5)
	
	if speed < target_speed:
		rover.engine_force = current_power * engine_multiplier
		rover.brake = 0.0
	else:
		rover.engine_force = 0.0
		var brake_strength = 10.0 + (speed - target_speed) * 2.0
		rover.brake = min(brake_strength, 35.0)
