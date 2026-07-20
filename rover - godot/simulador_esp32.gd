extends Control

const MENU_PATH = "res://scenes/menu_principal.tscn"

# ═══════════════════════════════════════════
# SERVIDOR WEBSOCKET
# ═══════════════════════════════════════════
var tcp_server = TCPServer.new()
var peer: WebSocketPeer = null
var servidor_activo: bool = false
var puerto: int = 9080

# ═══════════════════════════════════════════
# SIMULACION ROVER
# ═══════════════════════════════════════════
var lat: float = 0.0
var lon: float = 0.0
var lat_centro: float = 0.0
var lon_centro: float = 0.0
const ESCALA_MAPA: float = 100000.0
var velocidad: float = 0.0001
var direccion: Vector2 = Vector2.ZERO
var magnitud: float = 0.0

var timer_gps: float = 0.0
var intervalo_gps: float = 0.5
var enviando_gps: bool = false

var modo_manual: bool = false
var arrastrando_rover: bool = false

# ═══════════════════════════════════════════
# VENTANAS
# ═══════════════════════════════════════════
var ventanas_visibles = {"servidor": true, "config": true, "log": true}
var arrastrando_ventana: String = ""
var offset_arrastre: Vector2 = Vector2.ZERO

# ═══════════════════════════════════════════
# LOG
# ═══════════════════════════════════════════
var log_mensajes: Array[String] = []
var max_log: int = 20

# ═══════════════════════════════════════════
# ONREADY — VENTANAS
# ═══════════════════════════════════════════
@onready var ventana_servidor: Panel = $VentanaServidor
@onready var ventana_config: Panel = $VentanaConfig
@onready var ventana_log: Panel = $VentanaLog
@onready var menu_button: MenuButton = $MenuButton

@onready var titulo_servidor: HBoxContainer = $VentanaServidor/MarginContainer/VBoxContainer/TitleServidor
@onready var titulo_config: HBoxContainer = $VentanaConfig/MarginContainer/VBoxContainer/TitleConfig
@onready var titulo_log: HBoxContainer = $VentanaLog/MarginContainer/VBoxContainer/TitleLog

# ═══════════════════════════════════════════
# ONREADY — CONTROLES SERVIDOR
# ═══════════════════════════════════════════
@onready var line_edit_puerto: LineEdit = $VentanaServidor/MarginContainer/VBoxContainer/HBoxPuerto/LineEditPuerto
@onready var btn_iniciar: Button = $VentanaServidor/MarginContainer/VBoxContainer/HBoxBotones/BtnIniciar
@onready var btn_detener: Button = $VentanaServidor/MarginContainer/VBoxContainer/HBoxBotones/BtnDetener
@onready var label_estado: Label = $VentanaServidor/MarginContainer/VBoxContainer/LabelEstado

# ═══════════════════════════════════════════
# ONREADY — CONTROLES CONFIG
# ═══════════════════════════════════════════
@onready var spin_lat: SpinBox = $VentanaConfig/MarginContainer/VBoxContainer/HBoxLat/SpinLat
@onready var spin_lon: SpinBox = $VentanaConfig/MarginContainer/VBoxContainer/HBoxLon/SpinLon
@onready var spin_vel: SpinBox = $VentanaConfig/MarginContainer/VBoxContainer/HBoxVel/SpinVel
@onready var btn_aplicar: Button = $VentanaConfig/MarginContainer/VBoxContainer/BtnAplicar
@onready var btn_reset: Button = $VentanaConfig/MarginContainer/VBoxContainer/BtnReset
@onready var check_manual: CheckBox = $VentanaConfig/MarginContainer/VBoxContainer/CheckManual

# ═══════════════════════════════════════════
# ONREADY — MAPA
# ═══════════════════════════════════════════
@onready var mapa_area: Control = $MapaArea
@onready var bloque_rover: ColorRect = $MapaArea/BloqueRover
@onready var cruzh: ColorRect = $MapaArea/CruzH
@onready var cruzv: ColorRect = $MapaArea/CruzV
@onready var label_coords: Label = $MapaArea/LabelCoords

# ═══════════════════════════════════════════
# ONREADY — LOG
# ═══════════════════════════════════════════
@onready var label_ultimo: Label = $VentanaLog/MarginContainer/VBoxContainer/LabelUltimo
@onready var rich_log: RichTextLabel = $VentanaLog/MarginContainer/VBoxContainer/RichLog

