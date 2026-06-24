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

var camara_actual = 0
var nivel_cargado = false
var rotacion_original: Transform3D

func _ready() -> void:
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
	
	SignalBus.change_cam.connect(_on_change_cam)
	
	btn_navegar.disabled = true
	btn_ir_spawn.disabled = true

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if target_selector and target_selector.visible:
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
		nivel_cargado = true
		btn_navegar.disabled = false
		btn_ir_spawn.disabled = false

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

func _on_cambiar_camara_presionado() -> void:
	_cambiar_camara()

func _cambiar_camara() -> void:
	camara_actual = (camara_actual + 1) % 2
	SignalBus.emit_signal("change_cam", camara_actual)

func _on_change_cam(cam: int) -> void:
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
