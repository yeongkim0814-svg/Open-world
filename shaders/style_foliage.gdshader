shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;
// 식생 재질 (풀·나무 잎). style_lit + 정점 바람 + 회복에 따른 밀도·키.
// 정점색 (ArrayMesh는 8비트 0~1): R = 명도(×1.1), G = 바람 가중(뿌리 0 → 꼭대기 1), B ≥ 0.5 = 꽃 정점, A = AO.
// MultiMesh의 INSTANCE_CUSTOM.r = 0~1 문턱값: 인스턴스 위치의 밀도보다 크면 정점을 접어 숨긴다.
// instance_tint 켜면: .g = 명도(0..1 → ×0.85..1.12), .b = 색온도(0 차가움 ↔ 1 따뜻함, ±6 % 녹/황 이동), .a = 꽃색(< 0.5 노랑, ≥ 0.5 흰색).
#include "res://shaders/style_common.gdshaderinc"

uniform vec3 color_depleted : source_color = vec3(0.647, 0.675, 0.569);
uniform vec3 color_restored : source_color = vec3(0.435, 0.639, 0.353);
uniform vec3 tip_depleted : source_color = vec3(0.722, 0.737, 0.643);
uniform vec3 tip_restored : source_color = vec3(0.612, 0.769, 0.431);
uniform vec3 flower_depleted : source_color = vec3(0.769, 0.761, 0.722);
uniform vec3 flower_restored : source_color = vec3(0.933, 0.827, 0.416);
uniform vec3 flower2_depleted : source_color = vec3(0.847, 0.839, 0.808);
uniform vec3 flower2_restored : source_color = vec3(0.957, 0.945, 0.902);
uniform bool instance_tint = false;   // true 면 INSTANCE_CUSTOM.g/.b/.a 를 개체 색(명도·색온도·꽃색)으로 쓴다
uniform float noise_amount = 0.06;
uniform float roughness = 0.95;
uniform float wind_strength = 0.06;
uniform float wind_speed = 1.2;
uniform float density_depleted = 0.35;
uniform float density_restored = 1.0;
uniform float fade_start = 24.0;      // 카메라 거리 페이드 (풀: 먼 곳 반짝임·삼각형 줄이기, 나무는 크게)
uniform float fade_end = 36.0;
uniform float height_depleted = 0.6;   // 고갈 시 키 배율 (나무 잎은 1.0으로 둔다)

varying vec3 v_world;
varying float v_r;
varying vec3 v_tint;   // x = 명도 배율, y = 색온도(0..1), z = 꽃색 선택(0/1)

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

	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(origin, CAMERA_POSITION_WORLD));
	if (INSTANCE_CUSTOM.r > mix(density_depleted, density_restored, r) * fade) {
		p = vec3(0.0);
	}
	VERTEX = p;
	v_tint = vec3(1.0, 0.5, 0.0);
	if (instance_tint) {
		v_tint = vec3(mix(0.85, 1.12, INSTANCE_CUSTOM.g), INSTANCE_CUSTOM.b, step(0.5, INSTANCE_CUSTOM.a));
	}
	v_world = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec3 body = style_color(color_depleted, color_restored, v_r, v_world, noise_amount);
	vec3 tip = style_color(tip_depleted, tip_restored, v_r, v_world, noise_amount);
	vec3 col = mix(body, tip, smoothstep(0.25, 1.0, COLOR.g));
	if (COLOR.b > 0.5 && v_r >= 0.5) {
		vec3 yellow = style_color(flower_depleted, flower_restored, v_r, v_world, noise_amount * 0.5);
		vec3 white = style_color(flower2_depleted, flower2_restored, v_r, v_world, noise_amount * 0.5);
		col = mix(yellow, white, v_tint.z);
	} else if (instance_tint) {
		// 색온도: 0.5 가 중립. 따뜻하면 황색(빨강↑ 파랑↓), 차가우면 녹색(녹↑ 빨강↓), 최대 ±6 %
		float w = (v_tint.y - 0.5) * 2.0;
		vec3 shift = w > 0.0 ? vec3(1.06, 1.02, 0.94) : vec3(0.97, 1.06, 1.0);
		col *= mix(vec3(1.0), shift, abs(w));
	}
	ALBEDO = col * (COLOR.r * 1.1) * v_tint.x;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = roughness;
}
