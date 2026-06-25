extends Node
class_name RoverAutoController

@export var rover: VehicleBody3D
@export var navigation: NavigationSystem
@export var arrival_threshold: float = 1.2
@export var max_speed: float = 15.0
@export var rotation_speed: float = 5.0

@export_group("Remote Brain")
@export var use_remote_logic: bool = true
@export var remote_url: String = "ws://localhost:8767"

var is_active: bool = false
var target_position: Vector3 = Vector3.ZERO
var modified_path_positions: Array[Vector3] = []
var is_corner_waypoint: Array[bool] = []
var raw_grid_positions: Array[Vector3] = []
var is_actual_corner: Array[bool] = []
var current_waypoint_index: int = 0

var _ws_client: WebSocketPeer = WebSocketPeer.new()
var _ws_connected: bool = false
var _target_point_from_server: Vector3 = Vector3.ZERO

signal navigation_started
signal navigation_stopped(interrupted: bool)
signal waypoint_reached

func _ready():
	set_physics_process(false)
	# Cargar configuración desde RoverConfig
	if RoverConfig:
		max_speed = RoverConfig.velocidad_maxima * 0.5  # Aumentar velocidad máxima al 50% para mayor velocidad en rectas

func start():
	is_active = true
	if rover:
		rover.auto_controlled = true # Habilitar piloto automático
		rover.engine_force = 0.0
		rover.brake = 0.0
		rover.steering = 0.0
	
	_generate_lane_split_path()
	current_waypoint_index = 0
	
	# Cambiar el color del visualizador a verde
	var path_visualizer = get_node_or_null("../PathVisualizer")
	if path_visualizer and path_visualizer.has_method("set_color"):
		path_visualizer.set_color(Color.GREEN)
		
	if use_remote_logic:
		_ws_connected = false
		var err = _ws_client.connect_to_url(remote_url)
		if err == OK:
			print("[Autopilot] Conectando a servidor de lógica remota en ", remote_url)
		else:
			print("[Autopilot] Error al conectar a la lógica remota. Usando modo local.")
			use_remote_logic = false
			
	set_physics_process(true)
	navigation_started.emit()
	print("[Autopilot] Control automático activo.")

func stop(interrupted: bool = true):
	is_active = false
	set_physics_process(false)
	
	if use_remote_logic and _ws_connected:
		var message = {"type": "stop"}
		_ws_client.send_text(JSON.stringify(message))
		_ws_client.close()
		_ws_connected = false
		
	modified_path_positions.clear()
	is_corner_waypoint.clear()
	raw_grid_positions.clear()
	is_actual_corner.clear()
	current_waypoint_index = 0
	if rover:
		rover.auto_controlled = false
		rover.engine_force = 0.0
		rover.brake = 30.0
		rover.steering = 0.0
			
	var path_visualizer = get_node_or_null("../PathVisualizer")
	if path_visualizer and path_visualizer.has_method("clear"):
		path_visualizer.clear()
		
	if navigation:
		navigation.stop_navigation()
		
	navigation_stopped.emit(interrupted)
	print("[Autopilot] Desactivado.")

func _is_cell_walkable(col: int, row: int) -> bool:
	if not navigation:
		return false
	if row < 0 or row >= navigation.grid_rows or col < 0 or col >= navigation.grid_cols:
		return false
	return navigation.grid_weights[row][col] < 999999

