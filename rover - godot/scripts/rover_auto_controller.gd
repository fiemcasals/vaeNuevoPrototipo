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

# Logger variables
var _last_logged_pos: Vector3 = Vector3.ZERO
var _last_logged_speed: float = 0.0
var _last_logged_steer: float = 0.0
var _last_logged_engine_force: float = 0.0
var _last_logged_brake: float = 0.0
var _total_time: float = 0.0

# Remote Brain variables
var _reconnect_timer: float = 0.0
var _pending_level_init: bool = false
var _cached_tiles: Array = []
var _cached_spacing: float = 4.0
var _cached_path_payload: Array = []
var _python_pid: int = -1

signal remote_path_received(path: Array)
signal remote_path_failed
signal navigation_started
signal navigation_stopped(interrupted: bool)
signal waypoint_reached

func _ready():
	# Cargar configuración desde RoverConfig
	if RoverConfig:
		max_speed = RoverConfig.velocidad_maxima * 0.5  # Aumentar velocidad máxima al 50% para mayor velocidad en rectas
	
	set_process(true)
	set_physics_process(false)
	
	if use_remote_logic:
		_launch_python_brain()
		get_tree().create_timer(1.5).timeout.connect(_connect_to_server)

func _process(delta: float):
	if not use_remote_logic:
		return
		
	_ws_client.poll()
	var state = _ws_client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_connected:
			_ws_connected = true
			print("[Autopilot] Conexión establecida con el cerebro de pps-vae.")
			_send_level_init()
			if is_active and not _cached_path_payload.is_empty():
				_re_send_path()
				
		_read_messages_from_server(delta)
		
	elif state == WebSocketPeer.STATE_CLOSED:
		if _ws_connected:
			_ws_connected = false
			print("[Autopilot] Se perdió la conexión con el cerebro de pps-vae. Reintentando...")
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_reconnect_timer = 3.0
			_connect_to_server()

func _connect_to_server():
	print("[Autopilot] Conectando al cerebro pps-vae en ", remote_url)
	_ws_connected = false
	var err = null
	if (_ws_client.get_ready_state() == WebSocketPeer.STATE_CLOSED || _ws_client.get_ready_state() == WebSocketPeer.STATE_CLOSING):
		print("[Autopilot] Cerrando conexión WebSocket existente...")
		err = _ws_client.connect_to_url(remote_url)
	if err != OK:
		print("[Autopilot] Error al intentar iniciar conexión WebSocket: ", err)

func _launch_python_brain():
	var script_path = ProjectSettings.globalize_path("res://scripts/py/logic_system.py")
	var python_exe = "python"
	
	_python_pid = OS.create_process(python_exe, [script_path])
	if _python_pid > 0:
		print("[Autopilot] Cerebro pps-vae lanzado automáticamente (PID: %d)" % _python_pid)
	else:
		print("[Autopilot] Error: No se pudo lanzar el cerebro pps-vae. Ejecutalo manualmente: python %s" % script_path)

func _exit_tree():
	if _python_pid > 0:
		OS.kill(_python_pid)
		print("[Autopilot] Cerebro pps-vae detenido (PID: %d)" % _python_pid)

func is_connected_to_brain() -> bool:
	return _ws_connected

func init_remote_level(tiles: Array, spacing: float):
	_cached_tiles = tiles
	_cached_spacing = spacing
	_pending_level_init = true
	if _ws_connected:
		_send_level_init()

func _send_level_init():
	if _cached_tiles.is_empty():
		return
	var message = {
		"type": "init_level",
		"tiles": _cached_tiles,
		"tile_spacing": _cached_spacing
	}
	_ws_client.send_text(JSON.stringify(message))
	_pending_level_init = false
	print("[Autopilot] Cuadrícula del nivel enviada al cerebro pps-vae.")

func _re_send_path():
	if _cached_path_payload.is_empty():
		return
	var override_msg = {
		"type": "set_path",
		"path": _cached_path_payload
	}
	_ws_client.send_text(JSON.stringify(override_msg))
	print("[Autopilot] Ruta reenviada al cerebro de pps-vae tras reconexión.")

func request_remote_path(start_pos: Vector3, target_pos: Vector3, heading: float):
	if not _ws_connected:
		print("[Autopilot] Error: No conectado al cerebro pps-vae. Reintentando...")
		_connect_to_server()
		remote_path_failed.emit()
		return
		
	var server_heading = heading + PI
	while server_heading > PI:
		server_heading -= 2.0 * PI
	while server_heading <= -PI:
		server_heading += 2.0 * PI
		
	var message = {
		"type": "calculate_path",
		"start": { "x": start_pos.x, "z": start_pos.z, "heading": server_heading },
		"goal": { "x": target_pos.x, "z": target_pos.z }
	}
	_ws_client.send_text(JSON.stringify(message))
	print("[Autopilot] Solicitando cálculo de ruta al cerebro pps-vae...")

