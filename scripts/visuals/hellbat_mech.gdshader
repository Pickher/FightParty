shader_type spatial;

uniform vec4 team_paint : source_color;
uniform float stride = 0.0;
varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
	// The imported single mesh has no skeleton. Advance the two feet in opposite
	// directions and blend the displacement out at the hips.
	float leg = 1.0 - smoothstep(0.16, 0.40, VERTEX.y);
	float step_offset = stride * smoothstep(0.02, 0.13, abs(VERTEX.z)) * sign(VERTEX.z);
	VERTEX.x += step_offset * leg * 0.12;
	VERTEX.y += max(step_offset, 0.0) * leg * 0.04;
}

void fragment() {
	float shoulder = smoothstep(0.22, 0.35, abs(model_pos.z)) * smoothstep(0.34, 0.52, model_pos.y);
	vec3 steel = mix(vec3(0.11, 0.15, 0.18), vec3(0.37, 0.41, 0.43), smoothstep(0.2, 0.58, model_pos.y));
	ALBEDO = mix(steel, team_paint.rgb, shoulder * 0.85);
	METALLIC = 0.38;
	ROUGHNESS = 0.63;
}
