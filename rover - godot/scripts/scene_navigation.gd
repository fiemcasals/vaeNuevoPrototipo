extends Control

const MENU_PATH = "res://scenes/menu_principal.tscn"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_volver_al_menu()

func _volver_al_menu() -> void:
	get_tree().change_scene_to_file(MENU_PATH)
