extends Node3D

signal nivel_generado(path: String)
signal rover_instanciado(position: Vector3)

const TILE_TYPE_INDEX = {
	"no_caminable": 0,
	"peso_3_4": 1,
	"caminable": 2,
	"spawn_point": 3,
	"punto_interes": 4,
	"obstaculo": 5,
	"objetivo": 6,
}

const TILE_SCENE_INDEX = {
	"road": 0,
	"cruce": 1,
	"basecalle": 2,
}

const EDIFICIOS_INDICES = [3, 4, 5, 6, 7, 8, 9, 10]

@export var tiles: Array[PackedScene] = []
@export var rover_scene: PackedScene
@export var tile_spacing: float = 2.0
@export var rover_spawn_y: float = 0.0
@export var clear_before_generate: bool = true

var current_level_root: Node3D
var current_rover: Node = null
var rover_spawn_position: Vector3 = Vector3.ZERO
var has_spawn_position: bool = false
var grid_data: Array = []
var spawn_cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	SignalBus.connect("nivel_seleccionado", Callable(self, "_on_nivel_seleccionado"))

	current_level_root = Node3D.new()
	current_level_root.name = "NivelInstanciado"
	add_child(current_level_root)

func _on_nivel_seleccionado(path: String) -> void:
	_cargar_archivo(path)

