extends Control

@export var vehicle: VehicleBody3D = null
@export var min_angle: float = -124.0
@export var max_angle: float = 240.0
@export var max_speed: float = 120.0  # adjust to match your speedometer's max km/h label
@export var speed_text:String
@export var Visor_Vel:RichTextLabel
func _process(delta: float) -> void:
	if not vehicle:
		return
	var speed_ms = vehicle.linear_velocity.length()
	var speed_kmh = speed_ms * 3.6
	rotation_degrees = remap(clamp(speed_kmh, 0.0, max_speed), 0.0, max_speed, -125, 125)
	Visor_Vel.text="[center][b]%d"%[speed_kmh]