# ═══════════════════════════════════════════
# ONREADY — BOTONES CERRAR
# ═══════════════════════════════════════════
@onready var btn_cerrar_serv: Button = $VentanaServidor/MarginContainer/VBoxContainer/TitleServidor/BtnCerrar
@onready var btn_cerrar_conf: Button = $VentanaConfig/MarginContainer/VBoxContainer/TitleConfig/BtnCerrar
@onready var btn_cerrar_log: Button = $VentanaLog/MarginContainer/VBoxContainer/TitleLog/BtnCerrar

# ═══════════════════════════════════════════
func _ready():
	tcp_server = TCPServer.new()
	label_estado.text = "Servidor detenido"
	line_edit_puerto.text = str(puerto)

	btn_iniciar.pressed.connect(_iniciar_servidor)
	btn_detener.pressed.connect(_detener_servidor)
	btn_aplicar.pressed.connect(_aplicar_config)
	btn_reset.pressed.connect(_reset_posicion)
	check_manual.toggled.connect(_on_modo_manual_toggled)

	btn_cerrar_serv.pressed.connect(func(): _toggle_ventana("servidor", false))
	btn_cerrar_conf.pressed.connect(func(): _toggle_ventana("config", false))
	btn_cerrar_log.pressed.connect(func(): _toggle_ventana("log", false))

	spread_menu()
	spin_lat.value = lat
	spin_lon.value = lon
	spin_vel.value = velocidad * 10000.0

	_posicionar_rover()
	_posicionar_cruces()

	call_deferred("_posicionar_todo")

func _posicionar_todo():
	_posicionar_rover()
	_posicionar_cruces()

func spread_menu():
	var popup = menu_button.get_popup()
	popup.clear()
	popup.add_check_item("Servidor", 0)
	popup.set_item_checked(0, ventanas_visibles["servidor"])
	popup.add_check_item("Configuracion", 1)
	popup.set_item_checked(1, ventanas_visibles["config"])
	popup.add_check_item("Log", 2)
	popup.set_item_checked(2, ventanas_visibles["log"])
	popup.id_pressed.connect(_on_menu_item)

func _on_menu_item(id: int):
	match id:
		0: _toggle_ventana("servidor", not ventanas_visibles["servidor"])
		1: _toggle_ventana("config", not ventanas_visibles["config"])
		2: _toggle_ventana("log", not ventanas_visibles["log"])

func _toggle_ventana(nombre: String, visible: bool):
	ventanas_visibles[nombre] = visible
	match nombre:
		"servidor": ventana_servidor.visible = visible
		"config": ventana_config.visible = visible
		"log": ventana_log.visible = visible
	var popup = menu_button.get_popup()
	var ids = {"servidor": 0, "config": 1, "log": 2}
	popup.set_item_checked(ids[nombre], visible)

# ═══════════════════════════════════════════
# INPUT — ESC + ARRASTRE VENTANAS + ROVER
# ═══════════════════════════════════════════
func _input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		_detener_servidor()
		get_tree().change_scene_to_file(MENU_PATH)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_detectar_arrastre_ventana()
			if not arrastrando_ventana and modo_manual:
				if _mouse_cerca_del_rover():
					arrastrando_rover = true
		else:
			if arrastrando_ventana:
				arrastrando_ventana = ""
			elif arrastrando_rover:
				arrastrando_rover = false
				_sync_desde_posicion_bloque()
				_enviar_gps()

	if event is InputEventMouseMotion:
		if arrastrando_ventana:
			_mover_ventana_arrastrada()
		elif arrastrando_rover:
			_mover_bloque_a_mouse()

func _detectar_arrastre_ventana():
	var mouse_pos = get_global_mouse_position()
	if ventana_servidor.visible and _rect_de(titulo_servidor).has_point(mouse_pos):
		arrastrando_ventana = "servidor"
		offset_arrastre = ventana_servidor.position - mouse_pos
	elif ventana_config.visible and _rect_de(titulo_config).has_point(mouse_pos):
		arrastrando_ventana = "config"
		offset_arrastre = ventana_config.position - mouse_pos
	elif ventana_log.visible and _rect_de(titulo_log).has_point(mouse_pos):
		arrastrando_ventana = "log"
		offset_arrastre = ventana_log.position - mouse_pos