func _cargar_archivo(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("Archivo de nivel no existe: %s" % path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No se pudo abrir archivo: %s" % path)
		return

	var text = file.get_as_text()
	file.close()

	var parse_result = JSON.parse_string(text)
	if parse_result == null:
		push_error("Error parseando JSON: %s" % path)
		return

	var data: Dictionary = {}
	if typeof(parse_result) == TYPE_DICTIONARY and parse_result.has("error") and parse_result.has("result"):
		if parse_result.error != OK:
			push_error("Error parseando JSON: %s en %s" % [parse_result.error_string, path])
			return
		data = parse_result.result
	else:
		data = parse_result

	if typeof(data) != TYPE_DICTIONARY:
		push_error("Formato de nivel inválido. Se esperaba Dictionary.")
		return

	_generar_entorno(data)
	emit_signal("nivel_generado", path)

func _generar_entorno(data: Dictionary) -> void:
	if clear_before_generate:
		_limpiar_entorno()

	has_spawn_position = false
	rover_spawn_position = Vector3.ZERO

	if data.has("tiles"):
		grid_data = data["tiles"]
		_generar_tiles_por_matriz(data["tiles"])
	elif data.has("grid"):
		grid_data = data["grid"]
		_generar_tiles_por_matriz(data["grid"])
	elif data.has("cells"):
		_generar_tiles_por_cells(data["cells"])
	else:
		push_warning("El JSON no incluye 'tiles', 'grid' ni 'cells'. No se generaron tiles.")

	if data.has("rover_start"):
		_instanciar_rover(data["rover_start"])
	elif data.has("rover_cell"):
		_instanciar_rover(data["rover_cell"])
	elif data.has("spawn_point"):
		_instanciar_rover(data["spawn_point"])
	elif has_spawn_position:
		_instanciar_rover(rover_spawn_position)

func _generar_tiles_por_cells(cells) -> void:
	if typeof(cells) != TYPE_ARRAY:
		return

	for entry in cells:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var x = int(entry["x"])
		var y = int(entry["y"])
		var color_data = entry["color"]
		if typeof(color_data) != TYPE_ARRAY or color_data.size() < 3:
			continue
		var tile_id = _tile_id_from_color_array(color_data)
		_instanciar_tile(tile_id, x, y)

func _es_caminable(tile_value) -> bool:
	var resolved_id = _get_tile_index(tile_value)
	return resolved_id in [TILE_TYPE_INDEX["caminable"], TILE_TYPE_INDEX["spawn_point"], TILE_TYPE_INDEX["punto_interes"], TILE_TYPE_INDEX["objetivo"], TILE_TYPE_INDEX["peso_3_4"]]

func _es_barro(tile_value) -> bool:
	var resolved_id = _get_tile_index(tile_value)
	return resolved_id == TILE_TYPE_INDEX["peso_3_4"]

func _obtener_direcciones_vecinos_caminables(tile_rows: Array, row: int, col: int) -> Array:
	var direcciones_vecinos = []
	var direcciones = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	
	for dir in direcciones:
		var new_row = row + dir.y
		var new_col = col + dir.x
		
		if new_row >= 0 and new_row < tile_rows.size():
			var fila = tile_rows[new_row]
			if typeof(fila) == TYPE_ARRAY and new_col >= 0 and new_col < fila.size():
				if _es_caminable(fila[new_col]):
					direcciones_vecinos.append(dir)
	
	return direcciones_vecinos

func _son_lados_opuestos(dir1: Vector2i, dir2: Vector2i) -> bool:
	return (dir1.x + dir2.x == 0) and (dir1.y + dir2.y == 0)

func _generar_tiles_por_matriz(tile_rows) -> void:
	if typeof(tile_rows) != TYPE_ARRAY:
		push_error("tiles/grid debe ser un Array de filas.")
		return

	for z_index in tile_rows.size():
		var fila = tile_rows[z_index]
		if typeof(fila) != TYPE_ARRAY:
			continue
		for x_index in fila.size():
			var tile_id = fila[x_index]
			if tile_id == null:
				continue
			var resolved_id = _get_tile_index(tile_id)
			if resolved_id < 0:
				continue
			if resolved_id == TILE_TYPE_INDEX["spawn_point"]:
				has_spawn_position = true
				rover_spawn_position = Vector3(x_index * tile_spacing, rover_spawn_y, z_index * tile_spacing)
				spawn_cell = Vector2i(x_index, z_index)
			
			if resolved_id == TILE_TYPE_INDEX["spawn_point"]:
				_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.GREEN, false)
			elif resolved_id == TILE_TYPE_INDEX["punto_interes"]:
				_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.YELLOW, false)
			elif resolved_id == TILE_TYPE_INDEX["objetivo"]:
				_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.PURPLE, false)
			elif resolved_id == TILE_TYPE_INDEX["peso_3_4"]:
				var direcciones_vecinos = _obtener_direcciones_vecinos_caminables(tile_rows, z_index, x_index)
				var num_vecinos = direcciones_vecinos.size()
				
				if num_vecinos == 2:
					var dir1 = direcciones_vecinos[0]
					var dir2 = direcciones_vecinos[1]
					if _son_lados_opuestos(dir1, dir2):
						var rotacion = 0.0
						if dir1.x != 0:
							rotacion = PI / 2
						_instanciar_tile(TILE_SCENE_INDEX["road"], x_index, z_index, rotacion, Color.GRAY, true)
					else:
						_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.GRAY, true)
				elif num_vecinos > 2:
					_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.GRAY, true)
				else:
					_instanciar_tile(TILE_SCENE_INDEX["road"], x_index, z_index, 0.0, Color.GRAY, true)
			elif _es_caminable(tile_id):
				var direcciones_vecinos = _obtener_direcciones_vecinos_caminables(tile_rows, z_index, x_index)
				var num_vecinos = direcciones_vecinos.size()
				
				if num_vecinos == 2:
					var dir1 = direcciones_vecinos[0]
					var dir2 = direcciones_vecinos[1]
					if _son_lados_opuestos(dir1, dir2):
						var rotacion = 0.0
						if dir1.x != 0:
							rotacion = PI / 2
						_instanciar_tile(TILE_SCENE_INDEX["road"], x_index, z_index, rotacion, Color.WHITE, false)
					else:
						_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.WHITE, false)
				elif num_vecinos > 2:
					_instanciar_tile(TILE_SCENE_INDEX["cruce"], x_index, z_index, 0.0, Color.WHITE, false)
				else:
					_instanciar_tile(TILE_SCENE_INDEX["road"], x_index, z_index, 0.0, Color.WHITE, false)
			else:
				_instanciar_tile(TILE_SCENE_INDEX["basecalle"], x_index, z_index, 0.0, Color.WHITE, false)
				var container_stack = _crear_contenedor_node(x_index, z_index)
				current_level_root.add_child(container_stack)

