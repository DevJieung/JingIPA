shader_type canvas_item;
varying vec2 local_position;
varying vec4 vertex_ink;
void vertex() {
	local_position = VERTEX;
	vertex_ink = COLOR;
}
void fragment() {
	vec4 source = COLOR;
	if (min(min(vertex_ink.r, vertex_ink.g), vertex_ink.b) > 0.99) {
		float level = clamp((local_position.y - 99.0) / 84.0, 0.0, 1.0);
		vec3 metal = mix(vec3(1.0, 0.96, 0.72), vec3(1.0, 0.80, 0.31), smoothstep(0.05, 0.42, level));
		metal = mix(metal, vec3(0.75, 0.43, 0.10), smoothstep(0.44, 0.54, level));
		metal = mix(metal, vec3(1.0, 0.82, 0.34), smoothstep(0.55, 0.73, level));
		metal = mix(metal, vec3(0.91, 0.56, 0.14), smoothstep(0.80, 1.0, level));
		COLOR = vec4(metal * source.rgb, source.a);
	} else {
		COLOR = source;
	}
}

