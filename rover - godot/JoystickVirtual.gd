extends Control

signal joystick_movido(direccion: Vector2)
signal joystick_soltado()

var radio := 140.0
var radio_thumb := 55.0
var direccion := Vector2.ZERO
var activo := false
var touch_index := -1
var usando_mouse := false

@onready var base: ColorRect = $Base
@onready var aro: ColorRect = $Aro
@onready var thumb: ColorRect = $Thumb
@onready var cruz_h: ColorRect = $Thumb/CruzH
@onready var cruz_v: ColorRect = $Thumb/CruzV
@onready var eje_h: ColorRect = $EjeH
@onready var eje_v: ColorRect = $EjeV


func _ready():
	# Ignorar eventos en los hijos visuales para que lleguen al JoystickArea
	for child in get_children():
		child.mouse_filter = MOUSE_FILTER_IGNORE
	call_deferred("_posicionar_todo")


func _posicionar_todo():
	var centro = size / 2.0
	var diam = radio * 2.0
	var diam_thumb = radio_thumb * 2.0

	base.size = Vector2(diam, diam)
	base.position = centro - Vector2(radio, radio)

	aro.size = Vector2(diam + 4, diam + 4)
	aro.position = centro - Vector2(radio + 2, radio + 2)

	eje_h.size = Vector2(diam, 2.0)
	eje_h.position = centro - Vector2(radio, 1.0)

	eje_v.size = Vector2(2.0, diam)
	eje_v.position = centro - Vector2(1.0, radio)

	thumb.size = Vector2(diam_thumb, diam_thumb)
	_posicionar_thumb()

	cruz_h.size = Vector2(diam_thumb * 0.6, 3.0)
	cruz_h.position = Vector2(diam_thumb * 0.2, diam_thumb / 2.0 - 1.5)

	cruz_v.size = Vector2(3.0, diam_thumb * 0.6)
	cruz_v.position = Vector2(diam_thumb / 2.0 - 1.5, diam_thumb * 0.2)


func _posicionar_thumb():
	var centro = size / 2.0
	var desplazamiento = direccion * (radio - radio_thumb)
	thumb.position = centro - Vector2(radio_thumb, radio_thumb) + desplazamiento

	var col = Color(0.0, 0.55, 0.9, 0.9) if activo else Color(0.2, 0.5, 0.85, 0.7)
	thumb.color = col


func _process(_delta):
	if activo and usando_mouse:
		_actualizar(get_local_mouse_position())


func _gui_input(event):
	var centro = size / 2.0

	# ── Mouse (PC) ──
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		print("Mouse event: " + str(event))
		if event.pressed:
			if (event.position - centro).length() <= radio * 1.3:
				activo = true
				usando_mouse = true
				_actualizar(event.position)
		else:
			if activo and usando_mouse:
				activo = false
				usando_mouse = false
				direccion = Vector2.ZERO
				joystick_soltado.emit()
				_posicionar_thumb()

	# ── Touch (móvil) ──
	elif event is InputEventScreenTouch:
		if event.pressed and event.index == 0:
			if (event.position - centro).length() <= radio * 1.3:
				activo = true
				usando_mouse = false
				touch_index = event.index
				_actualizar(event.position)
		elif not event.pressed and event.index == touch_index:
			activo = false
			usando_mouse = false
			touch_index = -1
			direccion = Vector2.ZERO
			joystick_soltado.emit()
			_posicionar_thumb()

	elif event is InputEventScreenDrag and event.index == touch_index:
		if activo:
			_actualizar(event.position)


func _actualizar(pos: Vector2):
	var centro = size / 2.0
	var offset = pos - centro
	var dist = offset.length()
	if dist > radio:
		offset = offset.normalized() * radio
	direccion = offset / radio
	joystick_movido.emit(direccion)
	_posicionar_thumb()


func _on_resized():
	_posicionar_todo()
