shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;
// 식생 재질 (풀·나무 잎). style_lit + 정점 바람 + 회복에 따른 밀도·키.
// 정점색 (ArrayMesh는 8비트 0~1): R = 명도(×1.1), G = 바람 가중(뿌리 0 → 꼭대기 1), B ≥ 0.5 = 꽃 정점, A = AO.
// MultiMesh의 INSTANCE_CUSTOM.r = 0~1 문턱값: 인스턴스 위치의 밀도보다 크면 정점을 접어 숨긴다.
#include "res://shaders/style_common.gdshaderinc"

uniform vec3 color_depleted : source_color = vec3(0.647, 0.675, 0.569);
uniform vec3 color_restored : source_color = vec3(0.435, 0.639, 0.353);
uniform vec3 tip_depleted : source_color = vec3(0.722, 0.737, 0.643);
uniform vec3 tip_restored : source_color = vec3(0.612, 0.769, 0.431);
uniform vec3 flower_depleted : source_color = vec3(0.769, 0.761, 0.722);
uniform vec3 flower_restored : source_color = vec3(0.933, 0.827, 0.416);
uniform float noise_amount = 0.06;
uniform float roughness = 0.95;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.2;
uniform float density_depleted = 0.35;
uniform float density_restored = 1.0;
uniform float height_depleted = 0.6;   // 고갈 시 키 배율 (나무 잎은 1.0으로 둔다)

varying vec3 v_world;
varying float v_r;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float r = recovery_at(origin);
	v_r = r;

	vec3 p = VERTEX;
	p.y *= mix(height_depleted, 1.0, r);
	// 부드러운 흔들림: 위치마다 위상이 달라 군집이 한꺼번에 움직이지 않는다.
	float ph = TIME * wind_speed + origin.x * 0.7 + origin.z * 0.5;
	float sway = sin(ph) * 0.7 + sin(ph * 2.3 + 1.7) * 0.3;
	p.x += sway * wind_strength * COLOR.g;
	p.z += cos(ph * 0.8) * wind_strength * 0.6 * COLOR.g;

	if (INSTANCE_CUSTOM.r > mix(density_depleted, density_restored, r)) {
		p = vec3(0.0);
	}
	VERTEX = p;
	v_world = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec3 body = style_color(color_depleted, color_restored, v_r, v_world, noise_amount);
	vec3 tip = style_color(tip_depleted, tip_restored, v_r, v_world, noise_amount);
	vec3 col = mix(body, tip, smoothstep(0.25, 1.0, COLOR.g));
	if (COLOR.b > 0.5 && v_r >= 0.5) {
		col = style_color(flower_depleted, flower_restored, v_r, v_world, noise_amount * 0.5);
	}
	ALBEDO = col * (COLOR.r * 1.1);
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = roughness;
}
