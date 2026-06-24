# node_3d_list.gd
# © Copyright CookieBadger 2026
@tool

var node_transforms: Dictionary[Node3D, Transform3D] = {}


func _init(p_nodes: Array[Node3D] = []) -> void:
	node_transforms = {}
	for node_3d in p_nodes:
		node_transforms[node_3d] = node_3d.transform


func get_nodes() -> Array[Node3D]:
	return node_transforms.keys()


func size() -> int:
	return node_transforms.size()
