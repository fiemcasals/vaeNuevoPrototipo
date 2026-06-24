extends Node3D

@export var camera: Camera3D
@export var rover: Node3D
@export var transparent_material: ShaderMaterial

var objects_blocking: Array[Node] = []

func _ready():
	if not transparent_material:
		push_error("Transparent material not assigned!")
		return

func _physics_process(_delta):
	if not camera or not rover or not transparent_material:
		return
	
	_update_transparent_objects()

func _update_transparent_objects():
	# Restaurar materiales originales de los objetos que ya no bloquean
	for obj in objects_blocking:
		if is_instance_valid(obj):
			_restore_materials(obj)
	objects_blocking.clear()
	
	# Hacer raycast desde la cámara al rover
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		camera.global_position,
		rover.global_position
	)
	query.collision_mask = 0xFFFFFFFF  # Todas las capas
	
	var result = space_state.intersect_ray(query)
	
	# Si el raycast golpeó algo, aplicar material transparente
	if result and result.collider:
		var collider = result.collider
		
		# Buscar el edificio padre
		var building = _find_building_parent(collider)
		
		if building and building not in objects_blocking:
			_apply_transparent_material_to_building(building)
			objects_blocking.append(building)
	
	# Actualizar posición del rover en el shader
	transparent_material.set_shader_parameter("rover_world_position", rover.global_position)

func _find_building_parent(node: Node) -> Node:
	var current = node
	while current:
		if current.is_in_group("buildings"):
			return current
		current = current.get_parent()
	return null

func _apply_transparent_material_to_building(building: Node):
	var mesh_instances = _get_mesh_instances(building)
	
	for mesh_instance in mesh_instances:
		# Guardar materiales originales si no están guardados
		if not mesh_instance.has_meta("original_materials"):
			var original_mats = []
			for i in range(mesh_instance.get_surface_override_material_count()):
				original_mats.append(mesh_instance.get_surface_override_material(i))
			mesh_instance.set_meta("original_materials", original_mats)
		
		# Aplicar material transparente
		for i in range(mesh_instance.get_surface_override_material_count()):
			mesh_instance.set_surface_override_material(i, transparent_material)

func _restore_materials(building: Node):
	var mesh_instances = _get_mesh_instances(building)
	
	for mesh_instance in mesh_instances:
		if mesh_instance.has_meta("original_materials"):
			var original_mats = mesh_instance.get_meta("original_materials")
			for i in range(mesh_instance.get_surface_override_material_count()):
				if i < original_mats.size():
					mesh_instance.set_surface_override_material(i, original_mats[i])

func _get_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		meshes.append(node)
	
	for child in node.get_children():
		meshes.append_array(_get_mesh_instances(child))
	
	return meshes
