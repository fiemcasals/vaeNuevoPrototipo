# plugin_data.gd
# © Copyright CookieBadger 2026
@tool
extends Resource

const SceneData = preload("res://addons/assetplacer/data_formats/scene_data.gd")

@export var version := 1
@export var scene_data: Dictionary[String, SceneData] = {}
@export var global_data: Dictionary[String, Variant] = {}
@export var show_license_on_start := true
