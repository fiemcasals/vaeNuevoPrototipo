extends Node

var peso_rover: float = 500.0
var velocidad_maxima: float = 50.0
var aceleracion: float = 300.0
var torque: float = 300.0
var ancho_vehiculo: float = 2.0
var largo_vehiculo: float = 3.0
var ancho_ruedas: float = 0.2
var distancia_entre_ejes: float = 2.0
var distancia_entre_ruedas: float = 1.5
var margen_seguridad: float = 0.5
var op_mode: String = "vehicle" # "vehicle" or "turret"

func _ready() -> void:
	cargar_configuracion()

func cargar_configuracion() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://rover_config.cfg")
	if err == OK:
		peso_rover = config.get_value("rover", "peso", 500.0)
		velocidad_maxima = config.get_value("rover", "velocidad_maxima", 50.0)
		aceleracion = config.get_value("rover", "aceleracion", 300.0)
		torque = config.get_value("rover", "torque", 300.0)
		ancho_vehiculo = config.get_value("rover", "ancho_vehiculo", 2.0)
		largo_vehiculo = config.get_value("rover", "largo_vehiculo", 3.0)
		ancho_ruedas = config.get_value("rover", "ancho_ruedas", 0.2)
		distancia_entre_ejes = config.get_value("rover", "distancia_entre_ejes", 2.0)
		distancia_entre_ruedas = config.get_value("rover", "distancia_entre_ruedas", 1.5)
		margen_seguridad = config.get_value("rover", "margen_seguridad", 0.5)

func guardar_configuracion() -> void:
	var config = ConfigFile.new()
	config.set_value("rover", "peso", peso_rover)
	config.set_value("rover", "velocidad_maxima", velocidad_maxima)
	config.set_value("rover", "aceleracion", aceleracion)
	config.set_value("rover", "torque", torque)
	config.set_value("rover", "ancho_vehiculo", ancho_vehiculo)
	config.set_value("rover", "largo_vehiculo", largo_vehiculo)
	config.set_value("rover", "ancho_ruedas", ancho_ruedas)
	config.set_value("rover", "distancia_entre_ejes", distancia_entre_ejes)
	config.set_value("rover", "distancia_entre_ruedas", distancia_entre_ruedas)
	config.set_value("rover", "margen_seguridad", margen_seguridad)
	config.save("user://rover_config.cfg")

func aplicar_configuracion_a_rover(rover: VehicleBody3D) -> void:
	if rover:
		rover.mass = peso_rover
		if rover.has_method("set_power"):
			rover.set_power(torque)
		if rover.has_method("set_max_speed"):
			rover.set_max_speed(velocidad_maxima)
		# Aplicar valores directamente si el rover tiene las propiedades
		if rover.get("power") != null:
			rover.power = torque
		if rover.get("max_speed") != null:
			rover.max_speed = velocidad_maxima