func _get_lane_shift(cell: Vector2i, dir: Vector2) -> Vector3:
	var perp = Vector2(-dir.y, dir.x) # Perpendicular a la derecha
	
	# Contar celdas caminables a la derecha (camino ancho)
	var right_count = 0
	var check_cell = cell + Vector2i(round(perp.x), round(perp.y))
	while _is_cell_walkable(check_cell.x, check_cell.y):
		# Evitar contar calles cruzadas (intersecciones) como parte del ancho de este camino
		var ahead = check_cell + Vector2i(round(dir.x), round(dir.y))
		var behind = check_cell - Vector2i(round(dir.x), round(dir.y))
		if _is_cell_walkable(ahead.x, ahead.y) or _is_cell_walkable(behind.x, behind.y):
			right_count += 1
			check_cell += Vector2i(round(perp.x), round(perp.y))
		else:
			break
		if right_count > 10: break
		
	# Contar celdas caminables a la izquierda
	var left_count = 0
	var check_cell_l = cell - Vector2i(round(perp.x), round(perp.y))
	while _is_cell_walkable(check_cell_l.x, check_cell_l.y):
		# Evitar contar calles cruzadas (intersecciones) como parte del ancho de este camino
		var ahead = check_cell_l + Vector2i(round(dir.x), round(dir.y))
		var behind = check_cell_l - Vector2i(round(dir.x), round(dir.y))
		if _is_cell_walkable(ahead.x, ahead.y) or _is_cell_walkable(behind.x, behind.y):
			left_count += 1
			check_cell_l -= Vector2i(round(perp.x), round(perp.y))
		else:
			break
		if left_count > 10: break
		
	var total_road_width = 1 + right_count + left_count
	var road_width_m = total_road_width * navigation.tile_spacing
	var vehicle_width = RoverConfig.ancho_vehiculo if RoverConfig else 2.0
	
	# Calcular el centro de la calle y el desplazamiento hacia la derecha deseado (centro de la mitad derecha)
	var road_center_offset = (right_count - left_count) * 0.5
	var desired_shift_m = road_width_m * 0.25
	
	# Limitar el desplazamiento para asegurar el margen de seguridad respecto al borde derecho
	var safety_margin = RoverConfig.margen_seguridad if RoverConfig else 0.5
	var max_shift_m = (road_width_m - vehicle_width - 2.0 * safety_margin) * 0.5
	max_shift_m = max(0.0, max_shift_m)
	
	var shift_from_center = min(desired_shift_m, max_shift_m) / navigation.tile_spacing
	var offset_cells = road_center_offset + shift_from_center
		
	return Vector3(perp.x, 0, perp.y) * offset_cells * navigation.tile_spacing

