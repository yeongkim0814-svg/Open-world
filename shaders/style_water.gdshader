shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx, depth_draw_opaque;
// 물: 단색 + 얕음/깊음(정점색 R = 깊이 0~1, 높이 지도로 미리 계산) + 약한 파문. 깊이·화면 텍스처를 읽지 않는다(웹 호환).
#include "res://shaders/style_common.gdshaderinc"

uniform vec3 shallow_depleted : source_color = vec3(0.35, 0.43, 0.45);
uniform vec3 shallow_restored : source_color = vec3(0.16, 0.48, 0.49);
uniform vec3 deep_depleted : source_color = vec3(0.16, 0.22, 0.24);
uniform vec3 deep_restored : source_color = vec3(0.03, 0.16, 0.27);
uniform float alpha_deep = 0.9;
uniform float alpha_shore = 0.45;
uniform float wave_scale = 0.18;
uniform float wave_speed = 0.05;
uniform float wave_strength = 0.25;

varying vec3 v_world;
varying float v_depth;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = COLOR.r;
}

float wave_h(vec2 p) {
	return big_noise(p) * 0.65 + big_noise(p * 2.3 + 7.1) * 0.35;
}

void fragment() {
	float r = recovery_at(v_world);
	vec3 shallow = mix(shallow_depleted, shallow_restored, r);
	vec3 deep = mix(deep_depleted, deep_restored, r);
	ALBEDO = mix(shallow, deep, smoothstep(0.0, 1.0, v_depth));
	vec2 p = v_world.xz * wave_scale + TIME * wave_speed * vec2(1.0, 0.7);
	float e = 0.05;
	float h = wave_h(p);
	vec2 g = vec2(wave_h(p + vec2(e, 0.0)) - h, wave_h(p + vec2(0.0, e)) - h) / e;
	vec3 wn = normalize(vec3(-g.x * wave_strength, 1.0, -g.y * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = mix(0.35, 0.12, r);
	SPECULAR = 0.5;
	ALPHA = mix(alpha_shore, alpha_deep, smoothstep(0.0, 0.35, v_depth));
}
