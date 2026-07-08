extends CharacterBody3D

@export var Current_Target:Node3D
@export var Pivot_Target:Node3D
@export var Power:float=1
@export var Navigator:NavigationAgent3D
@export var Rotation_Speed: float = 8.0
@export var Acceleration: float = 4.0  # how fast it speeds up
@export var Friction: float = 6.0      # how fast it slows down
var turning_dir: float = 0.0
var movement: float = 0.0
var current_speed := 0.0 
@onready var wheel_pivot: Node3D = $WheelPivot
@onready var wheel_pivot_2: Node3D = $WheelPivot2

func _ready() -> void:
	Navigator.target_position=Current_Target.global_position

#func _physics_process(delta: float) -> void:
	#Pivot_Target.global_position = global_position
	#if not is_on_floor():
		#velocity.y -= 9.8 * delta
	#turning_dir=Input.get_axis("turn_left","turn_right")
	#movement=Input.get_axis("forward","backward")
	#if turning_dir!=0.0:
		#
		#Pivot_Target.rotation.y=Pivot_Target.rotation.y-turning_dir*delta
		#Pivot_Target.rotation.y=clampf(Pivot_Target.rotation.y,-0.7,0.7)
		#wheel_pivot.rotation.y=Pivot_Target.rotation.y
		#wheel_pivot_2.rotation.y=Pivot_Target.rotation.y
	#else:
		#Pivot_Target.rotation.y=lerp(Pivot_Target.rotation.y,0.0,0.009)
	#Navigator.target_position = Current_Target.global_position
	#var next_pos: Vector3 = Navigator.get_next_path_position()
	#var direction: Vector3 = next_pos - global_position
	## Rotate drone to face target (yaw only)
	#if direction.length() > 0.1 and movement !=0.0:
		#var target_yaw := atan2(direction.x, direction.z)
		#var angle_diff := angle_difference(rotation.y, target_yaw)
	## Only rotate if the difference is noticeable
		#if abs(angle_diff) > 0.05:
			## Clamp the rotation step so it can never snap more than X radians per frame
			#var max_turn := Rotation_Speed * delta
			#var clamped_diff = clampf(angle_diff, -max_turn, max_turn)
			#rotation.y += clamped_diff
	#if movement != 0.0:
		#current_speed = lerp(current_speed, movement * Power, Acceleration * delta)
	#else:
		#current_speed = lerp(current_speed, 0.0, Friction * delta)
	#velocity.x = -transform.basis.z.x * current_speed
	#velocity.z = -transform.basis.z.z * current_speed
	#
	#move_and_slide()



func _on_navigation_agent_3d_navigation_finished() -> void:
	print("yes")
