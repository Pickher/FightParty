shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D paint_map : source_color, hint_default_white, filter_nearest, repeat_disable;
uniform sampler2D metal_map : hint_default_white, filter_nearest, repeat_disable;
uniform sampler2D light_map : source_color, hint_default_black, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 lamp : source_color = vec4(0.0);
uniform float metal;
uniform float roughness;
uniform vec3 rail;
uniform float edge;
uniform float direction;
uniform float damage = 0.0;
uniform float coverage = 1.0;
varying float along;
void vertex() { along = dot(VERTEX,rail); }
void fragment() {
	// The solid leading edge seats over the other skin as this particular joint travels.
	if ((along-edge)*direction < 0.0) { discard; }
	if (coverage < 1.0) {
		float threshold = fract(52.9829189 * fract(dot(floor(FRAGCOORD.xy), vec2(.06711056, .00583715))));
		if (coverage <= threshold) { discard; }
	}
	vec3 rm = texture(metal_map,UV).rgb;
	ALBEDO = tint.rgb * texture(paint_map,UV).rgb * mix(vec3(1.), vec3(.38,.34,.30), damage);
	ROUGHNESS = mix(roughness * rm.g, .91, damage);
	METALLIC = metal * rm.b * (1.0 - .4 * damage);
	EMISSION = lamp.rgb * texture(light_map,UV).rgb * (1.0 - damage);
}