func _generate_lane_split_path():
	modified_path_positions.clear()
	is_corner_waypoint.clear()
	raw_grid_positions.clear()
	is_actual_corner.clear()
	
	var path = navigation.current_path
	if path.size() == 0:
		return
		
	var raw_positions: Array[Vector3] = []
	
	for i in range(path.size()):
		var cell_curr = path[i]
		var final_pos: Vector3
		
		if i == 0:
			if rover:
				final_pos = rover.global_position
			else:
				var dir = Vector2.UP
				if path.size() > 1:
					dir = Vector2(path[1] - path[0]).normalized()
				var shift = _get_lane_shift(cell_curr, dir)
				final_pos = navigation.grid_to_world(cell_curr) + shift
		elif i == path.size() - 1:
			var dir = Vector2(path[i] - path[i-1]).normalized()
			var shift = _get_lane_shift(cell_curr, dir)
			final_pos = navigation.grid_to_world(cell_curr) + shift
		else:
			var dir_prev = Vector2(path[i] - path[i-1]).normalized()
			var dir_next = Vector2(path[i+1] - path[i]).normalized()
			
			if dir_prev == dir_next:
				var shift = _get_lane_shift(cell_curr, dir_prev)
				final_pos = navigation.grid_to_world(cell_curr) + shift
			else:
				# ¡Esquina! Calcular la intersección geométrica de los dos carriles (previo y siguiente)
				# para evitar recortar la esquina hacia el interior.
				var shift_prev = _get_lane_shift(cell_curr, dir_prev)
				var shift_next = _get_lane_shift(cell_curr, dir_next)
				
				var world_center = navigation.grid_to_world(cell_curr)
				var pos_prev = world_center + shift_prev
				var pos_next = world_center + shift_next
				
				# Tomamos el X del carril del tramo vertical y el Z del carril del tramo horizontal
				var final_x = pos_prev.x if abs(dir_prev.y) > 0.1 else pos_next.x
				var final_z = pos_prev.z if abs(dir_prev.x) > 0.1 else pos_next.z
				
				final_pos = Vector3(final_x, world_center.y, final_z)
				
		raw_positions.append(final_pos)
		
	# Acortar el último segmento para detenerse antes del destino final
	if raw_positions.size() >= 2:
		var last_idx = raw_positions.size() - 1
		var segment = raw_positions[last_idx] - raw_positions[last_idx - 1]
		var segment_len = segment.length()
		var dir = segment.normalized()
		# Evitamos retroceder más del 50% del segmento si este fuera muy corto
		var shorten_dist = min(1.0, segment_len * 0.5)
		raw_positions[last_idx] = raw_positions[last_idx] - dir * shorten_dist
		
	# 1. Detectar esquinas sobre raw_positions ANTES del suavizado
	is_corner_waypoint.resize(raw_positions.size())
	is_corner_waypoint.fill(false)
	
	is_actual_corner.resize(raw_positions.size())
	is_actual_corner.fill(false)
	
	raw_grid_positions.resize(path.size())
	for i in range(path.size()):
		raw_grid_positions[i] = navigation.grid_to_world(path[i])
		
	for i in range(1, raw_positions.size() - 1):
		var v1 = (raw_positions[i] - raw_positions[i-1]).normalized()
		var v2 = (raw_positions[i+1] - raw_positions[i]).normalized()
		var dot = v1.dot(v2)
		if dot < 0.9:
			is_actual_corner[i] = true
			is_corner_waypoint[i] = true
			is_corner_waypoint[i-1] = true # Pre-frenar en el anterior
			if i + 1 < raw_positions.size():
				is_corner_waypoint[i+1] = true # Mantener frenado al salir de la esquina
		
	# 2. Aplicar filtro de suavizado binomial para redondear las transiciones rectilíneas,
	# pero preservamos los vértices exactos de las esquinas intactos para que no se recorten.
	modified_path_positions = _smooth_path_preserving_corners(raw_positions, is_actual_corner, 1)

func _smooth_path_preserving_corners(points: Array[Vector3], corners: Array[bool], passes: int = 1) -> Array[Vector3]:
	if points.size() < 3:
		return points
		
	var current = points.duplicate()
	for pass_idx in range(passes):
		var next_points: Array[Vector3] = []
		next_points.append(current[0])
		
		for i in range(1, current.size() - 1):
			if corners[i]:
				# Si es una esquina física, la mantenemos intacta (carril externo completo de giro)
				next_points.append(current[i])
			else:
				var prev = current[i-1]
				var curr = current[i]
				var nxt = current[i+1]
				var smoothed = prev * 0.25 + curr * 0.5 + nxt * 0.25
				next_points.append(smoothed)
				
		next_points.append(current[current.size() - 1])
		current = next_points
		
	return current

func _physics_process(delta: float):
	if not is_active or not rover or modified_path_positions.size() == 0:
		return
		
	if use_remote_logic:
		_ws_client.poll()
		var ws_state = _ws_client.get_ready_state()
		
		if ws_state == WebSocketPeer.STATE_OPEN:
			if not _ws_connected:
				_ws_connected = true
				print("[Autopilot] Conectado a la lógica remota. Enviando ruta...")
				_send_path_to_remote()
				
			_send_telemetry_to_remote()
			_read_orders_from_remote(delta)
			
		elif ws_state == WebSocketPeer.STATE_CLOSED:
			if _ws_connected:
				_ws_connected = false
				print("[Autopilot] Conexión cerrada con la lógica remota. Reintentando...")
			_ws_client.connect_to_url(remote_url)
			
		elif ws_state == WebSocketPeer.STATE_CONNECTING:
			pass
			
		_draw_visuals()
	else:
		_run_local_control(delta)

