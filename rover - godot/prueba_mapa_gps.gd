extends Control

const MENU_PATH = "res://scenes/menu_principal.tscn"

# ═══════════════════════════════════════════
# WEBSOCKET
# ═══════════════════════════════════════════
var socket = WebSocketPeer.new()
var conectado = false

# ═══════════════════════════════════════════
# GPS — MAPA
# ═══════════════════════════════════════════
@export var sensibilidad: float = 1.0
var lat_inicial: float = 0.0
var lon_inicial: float = 0.0
var lat_actual: float = 0.0
var lon_actual: float = 0.0
var posicion_inicial_guardada: bool = false

# ═══════════════════════════════════════════
# ONREADY
# ═══════════════════════════════════════════
@onready var line_edit_ip: LineEdit = $Panel/MarginContainer/VBoxContainer/HBoxIP/LineEditIP
@onready var label_estado: Label = $Panel/MarginContainer/VBoxContainer/LabelEstado
@onready var timer_reconexion: Timer = $TimerReconexion
@onready var btn_conectar: Button = $Panel/MarginContainer/VBoxContainer/HBoxBotones/BtnConectar
@onready var btn_desconectar: Button = $Panel/MarginContainer/VBoxContainer/HBoxBotones/BtnDesconectar
@onready var btn_accion: Button = $"Panel/MarginContainer/VBoxContainer/HBoxBotones/BtnAccion"
@onready var joystick: Control = $JoystickArea

@onready var mapa_area: Control = $MapaArea
@onready var bloque_gps: ColorRect = $MapaArea/BloqueGPS
@onready var cruz_h: ColorRect = $MapaArea/CruzCentroH
@onready var cruz_v: ColorRect = $MapaArea/CruzCentroV
@onready var slider_sensibilidad: HSlider = $PanelSensibilidad/MarginContainer/HBoxContainer/HSlider
@onready var label_sensibilidad: Label = $PanelSensibilidad/MarginContainer/HBoxContainer/LabelSensibilidad
@onready var label_coords: Label = $MapaArea/LabelCoords

# ═══════════════════════════════════════════
func _ready():
	label_estado.text = "Desconectado"
	timer_reconexion.timeout.connect(_intentar_conexion)

	btn_conectar.pressed.connect(_on_conectar_pressed)
	btn_desconectar.pressed.connect(_on_desconectar_pressed)
	btn_accion.pressed.connect(_on_boton_accion)

	joystick.joystick_movido.connect(_on_joystick_movido)
	joystick.joystick_soltado.connect(_on_joystick_soltado)

	slider_sensibilidad.value_changed.connect(_on_sensibilidad_cambiada)
	label_sensibilidad.text = "Sensibilidad: %.1f" % sensibilidad
	slider_sensibilidad.value = sensibilidad

	_posicionar_bloque()
	_posicionar_cruces()

func _input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		socket.close()
		get_tree().change_scene_to_file(MENU_PATH)

# ═══════════════════════════════════════════
# WEBSOCKET — Conexión
# ═══════════════════════════════════════════
func _on_conectar_pressed():
	var ip = line_edit_ip.text.strip_edges()
	if ip != "":
		_intentar_conexion()

func _on_desconectar_pressed():
	socket.close()
	conectado = false
	posicion_inicial_guardada = false
	label_estado.text = "Desconectado"

func _intentar_conexion():
	var ip = line_edit_ip.text.strip_edges()
	if ip == "":
		ip = "ws://127.0.0.1:9080"
	var state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		print("Conectando a: ", ip)
		var err = socket.connect_to_url(ip)
		if err != OK:
			print("Error al conectar: ", err)
			label_estado.text = "Error de conexión"
			timer_reconexion.start()
		else:
			label_estado.text = "Conectando..."

