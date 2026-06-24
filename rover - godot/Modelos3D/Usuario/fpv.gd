extends Camera3D

func _ready() -> void:
	SignalBus.change_cam.connect(change_state)

func change_state(cam:int):
	if cam==1:
		current=true
	if cam==3:
		current=false
