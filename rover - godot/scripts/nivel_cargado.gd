extends Node3D

const MENU_PATH = "res://scenes/menu_principal.tscn"

@onready var btn_volver = $UIOverlay/BtnVolverMenu
@onready var btn_cargar = $UIOverlay/BtnCargarNivel
@onready var btn_cambiar_camara = $UIOverlay/BtnCambiarCamara
@onready var btn_navegar = $UIOverlay/BtnNavegar
@onready var btn_ir_spawn = $UIOverlay/BtnIrSpawn
@onready var btn_reaparecer = $UIOverlay/BtnReaparecer
@onready var btn_voltear = $UIOverlay/BtnVoltear
@onready var file_dialog = $UIOverlay/FileDialog
@onready var target_selector = $UIOverlay/TargetSelector
@onready var camara_superior = $Camera3D
@onready var camara_seguimiento = $CamaraSeguimiento
@onready var creador = $CreadorDeNivel
@onready var navigation = $NavigationSystem
@onready var path_visualizer = $PathVisualizer
@onready var auto_controller = $RoverAutoController
@onready var camera_transparency = $CameraTransparency
@onready var btn_test_aleatorio = $UIOverlay/BtnTestAleatorio
@onready var spin_box_test = $UIOverlay/SpinBoxTest
@onready var btn_conectar_sensor = $UIOverlay/BtnConectarSensor
@onready var lbl_estado_autopilot = $UIOverlay/LblEstadoAutopilot

var camara_actual = 0
var nivel_cargado = false
var rotacion_original: Transform3D

# Nuevas variables para selector de modalidad e interfaz
var selection_hub: Panel
var turret_hud: Control
var turret_angle_label: Label

var test_mode_active: bool = false
var test_destinations_remaining: int = 0
var last_target_cell: Vector2i = Vector2i(-1, -1)
var _navigating_to_spawn: bool = false

func _ready() -> void:
	randomize()
	btn_volver.pressed.connect(_volver_al_menu)
	btn_cargar.pressed.connect(_on_cargar_presionado)
	btn_cambiar_camara.pressed.connect(_on_cambiar_camara_presionado)
	btn_navegar.pressed.connect(_on_navegar_presionado)
	btn_ir_spawn.pressed.connect(_on_ir_spawn_presionado)
	btn_reaparecer.pressed.connect(_on_reaparecer_presionado)
	btn_voltear.pressed.connect(_on_voltear_presionado)
	file_dialog.file_selected.connect(_on_archivo_seleccionado)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Seleccionar archivo de nivel"
	
	if target_selector:
		target_selector.target_selected.connect(_on_target_selected)
		target_selector.cancelled.connect(_on_target_selector_cancelled)
	
	if creador:
		creador.connect("rover_instanciado", Callable(self, "_on_rover_instanciado"))
	
	if navigation:
		navigation.path_calculated.connect(_on_path_calculated)
		navigation.target_reached.connect(_on_target_reached)
	
	if auto_controller:
		auto_controller.navigation = navigation
		auto_controller.remote_path_received.connect(_on_remote_path_received)
		auto_controller.remote_path_failed.connect(_on_remote_path_failed)
	
	SignalBus.change_cam.connect(_on_change_cam)
	
	btn_navegar.disabled = true
	btn_ir_spawn.disabled = true
	btn_test_aleatorio.disabled = true
	
	btn_test_aleatorio.pressed.connect(_on_test_aleatorio_presionado)
	
	btn_conectar_sensor.pressed.connect(_on_conectar_sensor_presionado)
	Sensor.conexion_cambiada.connect(_on_sensor_conexion_cambiada)
	
	auto_controller.navigation_stopped.connect(func(interrupted: bool):
		if interrupted and test_mode_active:
			test_mode_active = false
			test_destinations_remaining = 0
			btn_test_aleatorio.text = "Test Aleatorio"
			print("[Test] Prueba aleatoria cancelada por parada del piloto automático.")
	)
	
	setup_modality_uis()
	
	# Carga automática de nivel prueba1.json para agilizar las pruebas
	_cargar_nivel_automatico.call_deferred()