func _process(_delta):
	socket.poll()
	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not conectado:
			conectado = true
			print("Conectado al ESP32")
			label_estado.text = "Conectado"
			timer_reconexion.stop()
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var mensaje = packet.get_string_from_utf8()
			print("ESP32: ", mensaje)
			_procesar_gps(mensaje)

	elif state == WebSocketPeer.STATE_CLOSED:
		if conectado:
			conectado = false
			posicion_inicial_guardada = false
			label_estado.text = "Desconectado - Reintentando..."
			print("Conexión perdida")
		if timer_reconexion.is_stopped():
			timer_reconexion.start()

	elif state == WebSocketPeer.STATE_CONNECTING:
		label_estado.text = "Conectando..."

# ═══════════════════════════════════════════
# GPS — Parseo y actualización del bloque
# ═══════════════════════════════════════════
func _procesar_gps(mensaje: String):
	var regex = RegEx.new()
	regex.compile("GPS:\\s*(-?\\d+\\.?\\d*)\\s*,\\s*(-?\\d+\\.?\\d*)")
	var result = regex.search(mensaje)
	if result:
		lat_actual = float(result.get_string(1))
		lon_actual = float(result.get_string(2))

		if not posicion_inicial_guardada:
			lat_inicial = lat_actual
			lon_inicial = lon_actual
			posicion_inicial_guardada = true
			print("Posicion inicial GPS: ", lat_inicial, ", ", lon_inicial)

		label_coords.text = "GPS: %.6f, %.6f" % [lat_actual, lon_actual]
		_posicionar_bloque()

func _posicionar_bloque():
	if not is_inside_tree():
		return
	if not mapa_area or not bloque_gps:
		return

	if posicion_inicial_guardada:
		var centro = mapa_area.size / 2.0
		var delta_lat = (lat_actual - lat_inicial) * sensibilidad
		var delta_lon = (lon_actual - lon_inicial) * sensibilidad
		var tam = bloque_gps.size
		bloque_gps.position = centro - tam / 2.0 + Vector2(delta_lon, -delta_lat)
	else:
		var centro = mapa_area.size / 2.0
		var tam = bloque_gps.size
		bloque_gps.position = centro - tam / 2.0

func _posicionar_cruces():
	if not mapa_area or not cruz_h or not cruz_v:
		return
	var centro = mapa_area.size / 2.0
	cruz_h.size = Vector2(mapa_area.size.x, 1)
	cruz_h.position = Vector2(0, centro.y - 0.5)
	cruz_v.size = Vector2(1, mapa_area.size.y)
	cruz_v.position = Vector2(centro.x - 0.5, 0)

# ═══════════════════════════════════════════
# FOCUS / MULTITAREA
# ═══════════════════════════════════════════
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_posicionar_bloque()
		_posicionar_cruces()
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		print("App en primer plano. Verificando conexión...")
		_forzar_verificacion_red()

func _forzar_verificacion_red() -> void:
	socket.poll()
	var state = socket.get_ready_state()
	if state != WebSocketPeer.STATE_OPEN:
		print("Conexión fantasma detectada. Reseteando...")
		_limpiar_y_reconnect()

func _limpiar_y_reconnect() -> void:
	socket.close()
	conectado = false
	posicion_inicial_guardada = false
	label_estado.text = "Desconectado"
	if timer_reconexion.is_stopped():
		timer_reconexion.start()

# ═══════════════════════════════════════════
# ENVIAR COMANDOS
# ═══════════════════════════════════════════
func enviar_comando(comando: String) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(comando)
		print("Enviado: ", comando)
	else:
		print("No conectado al ESP32")

# ═══════════════════════════════════════════
# ⚡ STUBS
# ═══════════════════════════════════════════
func _on_joystick_movido(direccion: Vector2) -> void:
	enviar_comando("MOVER " + str(Vector2(direccion.x, -direccion.y)))

func _on_joystick_soltado() -> void:
	enviar_comando("STOP")

func _on_boton_accion() -> void:
	enviar_comando("ACCION")

func _on_sensibilidad_cambiada(valor: float):
	sensibilidad = valor
	label_sensibilidad.text = "Sensibilidad: %.1f" % sensibilidad
	_posicionar_bloque()
