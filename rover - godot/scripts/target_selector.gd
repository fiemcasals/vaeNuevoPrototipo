extends Control

signal target_selected(target_data: Dictionary)
signal cancelled

@onready var title_label = $PanelContainer/VBoxContainer/Title
@onready var list_container = $PanelContainer/VBoxContainer/ScrollContainer/ListContainer
@onready var cancel_button = $PanelContainer/VBoxContainer/CancelButton

func _ready():
	visible = false
	cancel_button.pressed.connect(_on_cancel_pressed)

func show_targets(targets: Array):
	_clear_list()
	
	if targets.is_empty():
		_add_label("No hay puntos de interés disponibles")
	else:
		for target in targets:
			_create_target_button(target)
	
	visible = true

func _clear_list():
	for child in list_container.get_children():
		child.queue_free()

func _add_label(text: String):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_container.add_child(label)

func _create_target_button(target_data: Dictionary):
	var button = Button.new()
	button.text = target_data["name"]
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(_on_target_button_pressed.bind(target_data))
	list_container.add_child(button)

func _on_target_button_pressed(target_data: Dictionary):
	visible = false
	target_selected.emit(target_data)

func _on_cancel_pressed():
	visible = false
	cancelled.emit()

func _input(event: InputEvent):
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		cancelled.emit()