func _cargar_nivel_automatico() -> void:
	var default_path = "res://prueba1.json"
	if FileAccess.file_exists(default_path):
		print("[Autoload] Cargando nivel automático: ", default_path)
		_on_archivo_seleccionado(default_path)
	else:
		default_path = "prueba1.json"
		if FileAccess.file_exists(default_path):
			print("[Autoload] Cargando nivel automático: ", default_path)
			_on_archivo_seleccionado(default_path)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if target_selector and target_selector.visible:
			return
		if RoverConfig:
			if RoverConfig.op_mode == "turret":
				_on_turret_back_pressed()
				return
			elif RoverConfig.op_mode == "hub":
				_volver_al_menu()
				return
		if auto_controller.is_active:
			auto_controller.stop()
		else:
			_volver_al_menu()
	
	if event.is_action_pressed("switch_cam"):
		_cambiar_camara()

func _volver_al_menu() -> void:
	get_tree().change_scene_to_file(MENU_PATH)

func _on_cargar_presionado() -> void:
	file_dialog.popup_centered(Vector2(800, 600))

func _on_archivo_seleccionado(path: String) -> void:
	SignalBus.emit_signal("nivel_seleccionado", path)

func _on_rover_instanciado(_position: Vector3) -> void:
	var rover = creador.current_rover
	if camara_superior:
		camara_superior.target = rover
	if camara_seguimiento:
		camara_seguimiento.target = rover
	
	if auto_controller:
		auto_controller.rover = rover
	
	if camera_transparency:
		camera_transparency.rover = rover
		# Usar la cámara activa actual
		if camara_actual == 0:
			camera_transparency.camera = camara_superior
		else:
			camera_transparency.camera = camara_seguimiento
	
	if RoverConfig:
		RoverConfig.aplicar_configuracion_a_rover(rover)
	
	# Guardar la rotación original
	rotacion_original = rover.global_transform
	
	if navigation and creador:
		var level_data = {
			"tiles": _get_level_tile_data()
		}
		navigation.initialize_level(level_data, creador.tile_spacing)
		
		if auto_controller and auto_controller.use_remote_logic:
			auto_controller.init_remote_level(level_data.tiles, creador.tile_spacing)
			
		nivel_cargado = true
		btn_navegar.disabled = false
		btn_ir_spawn.disabled = false
		btn_test_aleatorio.disabled = false
		
		if RoverConfig:
			RoverConfig.op_mode = "hub"
			update_mode_visibility()

func _get_level_tile_data() -> Array:
	var tile_data = []
	for z in range(creador.grid_data.size()):
		var row = []
		for x in range(creador.grid_data[z].size()):
			row.append(creador.grid_data[z][x])
		tile_data.append(row)
	return tile_data

func _on_navegar_presionado() -> void:
	if not nivel_cargado or not creador or not creador.current_rover:
		return
	
	if auto_controller.is_active:
		auto_controller.stop()
		path_visualizer.clear()
		btn_navegar.text = "Seleccionar Destino"
		btn_ir_spawn.text = "Ir al Spawn"
		return
	
	var rover = creador.current_rover
	var target_types = ["punto_interes", "objetivo"]
	var targets = navigation.get_all_targets(rover.global_position, target_types)
	
	if targets.is_empty():
		print("No hay puntos de interés disponibles")
		return
	
	target_selector.show_targets(targets)

func _on_target_selected(target_data: Dictionary) -> void:
	if not creador or not creador.current_rover:
		return
	
	var rover = creador.current_rover
	var target_cell = target_data["cell"]
	var target_pos = navigation.grid_to_world(target_cell)
	print("Navegando a: ", target_data["name"])
	_navigating_to_spawn = false
	
	if auto_controller and auto_controller.use_remote_logic:
		auto_controller.request_remote_path(rover.global_position, target_pos, rover.global_rotation.y)
	else:
		var path = navigation.calculate_path(rover.global_position, target_pos)
		if path.size() > 0:
			navigation.start_navigation()
			var visual_points = navigation.get_path_visual_points()
			path_visualizer.draw_path(visual_points)
			auto_controller.start()
			btn_navegar.text = "Detener"

func _on_target_selector_cancelled() -> void:
	print("Selección de destino cancelada")

