extends Node

var socket = WebSocketPeer.new()
var url = "ws://10.24.206.226:81" # <-- Reemplaza con la IP de tu ESP
var conectado = false
@onready var label_estado: Label = $Label
@onready var timer_reconexion: Timer = $TimerReconexion
func _ready() -> void:
	print("Conectando al ESP...")
	var err = socket.connect_to_url(url)
	if err != OK:
		print("No se pudo iniciar la conexión: ", err)
		set_process(false)
	timer_reconexion.timeout.connect(_intentar_conexion)
	_intentar_conexion()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		print("La app volvió a primer plano. Verificando estado real...")
		_forzar_verificacion_red()

func _forzar_verificacion_red() -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state != WebSocketPeer.STATE_OPEN:
		print("Conexión fantasma detectada tras minimizar. Reseteando...")
		_limpiar_y_reconnect()

func _limpiar_y_reconnect() -> void:
	socket.close()
	conectado = false
	if timer_reconexion.is_stopped():
		timer_reconexion.start()

func _intentar_conexion() -> void:
	var state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		print("Intentando conectar al ESP...")
		var err = socket.connect_to_url(url)
		if err != OK:
			print("Error al iniciar conexión. Reintentando en 3 segundos...")
			timer_reconexion.start()

func _process(_delta: float) -> void:
	socket.poll() # Requerido para mantener vivo el socket y recibir eventos
	
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not conectado:
			conectado = true
			print("¡Conectado exitosamente!")
			timer_reconexion.stop() # Frenamos el timer de reconexión
		# Si hay paquetes esperando, los leemos
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var mensaje = packet.get_string_from_utf8()
			print("Respuesta del ESP: ", mensaje)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if conectado:
			conectado = false
			print("Se perdió la conexión. Iniciando bucle de reconexión...")
		
		# Si el timer no está corriendo, lo activamos para que reintente en 3 segundos
		if timer_reconexion.is_stopped():
			timer_reconexion.start()
		var code = socket.get_close_code()
		var reason = socket.get_close_reason()
		print("Conexión cerrada. Código: %d, Razón: %s" % [code, reason])
		#set_process(false)

	# Mostrar el estado actual en la pantalla del celular
	if state == WebSocketPeer.STATE_CONNECTING:
		label_estado.text = "Estado: Conectando..."
	elif state == WebSocketPeer.STATE_OPEN:
		label_estado.text = "Estado: ¡CONECTADO!"
	elif state == WebSocketPeer.STATE_CLOSED:
		label_estado.text = "Estado: Conexión cerrada"


# Función para enviar comandos desde Godot (puedes conectarla a un Botón)
func enviar_comando(comando: String) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(comando)
		print("Enviado: ", comando)
	else:
		print("No estás conectado al ESP.")

# Ejemplo de prueba con una tecla
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"): # Tecla Enter / Espacio
		enviar_comando("ENCENDER")


func _on_button_pressed() -> void:
	enviar_comando("ENCENDER")


func _on_buttonmsg_1_pressed() -> void:
	enviar_comando("1")
