shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D shoe_path : filter_linear, repeat_enable;
uniform float distance_traveled;
uniform float perimeter;
uniform float belt_width;
uniform float shoe_count;
uniform float coverage = 1.0;
varying vec3 pad;
varying float steel_link;

vec3 on_path(float t) {
	return textureLod(shoe_path, vec2(t, 0.5), 0.0).xyz;
}
void vertex() {
	float t = (float(INSTANCE_ID)+0.5)/shoe_count + distance_traveled/perimeter;
	vec3 center = on_path(t);
	vec3 tangent = normalize(on_path(t+0.004)-on_path(t-0.004));
	vec3 side = normalize(vec3(0,0,1)-tangent*tangent.z);
	vec3 normal = normalize(cross(side,tangent));
	mat3 frame = mat3(tangent,normal,side);
	pad = VERTEX;
	vec3 dimensions = vec3(perimeter/shoe_count*0.81,0.009,belt_width);
	VERTEX = center + normal * 0.0018 + frame*(VERTEX*dimensions);
	NORMAL = normalize(frame*NORMAL);
	steel_link = mod(float(INSTANCE_ID),6.) < 0.5 ? 1.0 : 0.0;
}
void fragment() {
	vec2 pixel = floor(FRAGCOORD.xy);
	if (coverage <= fract(52.9829189*fract(dot(pixel,vec2(.06711056,.00583715))))) { discard; }
	float cleat = 1.0-smoothstep(.09,.23,abs(pad.x-.16*abs(pad.z)));
	float wear = min(.95,.17+steel_link*.34+cleat*.39+smoothstep(.35,.49,abs(pad.z))*.14);
	ALBEDO = mix(vec3(.12,.145,.16),vec3(.39,.42,.42),wear);
	ROUGHNESS = .79 - .19*wear;
	METALLIC = .39;
}