func _on_ir_spawn_presionado() -> void:
	if not nivel_cargado or not creador or not creador.current_rover:
		return
	
	if auto_controller.is_active:
		auto_controller.stop()
		path_visualizer.clear()
		btn_ir_spawn.text = "Ir al Spawn"
		btn_navegar.text = "Seleccionar Destino"
		return
	
	var rover = creador.current_rover
	var spawn_pos = navigation.grid_to_world(creador.spawn_cell)
	_navigating_to_spawn = true
	
	if auto_controller and auto_controller.use_remote_logic:
		auto_controller.request_remote_path(rover.global_position, spawn_pos, rover.global_rotation.y)
	else:
		var path = navigation.calculate_path(rover.global_position, spawn_pos)
		if path.size() > 0:
			navigation.start_navigation()
			var visual_points = navigation.get_path_visual_points()
			path_visualizer.draw_path(visual_points)
			auto_controller.start()
			btn_ir_spawn.text = "Detener"

func _on_reaparecer_presionado() -> void:
	if not nivel_cargado or not creador or not creador.current_rover:
		print("Error: No se ha cargado un nivel o no hay un rover actual")
		return
	
	var rover = creador.current_rover
	
	if auto_controller.is_active:
		auto_controller.stop()
		path_visualizer.clear()
		btn_navegar.text = "Seleccionar Destino"
		btn_ir_spawn.text = "Ir al Spawn"
	
	var spawn_pos = navigation.grid_to_world(creador.spawn_cell)
	print("Reapareciendo rover en spawn: ", spawn_pos)
	print("Posición actual del rover antes de reaparecer: ", rover.global_transform.origin)
	# Detener completamente el rover
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	rover.engine_force = 0.0
	rover.brake = 20.0
	
	# Resetear las ruedas
	for wheel in rover.get_children():
		if wheel is VehicleWheel3D:
			wheel.brake = 20.0
	
	# Teletransportar al spawn con rotación original
	rover.freeze = true
	await get_tree().physics_frame
	var new_transform = rotacion_original
	new_transform.origin = spawn_pos + Vector3(0, 1.0, 0)
	rover.global_transform = new_transform
	await get_tree().physics_frame
	rover.freeze = false
	
	print("Rover reaparecido en spawn con rotación original")

func _on_voltear_presionado() -> void:
	if not nivel_cargado or not creador or not creador.current_rover:
		return
	
	var rover = creador.current_rover
	
	# Detener el rover primero
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	rover.engine_force = 0.0
	rover.brake = 20.0
	
	# Teletransportar hacia arriba con rotación original
	rover.freeze = true
	await get_tree().physics_frame
	var new_transform = rotacion_original
	new_transform.origin = rover.global_transform.origin + Vector3(0, 1.0, 0)
	rover.global_transform = new_transform
	await get_tree().physics_frame
	rover.freeze = false
	
	# Resetear las ruedas
	for wheel in rover.get_children():
		if wheel is VehicleWheel3D:
			wheel.brake = 20.0
	
	print("Rover teletransportado hacia arriba")

func _on_path_calculated(path: Array) -> void:
	print("Path calculado con ", path.size(), " nodos")

func _on_target_reached() -> void:
	print("¡Objetivo alcanzado!")
	path_visualizer.clear()
	btn_navegar.text = "Seleccionar Destino"
	btn_ir_spawn.text = "Ir al Spawn"
	
	if test_mode_active:
		test_destinations_remaining -= 1
		if test_destinations_remaining > 0:
			btn_test_aleatorio.text = "Detener Test (%d)" % test_destinations_remaining
			print("[Test] Esperando 1.5s antes de reanudar...")
			await get_tree().create_timer(1.5).timeout
			if test_mode_active:
				_ir_a_siguiente_destino_test()
		else:
			_stop_test_mode()

func _on_cambiar_camara_presionado() -> void:
	_cambiar_camara()

func _cambiar_camara() -> void:
	camara_actual = (camara_actual + 1) % 2
	SignalBus.emit_signal("change_cam", camara_actual)

