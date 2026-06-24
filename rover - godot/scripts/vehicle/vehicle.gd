## vehicle.gd — Ejemplo de cómo consumir los datos del sensor en tu vehículo
## Conectá este script al nodo de tu vehículo en Godot.
##
## Requisito: sensor_reader.gd registrado como Autoload con el nombre "Sensor"
## (Project → Project Settings → Autoload → agregar sensor_reader.gd como "Sensor")

extends VehicleBody3D   # o CharacterBody3D, RigidBody3D, lo que uses
var first_frame: bool = true
var origen_lat = -34.570000
var origen_lon = -58.430000
var origen_alt = 0.0
@export var escala_posicion: float = 111_111.0  # metros por grado, ajustá según tu zona
@export var margen_error_vector_inicial = Vector3(0.0, -25.0, 0.0)  # Ajustá según tu modelo y orientación inicial
func _ready() -> void:
	# Conectamos la señal del Autoload a nuestro método local
	Sensor.datos_recibidos.connect(_on_datos_sensor)
	Sensor.conexion_cambiada.connect(_on_conexion_cambiada)


func _on_conexion_cambiada(conectado: bool) -> void:
	if conectado:
		print("[Vehículo] Sensor conectado — recibiendo telemetría.")
	else:
		print("[Vehículo] Sensor desconectado.")


func _on_datos_sensor(datos: Dictionary) -> void:
	# ── Orientación ──────────────────────────────────────────────────────────
	var yaw:   float = datos["orientacion"]["yaw_grados"]
	var pitch: float = datos["orientacion"]["pitch_grados"]
	var roll:  float = datos["orientacion"]["roll_grados"]

	# Convertimos a radianes y aplicamos la rotación al nodo
	# Nota: en Godot el sistema de coordenadas es Y-up, ajustá los ejes según
	# cómo esté orientado tu modelo 3D.
	rotation.y = deg_to_rad(-yaw)    # Yaw  → rotación horizontal
	rotation.x = deg_to_rad(pitch)   # Pitch → inclinación frontal
	rotation.z = deg_to_rad(-roll)   # Roll  → alabeo lateral

	# ── Posición (opcional — útil para debug o modo mapa) ─────────────────
	var lat: float = datos["posicion"]["latitud"]
	var lon: float = datos["posicion"]["longitud"]
	var alt: float = datos["posicion"]["altitud_metros"]
	# Si querés convertir lat/lon a coordenadas locales de Godot,
	# necesitás un origen de referencia. Ejemplo básico:
	if first_frame:
		print("[Vehículo] Posición inicial: lat=", lat, " lon=", lon, " alt=", alt)
		first_frame = false
		origen_lat = lat
		origen_lon = lon
		origen_alt = alt
	
	var escala     = escala_posicion   # metros por grado
	position.x = (lon - origen_lon) * escala
	position.z = -(lat - origen_lat) * escala
	position.y = alt - origen_alt
	# ── Velocidad ────────────────────────────────────────────────────────────
	var v_norte: float = datos["velocidad"]["norte_m_s"]
	var v_este:  float = datos["velocidad"]["este_m_s"]
	var v_abajo: float = datos["velocidad"]["abajo_m_s"]

	# Podés usarlos para animar efectos de velocidad, HUD, partículas, etc.
	var speed: float = sqrt(v_norte**2 + v_este**2 + v_abajo**2)
	# Ejemplo: $HUD.set_speed(speed)

	# ── Incertidumbre (para debug visual) ────────────────────────────────────
	# var unc_pos: float = datos["incertidumbre"]["posicion"]
	# Si la incertidumbre es alta, podés mostrar un indicador de "señal débil"