func _instanciar_tile(tile_value, x_index: int, z_index: int, rotacion_y: float = 0.0, color: Color = Color.WHITE, es_barro: bool = false, es_edificio: bool = false) -> void:
	var resolved_id: int
	
	if typeof(tile_value) == TYPE_INT:
		resolved_id = tile_value
	elif typeof(tile_value) == TYPE_STRING and tile_value == "cruce":
		resolved_id = TILE_SCENE_INDEX["cruce"]
	elif typeof(tile_value) == TYPE_STRING and tile_value == "road":
		resolved_id = TILE_SCENE_INDEX["road"]
	elif typeof(tile_value) == TYPE_STRING and tile_value == "basecalle":
		resolved_id = TILE_SCENE_INDEX["basecalle"]
	else:
		resolved_id = _get_tile_index(tile_value)
	
	if resolved_id < 0 or resolved_id >= tiles.size():
		return

	var scene = tiles[resolved_id]
	if scene == null:
		return

	var instance = scene.instantiate()
	if instance == null:
		return

	current_level_root.add_child(instance)
	if instance is Node3D:
		instance.transform.origin = Vector3(x_index * tile_spacing, 0.0, z_index * tile_spacing)
		if rotacion_y != 0.0:
			instance.rotation.y = rotacion_y
		
		if color != Color.WHITE:
			_aplicar_color_a_tile(instance, color)
		
		if es_barro:
			_agregar_zona_barro(instance)
		
		if es_edificio:
			instance.add_to_group("buildings")
	elif instance.has_method("set_position"):
		instance.call("set_position", Vector2(x_index * tile_spacing, z_index * tile_spacing))

func _agregar_zona_barro(tile_instance: Node3D) -> void:
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(tile_spacing, 1.0, tile_spacing)
	collision.shape = shape
	collision.transform.origin = Vector3(0, 0.5, 0)
	
	area.add_child(collision)
	tile_instance.add_child(area)
	
	var mud_script = load("res://scripts/mud_zone.gd")
	if mud_script:
		area.set_script(mud_script)
		area.set("slow_factor", 0.3)
		area.set("max_speed_in_mud", 5.0)
		
		# Conectar las señales manualmente
		area.body_entered.connect(area._on_body_entered)
		area.body_exited.connect(area._on_body_exited)
		
		area.set_physics_process(true)

func _aplicar_color_a_tile(tile_instance: Node3D, color: Color) -> void:
	for child in tile_instance.get_children():
		if child is MeshInstance3D:
			var mesh_instance = child as MeshInstance3D
			var surface_count = mesh_instance.get_surface_override_material_count()
			for i in range(surface_count):
				var material = mesh_instance.get_surface_override_material(i)
				if material == null:
					var surface_material = mesh_instance.get_active_material(i)
					if surface_material and surface_material is StandardMaterial3D:
						material = surface_material.duplicate()
						mesh_instance.set_surface_override_material(i, material)
				
				if material and material is StandardMaterial3D:
					material.albedo_color = color
					material.emission_enabled = true
					material.emission = color
					material.emission_energy_multiplier = 0.5

func _tile_id_from_color_array(color_data: Array) -> int:
	var color = Color(color_data[0], color_data[1], color_data[2], color_data[3])
	return _tile_id_from_color(color)

func _tile_id_from_color(color: Color) -> int:
	if color == Color.BLACK:
		return TILE_TYPE_INDEX["no_caminable"]
	if color == Color.GRAY:
		return TILE_TYPE_INDEX["peso_3_4"]
	if color == Color.WHITE:
		return TILE_TYPE_INDEX["caminable"]
	if color == Color.GREEN:
		return TILE_TYPE_INDEX["spawn_point"]
	if color == Color.YELLOW:
		return TILE_TYPE_INDEX["punto_interes"]
	if color == Color.ORANGE:
		return TILE_TYPE_INDEX["obstaculo"]
	if color == Color.PURPLE:
		return TILE_TYPE_INDEX["objetivo"]
	return TILE_TYPE_INDEX["no_caminable"]

func _get_tile_index(tile_value) -> int:
	if typeof(tile_value) == TYPE_INT:
		return int(tile_value)
	if typeof(tile_value) == TYPE_STRING:
		var key = tile_value.to_lower()
		if TILE_TYPE_INDEX.has(key):
			return TILE_TYPE_INDEX[key]
		match key:
			"negro", "blocked", "no_caminable":
				return TILE_TYPE_INDEX["no_caminable"]
			"gris", "gray", "peso_3_4":
				return TILE_TYPE_INDEX["peso_3_4"]
			"blanco", "walkable", "caminable":
				return TILE_TYPE_INDEX["caminable"]
			"verde", "spawnpoint", "spawn_point":
				return TILE_TYPE_INDEX["spawn_point"]
			"amarillo", "punto_interes", "interest_point", "interest":
				return TILE_TYPE_INDEX["punto_interes"]
			"naranja", "obstaculo", "obstacle":
				return TILE_TYPE_INDEX["obstaculo"]
			"violeta", "objetivo", "target":
				return TILE_TYPE_INDEX["objetivo"]
	return -1

