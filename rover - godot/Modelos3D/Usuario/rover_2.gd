extends VehicleBody3D
class_name Rover

@export var max_steer: float = 0.4
@export var brake_force: float = 20.0
@export var handbrake_force: float = 100.0
@export var steer_speed: float = 8.0
@export var deadzone: float = 0.15
@export var input_curve: float = 2.0
@export var speed_steer_limit: float = 0.3

@export var r_trasera_iz: VehicleWheel3D = null
@export var r_trasera_der: VehicleWheel3D = null
@export var speed_modifier:float=1.0

# Zonas de evasion circular
@export var evasion_activada: bool = true
@export var radio_interno: float = 0.1
@export var radio_intermedio: float = 0.3
@export var radio_externo: float = 0.5
@export var altura_zona: float = 5.0
@export var mostrar_gizmos: bool = true
@export_group("Colores Gizmos")
@export var color_interno: Color = Color(1.0, 0.2, 0.2, 0.3)
@export var color_intermedio: Color = Color(1.0, 0.7, 0.2, 0.3)
@export var color_externo: Color = Color(0.2, 0.7, 1.0, 0.3)

var zona_interna: Area3D
var zona_intermedia: Area3D
var zona_externa: Area3D

var cuerpos_interna: Array = []
var cuerpos_intermedia: Array = []
var cuerpos_externa: Array = []

var direccion_evasion: Vector3 = Vector3.ZERO
var freno_evasion: float = 0.0
var evasion_retrocediendo: bool = false
var evasion_fase: int = 0
var evasion_timer_freno: float = 0.0
var evasion_nivel_zona: int = 0

enum FaseEvasion {
	NINGUNA = 0,
	FRENANDO = 1,
	RETROCEDIENDO = 2
}

var panel_evasion: Control
var panel_visible: bool = false

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
	_crear_zonas_evasion()
	_crear_panel_evasion()

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
	_procesar_evasion(delta)
	
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

	if evasion_retrocediendo:
		engine_force = -power * 0.6
		brake = 0.0
		r_trasera_iz.brake = 0
		r_trasera_der.brake = 0
		steering = -direccion_evasion.x * 0.5
		return

	if auto_controlled:
		return

	var evasion_activa = direccion_evasion.length() > 0.01 or freno_evasion > 0.0
	
	var throttle = Input.get_axis("backward", "forward")
	var raw_steer = Input.get_axis("turn_right", "turn_left")
	var is_braking = Input.is_action_pressed("brake")
	var is_handbraking = Input.is_action_pressed("handbrake")
	
	var in_mud = mud_zones.size() > 0
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
	
	if evasion_activa:
		steering += direccion_evasion.x * delta * steer_speed

	# Braking
	if freno_evasion > 0.0:
		engine_force = 0
		brake = max(brake_force * brake_multiplier, freno_evasion)
		r_trasera_iz.brake = 0
		r_trasera_der.brake = 0
	elif is_braking:
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
		if evasion_activa and freno_evasion == 0.0:
			engine_force = throttle * power * speed_modifier * engine_multiplier * 0.5
		else:
			engine_force = throttle * power * speed_modifier * engine_multiplier

	# Coasting friction
	if throttle == 0 and not is_braking and not is_handbraking and freno_evasion == 0.0:
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
	
	if event.is_action_pressed("ui_home"):
		if panel_evasion:
			panel_visible = not panel_visible
			panel_evasion.visible = panel_visible

func add_mud_zone(zone: Area3D) -> void:
	if zone not in mud_zones:
		mud_zones.append(zone)
		print("Zonas de barro activas: ", mud_zones.size())

func remove_mud_zone(zone: Area3D) -> void:
	mud_zones.erase(zone)
	print("Zonas de barro activas: ", mud_zones.size())

func _crear_zonas_evasion() -> void:
	zona_externa = _crear_zona(radio_externo, color_externo, "_on_zona_externa_entered", "_on_zona_externa_exited")
	zona_intermedia = _crear_zona(radio_intermedio, color_intermedio, "_on_zona_intermedia_entered", "_on_zona_intermedia_exited")
	zona_interna = _crear_zona(radio_interno, color_interno, "_on_zona_interna_entered", "_on_zona_interna_exited")

