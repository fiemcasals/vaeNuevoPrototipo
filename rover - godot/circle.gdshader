shader_type canvas_item;

void fragment() {
	vec2 center = UV - vec2(0.5);
	if (length(center) > 0.5) {
		COLOR.a = 0.0;
	}
}