func _rect_de(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size)

func _mover_ventana_arrastrada():
	var nueva_pos = get_global_mouse_position() + offset_arrastre
	nueva_pos.x = clamp(nueva_pos.x, 0, size.x - 100)
	nueva_pos.y = clamp(nueva_pos.y, 0, size.y - 30)
	match arrastrando_ventana:
		"servidor": ventana_servidor.position = nueva_pos
		"config": ventana_config.position = nueva_pos
		"log": ventana_log.position = nueva_pos

# ═══════════════════════════════════════════
# ARRASTRE ROVER MANUAL
# ═══════════════════════════════════════════
func _mouse_cerca_del_rover() -> bool:
	if not mapa_area or not bloque_rover:
		return false
	var pos_local = mapa_area.get_local_mouse_position()
	if pos_local.x < 0 or pos_local.y < 0 or pos_local.x > mapa_area.size.x or pos_local.y > mapa_area.size.y:
		return false
	var rover_rect = Rect2(bloque_rover.position, bloque_rover.size)
	rover_rect = rover_rect.grow(12)
	return rover_rect.has_point(pos_local)

func _mover_bloque_a_mouse():
	var pos_local = mapa_area.get_local_mouse_position()
	var tam = bloque_rover.size
	pos_local.x = clamp(pos_local.x, 0, mapa_area.size.x)
	pos_local.y = clamp(pos_local.y, 0, mapa_area.size.y)
	bloque_rover.position = pos_local - tam / 2.0
	_sync_desde_posicion_bloque()

func _sync_desde_posicion_bloque():
	var centro = mapa_area.size / 2.0
	var screen_offset = (bloque_rover.position + bloque_rover.size / 2.0) - centro
	lon = lon_centro + screen_offset.x / ESCALA_MAPA
	lat = lat_centro - screen_offset.y / ESCALA_MAPA
	label_coords.text = "GPS: %.6f, %.6f" % [lat, lon]
	spin_lat.value = lat
	spin_lon.value = lon

# ═══════════════════════════════════════════
func _process(delta):
	if not servidor_activo:
		return

	if not tcp_server.is_listening():
		return

	if tcp_server.is_connection_available():
		var conn = tcp_server.take_connection()
		if peer and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_log("(ocupado, rechazando nueva conexion)")
			return
		peer = WebSocketPeer.new()
		peer.accept_stream(conn)
		_log("Cliente conectado")
		label_estado.text = "Conectado"
		enviando_gps = false
		timer_gps = 0.0

	if not peer:
		return

	peer.poll()
	var state = peer.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		while peer.get_available_packet_count() > 0:
			var packet = peer.get_packet()
			var msg = packet.get_string_from_utf8()
			_procesar_comando(msg)

		if direccion != Vector2.ZERO and not modo_manual:
			var delta_mag = magnitud
			lon += direccion.x * velocidad * delta_mag * delta
			lat += direccion.y * velocidad * delta_mag * delta
			_posicionar_rover()
			enviando_gps = true

		if enviando_gps:
			timer_gps += delta
			if timer_gps >= intervalo_gps:
				timer_gps = 0.0
				_enviar_gps()

	elif state == WebSocketPeer.STATE_CLOSED:
		_log("Cliente desconectado")
		label_estado.text = "Esperando conexion..."
		peer = null
		enviando_gps = false

# ═══════════════════════════════════════════
# COMANDOS DEL CLIENTE
# ═══════════════════════════════════════════
func _procesar_comando(msg: String):
	_log("Recibido: " + msg)

	if msg.begins_with("MOVER "):
		var str_vec = msg.trim_prefix("MOVER ")
		var sin_parentesis = str_vec.replace("(", "").replace(")", "")
		var partes = sin_parentesis.split_floats(",")
		if partes.size() >= 2:
			var x = partes[0]
			var y = partes[1]
			direccion = Vector2(x, y)
			magnitud = clampf(direccion.length(), 0.0, 1.0)
			if magnitud < 0.05:
				magnitud = 0.0
				direccion = Vector2.ZERO
				enviando_gps = false
			label_ultimo.text = "MOVER: (%.2f, %.2f) mag=%.2f" % [x, y, magnitud]

	elif msg == "STOP":
		direccion = Vector2.ZERO
		magnitud = 0.0
		enviando_gps = false
		label_ultimo.text = "STOP"

	elif msg == "ACCION":
		label_ultimo.text = "ACCION"
		_enviar_gps()

