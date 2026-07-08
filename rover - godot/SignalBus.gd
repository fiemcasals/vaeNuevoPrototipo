extends Node

signal change_cam(cam: int)
signal nivel_seleccionado(path: String)

func emit_nivel_seleccionado(path: String) -> void:
	nivel_seleccionado.emit(path)

func emit_change_cam(cam: int) -> void:
	change_cam.emit(cam)