func _send_path_to_remote():
	if modified_path_positions.size() == 0:
		return
	var path_data = []
	for i in range(modified_path_positions.size()):
		var pos = modified_path_positions[i]
		var is_corner = 0.4 if is_actual_corner[i] else 0.0
		path_data.append({
			"x": pos.x,
			"z": pos.z,
			"steer": is_corner,
			"direction": 1
		})
	var message = {
		"type": "set_path",
		"path": path_data
	}
	_ws_client.send_text(JSON.stringify(message))

func _send_telemetry_to_remote():
	var forward_basis = -rover.global_transform.basis.z
	var linear_vel = rover.linear_velocity
	var speed_val = linear_vel.length()
	if linear_vel.dot(forward_basis) < 0:
		speed_val = -speed_val
		
	var message = {
		"type": "telemetry",
		"x": rover.global_position.x,
		"z": rover.global_position.z,
		"yaw": rover.global_rotation.y,
		"speed": speed_val,
		"config": {
			"wheelbase": RoverConfig.distancia_entre_ejes if RoverConfig else 2.0,
			"torque": RoverConfig.torque if RoverConfig else 300.0,
			"max_speed": max_speed
		}
	}
	_ws_client.send_text(JSON.stringify(message))

func _read_orders_from_remote(delta: float):
	while _ws_client.get_available_packet_count() > 0:
		var packet = _ws_client.get_packet()
		var msg_str = packet.get_string_from_utf8()
		var json = JSON.new()
		var err = json.parse(msg_str)
		if err == OK:
			var data = json.get_data()
			if data.has("type") and data["type"] == "orders":
				if data.has("completed") and data["completed"]:
					print("[Autopilot] Destino alcanzado (Lógica Remota).")
					stop(false)
					if navigation:
						navigation.target_reached.emit()
					return
					
				var target_steering = data.get("steering", 0.0)
				var engine_force = data.get("engine_force", 0.0)
				var brake = data.get("brake", 0.0)
				
				# Apply steering with actuator speed limits
				var steering_speed = 4.0
				rover.steering = move_toward(rover.steering, target_steering, steering_speed * delta)
				
				# Apply forces
				rover.engine_force = engine_force
				rover.brake = brake
				
				# Update indices & visual targets
				if data.has("current_waypoint_index"):
					current_waypoint_index = int(data["current_waypoint_index"])
				if data.has("target_point") and data["target_point"] != null:
					var pt = data["target_point"]
					_target_point_from_server = Vector3(pt["x"], rover.global_position.y, pt["z"])
					target_position = _target_point_from_server

func _draw_visuals():
	var points = PackedVector3Array()
	points.append(rover.global_position)
	
	for i in range(current_waypoint_index, modified_path_positions.size()):
		points.append(modified_path_positions[i])
		
	var path_visualizer = get_node_or_null("../PathVisualizer")
	if path_visualizer:
		if path_visualizer.has_method("draw_path"):
			path_visualizer.draw_path(points)
		if path_visualizer.has_method("draw_corners"):
			var corner_points = PackedVector3Array()
			for i in range(current_waypoint_index, raw_grid_positions.size()):
				if is_actual_corner[i]:
					corner_points.append(raw_grid_positions[i])
			path_visualizer.draw_corners(corner_points)

