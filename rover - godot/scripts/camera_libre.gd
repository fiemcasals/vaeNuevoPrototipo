extends Camera3D

@export var move_speed: float = 12.0
@export var look_sensitivity: float = 0.0025
@export var fast_multiplier: float = 2.5

var rotation_x: float = 0.0
var rotation_y: float = 0.0
var is_rotating: bool = false

func _ready():
	rotation_x = rotation.x
	rotation_y = rotation.y

func _input(event: InputEvent) -> void:
	if not current:
		return
		
	# Rotación usando click derecho sostenido del mouse
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			if is_rotating:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				
	if event is InputEventMouseMotion and is_rotating:
		rotation_y -= event.relative.x * look_sensitivity
		rotation_x -= event.relative.y * look_sensitivity
		rotation_x = clamp(rotation_x, -deg_to_rad(85.0), deg_to_rad(85.0))
		
		rotation = Vector3(rotation_x, rotation_y, 0.0)

func _process(delta: float) -> void:
	if not current:
		return
		
	var speed = move_speed
	# SHIFT para movimiento rápido
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
		
	var direction = Vector3.ZERO
	
	# Controles WASD / Flechas para movimiento horizontal
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction += global_transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += global_transform.basis.x
		
	# Controles E / Q o Espacio / Control para subir o bajar verticalmente
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		direction -= Vector3.UP
		
	if direction.length_squared() > 0.0:
		global_position += direction.normalized() * speed * delta
