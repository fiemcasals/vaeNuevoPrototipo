extends Area3D

@export var speed_modifier:float=1.0
@export var Area:CollisionShape3D=null
@export var CuerpoFisico:CollisionShape3D=null
@onready var cuerpo: StaticBody3D = $Cuerpo

func _ready() -> void:
	if CuerpoFisico:
		remove_child(CuerpoFisico)
		cuerpo.add_child(CuerpoFisico)


func _on_body_entered(body: Node3D) -> void:
	if body is Rover:
		print("dentro")
		body.speed_modifier=speed_modifier



func _on_body_exited(body: Node3D) -> void:
	if body is Rover:
		print("fuera")
		body.speed_modifier=1