func _crear_zona(radio: float, color: Color, metodo_enter: String, metodo_exit: String) -> Area3D:
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.name = "ZonaEvasion_r" + str(radio)
	add_child(area)
	
	var col_shape = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var cylinder = CylinderShape3D.new()
	cylinder.radius = radio
	cylinder.height = altura_zona
	col_shape.shape = cylinder
	col_shape.position = Vector3(0, altura_zona / 2.0, 0)
	col_shape.debug_color = color
	area.add_child(col_shape)
	
	area.body_entered.connect(Callable(self, metodo_enter))
	area.body_exited.connect(Callable(self, metodo_exit))
	
	if ConfigDebug.evasion_mostrar_gizmos:
		var ring = MeshInstance3D.new()
		ring.name = "AnilloVisual"
		var ring_mesh = CylinderMesh.new()
		ring_mesh.top_radius = radio
		ring_mesh.bottom_radius = radio
		ring_mesh.height = 0.1
		ring_mesh.radial_segments = 64
		ring.mesh = ring_mesh
		ring.position = Vector3(0, 0.05, 0)
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring.material_override = mat
		area.add_child(ring)
	
	return area

func _crear_panel_evasion() -> void:
	var canvas = get_node_or_null("CanvasLayer")
	if not canvas:
		return
	
	panel_evasion = Control.new()
	panel_evasion.name = "PanelEvasion"
	panel_evasion.visible = false
	panel_evasion.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel_evasion.position = Vector2(10, 200)
	canvas.add_child(panel_evasion)
	
	var panel_bg = Panel.new()
	panel_bg.name = "Fondo"
	panel_bg.custom_minimum_size = Vector2(280, 220)
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_evasion.add_child(panel_bg)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	panel_bg.add_child(vbox)
	
	var title_bg = Panel.new()
	title_bg.name = "TitleBg"
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color(0.15, 0.15, 0.15, 1)
	title_bg.add_theme_stylebox_override("panel", title_style)
	vbox.add_child(title_bg)
	
	var title = Label.new()
	title.name = "Titulo"
	title.text = "  Zonas de Evasion (Home)"
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title_bg.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	
	_agregar_slider(content, "Interna (Rojo)", radio_interno, color_interno, 0.0, 1.0,
		func(v): radio_interno = v; _actualizar_zona(zona_interna, v))
	_agregar_slider(content, "Intermedia (Naranja)", radio_intermedio, color_intermedio, 0.0, 2.0,
		func(v): radio_intermedio = v; _actualizar_zona(zona_intermedia, v))
	_agregar_slider(content, "Externa (Azul)", radio_externo, color_externo, 0.0, 4.0,
		func(v): radio_externo = v; _actualizar_zona(zona_externa, v))
	
	var activar_check = CheckBox.new()
	activar_check.name = "ActivarEvasion"
	activar_check.text = "Evasion activada"
	activar_check.button_pressed = ConfigDebug.evasion_zonas_activada
	activar_check.toggled.connect(func(v): ConfigDebug.evasion_zonas_activada = v)
	content.add_child(activar_check)

func _agregar_slider(parent: Control, label_text: String, valor: float, color: Color, min_v: float, max_v: float, callback: Callable) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_color_override("font_color", color)
	row.add_child(lbl)
	
	var val_lbl = Label.new()
	val_lbl.name = "ValorLabel"
	val_lbl.text = "%.1f" % valor
	val_lbl.custom_minimum_size = Vector2(35, 0)
	val_lbl.add_theme_color_override("font_color", color)
	row.add_child(val_lbl)
	
	var slider = HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.1
	slider.value = valor
	slider.custom_minimum_size = Vector2(95, 0)
	slider.value_changed.connect(func(v):
		val_lbl.text = "%.1f" % v
		callback.call(v)
	)
	row.add_child(slider)

func _actualizar_zona(area: Area3D, radio: float) -> void:
	if not area:
		return
	var col = area.get_node_or_null("CollisionShape3D")
	if col and col.shape is CylinderShape3D:
		(col.shape as CylinderShape3D).radius = radio
	for child in area.get_children():
		if child is MeshInstance3D and child.name == "AnilloVisual":
			var m = child.mesh
			if m is CylinderMesh:
				m.top_radius = radio
				m.bottom_radius = radio