# ═══════════════════════════════════════════
func _enviar_gps():
	if peer and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var gps_msg = "GPS: %.6f, %.6f" % [lat, lon]
		peer.send_text(gps_msg)
		label_coords.text = "GPS: %.6f, %.6f" % [lat, lon]

# ═══════════════════════════════════════════
# SERVIDOR
# ═══════════════════════════════════════════
func _iniciar_servidor():
	puerto = int(line_edit_puerto.text)
	if puerto <= 0 or puerto > 65535:
		puerto = 9080
		line_edit_puerto.text = "9080"
	var err = tcp_server.listen(puerto, "127.0.0.1")
	if err != OK:
		label_estado.text = "Error al iniciar servidor"
		_log("Error al iniciar servidor en puerto %d" % puerto)
		return
	servidor_activo = true
	label_estado.text = "Esperando conexion en :%d..." % puerto
	_log("Servidor iniciado en 127.0.0.1:%d" % puerto)

func _detener_servidor():
	if peer:
		peer.close()
		peer = null
	tcp_server.stop()
	servidor_activo = false
	label_estado.text = "Servidor detenido"
	_log("Servidor detenido")

# ═══════════════════════════════════════════
func _on_modo_manual_toggled(activado: bool):
	modo_manual = activado
	arrastrando_rover = false
	if activado:
		direccion = Vector2.ZERO
		magnitud = 0.0
		enviando_gps = false
		bloque_rover.color = Color(1, 0.6, 0.0, 0.95)
		_log("Modo Manual activado - arrastra el bloque en el mapa")
	else:
		bloque_rover.color = Color(1, 0.2, 0.1, 0.95)
		_log("Modo Automatico (joystick)")

# ═══════════════════════════════════════════
# CONFIGURACION
# ═══════════════════════════════════════════
func _aplicar_config():
	lat_centro = spin_lat.value
	lon_centro = spin_lon.value
	lat = lat_centro
	lon = lon_centro
	velocidad = spin_vel.value / 10000.0
	_posicionar_rover()
	label_coords.text = "GPS: %.6f, %.6f" % [lat, lon]
	_log("Config aplicada: lat=%.6f lon=%.6f vel=%.6f" % [lat, lon, velocidad])

func _reset_posicion():
	lat_centro = 0.0
	lon_centro = 0.0
	lat = 0.0
	lon = 0.0
	direccion = Vector2.ZERO
	magnitud = 0.0
	enviando_gps = false
	spin_lat.value = 0.0
	spin_lon.value = 0.0
	_posicionar_rover()
	label_coords.text = "GPS: 0.000000, 0.000000"
	label_ultimo.text = "---"
	_log("Posicion reseteada a (0, 0)")

# ═══════════════════════════════════════════
# MAPA — POSICIONAMIENTO
# ═══════════════════════════════════════════
func _posicionar_rover():
	if not mapa_area or not bloque_rover:
		return
	var centro = mapa_area.size / 2.0
	var delta_lon = (lon - lon_centro) * ESCALA_MAPA
	var delta_lat = (lat - lat_centro) * ESCALA_MAPA
	var tam = bloque_rover.size
	bloque_rover.position = centro - tam / 2.0 + Vector2(delta_lon, -delta_lat)

func _posicionar_cruces():
	if not mapa_area or not cruzh or not cruzv:
		return
	var centro = mapa_area.size / 2.0
	cruzh.size = Vector2(mapa_area.size.x, 1)
	cruzh.position = Vector2(0, centro.y - 0.5)
	cruzv.size = Vector2(1, mapa_area.size.y)
	cruzv.position = Vector2(centro.x - 0.5, 0)

# ═══════════════════════════════════════════
# LOG
# ═══════════════════════════════════════════
func _log(texto: String):
	var ts = Time.get_time_string_from_system()
	log_mensajes.push_front("[%s] %s" % [ts, texto])
	if log_mensajes.size() > max_log:
		log_mensajes.resize(max_log)
	rich_log.text = "\n".join(log_mensajes)

# ═══════════════════════════════════════════
# RESIZE
# ═══════════════════════════════════════════
func _notification(what: int):
	if what == NOTIFICATION_RESIZED:
		_posicionar_rover()
		_posicionar_cruces()
