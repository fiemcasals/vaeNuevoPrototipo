extends Node3D
class_name PathVisualizer

var mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var material: StandardMaterial3D

var corners_mesh_instance: MeshInstance3D
var corners_immediate_mesh: ImmediateMesh
var corners_material: StandardMaterial3D

func _ready():
	mesh_instance = MeshInstance3D.new()
	immediate_mesh = ImmediateMesh.new()
	
	material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.8, 1.0)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	mesh_instance.mesh = immediate_mesh
	mesh_instance.material_override = material
	add_child(mesh_instance)
	
	# Inicializar visualizador de esquinas rojas
	corners_mesh_instance = MeshInstance3D.new()
	corners_immediate_mesh = ImmediateMesh.new()
	
	corners_material = StandardMaterial3D.new()
	corners_material.albedo_color = Color.RED
	corners_material.emission_enabled = true
	corners_material.emission = Color.RED
	corners_material.emission_energy_multiplier = 3.0
	corners_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	corners_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	corners_mesh_instance.mesh = corners_immediate_mesh
	corners_mesh_instance.material_override = corners_material
	add_child(corners_mesh_instance)
	
	visible = false

func draw_path(points: PackedVector3Array):
	clear_path_mesh()
	
	if points.size() < 2:
		return
	
	visible = true
	
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	
	for point in points:
		var draw_point = point + Vector3(0, 0.1, 0)
		immediate_mesh.surface_add_vertex(draw_point)
	
	immediate_mesh.surface_end()
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_POINTS, material)
	for point in points:
		var draw_point = point + Vector3(0, 0.15, 0)
		immediate_mesh.surface_add_vertex(draw_point)
	immediate_mesh.surface_end()

func draw_corners(points: PackedVector3Array):
	if corners_immediate_mesh:
		corners_immediate_mesh.clear_surfaces()
		if points.size() == 0:
			return
		
		visible = true
		var segments = 24
		var radius = 0.6
		
		for point in points:
			corners_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, corners_material)
			for j in range(segments + 1):
				var angle = j * (2.0 * PI) / segments
				var vertex = point + Vector3(cos(angle) * radius, 0.2, sin(angle) * radius)
				corners_immediate_mesh.surface_add_vertex(vertex)
			corners_immediate_mesh.surface_end()

func draw_path_segment(start: Vector3, end: Vector3):
	clear()
	visible = true
	
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	
	immediate_mesh.surface_add_vertex(start + Vector3(0, 0.1, 0))
	immediate_mesh.surface_add_vertex(end + Vector3(0, 0.1, 0))
	
	immediate_mesh.surface_end()

func clear_path_mesh():
	if immediate_mesh:
		immediate_mesh.clear_surfaces()

func clear():
	if immediate_mesh:
		immediate_mesh.clear_surfaces()
	if corners_immediate_mesh:
		corners_immediate_mesh.clear_surfaces()
	visible = false

func set_color(color: Color):
	if material:
		material.albedo_color = color
		material.emission = color
