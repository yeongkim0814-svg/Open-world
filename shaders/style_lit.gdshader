shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// 공통 색면 재질 (바위·건축·구름·나무 줄기). 색 = 기본색(고갈↔회복) × 정점색 RGB × 저주파 얼룩, AO = 정점색 A.
// 생성기 메시는 이미 면마다 법선이 따로라 평면 음영. flat_shading은 부드러운 메시를 각지게 볼 때만.
#include "res://shaders/style_common.gdshaderinc"

uniform vec3 color_depleted : source_color = vec3(0.26, 0.28, 0.27);
uniform vec3 color_restored : source_color = vec3(0.27, 0.25, 0.22);
uniform float noise_amount = 0.06;
uniform float roughness = 0.95;
uniform bool flat_shading = false;
uniform float flat_fade_end = 150.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float wobble = 0.0;           // 구름: 노이즈 정점 움직임 (정점색 G 가중, 모델 크기 비율)

varying vec3 v_world;
varying float v_r;

void vertex() {
	if (wobble > 0.0) {
		float ph = dot(VERTEX, vec3(3.1, 2.3, 1.7));
		VERTEX += NORMAL * sin(TIME * 0.35 + ph) * wobble * COLOR.g;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_r = recovery_at(v_world);
}

void fragment() {
	// 구름(wobble > 0)은 정점색 G = 흔들림 가중이라 색에는 R(명도)만 쓴다.
	vec3 vc = wobble > 0.0 ? vec3(COLOR.r) : COLOR.rgb;
	ALBEDO = style_color(color_depleted, color_restored, v_r, v_world, noise_amount) * vc;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = roughness;
	if (flat_shading) {
		float k = 1.0 - smoothstep(flat_fade_end * 0.7, flat_fade_end, -VERTEX.z);
		NORMAL = normalize(mix(NORMAL, face_normal(VERTEX), k));
	}
	EMISSION = emission_color * emission_energy;
}
