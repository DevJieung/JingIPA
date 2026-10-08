shader_type spatial;
render_mode diffuse_burley;
uniform vec4 ground_color : source_color = vec4(0.12,0.20,0.22,1.0);
uniform vec4 moss_color : source_color = vec4(0.14,0.27,0.20,1.0);
uniform float motif_seed = 1.0;
float random(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))+motif_seed)*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(random(i),random(i+vec2(1.0,0.0)),f.x),mix(random(i+vec2(0.0,1.0)),random(i+vec2(1.0,1.0)),f.x),f.y);
}
void fragment() {
 float patches=noise(UV*13.0)+noise(UV*27.0)*0.25;
 float grit=noise(UV*420.0);
 ALBEDO=mix(ground_color.rgb,moss_color.rgb,smoothstep(0.42,0.86,patches))*(0.73+grit*0.30);
 ROUGHNESS=0.96;
}