func _on_change_cam(cam: int) -> void:
	if RoverConfig and RoverConfig.op_mode == "turret":
		return
	if cam == 0:
		camara_superior.current = true
		camara_seguimiento.current = false
		if camera_transparency:
			camera_transparency.camera = camara_superior
	else:
		camara_superior.current = false
		camara_seguimiento.current = true
		if camera_transparency:
			camera_transparency.camera = camara_seguimiento

func _on_test_aleatorio_presionado() -> void:
	if not nivel_cargado or not creador or not creador.current_rover:
		return
		
	if test_mode_active:
		_stop_test_mode()
		return
		
	var rover = creador.current_rover
	var target_types = ["punto_interes", "objetivo"]
	var targets = navigation.get_all_targets(rover.global_position, target_types)
	
	if targets.is_empty():
		print("[Test] No hay destinos disponibles para iniciar el test.")
		return
		
	var num_destinos = int(spin_box_test.value)
	test_destinations_remaining = num_destinos
	test_mode_active = true
	last_target_cell = Vector2i(-1, -1)
	btn_test_aleatorio.text = "Detener Test (%d)" % test_destinations_remaining
	
	print("[Test] Iniciando prueba aleatoria de %d destinos..." % num_destinos)
	_ir_a_siguiente_destino_test()

func _ir_a_siguiente_destino_test() -> void:
	if not test_mode_active or test_destinations_remaining <= 0:
		_stop_test_mode()
		return
		
	var rover = creador.current_rover
	var current_cell = navigation.world_to_grid(rover.global_position)
	var target_types = ["punto_interes", "objetivo"]
	var targets = navigation.get_all_targets(rover.global_position, target_types)
	
	var valid_targets = []
	for tgt in targets:
		var cell = tgt["cell"] as Vector2i
		if cell != current_cell and cell != last_target_cell:
			valid_targets.append(tgt)
			
	if valid_targets.is_empty():
		for tgt in targets:
			var cell = tgt["cell"] as Vector2i
			if cell != current_cell:
				valid_targets.append(tgt)
				
	if valid_targets.is_empty():
		print("[Test] No se encontraron destinos válidos para el test.")
		_stop_test_mode()
		return
		
	var selected_target = valid_targets[randi() % valid_targets.size()]
	last_target_cell = selected_target["cell"]
	
	var target_pos = navigation.grid_to_world(last_target_cell)
	print("[Test] Destinos restantes: %d. Próximo destino aleatorio: %s" % [test_destinations_remaining, selected_target["name"]])
	_navigating_to_spawn = false
	
	if auto_controller and auto_controller.use_remote_logic:
		auto_controller.request_remote_path(rover.global_position, target_pos, rover.global_rotation.y)
	else:
		var path = navigation.calculate_path(rover.global_position, target_pos)
		if path.size() > 0:
			navigation.start_navigation()
			var visual_points = navigation.get_path_visual_points()
			path_visualizer.draw_path(visual_points)
			auto_controller.start()
			btn_navegar.text = "Detener"
		else:
			print("[Test] Error: No se pudo trazar una ruta hacia %s. Reintentando..." % selected_target["name"])
			await get_tree().physics_frame
			_ir_a_siguiente_destino_test()

func _on_remote_path_received(path: Array) -> void:
	navigation.start_navigation()
	path_visualizer.draw_path(path)
	auto_controller.start()
	if _navigating_to_spawn:
		btn_ir_spawn.text = "Detener"
	else:
		btn_navegar.text = "Detener"

func _on_remote_path_failed() -> void:
	print("[Autopilot] Error: No se pudo obtener la ruta del cerebro pps-vae.")
	if test_mode_active:
		print("[Test] Reintentando otro destino...")
		await get_tree().physics_frame
		_ir_a_siguiente_destino_test()

func _stop_test_mode() -> void:
	test_mode_active = false
	test_destinations_remaining = 0
	if btn_test_aleatorio:
		btn_test_aleatorio.text = "Test Aleatorio"
	if auto_controller.is_active:
		auto_controller.stop()
	if path_visualizer:
		path_visualizer.clear()
	if btn_navegar:
		btn_navegar.text = "Seleccionar Destino"
	print("[Test] Prueba aleatoria finalizada.")