func start():
	is_active = true
	_total_time = 0.0
	_last_logged_pos = Vector3.ZERO
	_last_logged_speed = 0.0
	_last_logged_steer = 0.0
	_last_logged_engine_force = 0.0
	_last_logged_brake = 0.0
	if rover:
		rover.auto_controlled = true # Habilitar piloto automático
		rover.engine_force = 0.0
		rover.brake = 0.0
		rover.steering = 0.0
	
	if not use_remote_logic:
		_generate_lane_split_path()
		
	current_waypoint_index = 0
	
	# Cambiar el color del visualizador a verde
	var path_visualizer = get_node_or_null("../PathVisualizer")
	if path_visualizer and path_visualizer.has_method("set_color"):
		path_visualizer.set_color(Color.GREEN)
		
	set_physics_process(true)
	navigation_started.emit()
	print("[Autopilot] Control automático activo.")

func stop(interrupted: bool = true):
	is_active = false
	set_physics_process(false)
	_cached_path_payload.clear()
	
	if use_remote_logic and _ws_connected:
		var message = {"type": "stop"}
		_ws_client.send_text(JSON.stringify(message))
		
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
		
	_log_vehicle_status(delta)
		
	if use_remote_logic:
		_send_telemetry_to_remote()
		_draw_visuals()
	else:
		_run_local_control(delta)

func _send_telemetry_to_remote():
	if not rover or not _ws_connected:
		return
	var forward_basis = -rover.global_transform.basis.z
	var linear_vel = rover.linear_velocity
	var speed_val = linear_vel.length()
	if linear_vel.dot(forward_basis) < 0:
		speed_val = -speed_val
		
	var server_heading = rover.global_rotation.y + PI
	while server_heading > PI:
		server_heading -= 2.0 * PI
	while server_heading <= -PI:
		server_heading += 2.0 * PI
		
	var message = {
		"type": "telemetry",
		"x": rover.global_position.x,
		"z": rover.global_position.z,
		"heading": server_heading,
		"speed": speed_val
	}
	if ConfigDebug and ConfigDebug.enviar_evasion_brain:
		message["evasion"] = {
			"inner_count": rover.cuerpos_interna.size(),
			"middle_count": rover.cuerpos_intermedia.size(),
			"outer_count": rover.cuerpos_externa.size(),
			"lateral": rover.direccion_evasion.x,
			"brake": rover.freno_evasion,
			"retrocediendo": rover.evasion_retrocediendo,
			"nivel_zona": rover.evasion_nivel_zona
		}
	_ws_client.send_text(JSON.stringify(message))

func _read_messages_from_server(delta: float):
	while _ws_client.get_available_packet_count() > 0:
		var packet = _ws_client.get_packet()
		var msg_str = packet.get_string_from_utf8()
		var json = JSON.new()
		var err = json.parse(msg_str)
		if err == OK:
			var data = json.get_data()
			var msg_type = data.get("type", "")
			
			if msg_type == "level_initialized":
				print("[Autopilot] Cerebro pps-vae listo: Cuadrícula de nivel inicializada.")
				
			elif msg_type == "path_calculated":
				var raw_path = data.get("path", [])
				var converted_path = _process_remote_path(raw_path)
				
				# Store path locally for visualization
				modified_path_positions = converted_path
				current_waypoint_index = 0
				
				# Populate grid/corner visualizer data
				raw_grid_positions.clear()
				for pt in converted_path:
					raw_grid_positions.append(pt)
					
				# Send the lane-shifted path back to the server so the tracker follows it
				var path_payload = []
				for i in range(converted_path.size()):
					var pos = converted_path[i]
					var orig_pt = raw_path[i]
					path_payload.append({
						"x": pos.x,
						"z": pos.z,
						"direction": orig_pt.get("direction", 1),
						"steer": 0.2 if is_actual_corner[i] else 0.0
					})
				
				_cached_path_payload = path_payload
				var override_msg = {
					"type": "set_path",
					"path": path_payload
				}
				_ws_client.send_text(JSON.stringify(override_msg))
				print("[Autopilot] Enviando ruta desplazada y suavizada al cerebro remoto.")
				
				remote_path_received.emit(converted_path)
				
			elif msg_type == "path_failed":
				print("[Autopilot] Cerebro pps-vae reportó que no se pudo encontrar ruta.")
				remote_path_failed.emit()
				
			elif msg_type == "orders":
				if not is_active:
					continue
				
				if data.has("completed") and data["completed"]:
					print("[Autopilot] Destino alcanzado (Cerebro pps-vae).")
					stop(false)
					if navigation:
						navigation.target_reached.emit()
					return
				
				var target_steering = data.get("steering", 0.0)
				var engine_force = data.get("engine_force", 0.0)
				var brake_val = data.get("brake", 0.0)
				
				# Apply steering with wheel physical speed limits
				var steering_speed = 4.0
				rover.steering = move_toward(rover.steering, target_steering, steering_speed * delta)
				
				# Apply forces: negate engine_force by direction (convención del sistema)
				rover.engine_force = engine_force
				rover.brake = brake_val
				
				# Update current waypoint index and target point for drawing
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
	
	_aplicar_evasion()
	
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
		rover.engine_force = -acceleration_force
		rover.brake = 0.0
	else:
		rover.engine_force = 0.0
		var brake_strength = 10.0 + (speed - target_speed) * 2.0
		rover.brake = min(brake_strength, 35.0)

