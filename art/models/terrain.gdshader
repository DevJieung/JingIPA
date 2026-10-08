shader_type spatial;
render_mode diffuse_burley;
uniform vec4 ground_color : source_color = vec4(0.12,0.20,0.22,1.0);
uniform vec4 moss_color : source_color = vec4(0.14,0.27,0.20,1.0);
uniform float motif_seed = 1.0;
varying vec2 ground_uv;
float random(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))+motif_seed)*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(random(i),random(i+vec2(1.0,0.0)),f.x),mix(random(i+vec2(0.0,1.0)),random(i+vec2(1.0,1.0)),f.x),f.y);
}
void vertex() {
 ground_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
 // World scale keeps the moss readable on both ground meshes and at camera zooms.
 float patches=noise(ground_uv*0.53)+noise(ground_uv*1.6)*0.26;
 float grit=noise(ground_uv*26.0);
 float soil=noise(ground_uv*3.2);
 ALBEDO=mix(ground_color.rgb,moss_color.rgb,smoothstep(0.38,0.82,patches))*(0.78+soil*0.20+grit*0.08);
 // Analytic micro-normal: a quiet surface variation, not a swimming screen filter.
 NORMAL_MAP=normalize(vec3(dFdx(soil)*0.25,dFdy(soil)*0.25,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH=0.28;
 ROUGHNESS=0.96;
}
