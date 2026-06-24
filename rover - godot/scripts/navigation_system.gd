extends Node3D
class_name NavigationSystem

signal path_calculated(path: Array)
signal path_completed
signal target_reached

var grid_data: Array = []
var grid_weights: Array = []
var grid_rows: int = 0
var grid_cols: int = 0
var tile_spacing: float = 4.0

var current_path: Array = []
var current_path_index: int = 0
var is_navigating: bool = false

const WEIGHTS = {
	"no_caminable": 999999,
	"peso_3_4": 3,
	"caminable": 1,
	"spawn_point": 1,
	"punto_interes": 1,
	"obstaculo": 999999,
	"objetivo": 1
}

func _ready():
	set_process(false)

func initialize_level(data: Dictionary, spacing: float):
	tile_spacing = spacing
	grid_data = data.get("tiles", [])
	grid_rows = grid_data.size()
	if grid_rows > 0:
		grid_cols = grid_data[0].size()
	
	_build_weight_grid()
	print("NavigationSystem initialized: ", grid_rows, "x", grid_cols)

func _build_weight_grid():
	grid_weights.clear()
	for row in range(grid_rows):
		var weight_row = []
		for col in range(grid_cols):
			var tile_type = grid_data[row][col]
			var weight = WEIGHTS.get(tile_type, 1)
			weight_row.append(weight)
		grid_weights.append(weight_row)

func find_nearest_target(start_pos: Vector3, target_types: Array) -> Vector2i:
	var start_cell = world_to_grid(start_pos)
	var nearest_target = Vector2i(-1, -1)
	var min_distance = INF
	
	for row in range(grid_rows):
		for col in range(grid_cols):
			var tile_type = grid_data[row][col]
			if tile_type in target_types:
				var distance = abs(row - start_cell.y) + abs(col - start_cell.x)
				if distance < min_distance:
					min_distance = distance
					nearest_target = Vector2i(col, row)
	
	return nearest_target

func get_all_targets(start_pos: Vector3, target_types: Array) -> Array:
	var targets = []
	var start_cell = world_to_grid(start_pos)
	
	for row in range(grid_rows):
		for col in range(grid_cols):
			var tile_type = grid_data[row][col]
			if tile_type in target_types:
				var cell = Vector2i(col, row)
				var distance = abs(row - start_cell.y) + abs(col - start_cell.x)
				targets.append({
					"cell": cell,
					"type": tile_type,
					"distance": distance,
					"name": _get_target_name(tile_type, col, row)
				})
	
	targets.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return targets

func _get_target_name(tile_type: String, col: int, row: int) -> String:
	match tile_type:
		"punto_interes":
			return "Punto de Interés (%d, %d)" % [col, row]
		"objetivo":
			return "Objetivo (%d, %d)" % [col, row]
		_:
			return "Target (%d, %d)" % [col, row]

func calculate_path(start_pos: Vector3, target_pos: Vector3) -> Array:
	var start_cell = world_to_grid(start_pos)
	var target_cell = world_to_grid(target_pos)
	
	print("Calculating path from ", start_cell, " to ", target_cell)
	
	var path = _a_star(start_cell, target_cell)
	
	if path.size() > 0:
		current_path = path
		current_path_index = 0
		path_calculated.emit(path)
		print("Path calculated with ", path.size(), " nodes")
	else:
		print("No path found!")
	
	return path

func _a_star(start: Vector2i, goal: Vector2i) -> Array:
	var open_set = [start]
	var came_from = {}
	
	var g_score = {}
	var f_score = {}
	
	g_score[start] = 0
	f_score[start] = _heuristic(start, goal)
	
	var iterations = 0
	var max_iterations = 10000
	
	while open_set.size() > 0 and iterations < max_iterations:
		iterations += 1
		
		var current = _get_lowest_f_score(open_set, f_score)
		
		if current == goal:
			return _reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		for neighbor in _get_neighbors(current):
			if not _is_walkable(neighbor):
				continue
			
			var tentative_g = g_score[current] + grid_weights[neighbor.y][neighbor.x]
			
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)
				
				if neighbor not in open_set:
					open_set.append(neighbor)
	
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _get_lowest_f_score(set: Array, f_score: Dictionary) -> Vector2i:
	var lowest = set[0]
	var lowest_f = f_score[lowest]
	
	for node in set:
		if f_score[node] < lowest_f:
			lowest = node
			lowest_f = f_score[node]
	
	return lowest

func _get_neighbors(cell: Vector2i) -> Array:
	var neighbors = []
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0)
	]
	
	for dir in directions:
		var neighbor = cell + dir
		if _is_in_bounds(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_cols and cell.y >= 0 and cell.y < grid_rows

func _is_walkable(cell: Vector2i) -> bool:
	if not _is_in_bounds(cell):
		return false
	return grid_weights[cell.y][cell.x] < 999999

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var path = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var x = int(round(world_pos.x / tile_spacing))
	var z = int(round(world_pos.z / tile_spacing))
	return Vector2i(clamp(x, 0, grid_cols - 1), clamp(z, 0, grid_rows - 1))

func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(grid_pos.x * tile_spacing, 0.38, grid_pos.y * tile_spacing)

func start_navigation():
	if current_path.size() > 0:
		is_navigating = true
		current_path_index = 0
		set_process(true)

func stop_navigation():
	is_navigating = false
	set_process(false)

func get_next_waypoint() -> Vector3:
	if current_path_index < current_path.size():
		return grid_to_world(current_path[current_path_index])
	return Vector3.ZERO

func advance_to_next_waypoint() -> bool:
	current_path_index += 1
	if current_path_index >= current_path.size():
		is_navigating = false
		target_reached.emit()
		return false
	return true

func get_current_target() -> Vector3:
	if is_navigating and current_path_index < current_path.size():
		return grid_to_world(current_path[current_path_index])
	return Vector3.ZERO

func get_path_visual_points() -> PackedVector3Array:
	var points = PackedVector3Array()
	for cell in current_path:
		points.append(grid_to_world(cell))
	return points