func _run_local_control(delta: float):
	# 1. Obtener el waypoint actual
	if current_waypoint_index < modified_path_positions.size():
		target_position = modified_path_positions[current_waypoint_index]
	else:
		stop(false)
		if navigation:
			navigation.target_reached.emit()
		return
		
	var distance_to_target = _get_horizontal_distance(rover.global_position, target_position)
	var distance_to_final = _get_horizontal_distance(rover.global_position, modified_path_positions[modified_path_positions.size() - 1])
	
	# 2. Si estamos cerca del waypoint actual o ya lo pasamos, avanzar al siguiente
	var current_threshold = arrival_threshold
	if current_waypoint_index < is_corner_waypoint.size() and is_corner_waypoint[current_waypoint_index]:
		current_threshold = 1.5
		
	var has_passed = false
	if current_waypoint_index > 0 and current_waypoint_index < modified_path_positions.size():
		var prev_pt = modified_path_positions[current_waypoint_index - 1]
		var curr_pt = modified_path_positions[current_waypoint_index]
		var segment_dir = (curr_pt - prev_pt).normalized()
		var to_vehicle = (rover.global_position - curr_pt)
		segment_dir.y = 0
		to_vehicle.y = 0
		if to_vehicle.dot(segment_dir) > 0:
			has_passed = true
			
	if distance_to_target < current_threshold or has_passed:
		current_waypoint_index += 1
		waypoint_reached.emit()
		
		if current_waypoint_index < modified_path_positions.size():
			target_position = modified_path_positions[current_waypoint_index]
		else:
			stop(false)
			if navigation:
				navigation.target_reached.emit()
			return
			
		distance_to_target = _get_horizontal_distance(rover.global_position, target_position)
		distance_to_final = _get_horizontal_distance(rover.global_position, modified_path_positions[modified_path_positions.size() - 1])
		
	# 3. Autopilot: Conducir físicamente hacia el waypoint actual
	_steer_towards_target(delta)
	_drive_forward(distance_to_final)
	
	# 4. Dibujar
	_draw_visuals()

func _get_horizontal_distance(from: Vector3, to: Vector3) -> float:
	var diff = to - from
	diff.y = 0
	return diff.length()

func _steer_towards_target(delta: float):
	var wheelbase = RoverConfig.distancia_entre_ejes if RoverConfig else 2.0
	var speed = rover.linear_velocity.length()
	var lookahead_dist = max(3.0, speed * 0.4 + 2.0)
	
	var next_corner_idx = -1
	for k in range(current_waypoint_index, modified_path_positions.size()):
		if is_actual_corner[k]:
			next_corner_idx = k
			break
			
	var steering_target = target_position
	for i in range(current_waypoint_index, modified_path_positions.size()):
		if next_corner_idx != -1 and i > next_corner_idx:
			break
		var pt = modified_path_positions[i]
		var dist = _get_horizontal_distance(rover.global_position, pt)
		if dist >= lookahead_dist:
			steering_target = pt
			break
			
	var rear_axle_transform = rover.global_transform.translated_local(Vector3(0, 0, -wheelbase * 0.5))
	var local_target = rear_axle_transform.affine_inverse() * steering_target
	var distance_squared = local_target.x * local_target.x + local_target.z * local_target.z
	
	var target_steering = 0.0
	if distance_squared > 0.01:
		target_steering = atan2(2.0 * wheelbase * local_target.x, distance_squared)
		
	var max_steering_rad = deg_to_rad(30.0)
	target_steering = clamp(target_steering, -max_steering_rad, max_steering_rad)
	
	var steering_speed = 4.0
	rover.steering = move_toward(rover.steering, target_steering, steering_speed * delta)

func _drive_forward(distance_to_final: float):
	var speed = rover.linear_velocity.length()
	var in_mud = rover.mud_zones.size() > 0
	var current_max_speed = 5.0 if in_mud else max_speed
	var engine_multiplier = 0.3 if in_mud else 1.0
	var current_power = RoverConfig.torque if RoverConfig else 300.0
	
	var target_speed = current_max_speed
	var approaching_corner = false
	for k in range(current_waypoint_index, min(current_waypoint_index + 3, modified_path_positions.size())):
		if is_corner_waypoint[k]:
			approaching_corner = true
			break
			
	if approaching_corner:
		target_speed = min(target_speed, 3.2)
		
	var braking_distance = 12.0
	if distance_to_final < braking_distance:
		var speed_factor = distance_to_final / braking_distance
		target_speed = min(target_speed, current_max_speed * speed_factor * speed_factor)
	
	target_speed = max(target_speed, 0.5)
	var acceleration_force = current_power * 2.0 * engine_multiplier
	
	if speed < target_speed:
		rover.engine_force = acceleration_force
		rover.brake = 0.0
	else:
		rover.engine_force = 0.0
		var brake_strength = 10.0 + (speed - target_speed) * 2.0
		rover.brake = min(brake_strength, 35.0)