func _process_remote_path(raw_path: Array) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if raw_path.size() == 0:
		return positions
	
	for pt in raw_path:
		positions.append(Vector3(pt["x"], rover.global_position.y if rover else 0.38, pt["z"]))
	
	if ConfigDebug and ConfigDebug.lane_shift_activado:
		for i in range(raw_path.size()):
			var pos = positions[i]
			
			var dir = Vector2.UP
			if raw_path.size() > 1:
				if i == 0:
					dir = Vector2(raw_path[1]["x"] - raw_path[0]["x"], raw_path[1]["z"] - raw_path[0]["z"]).normalized()
				elif i == raw_path.size() - 1:
					dir = Vector2(raw_path[i]["x"] - raw_path[i-1]["x"], raw_path[i]["z"] - raw_path[i-1]["z"]).normalized()
				else:
					dir = Vector2(raw_path[i+1]["x"] - raw_path[i]["x"], raw_path[i+1]["z"] - raw_path[i]["z"]).normalized()
					
			var cell_curr = Vector2i(
				round(pos.x / navigation.tile_spacing),
				round(pos.z / navigation.tile_spacing)
			)
			
			var shift = _get_lane_shift(cell_curr, dir)
			positions[i] = pos + shift
	
	if ConfigDebug and ConfigDebug.acortar_ruta_activado and positions.size() >= 2:
		var last_idx = positions.size() - 1
		var segment = positions[last_idx] - positions[last_idx - 1]
		var segment_len = segment.length()
		var dir = segment.normalized()
		var shorten_dist = min(1.0, segment_len * 0.5)
		positions[last_idx] = positions[last_idx] - dir * shorten_dist
	
	is_actual_corner.resize(positions.size())
	is_actual_corner.fill(false)
	is_corner_waypoint.resize(positions.size())
	is_corner_waypoint.fill(false)
	
	for i in range(1, positions.size() - 1):
		var v1 = (positions[i] - positions[i-1]).normalized()
		var v2 = (positions[i+1] - positions[i]).normalized()
		var dot = v1.dot(v2)
		if dot < 0.9:
			is_actual_corner[i] = true
			is_corner_waypoint[i] = true
			is_corner_waypoint[i-1] = true
			if i + 1 < positions.size():
				is_corner_waypoint[i+1] = true
	
	if ConfigDebug and ConfigDebug.suavizado_ruta_activado:
		return _smooth_path_preserving_corners(positions, is_actual_corner, 1)
	
	return positions

func _log_vehicle_status(delta: float):
	_total_time += delta
	if not rover:
		return
		
	var current_pos = rover.global_position
	var current_speed = rover.linear_velocity.length()
	var forward_basis = -rover.global_transform.basis.z
	if rover.linear_velocity.dot(forward_basis) < 0:
		current_speed = -current_speed
		
	var current_steer = rover.steering
	var current_engine_force = rover.engine_force
	var current_brake = rover.brake
	
	var pos_changed = current_pos.distance_to(_last_logged_pos) > 0.05
	var speed_changed = abs(current_speed - _last_logged_speed) > 0.05
	var steer_changed = abs(current_steer - _last_logged_steer) > 0.01
	var force_changed = abs(current_engine_force - _last_logged_engine_force) > 1.0
	var brake_changed = abs(current_brake - _last_logged_brake) > 1.0
	
	if pos_changed or speed_changed or steer_changed or force_changed or brake_changed:
		_last_logged_pos = current_pos
		_last_logged_speed = current_speed
		_last_logged_steer = current_steer
		_last_logged_engine_force = current_engine_force
		_last_logged_brake = current_brake
		
		print("[VEHICLE_STATE] t=%.2fs | Pos=(%.2f, %.2f) | Speed=%.2f m/s | Steer=%.2f rad | EngineForce=%.1f | Brake=%.1f" % [
			_total_time,
			current_pos.x,
			current_pos.z,
			current_speed,
			current_steer,
			current_engine_force,
			current_brake
		])

func _aplicar_evasion() -> void:
	if not rover:
		return
	var ev_dir = rover.get("direccion_evasion")
	if rover.get("evasion_retrocediendo") and rover.get("evasion_retrocediendo") == true:
		rover.engine_force = -RoverConfig.torque * 0.6 if RoverConfig else -180.0
		rover.brake = 0.0
		if ev_dir:
			rover.steering = -ev_dir.x * 0.5
		return
	
	var ev_freno = rover.get("freno_evasion")
	if ev_freno == null or ev_dir == null:
		return
	if ev_freno > 0.0:
		rover.engine_force = 0
		rover.brake = max(rover.brake, ev_freno)
	if ev_dir.length() > 0.01:
		rover.steering += ev_dir.x
