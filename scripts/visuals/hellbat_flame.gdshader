shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float elapsed;
uniform float firing_time;
uniform float spread = 0.4142;
uniform float reach;
uniform float nozzle_angle;
uniform float nozzle_pitch;
uniform float shot_seed;
float hash(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}
float noise_field(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);
}
float sweep(float seconds) {
	return 0.52 * sin(seconds * 8.4) * smoothstep(0.0,0.09,seconds);
}
void vertex() {
	float u = UV.x, flank = UV.y * 2.0 - 1.0;
	float now = min(elapsed,firing_time);
	// Downstream fire keeps the nozzle bearing from the instant that fuel left it.
	float past = max(0.0, now - 0.15 * smoothstep(0.0, 0.96, u));
	float angle = nozzle_angle + 0.64 * (sweep(past) - sweep(now));
	vec3 axis = vec3(cos(angle),0,sin(angle));
	vec3 lateral = vec3(-axis.z,0,axis.x);
	vec3 eye = normalize(inverse(mat3(MODEL_MATRIX)) * INV_VIEW_MATRIX[2].xyz);
	vec3 facing = cross(axis, eye);
	if (dot(facing,lateral)<0.0) { facing = -facing; }
	vec3 span = normalize(lateral + 0.65 * facing);
	float width = 0.025 + reach * spread * (0.26*u + 0.74*pow(u,0.94));
	VERTEX = axis * (reach*u) + span * (flank*width);
	VERTEX.y += tan(nozzle_pitch) * min(reach*u,0.35) - 0.20*u*u;
}
void fragment() {
	float u = UV.x, v = UV.y * 2.0 - 1.0;
	float time = elapsed + shot_seed;
	vec2 p = vec2(u*6.4 - time*9.2, v*2.35 + 0.32*sin(u*7.0-time*6.0));
	float f = noise_field(p)*0.54 + noise_field(p*2.13+4.5)*0.30 + noise_field(p*4.21-3.0)*0.16;
	float drift = (0.12*sin(u*16.0-time*11.0)+0.08*sin(u*9.0-time*6.0))*u;
	float billow = (0.53 + 0.62*f) * (1.0 - 0.38*smoothstep(0.55,0.99,u));
	float envelope = billow - abs(v-drift) + 0.28*(f-.5);
	float fingers = 0.5 + 0.5*sin(v*15.2 + 2.6*noise_field(vec2(v*6.0,time*2.6)) - time*3.0);
	float front = min(0.81 + 0.17*fingers - 0.09*abs(v) + 0.06*(f-.5), 0.04 + elapsed*6.4);
	float tail = clamp((elapsed-firing_time)*6.3,0.0,1.16);
	float tip = (1.0 - smoothstep(front-.13,front+.025,u)) * (1.0 - smoothstep(.93,1.0,u));
	float alpha = smoothstep(-.13,.19,envelope)*tip*smoothstep(tail-.11,tail+.015,u);
	float hot = clamp(envelope*1.22 + (f-0.49)*1.7 - u*.44,0.0,1.0);
	vec3 color = mix(vec3(.78,.21,.026),vec3(1.,.49,.056),smoothstep(.05,.42,hot));
	color = mix(color,vec3(1.,.90,.52),smoothstep(.40,.83,hot));
	color = mix(color,vec3(.76,.90,1.0),0.82*(1.0-smoothstep(.0,.10,u))*hot);
	ALBEDO = color;
	ALPHA = alpha * (.43+.55*hot) * (1.0-smoothstep(firing_time+.07,firing_time+.19,elapsed));
}
