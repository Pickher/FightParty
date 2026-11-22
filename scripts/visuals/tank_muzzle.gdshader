shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float age;
uniform float siege;
uniform float seed;
varying float vent;
float hash(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}
float noise2(vec2 p) {
	vec2 cell = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+1.0),f.x),f.y);
}
void vertex() {
	vent = round(COLOR.r*2.0);
	float sign_side = vent < 1.5 ? -1.0 : 1.0;
	vec3 axis = vent < 0.5 ? vec3(1,0,0) : normalize(vec3(0.50,0.08,sign_side));
	vec3 camera_direction = normalize(inverse(mat3(MODEL_MATRIX)) * INV_VIEW_MATRIX[2].xyz);
	vec3 span = cross(axis,camera_direction);
	span = dot(span,span)>0.00001 ? normalize(span) : vec3(0,1,0);
	float smoke = smoothstep(0.06,0.22,age);
	float length_fire = mix(0.26,0.44,siege)*(vent < 0.5 ? 1.0 : 0.49);
	float mouth = mix(0.047,0.083,siege)*(vent < 0.5 ? 1.0 : 0.68);
	float u = UV.x;
	float distance = (u-0.015) * length_fire * (0.76 + 0.32*smoothstep(0.,0.035,age) + smoke*0.48);
	VERTEX = axis * distance + span * (UV.y*2.0-1.0)*mouth*(0.65 + u + 0.78*smoke);
	VERTEX.y += smoke * u * mix(0.054,0.09,siege);
}
void fragment() {
	float u = UV.x, v = UV.y * 2.0 - 1.0;
	float f = noise2(vec2(u*6.0-age*15.0+seed, v*2.5+seed))*.67
			+ noise2(vec2(u*11.0-age*22.0, v*5.6))*.33;
	float fire_t = age / mix(0.107,0.152,siege);
	float profile = mix(0.63,0.93,sin(3.14159*u))*(1.0 - .55*smoothstep(.43,1.,u));
	float envelope = profile - abs(v) + (f-.50)*.53;
	float front = .88 + .10*sin(v*7.2+seed) - .19*abs(v);
	float fire = smoothstep(-.10,.13,envelope) * (1.-smoothstep(front-.16,front+.02,u))
			* (1.-smoothstep(.25,1.,fire_t));
	float smoke_t = age / mix(.25,.38,siege);
	float soot = smoothstep(-.14,.21,envelope) * smoothstep(.08,.35,smoke_t)
			* (1.-smoothstep(.38,1.,smoke_t)) * (1.-smoothstep(.57,.97,u)) * (.50+.50*f);
	float heat = clamp(envelope*1.45 + (.50-u)*.65,0.,1.);
	vec3 flame = mix(vec3(1.,.27,.035),vec3(1.,.98,.78),smoothstep(.05,.79,heat));
	vec3 fumes = mix(vec3(.34,.31,.28),vec3(.64,.61,.56),f);
	ALBEDO = mix(fumes,flame,fire/(fire+soot*.48+.001));
	ALPHA = max(fire,soot*.52) * (vent < .5 ? 1. : siege*.81);
}
