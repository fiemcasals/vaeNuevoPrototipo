extends Node

var muro_colision_activado: bool = true
var evasion_zonas_activada: bool = true
var evasion_reversa_activada: bool = true
var evasion_mostrar_gizmos: bool = true
var lane_shift_activado: bool = true
var suavizado_ruta_activado: bool = true
var acortar_ruta_activado: bool = true
var enviar_evasion_brain: bool = true

signal config_changed(propiedad: String, valor: bool)

func notify_config_changed(propiedad: String, valor: bool) -> void:
	config_changed.emit(propiedad, valor)
