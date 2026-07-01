## sensor_reader.gd
## Conecta a un servidor WebSocket que transmite tramas $VNINS
## y expone los datos como señales para que cualquier nodo los consuma.
##
## Uso:
##   1. Adjuntá este script a un nodo (ej. un Autoload llamado "Sensor")
##   2. Conectá las señales que necesites en tu vehículo / HUD
##   3. Corré el simulator.py antes de iniciar Godot

extends Node

# ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────
@export var ws_url: String = "ws://localhost:8765"
@export var auto_reconnect: bool = true
@export var reconnect_delay: float = 3.0
# ──────────────────────────────────────────────────────────────────────────────

## Emitida cada vez que llega una trama válida.
## `datos` es un Dictionary con la misma estructura que el JSON del reader.py
signal datos_recibidos(datos: Dictionary)

## Emitida cuando cambia el estado de la conexión.
signal conexion_cambiada(conectado: bool)

# Estado interno
var _ws: WebSocketPeer = WebSocketPeer.new()
var _conectado: bool = false
var _reconectar_en: float = 0.0


func _ready() -> void:
	pass


func conectar() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN or _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return
	print("[Sensor] Conectando a ", ws_url, " ...")
	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		push_warning("[Sensor] No se pudo iniciar la conexión: %s" % err)


func desconectar() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close()
		_conectado = false
		print("[Sensor] Desconectado manualmente.")
		conexion_cambiada.emit(false)


func _process(delta: float) -> void:
	_ws.poll()

	var estado = _ws.get_ready_state()

	match estado:
		WebSocketPeer.STATE_OPEN:
			if not _conectado:
				_conectado = true
				print("[Sensor] Conexión establecida.")
				conexion_cambiada.emit(true)

			# Procesar todos los mensajes disponibles en el buffer
			while _ws.get_available_packet_count() > 0:
				var paquete: PackedByteArray = _ws.get_packet()
				var linea: String = paquete.get_string_from_utf8().strip_edges()
				_procesar_linea(linea)

		WebSocketPeer.STATE_CLOSED:
			if _conectado:
				_conectado = false
				print("[Sensor] Conexión cerrada.")
				conexion_cambiada.emit(false)

			if auto_reconnect:
				_reconectar_en -= delta
				if _reconectar_en <= 0.0:
					_reconectar_en = reconnect_delay
					_ws = WebSocketPeer.new()
					conectar()


func _procesar_linea(linea: String) -> void:
	if linea == "__FIN__":
		print("[Sensor] El simulador indicó que terminó la secuencia.")
		return

	var datos = _parsear_vnins(linea)
	if datos:
		datos_recibidos.emit(datos)


func _parsear_vnins(linea: String) -> Dictionary:
	"""Parsea una trama $VNINS y devuelve un Dictionary o {} si falla."""
	var partes: PackedStringArray = linea.split(",")
	if partes.size() < 16 or partes[0] != "$VNINS":
		return {}

	# El último campo trae el checksum pegado: "0.25*62" → "0.25"
	var vel_unc_str: String = partes[15].split("*")[0]

	var datos: Dictionary = {
		"tipo_mensaje": partes[0],
		"tiempo_gps":   float(partes[1]),
		"semana_gps":   int(partes[2]),
		"estado":       partes[3],
		"orientacion": {
			"yaw_grados":   float(partes[4]),
			"pitch_grados": float(partes[5]),
			"roll_grados":  float(partes[6]),
		},
		"posicion": {
			"latitud":        float(partes[7]),
			"longitud":       float(partes[8]),
			"altitud_metros": float(partes[9]),
		},
		"velocidad": {
			"norte_m_s": float(partes[10]),
			"este_m_s":  float(partes[11]),
			"abajo_m_s": float(partes[12]),
		},
		"incertidumbre": {
			"actitud":   float(partes[13]),
			"posicion":  float(partes[14]),
			"velocidad": float(vel_unc_str),
		},
	}
	return datos


# ─── HELPERS de acceso rápido ─────────────────────────────────────────────────
## Podés llamar estos métodos desde tu vehículo si preferís polling en vez de señales.

func esta_conectado() -> bool:
	return _conectado