func _on_zona_externa_entered(body: Node) -> void:
	if body not in cuerpos_externa:
		cuerpos_externa.append(body)

func _on_zona_externa_exited(body: Node) -> void:
	cuerpos_externa.erase(body)

func _on_zona_intermedia_entered(body: Node) -> void:
	if body not in cuerpos_intermedia:
		cuerpos_intermedia.append(body)

func _on_zona_intermedia_exited(body: Node) -> void:
	cuerpos_intermedia.erase(body)

func _on_zona_interna_entered(body: Node) -> void:
	if body not in cuerpos_interna:
		cuerpos_interna.append(body)

func _on_zona_interna_exited(body: Node) -> void:
	cuerpos_interna.erase(body)

func _procesar_evasion(delta: float) -> void:
	if not ConfigDebug.evasion_zonas_activada:
		direccion_evasion = Vector3.ZERO
		freno_evasion = 0.0
		evasion_nivel_zona = 0
		evasion_retrocediendo = false
		evasion_fase = FaseEvasion.NINGUNA
		evasion_timer_freno = 0.0
		return
	
	var vector_evasion = Vector3.ZERO
	var nivel_zona = 0
	
	for body in cuerpos_interna:
		if is_instance_valid(body) and body is Node3D:
			var dir = (body as Node3D).global_transform.origin - global_transform.origin
			dir.y = 0
			if dir.length() > 0.01:
				vector_evasion += dir.normalized()
			nivel_zona = max(nivel_zona, 3)
	
	for body in cuerpos_intermedia:
		if is_instance_valid(body) and body is Node3D:
			var dir = (body as Node3D).global_transform.origin - global_transform.origin
			dir.y = 0
			if dir.length() > 0.01:
				vector_evasion += dir.normalized() * 0.6
			nivel_zona = max(nivel_zona, 2)
	
	for body in cuerpos_externa:
		if is_instance_valid(body) and body is Node3D:
			var dir = (body as Node3D).global_transform.origin - global_transform.origin
			dir.y = 0
			if dir.length() > 0.01:
				vector_evasion += dir.normalized() * 0.3
			nivel_zona = max(nivel_zona, 1)
	
	evasion_nivel_zona = nivel_zona
	
	if vector_evasion.length() > 0.01:
		var forward = -global_transform.basis.z
		var right = global_transform.basis.x
		
		var dir_escape = -vector_evasion.normalized()
		var lateral = dir_escape.dot(right)
		var frontal = dir_escape.dot(forward)
		
		match nivel_zona:
			3:
				direccion_evasion = Vector3(lateral * 0.8, 0, 0)
				freno_evasion = brake_force * 1.5
			2:
				direccion_evasion = Vector3(lateral * 0.3, 0, 0)
				freno_evasion = 0.0
			1:
				direccion_evasion = Vector3(lateral * 0.1, 0, 0)
				freno_evasion = 0.0
		
		if frontal < 0:
			freno_evasion = 0.0
		
		if nivel_zona >= 3 and ConfigDebug.evasion_reversa_activada:
			var speed = linear_velocity.length()
			match evasion_fase:
				FaseEvasion.NINGUNA:
					evasion_fase = FaseEvasion.FRENANDO
					evasion_timer_freno = 0.0
					direccion_evasion = Vector3.ZERO
				FaseEvasion.FRENANDO:
					direccion_evasion = Vector3.ZERO
					freno_evasion = brake_force * 2.0
					if speed < 0.3:
						evasion_timer_freno += delta
						if evasion_timer_freno > 0.5:
							evasion_fase = FaseEvasion.RETROCEDIENDO
							evasion_retrocediendo = true
					else:
						evasion_timer_freno = 0.0
				FaseEvasion.RETROCEDIENDO:
					evasion_retrocediendo = true
		else:
			evasion_fase = FaseEvasion.NINGUNA
			evasion_retrocediendo = false
			evasion_timer_freno = 0.0
	else:
		direccion_evasion = Vector3.ZERO
		freno_evasion = 0.0
		evasion_retrocediendo = false
		evasion_fase = FaseEvasion.NINGUNA
		evasion_timer_freno = 0.0
