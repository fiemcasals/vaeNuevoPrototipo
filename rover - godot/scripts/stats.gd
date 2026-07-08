extends Control

const MENU_PATH = "res://scenes/menu_principal.tscn"

@onready var spin_peso: SpinBox = $ScrollContainer/VBoxContainer/PesoContainer/SpinBox
@onready var spin_velocidad: SpinBox = $ScrollContainer/VBoxContainer/VelocidadContainer/SpinBox
@onready var spin_aceleracion: SpinBox = $ScrollContainer/VBoxContainer/AceleracionContainer/SpinBox
@onready var spin_torque: SpinBox = $ScrollContainer/VBoxContainer/TorqueContainer/SpinBox
@onready var spin_ancho: SpinBox = $ScrollContainer/VBoxContainer/AnchoContainer/SpinBox
@onready var spin_largo: SpinBox = $ScrollContainer/VBoxContainer/LargoContainer/SpinBox
@onready var spin_ancho_ruedas: SpinBox = $ScrollContainer/VBoxContainer/AnchoRuedasContainer/SpinBox
@onready var spin_distancia_ejes: SpinBox = $ScrollContainer/VBoxContainer/DistanciaEjesContainer/SpinBox
@onready var spin_distancia_ruedas: SpinBox = $ScrollContainer/VBoxContainer/DistanciaRuedasContainer/SpinBox
@onready var spin_margen: SpinBox = $ScrollContainer/VBoxContainer/MargenContainer/SpinBox
@onready var btn_guardar: Button = $ScrollContainer/VBoxContainer/BtnGuardar
@onready var btn_volver: Button = $ScrollContainer/VBoxContainer/BtnVolver

func _ready() -> void:
	_cargar_valores()
	
	btn_guardar.pressed.connect(_on_guardar_pressed)
	btn_volver.pressed.connect(_volver_al_menu)

func _cargar_valores() -> void:
	spin_peso.value = RoverConfig.peso_rover
	spin_velocidad.value = RoverConfig.velocidad_maxima
	spin_aceleracion.value = RoverConfig.aceleracion
	spin_torque.value = RoverConfig.torque
	spin_ancho.value = RoverConfig.ancho_vehiculo
	spin_largo.value = RoverConfig.largo_vehiculo
	spin_ancho_ruedas.value = RoverConfig.ancho_ruedas
	spin_distancia_ejes.value = RoverConfig.distancia_entre_ejes
	spin_distancia_ruedas.value = RoverConfig.distancia_entre_ruedas
	spin_margen.value = RoverConfig.margen_seguridad

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_volver_al_menu()

func _on_guardar_pressed() -> void:
	RoverConfig.peso_rover = spin_peso.value
	RoverConfig.velocidad_maxima = spin_velocidad.value
	RoverConfig.aceleracion = spin_aceleracion.value
	RoverConfig.torque = spin_torque.value
	RoverConfig.ancho_vehiculo = spin_ancho.value
	RoverConfig.largo_vehiculo = spin_largo.value
	RoverConfig.ancho_ruedas = spin_ancho_ruedas.value
	RoverConfig.distancia_entre_ejes = spin_distancia_ejes.value
	RoverConfig.distancia_entre_ruedas = spin_distancia_ruedas.value
	RoverConfig.margen_seguridad = spin_margen.value
	
	RoverConfig.guardar_configuracion()
	print("Configuración guardada")

func _volver_al_menu() -> void:
	get_tree().change_scene_to_file(MENU_PATH)
