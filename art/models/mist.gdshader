shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
float cloud(vec2 p) { return (sin(p.x*1.7+sin(p.y*1.2))+cos(p.y*2.1+sin(p.x*0.7)))*0.25+0.5; }
void fragment() {
 float body=cloud(UV*8.0+vec2(TIME*0.024,TIME*0.013));
 float edge=smoothstep(0.0,0.12,UV.x)*smoothstep(0.0,0.12,1.0-UV.x)*smoothstep(0.0,0.12,UV.y)*smoothstep(0.0,0.12,1.0-UV.y);
 ALBEDO=vec3(0.54,0.64,0.70);
 ALPHA=smoothstep(0.35,0.90,body)*0.14*edge;
}
