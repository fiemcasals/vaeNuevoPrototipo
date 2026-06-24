extends Control

const TEST_LEVEL_PATH = "res://test_level.tscn"
const CREACION_NIVEL_PATH = "res://scenes/2D/ventana_creacion_nivel.tscn"
const NIVEL_CARGADO_PATH = "res://scenes/nivel_cargado.tscn"
const STATS_PATH = "res://scenes/stats.tscn"

func _ready() -> void:
	$VBoxContainer/BtnJugar.pressed.connect(_on_jugar_pressed)
	$VBoxContainer/BtnEditor.pressed.connect(_on_editor_pressed)
	$VBoxContainer/BtnCargar.pressed.connect(_on_cargar_pressed)
	$VBoxContainer/BtnStats.pressed.connect(_on_stats_pressed)
	$VBoxContainer/BtnSalir.pressed.connect(_on_salir_presionado)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _on_jugar_pressed() -> void:
	get_tree().change_scene_to_file(TEST_LEVEL_PATH)

func _on_editor_pressed() -> void:
	get_tree().change_scene_to_file(CREACION_NIVEL_PATH)

func _on_cargar_pressed() -> void:
	get_tree().change_scene_to_file(NIVEL_CARGADO_PATH)

func _on_stats_pressed() -> void:
	get_tree().change_scene_to_file(STATS_PATH)

func _on_salir_presionado() -> void:
	get_tree().quit()
