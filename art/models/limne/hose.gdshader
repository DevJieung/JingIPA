shader_type spatial;
render_mode cull_back;
uniform vec3 p0;
uniform vec3 p1;
uniform vec3 p2;
uniform vec3 p3;
void vertex() {
	float t = VERTEX.z;
	float u = 1.0 - t;
	vec3 center = u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3;
	vec3 tangent = normalize(3.0*u*u*(p1-p0)+6.0*u*t*(p2-p1)+3.0*t*t*(p3-p2));
	vec3 axis = abs(tangent.z) < 0.97 ? vec3(0,0,1) : vec3(1,0,0);
	vec3 right = normalize(cross(tangent,axis));
	vec3 up = cross(right,tangent);
	vec3 normal = (right*VERTEX.x + up*VERTEX.y)/0.026;
	VERTEX = center + normal*0.026;
	NORMAL = normalize(normal);
}
void fragment() {
	ALBEDO = vec3(0.028,0.12,0.31);
	ROUGHNESS = 0.72;
}
