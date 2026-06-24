extends Camera3D

@export var target: Node3D = null
@export var lerp_speed: float = 3.0
@export var offset: Vector3 = Vector3(0, 1, -2)

func _ready() -> void:
	SignalBus.change_cam.connect(change_state)

func _physics_process(delta: float) -> void:
	if not target:
		return
	var target_xform = target.global_transform.translated_local(offset)
	global_transform = global_transform.interpolate_with(target_xform, lerp_speed * delta)
	look_at(target.global_transform.origin, Vector3.UP)

func change_state(cam:int):
	if cam == 0:
		current = false
	elif cam == 1:
		current = true