func _process(_delta: float) -> void:
	if RoverConfig and RoverConfig.op_mode == "turret" and turret_angle_label:
		var rover = creador.current_rover
		if rover:
			var yaw = rover.get("turret_yaw") if rover.get("turret_yaw") != null else 0.0
			var pitch = rover.get("turret_pitch") if rover.get("turret_pitch") != null else 0.0
			
			var yaw_deg = round(rad_to_deg(yaw))
			# Normalizar grados de Azimut a 0-360
			var yaw_deg_int = int(yaw_deg) % 360
			if yaw_deg_int < 0:
				yaw_deg_int += 360
				
			var pitch_deg = round(rad_to_deg(pitch))
			
			turret_angle_label.text = "AZIMUT: %d°\nELEVACIÓN: %d°" % [yaw_deg_int, pitch_deg]

	if auto_controller and lbl_estado_autopilot:
		if auto_controller.is_connected_to_brain():
			lbl_estado_autopilot.text = "Autopilot: Conectado"
			lbl_estado_autopilot.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
		else:
			lbl_estado_autopilot.text = "Autopilot: Desconectado"
			lbl_estado_autopilot.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

func _on_conectar_sensor_presionado() -> void:
	if Sensor.esta_conectado():
		Sensor.desconectar()
		btn_conectar_sensor.text = "Conectar Sensor"
	else:
		Sensor.conectar()
		btn_conectar_sensor.text = "Desconectar Sensor"


func _on_sensor_conexion_cambiada(conectado: bool) -> void:
	btn_conectar_sensor.text = "Desconectar Sensor" if conectado else "Conectar Sensor"


