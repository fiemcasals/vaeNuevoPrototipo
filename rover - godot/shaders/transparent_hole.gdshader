shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 rover_world_position = vec3(0.0, 0.0, 0.0);
uniform float hole_radius = 1.5;
uniform float hole_blur = 0.2;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Calcular la dirección desde la cámara al rover
	vec3 camera_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_rover = normalize(rover_world_position - camera_pos);
	
	// Calcular la dirección desde la cámara al fragmento
	vec3 to_fragment = normalize(world_position - camera_pos);
	
	// Calcular el ángulo entre las dos direcciones
	float dot_product = dot(to_rover, to_fragment);
	
	// Convertir a distancia angular (0 = misma dirección, 1 = direcciones opuestas)
	float angle_factor = 1.0 - dot_product;
	
	// Normalizar el radio
	float normalized_radius = hole_radius * 0.01;
	
	// Crear el efecto de agujero (transparente cerca del rover, opaco lejos)
	float alpha = smoothstep(normalized_radius, normalized_radius * (1.0 + hole_blur), angle_factor);
	
	ALBEDO = vec3(1.0);
	ALPHA = alpha;
}
