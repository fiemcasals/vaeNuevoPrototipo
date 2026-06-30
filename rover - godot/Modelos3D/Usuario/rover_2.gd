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

# Torreta
var turret_base: Node3D
var turret_barrel: Node3D
var turret_camera: Camera3D
var turret_yaw: float = 0.0
var turret_pitch: float = 0.0
var _mouse_relative: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Aplicar configuración desde RoverConfig
	if RoverConfig:
		power = RoverConfig.torque
		max_speed = RoverConfig.velocidad_maxima
		mass = RoverConfig.peso_rover
	setup_turret()

func setup_turret() -> void:
	# 1. Crear TurretBase
	turret_base = Node3D.new()
	turret_base.name = "TurretBase"
	turret_base.position = Vector3(0.0, 0.35, -0.1) # Sobre el techo
	add_child(turret_base)
	
	# Crear cilindro base
	var base_mesh_inst = MeshInstance3D.new()
	base_mesh_inst.name = "BaseMesh"
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.2
	cylinder_mesh.bottom_radius = 0.22
	cylinder_mesh.height = 0.1
	base_mesh_inst.mesh = cylinder_mesh
	
	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(0.2, 0.2, 0.15)
	base_material.metallic = 0.7
	base_material.roughness = 0.4
	base_mesh_inst.material_override = base_material
	turret_base.add_child(base_mesh_inst)
	
	# 2. Crear TurretBarrel (elevación/pitch)
	turret_barrel = Node3D.new()
	turret_barrel.name = "TurretBarrel"
	turret_barrel.position = Vector3(0.0, 0.1, 0.0)
	turret_base.add_child(turret_barrel)
	
	# Cajón de mecanismos
	var receptor_mesh_inst = MeshInstance3D.new()
	receptor_mesh_inst.name = "ReceptorMesh"
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.12, 0.1, 0.2)
	receptor_mesh_inst.mesh = box_mesh
	
	var gun_material = StandardMaterial3D.new()
	gun_material.albedo_color = Color(0.1, 0.1, 0.1)
	gun_material.metallic = 0.8
	gun_material.roughness = 0.3
	receptor_mesh_inst.material_override = gun_material
	turret_barrel.add_child(receptor_mesh_inst)
	
	# Cañón cilíndrico
	var barrel_mesh_inst = MeshInstance3D.new()
	barrel_mesh_inst.name = "BarrelMesh"
	var barrel_cyl = CylinderMesh.new()
	barrel_cyl.top_radius = 0.02
	barrel_cyl.bottom_radius = 0.025
	barrel_cyl.height = 0.4
	barrel_mesh_inst.mesh = barrel_cyl
	barrel_mesh_inst.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	barrel_mesh_inst.position = Vector3(0.0, 0.0, 0.2) # apunta adelante (+Z)
	barrel_mesh_inst.material_override = gun_material
	turret_barrel.add_child(barrel_mesh_inst)
	
	# 3. Crear TurretCamera
	turret_camera = Camera3D.new()
	turret_camera.name = "TurretCamera"
	turret_camera.position = Vector3(0.0, 0.15, -0.25)
	turret_camera.rotation_degrees = Vector3(-5.0, 180.0, 0.0) # Apunta adelante junto con el cañón
	turret_barrel.add_child(turret_camera)

func _physics_process(delta: float) -> void:
	if RoverConfig and RoverConfig.op_mode == "turret":
		# Control de torreta
		var yaw_input = Input.get_axis("turn_right", "turn_left") # A/D
		var pitch_input = Input.get_axis("backward", "forward") # W/S
		
		# Soporte para flechas si no están mapeadas
		if yaw_input == 0:
			if Input.is_key_pressed(KEY_LEFT): yaw_input = 1.0
			elif Input.is_key_pressed(KEY_RIGHT): yaw_input = -1.0
		if pitch_input == 0:
			if Input.is_key_pressed(KEY_UP): pitch_input = 1.0
			elif Input.is_key_pressed(KEY_DOWN): pitch_input = -1.0
			
		turret_yaw += yaw_input * delta * 1.5
		turret_pitch += pitch_input * delta * 1.0
		turret_pitch = clamp(turret_pitch, -0.4, 0.8) # Limitar elevación
		
		# Control de arrastre del mouse
		if _mouse_relative != Vector2.ZERO:
			turret_yaw -= _mouse_relative.x * 0.003
			turret_pitch -= _mouse_relative.y * 0.003
			turret_pitch = clamp(turret_pitch, -0.4, 0.8)
			_mouse_relative = Vector2.ZERO
			
		if turret_base:
			turret_base.rotation.y = turret_yaw
		if turret_barrel:
			turret_barrel.rotation.x = turret_pitch
			
		# Frenar y mantener inmóvil el chasis
		steering = 0.0
		engine_force = 0.0
		brake = 15.0
		return

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
	if RoverConfig and RoverConfig.op_mode == "turret":
		if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
			_mouse_relative = event.relative
			
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