func setup_modality_uis() -> void:
	var overlay = $UIOverlay
	if not overlay:
		return
		
	# --- SELECTION HUB PANEL ---
	selection_hub = Panel.new()
	selection_hub.name = "SelectionHub"
	selection_hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.97) # Fondo oscuro moderno
	selection_hub.add_theme_stylebox_override("panel", sb)
	overlay.add_child(selection_hub)
	
	# VBoxContainer principal para centrar de forma responsiva
	var v_main = VBoxContainer.new()
	v_main.alignment = BoxContainer.ALIGNMENT_CENTER
	v_main.add_theme_constant_override("separation", 40)
	v_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v_main.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v_main.grow_vertical = Control.GROW_DIRECTION_BOTH
	selection_hub.add_child(v_main)
	
	# Cabecera
	var v_header = VBoxContainer.new()
	v_header.alignment = BoxContainer.ALIGNMENT_CENTER
	v_header.add_theme_constant_override("separation", 10)
	v_main.add_child(v_header)
	
	var title = Label.new()
	title.text = "SCCpVA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.91, 0.27, 0.38)) # #e94560
	v_header.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Seleccione estación de operación"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	v_header.add_child(subtitle)
	
	# HBoxContainer para las tarjetas de selección
	var hbox_cards = HBoxContainer.new()
	hbox_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_cards.add_theme_constant_override("separation", 50)
	v_main.add_child(hbox_cards)
	
	# Estilo común para tarjetas
	var sb_card = StyleBoxFlat.new()
	sb_card.bg_color = Color(0.12, 0.12, 0.18, 0.9)
	sb_card.border_color = Color(0.91, 0.27, 0.38, 0.3)
	sb_card.border_width_left = 2
	sb_card.border_width_right = 2
	sb_card.border_width_top = 2
	sb_card.border_width_bottom = 2
	sb_card.corner_radius_top_left = 16
	sb_card.corner_radius_top_right = 16
	sb_card.corner_radius_bottom_left = 16
	sb_card.corner_radius_bottom_right = 16
	sb_card.shadow_color = Color(0, 0, 0, 0.4)
	sb_card.shadow_size = 12
	
	# Tarjeta 1: Conducción
	var card_veh = PanelContainer.new()
	card_veh.custom_minimum_size = Vector2(280, 320)
	card_veh.add_theme_stylebox_override("panel", sb_card)
	hbox_cards.add_child(card_veh)
	
	var v_veh = VBoxContainer.new()
	v_veh.alignment = BoxContainer.ALIGNMENT_CENTER
	v_veh.add_theme_constant_override("separation", 20)
	card_veh.add_child(v_veh)
	
	var icon_veh = Label.new()
	icon_veh.text = "🚗"
	icon_veh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_veh.add_theme_font_size_override("font_size", 72)
	v_veh.add_child(icon_veh)
	
	var lbl_veh = Label.new()
	lbl_veh.text = "Conducción"
	lbl_veh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_veh.add_theme_font_size_override("font_size", 24)
	lbl_veh.add_theme_color_override("font_color", Color(1, 1, 1))
	v_veh.add_child(lbl_veh)
	
	var desc_veh = Label.new()
	desc_veh.text = "Control manual del vehículo\ny piloto automático autónomo"
	desc_veh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_veh.add_theme_font_size_override("font_size", 14)
	desc_veh.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	v_veh.add_child(desc_veh)
	
	var btn_veh = Button.new()
	btn_veh.text = "Operar Vehículo"
	btn_veh.custom_minimum_size = Vector2(180, 45)
	btn_veh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb_btn = StyleBoxFlat.new()
	sb_btn.bg_color = Color(0.91, 0.27, 0.38) # e94560
	sb_btn.corner_radius_top_left = 10
	sb_btn.corner_radius_top_right = 10
	sb_btn.corner_radius_bottom_left = 10
	sb_btn.corner_radius_bottom_right = 10
	btn_veh.add_theme_stylebox_override("normal", sb_btn)
	btn_veh.pressed.connect(_on_mode_vehicle_selected)
	v_veh.add_child(btn_veh)
	
	# Tarjeta 2: Armamento
	var card_tur = PanelContainer.new()
	card_tur.custom_minimum_size = Vector2(280, 320)
	card_tur.add_theme_stylebox_override("panel", sb_card)
	hbox_cards.add_child(card_tur)
	
	var v_tur = VBoxContainer.new()
	v_tur.alignment = BoxContainer.ALIGNMENT_CENTER
	v_tur.add_theme_constant_override("separation", 20)
	card_tur.add_child(v_tur)
	
	var icon_tur = Label.new()
	icon_tur.text = "🔫"
	icon_tur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_tur.add_theme_font_size_override("font_size", 72)
	v_tur.add_child(icon_tur)
	
	var lbl_tur = Label.new()
	lbl_tur.text = "Armamento"
	lbl_tur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_tur.add_theme_font_size_override("font_size", 24)
	lbl_tur.add_theme_color_override("font_color", Color(1, 1, 1))
	v_tur.add_child(lbl_tur)
	
	var desc_tur = Label.new()
	desc_tur.text = "Control de apuntado de la\ntorreta y arma de apoyo"
	desc_tur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_tur.add_theme_font_size_override("font_size", 14)
	desc_tur.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	v_tur.add_child(desc_tur)
	
	var btn_tur = Button.new()
	btn_tur.text = "Operar Arma"
	btn_tur.custom_minimum_size = Vector2(180, 45)
	btn_tur.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_tur.add_theme_stylebox_override("normal", sb_btn)
	btn_tur.pressed.connect(_on_mode_turret_selected)
	v_tur.add_child(btn_tur)
	
	# Footer
	var footer = Label.new()
	footer.text = "Sistema de Comando y Control para Vehículos Autónomos"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	v_main.add_child(footer)
	
	# --- TURRET HUD ---
	turret_hud = Control.new()
	turret_hud.name = "TurretHUD"
	turret_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	turret_hud.visible = false
	overlay.add_child(turret_hud)
	
	# Retícula de mira central
	var crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	crosshair.draw.connect(func():
		var c_color = Color(0.91, 0.27, 0.38, 0.8) # e94560
		crosshair.draw_line(Vector2(-20, 0), Vector2(-6, 0), c_color, 2.0)
		crosshair.draw_line(Vector2(6, 0), Vector2(20, 0), c_color, 2.0)
		crosshair.draw_line(Vector2(0, -20), Vector2(0, -6), c_color, 2.0)
		crosshair.draw_line(Vector2(0, 6), Vector2(0, 20), c_color, 2.0)
		crosshair.draw_arc(Vector2.ZERO, 8.0, 0, TAU, 24, Color(0.91, 0.27, 0.38, 0.4), 1.0)
	)
	turret_hud.add_child(crosshair)
	
	# Botón Volver
	var btn_back = Button.new()
	btn_back.text = "✏️ Volver"
	btn_back.custom_minimum_size = Vector2(140, 45)
	btn_back.position = Vector2(40, 40)
	var sb_back = StyleBoxFlat.new()
	sb_back.bg_color = Color(0, 0, 0, 0.6)
	sb_back.border_color = Color(0.91, 0.27, 0.38, 0.5)
	sb_back.border_width_left = 1
	sb_back.border_width_right = 1
	sb_back.border_width_top = 1
	sb_back.border_width_bottom = 1
	sb_back.corner_radius_top_left = 8
	sb_back.corner_radius_top_right = 8
	sb_back.corner_radius_bottom_left = 8
	sb_back.corner_radius_bottom_right = 8
	btn_back.add_theme_stylebox_override("normal", sb_back)
	btn_back.pressed.connect(_on_turret_back_pressed)
	turret_hud.add_child(btn_back)
	
	# Panel indicador de ángulos
	var angle_panel = PanelContainer.new()
	angle_panel.custom_minimum_size = Vector2(200, 110)
	angle_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	angle_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	angle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	angle_panel.position = Vector2(overlay.get_viewport().size.x - 240, overlay.get_viewport().size.y - 150)
	angle_panel.add_theme_stylebox_override("panel", sb_back)
	turret_hud.add_child(angle_panel)
	
	overlay.get_viewport().size_changed.connect(func():
		var size = overlay.get_viewport().size
		angle_panel.position = Vector2(size.x - 240, size.y - 150)
	)
	
	var v_ang = VBoxContainer.new()
	v_ang.alignment = BoxContainer.ALIGNMENT_CENTER
	v_ang.add_theme_constant_override("separation", 6)
	angle_panel.add_child(v_ang)
	
	var lbl_ang_title = Label.new()
	lbl_ang_title.text = "TORRETA"
	lbl_ang_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_ang_title.add_theme_font_size_override("font_size", 13)
	lbl_ang_title.add_theme_color_override("font_color", Color(0.91, 0.27, 0.38))
	v_ang.add_child(lbl_ang_title)
	
	turret_angle_label = Label.new()
	turret_angle_label.text = "AZIMUT: 0°\nELEVACIÓN: 0°"
	turret_angle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turret_angle_label.add_theme_font_size_override("font_size", 18)
	v_ang.add_child(turret_angle_label)

func set_standard_ui_visible(is_visible: bool) -> void:
	for child in $UIOverlay.get_children():
		if child != selection_hub and child != turret_hud:
			child.visible = is_visible

func update_mode_visibility() -> void:
	var rover = creador.current_rover
	if not rover:
		return
		
	var canvas_layer = rover.get_node_or_null("CanvasLayer")
	
	if RoverConfig.op_mode == "vehicle":
		if selection_hub: selection_hub.visible = false
		if turret_hud: turret_hud.visible = false
		set_standard_ui_visible(true)
		if canvas_layer: canvas_layer.visible = true
		_on_change_cam(camara_actual)
	elif RoverConfig.op_mode == "turret":
		if selection_hub: selection_hub.visible = false
		if turret_hud: turret_hud.visible = true
		set_standard_ui_visible(false)
		if canvas_layer: canvas_layer.visible = false
		
		# Activar cámara de torreta
		var turret_cam = rover.get_node_or_null("TurretBase/TurretBarrel/TurretCamera") as Camera3D
		if turret_cam:
			turret_cam.current = true
	else:
		# Selection Hub
		if selection_hub: selection_hub.visible = true
		if turret_hud: turret_hud.visible = false
		set_standard_ui_visible(false)
		if canvas_layer: canvas_layer.visible = false
		_on_change_cam(camara_actual)

func _on_mode_vehicle_selected() -> void:
	if RoverConfig:
		RoverConfig.op_mode = "vehicle"
		update_mode_visibility()

func _on_mode_turret_selected() -> void:
	if RoverConfig:
		RoverConfig.op_mode = "turret"
		update_mode_visibility()

func _on_turret_back_pressed() -> void:
	if RoverConfig:
		RoverConfig.op_mode = "hub"
		update_mode_visibility()
