shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// 바위 재질 (B2 9.2): style_lit + 윗면 이끼. 정점색 R = 명도, B ≥ 0.95 = 윗면(법선 y > 0.6, RockGen), A = AO.
// 윗면은 이끼색(회복 0 = 마른 황회색, 회복 1 = 이끼 초록), 나머지는 몸체색(회복 0 = 차가운 청회색).
#include "res://shaders/style_common.gdshaderinc"

uniform vec3 color_depleted : source_color = vec3(0.494, 0.522, 0.549);
uniform vec3 color_restored : source_color = vec3(0.557, 0.541, 0.510);
uniform vec3 moss_depleted : source_color = vec3(0.620, 0.604, 0.525);
uniform vec3 moss_restored : source_color = vec3(0.435, 0.561, 0.333);
uniform float noise_amount = 0.06;
uniform float roughness = 0.95;
uniform bool flat_shading = false;
uniform float flat_fade_end = 150.0;

varying vec3 v_world;
varying float v_r;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_r = recovery_at(v_world);
}

void fragment() {
	vec3 body = style_color(color_depleted, color_restored, v_r, v_world, noise_amount);
	vec3 moss = style_color(moss_depleted, moss_restored, v_r, v_world, noise_amount);
	float top = step(0.95, COLOR.b);
	// 명도는 R 만 쓴다 (B 채널이 윗면 표시라 RGB 를 그대로 곱하면 푸른 기가 낀다)
	ALBEDO = mix(body, moss, top) * COLOR.r;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = roughness;
	if (flat_shading) {
		float k = 1.0 - smoothstep(flat_fade_end * 0.7, flat_fade_end, -VERTEX.z);
		NORMAL = normalize(mix(NORMAL, face_normal(VERTEX), k));
	}
}
