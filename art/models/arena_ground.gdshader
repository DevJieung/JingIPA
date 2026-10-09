shader_type spatial;
render_mode diffuse_burley;
uniform vec4 ground_color : source_color = vec4(0.05, 0.17, 0.25, 1.0);
uniform vec4 edge_color : source_color = vec4(0.45, 0.62, 0.72, 1.0);
uniform vec2 half_extent = vec2(11.04, 8.16);
uniform float field_radius = 0.0;
uniform float frozen = 1.0;
uniform float motif_seed = 1.0;
varying vec2 ground_uv;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))+motif_seed)*43758.5453); }
vec2 hash2(vec2 p) { return vec2(hash(p), hash(p+vec2(19.7,41.3))); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);
}
void vertex() { ground_uv = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz; }
void fragment() {
 vec2 p=ground_uv;
 vec2 warped=p+vec2(noise(p*0.87),noise(p*0.91+vec2(32.0,19.0)))*0.65;
 float cloud=noise(p*0.42)*0.6+noise(p*1.1)*0.28+noise(p*3.7)*0.12;
 float grain=noise(p*31.0);
 vec2 cell=floor(warped*0.76); vec2 local=fract(warped*0.76);
 float first=8.0; float second=8.0;
 for(int x=-1;x<=1;x++) { for(int y=-1;y<=1;y++) {
  vec2 offset=vec2(float(x),float(y));
  vec2 delta=offset+hash2(cell+offset)-local;
  float dist=dot(delta,delta);
  if(dist<first) { second=first; first=dist; } else if(dist<second) { second=dist; }
 } }
 float crack_mask=smoothstep(0.20,0.70,noise(p*0.31+vec2(17.0,7.0)));
 float fracture=(1.0-smoothstep(0.015,0.065,second-first))*crack_mask;
 float hairline=(1.0-smoothstep(0.009,0.026,second-first))*crack_mask;
 float distance_to_edge=field_radius>0.0 ? field_radius-length(p) : min(half_extent.x-abs(p.x),half_extent.y-abs(p.y));
 float snow=1.0-smoothstep(0.15,1.65,distance_to_edge+(cloud-0.5)*1.8);
 float frost=smoothstep(0.58,0.78,cloud)*0.23;
 vec3 deep=ground_color.rgb*(0.58+cloud*0.67);
 vec3 ice=mix(deep,vec3(0.13,0.41,0.53),cloud*0.18*frozen);
 ice+=vec3(0.22,0.47,0.58)*fracture*0.19*frozen;
 ice+=vec3(0.31,0.62,0.70)*hairline*0.09*frozen;
 float streak=noise(p*vec2(5.0,1.2)+cloud*1.1);
 ALBEDO=mix(ice,edge_color.rgb,snow*0.53+frost*frozen)*(0.76+grain*0.10+streak*0.17);
 ROUGHNESS=mix(0.91,0.32+cloud*0.16,frozen*(1.0-snow));
 METALLIC=0.12*frozen*(1.0-snow);
 SPECULAR=0.46;
 EMISSION=vec3(0.01,0.035,0.045)*hairline*frozen;
}
