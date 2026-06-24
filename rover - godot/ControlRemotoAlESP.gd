extends Control

# ═══════════════════════════════════════════
# WEBSOCKET
# ═══════════════════════════════════════════
var socket = WebSocketPeer.new()
var conectado = false

# ═══════════════════════════════════════════
# ONREADY
# ═══════════════════════════════════════════
@onready var line_edit_ip: LineEdit = $Panel/MarginContainer/VBoxContainer/HBoxIP/LineEditIP
@onready var label_estado: Label = $Panel/MarginContainer/VBoxContainer/LabelEstado
@onready var timer_reconexion: Timer = $TimerReconexion
@onready var btn_conectar: Button = $Panel/MarginContainer/VBoxContainer/HBoxBotones/BtnConectar
@onready var btn_desconectar: Button = $Panel/MarginContainer/VBoxContainer/HBoxBotones/BtnDesconectar
@onready var btn_accion: Button = $"Panel/MarginContainer/VBoxContainer/HBoxBotones/BtnAccion"
@onready var joystick = $JoystickArea

# ═══════════════════════════════════════════
func _ready():
	label_estado.text = "Desconectado"
	timer_reconexion.timeout.connect(_intentar_conexion)

	btn_conectar.pressed.connect(_on_conectar_pressed)
	btn_desconectar.pressed.connect(_on_desconectar_pressed)
	btn_accion.pressed.connect(_on_boton_accion)

	# Conectar señales del JoystickVirtual a los stubs
	joystick.joystick_movido.connect(_on_joystick_movido)
	joystick.joystick_soltado.connect(_on_joystick_soltado)

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
	label_estado.text = "Desconectado"

func _intentar_conexion():
	var ip = line_edit_ip.text.strip_edges()
	if ip == "":
		ip = "ws://10.24.206.226:81"
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

	elif state == WebSocketPeer.STATE_CLOSED:
		if conectado:
			conectado = false
			label_estado.text = "Desconectado - Reintentando..."
			print("Conexión perdida")
		if timer_reconexion.is_stopped():
			timer_reconexion.start()

	elif state == WebSocketPeer.STATE_CONNECTING:
		label_estado.text = "Conectando..."

# ═══════════════════════════════════════════
# FOCUS / MULTITAREA
# ═══════════════════════════════════════════
func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		print("App en primer plano. Verificando conexión...")
		_forzar_verificacion_red()

func _forzar_verificacion_red():
	socket.poll()
	var state = socket.get_ready_state()
	if state != WebSocketPeer.STATE_OPEN:
		print("Conexión fantasma detectada. Reseteando...")
		_limpiar_y_reconnect()

func _limpiar_y_reconnect():
	socket.close()
	conectado = false
	label_estado.text = "Desconectado"
	if timer_reconexion.is_stopped():
		timer_reconexion.start()

# ═══════════════════════════════════════════
# ENVIAR COMANDOS
# ═══════════════════════════════════════════
func enviar_comando(comando: String):
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(comando)
		print("Enviado: ", comando)
	else:
		print("No conectado al ESP32")

# ═══════════════════════════════════════════
# ⚡ STUBS — RELLENÁ CON TUS COMANDOS
# ═══════════════════════════════════════════

func _on_joystick_movido(direccion: Vector2):
	# TODO: Elegí qué enviar según la dirección del joystick
	# Ej: enviar_comando("MOVER " + str(direccion))
	enviar_comando("MOVER " + str(direccion))
	pass

func _on_joystick_soltado():
	# TODO: Comando cuando se suelta el joystick (ej: "STOP")
	enviar_comando("STOP")
	pass

func _on_boton_accion():
	# TODO: Comando del botón de acción extra
	enviar_comando("ACCION")
	pass
