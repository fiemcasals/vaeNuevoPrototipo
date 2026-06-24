extends Area3D

@export var slow_factor: float = 0.3
@export var max_speed_in_mud: float = 5.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body is VehicleBody3D and body.has_method("add_mud_zone"):
		body.add_mud_zone(self)
		print("Rover entró en zona pesada")

func _on_body_exited(body: Node3D) -> void:
	if body is VehicleBody3D and body.has_method("remove_mud_zone"):
		body.remove_mud_zone(self)
		print("Rover salió de zona pesada")
