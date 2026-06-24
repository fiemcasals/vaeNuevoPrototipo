extends Control

const MENU_PATH = "res://scenes/menu_principal.tscn"

signal nivel_seleccionado(path: String)

@onready var button_cargar_nivel: Button = $ButtonCargarNivel
@onready var file_dialog: FileDialog = $FileDialog
@onready var btn_volver: Button = $BtnVolverMenu

func _ready() -> void:
	if button_cargar_nivel:
		button_cargar_nivel.pressed.connect(_on_button_cargar_nivel_pressed)
	if file_dialog:
		file_dialog.file_selected.connect(_on_file_selected)
		file_dialog.filters = ["*.json ; JSON Files", "*.tscn ; Scenes", "*.* ; All files"]
	if btn_volver:
		btn_volver.pressed.connect(_volver_al_menu)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_volver_al_menu()

func _volver_al_menu() -> void:
	get_tree().change_scene_to_file(MENU_PATH)

func _on_button_cargar_nivel_pressed() -> void:
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.title = "Seleccionar archivo de nivel"
		file_dialog.popup_centered(Vector2(800, 600))

func _on_file_selected(path: String) -> void:
	emit_signal("nivel_seleccionado", path)
	_emit_path_to_bus(path)

func _emit_path_to_bus(path: String) -> void:
	SignalBus.emit_signal("nivel_seleccionado", path)
