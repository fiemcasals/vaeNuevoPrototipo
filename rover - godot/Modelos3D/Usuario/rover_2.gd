extends VehicleBody3D
class_name Rover

@export var max_steer = 0.4
@export var brake_force = 20.0
@export var handbrake_force = 100.0
@export var steer_speed = 8.0
@export var deadzone = 0.15
@export var input_curve = 2.0
@export var speed_steer_limit = 0.3

@export var r_trasera_iz: VehicleWheel3D = null
@export var r_trasera_der: VehicleWheel3D = null
@export var speed_modifier:float=1.0

var current_cam:int=3
var auto_controlled: bool = false
var mud_zones: Array = []

# Valores de configuración
var power: float = 300.0
var max_speed: float = 50.0

func _ready() -> void:
	# Aplicar configuración desde RoverConfig
	if RoverConfig:
		power = RoverConfig.torque
		max_speed = RoverConfig.velocidad_maxima
		mass = RoverConfig.peso_rover

func _physics_process(delta: float) -> void:
	if auto_controlled:
		return
	
	var throttle = Input.get_axis("backward", "forward")
	var raw_steer = Input.get_axis("turn_right", "turn_left")
	var is_braking = Input.is_action_pressed("brake")
	var is_handbraking = Input.is_action_pressed("handbrake")
	
	var in_mud = mud_zones.size() > 0
	var current_max_speed = 5.0 if in_mud else max_speed
	var engine_multiplier = 0.3 if in_mud else 1.0
	var brake_multiplier = 15.0 if in_mud else 1.0

	# Apply deadzone
	var steer_input = 0.0
	if abs(raw_steer) > deadzone:
		steer_input = (abs(raw_steer) - deadzone) / (1.0 - deadzone)
		steer_input = sign(raw_steer) * steer_input

	# Apply input curve
	steer_input = sign(steer_input) * pow(abs(steer_input), input_curve)

	# Speed-sensitive steering
	var speed = linear_velocity.length()
	var speed_factor = clamp(1.0 - (speed / 50.0), speed_steer_limit, 1.0)
	var effective_steer = max_steer * speed_factor

	# Steering
	steering = move_toward(steering, steer_input * effective_steer, delta * steer_speed)

	# Braking
	if is_braking:
		engine_force = 0
		brake = brake_force * brake_multiplier
		r_trasera_iz.brake = 0
		r_trasera_der.brake = 0
	elif is_handbraking:
		engine_force = 0
		brake = 0
		r_trasera_iz.brake = handbrake_force
		r_trasera_der.brake = handbrake_force
	else:
		brake = 0
		r_trasera_iz.brake = 0
		r_trasera_der.brake = 0
		engine_force = throttle * power * speed_modifier * engine_multiplier

	# Coasting friction
	if throttle == 0 and not is_braking and not is_handbraking:
		brake = 5.0
	
	# Limitar velocidad en barro
	if in_mud:
		speed = linear_velocity.length()
		if speed > max_speed:
			var brake_force_mud = (speed - max_speed) * 15.0
			brake = max(brake, min(brake_force_mud, 40.0))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_cam"):
		match current_cam:
			1:
				current_cam=3
				SignalBus.change_cam.emit(current_cam)
			3:
				current_cam=1
				SignalBus.change_cam.emit(current_cam)

func add_mud_zone(zone: Area3D) -> void:
	if zone not in mud_zones:
		mud_zones.append(zone)
		print("Zonas de barro activas: ", mud_zones.size())

func remove_mud_zone(zone: Area3D) -> void:
	mud_zones.erase(zone)
	print("Zonas de barro activas: ", mud_zones.size())