func _instanciar_rover(start_data = null) -> void:
	if rover_scene == null:
		push_warning("No se asignó rover_scene para instanciar el rover.")
		return

	var instance = rover_scene.instantiate()
	if instance == null:
		return

	if current_rover:
		current_rover.queue_free()

	current_rover = instance
	add_child(current_rover)

	var _position = _parse_rover_position(start_data)
	if current_rover is Node3D:
		current_rover.transform.origin = _position
	elif current_rover.has_method("set_position"):
		current_rover.call("set_position", Vector2(_position.x, _position.z))

	emit_signal("rover_instanciado", _position)

func _parse_rover_position(start_data) -> Vector3:
	var _position = Vector3(0, rover_spawn_y, 0)

	if typeof(start_data) == TYPE_VECTOR3:
		return start_data
	if typeof(start_data) == TYPE_DICTIONARY:
		if start_data.has("x"):
			_position.x = float(start_data["x"])
		if start_data.has("y"):
			_position.y = float(start_data["y"])
		if start_data.has("z"):
			_position.z = float(start_data["z"])
		if start_data.has("row") and start_data.has("col"):
			_position.x = float(start_data["col"]) * tile_spacing
			_position.z = float(start_data["row"]) * tile_spacing
			_position.y = float(start_data.get("y", rover_spawn_y))
		if start_data.has("cell_x") and start_data.has("cell_y"):
			_position.x = float(start_data["cell_x"]) * tile_spacing
			_position.z = float(start_data["cell_y"]) * tile_spacing
			_position.y = float(start_data.get("y", rover_spawn_y))
	elif typeof(start_data) == TYPE_ARRAY and start_data.size() >= 2:
		_position.x = float(start_data[0])
		if start_data.size() >= 3:
			_position.y = float(start_data[1])
			_position.z = float(start_data[2])
		else:
			_position.z = float(start_data[1])

	return _position

func _limpiar_entorno() -> void:
	for child in current_level_root.get_children():
		child.queue_free()
	current_level_root.get_children().clear()

func _crear_contenedor_node(x_index: int, z_index: int) -> Node3D:
	var container_stack = Node3D.new()
	container_stack.name = "ContenedorStack_%d_%d" % [x_index, z_index]
	container_stack.transform.origin = Vector3(x_index * tile_spacing, 0.0, z_index * tile_spacing)
	
	# Agregar al grupo de edificios para que la cámara con transparencia lo detecte
	container_stack.add_to_group("buildings")
	
	# Cantidad de contenedores en la pila: entre 1 y 3
	var stack_count = randi_range(1, 3)
	
	# Colores de puerto
	var colors = [
		Color(0.8, 0.15, 0.15), # Rojo
		Color(0.15, 0.35, 0.8), # Azul
		Color(0.15, 0.6, 0.25), # Verde
		Color(0.85, 0.45, 0.1), # Naranja
		Color(0.85, 0.75, 0.1)  # Amarillo
	]
	
	# Rotación de la pila en múltiplos de 90 grados
	var rot_y = (randi() % 4) * (PI / 2.0)
	container_stack.rotation.y = rot_y
	
	var container_width = 1.8
	var container_height = 1.8
	var container_length = 3.6
	
	for h in range(stack_count):
		var single_container = Node3D.new()
		single_container.name = "Contenedor_%d" % h
		
		# Offset muy leve
		var offset_x = randf_range(-0.05, 0.05)
		var offset_z = randf_range(-0.05, 0.05)
		var pos_y = h * container_height + (container_height / 2.0)
		single_container.transform.origin = Vector3(offset_x, pos_y, offset_z)
		
		# Visualización
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(container_width, container_height, container_length)
		mesh_instance.mesh = box_mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = colors[randi() % colors.size()]
		mat.roughness = 0.4
		mat.metallic = 0.7
		
		mesh_instance.set_surface_override_material(0, mat)
		single_container.add_child(mesh_instance)
		
		# Colisión física
		var static_body = StaticBody3D.new()
		static_body.name = "StaticBody3D"
		static_body.collision_layer = 1
		static_body.collision_mask = 1
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(container_width, container_height, container_length)
		collision_shape.shape = box_shape
		
		static_body.add_child(collision_shape)
		single_container.add_child(static_body)
		
		container_stack.add_child(single_container)
		
	return container_stack
