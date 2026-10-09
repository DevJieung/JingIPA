shader_type spatial;
render_mode diffuse_burley;
uniform vec4 road_color : source_color = vec4(0.29,0.40,0.45,1.0);
uniform float field_radius = 10.0;
uniform bool plaza = false;
varying vec2 ground_uv;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() { ground_uv=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
 if(length(ground_uv)>field_radius+0.012) discard;
 vec2 paving=plaza ? ground_uv*vec2(1.25,1.7) : vec2(UV.x*1.25,UV.y*3.0);
 paving.x+=mod(floor(paving.y),2.0)*0.5;
 vec2 cell=fract(paving);
 float seam=1.0-smoothstep(0.015,0.055,min(min(cell.x,1.0-cell.x),min(cell.y,1.0-cell.y)));
 float grain=hash(floor(ground_uv*47.0));
 float variation=hash(floor(paving));
 float rim=plaza ? 0.0 : smoothstep(0.86,0.98,abs(UV.y-0.5)*2.0);
 ALBEDO=road_color.rgb*(0.81+variation*0.19+grain*0.07)*(1.0-seam*0.31);
 ALBEDO=mix(ALBEDO,road_color.rgb*1.32,rim*0.62);
 ROUGHNESS=0.92;
 METALLIC=0.03;
}
