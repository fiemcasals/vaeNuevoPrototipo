extends Control

const MENU_PATH = "res://scenes/menu_principal.tscn"

@onready var file_dialog: FileDialog = $FileDialog
@onready var btn_volver: Button = $BtnVolverMenu

var selected_color: Color = Color.WHITE
var colors = [
	Color.WHITE,Color.BLACK,Color.GRAY, Color.GREEN, Color.YELLOW,
	Color.ORANGE, Color.PURPLE,
]

@onready var grid: GridContainer = $GridContainer
@onready var guardar_btn: Button = $ButtonsContainer/Guardar
@onready var cargar_btn: Button = $ButtonsContainer/CargarGrilla
var selected_btn: Button = null

const GRID_COLS = 16
const GRID_ROWS = 16
const CELL_SIZE = 32

const TILE_TYPE_COLORS = {
	"no_caminable": Color.BLACK,
	"peso_3_4": Color.GRAY,
	"caminable": Color.WHITE,
	"spawn_point": Color.GREEN,
	"punto_interes": Color.YELLOW,
	"obstaculo": Color.ORANGE,
	"objetivo": Color.PURPLE,
}

var grid_colors: Dictionary = {}  # {Vector2i: Color}
var is_painting = false

func _ready() -> void:
	for color in colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(32, 32)

		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = color
		btn.add_theme_stylebox_override("normal", stylebox)
		btn.add_theme_stylebox_override("hover", stylebox)
		btn.add_theme_stylebox_override("pressed", stylebox)
		btn.pressed.connect(func(): select_color(color, btn))
		grid.add_child(btn)

	guardar_btn.pressed.connect(_on_guardar_pressed)
	cargar_btn.pressed.connect(_on_cargar_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.filters = ["*.json ; JSON Files"]
	btn_volver.pressed.connect(_volver_al_menu)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_volver_al_menu()

func _volver_al_menu() -> void:
	get_tree().change_scene_to_file(MENU_PATH)
	

func _on_guardar_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Guardar grilla"
	file_dialog.current_file = "pencil_grid.json"
	file_dialog.popup_centered(Vector2(800, 600))

func _on_cargar_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Cargar grilla"
	file_dialog.popup_centered(Vector2(800, 600))
func _on_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_guardar(path)
	else:
		_cargar(path)


func _guardar(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo abrir el archivo para guardar: %s" % path)
		return

	var tiles = []
	for row in range(GRID_ROWS):
		var row_tiles = []
		for col in range(GRID_COLS):
			var cell = Vector2i(col, row)
			var color = grid_colors.get(cell, Color.BLACK)
			row_tiles.append(_get_tile_type_from_color(color))
		tiles.append(row_tiles)

	var data = {
		"version": 2,
		"read_mode": "tile_types",
		"cols": GRID_COLS,
		"rows": GRID_ROWS,
		"tiles": tiles,
	}

	file.store_string(JSON.stringify(data))
	file.close()
	print("Grilla guardada en formato de tiles: %s" % path)

func _cargar(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("No existe el archivo: %s" % path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No se pudo abrir el archivo: %s" % path)
		return

	var text = file.get_as_text()
	file.close()

	var parse_result = JSON.parse_string(text)
	if parse_result == null:# or parse_result.error != OK:
		push_error("Error al parsear JSON: %s" % path)
		return

	var data = parse_result
	grid_colors.clear()

	if data.has("tiles") and typeof(data["tiles"]) == TYPE_ARRAY:
		_load_tiles_from_matrix(data["tiles"])
	elif data.has("cells") and typeof(data["cells"]) == TYPE_ARRAY:
		_load_cells_from_legacy_format(data["cells"])
	else:
		push_error("Formato desconocido de JSON. Se esperaba 'tiles' o 'cells'.")
		return

	queue_redraw()
	print("Grilla cargada desde: %s" % path)

func _get_tile_type_from_color(color: Color) -> String:
	if color == Color.BLACK:
		return "no_caminable"
	if color == Color.GRAY:
		return "peso_3_4"
	if color == Color.WHITE:
		return "caminable"
	if color == Color.GREEN:
		return "spawn_point"
	if color == Color.YELLOW:
		return "punto_interes"
	if color == Color.ORANGE:
		return "obstaculo"
	if color == Color.PURPLE:
		return "objetivo"
	return "no_caminable"

func _get_color_from_tile_type(tile_type: String) -> Color:
	var normalized = tile_type.to_lower()
	match normalized:
		"no_caminable", "negro", "blocked":
			return Color.BLACK
		"peso_3_4", "gris", "gray":
			return Color.GRAY
		"caminable", "blanco", "walkable":
			return Color.WHITE
		"spawn_point", "verde", "spawnpoint":
			return Color.GREEN
		"punto_interes", "amarillo", "interest_point", "interest":
			return Color.YELLOW
		"obstaculo", "naranja", "obstacle":
			return Color.ORANGE
		"objetivo", "violeta", "target":
			return Color.PURPLE
		_:
			return Color.BLACK

func _load_tiles_from_matrix(tile_matrix: Array) -> void:
	for row_index in tile_matrix.size():
		var row = tile_matrix[row_index]
		if typeof(row) != TYPE_ARRAY:
			continue
		for col_index in row.size():
			var tile_type = row[col_index]
			var color: Color
			if typeof(tile_type) == TYPE_STRING:
				color = _get_color_from_tile_type(tile_type)
			elif typeof(tile_type) == TYPE_INT:
				color = _get_color_from_tile_type(str(tile_type))
			else:
				color = Color.BLACK
			grid_colors[Vector2i(col_index, row_index)] = color

func _load_cells_from_legacy_format(cells: Array) -> void:
	for entry in cells:
		var cell = Vector2i(entry["x"], entry["y"])
		var color_data = entry["color"]
		grid_colors[cell] = Color(color_data[0], color_data[1], color_data[2], color_data[3])
func select_color(color: Color, btn: Button) -> void:
	selected_color = color

	# Resetear botón anterior
	if selected_btn:
		var old_style = StyleBoxFlat.new()
		old_style.bg_color = selected_btn.get_theme_stylebox("normal").bg_color
		selected_btn.add_theme_stylebox_override("normal", old_style)
		selected_btn.add_theme_stylebox_override("hover", old_style)
		selected_btn.add_theme_stylebox_override("pressed", old_style)

	# Marcar el nuevo
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_color = Color.WHITE
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	selected_btn = btn

func _draw():
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cell = Vector2i(col, row)
			var rect = Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)

			# Fondo de la celda
			var color = grid_colors.get(cell, Color(0.2, 0.2, 0.2))
			draw_rect(rect, color)

			# Borde
			draw_rect(rect, Color.BLACK, false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		is_painting = event.pressed

	if (is_painting and event is InputEventMouseMotion) or \
	   (event is InputEventMouseButton and event.pressed):
		var cell = get_cell_at(event.position)
		if is_valid_cell(cell):
			grid_colors[cell] = selected_color  # viene del color picker
			queue_redraw()

func get_cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / CELL_SIZE), int(pos.y / CELL_SIZE))

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS
