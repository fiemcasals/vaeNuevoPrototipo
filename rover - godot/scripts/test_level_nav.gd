extends Node3D

const MENU_PATH = "res://scenes/menu_principal.tscn"

@onready var btn_volver = $UIOverlay/BtnVolverMenu

func _ready() -> void:
	if btn_volver:
		btn_volver.pressed.connect(_volver_al_menu)
	
	aplicar_peso_rover()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_volver_al_menu()

func _volver_al_menu() -> void:
	get_tree().change_scene_to_file(MENU_PATH)

func aplicar_peso_rover() -> void:
	var rover = get_node_or_null("VehicleBody3D")
	if rover and RoverConfig:
		RoverConfig.aplicar_configuracion_a_rover(rover)
