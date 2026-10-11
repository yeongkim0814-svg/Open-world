shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// 풀 덩어리 카드 (MultiMesh). UV.y = 높이 0(뿌리)→1(끝), UV.x = 풀잎 번호 0..1.
// 회복 전: 키 40%·누런 잿빛·바람 약함 / 회복 후: 키 100%·연두 #8CC63F ↔ 짙은 초록 #4E8F2A·흰 꽃점.
#include "res://shaders/vitality.gdshaderinc"

uniform vec3 tip_color : source_color = vec3(0.549, 0.776, 0.247);   // #8CC63F
uniform vec3 root_color : source_color = vec3(0.306, 0.561, 0.165);  // #4E8F2A
uniform vec3 grey_tip : source_color = vec3(0.58, 0.55, 0.42);
uniform vec3 grey_root : source_color = vec3(0.32, 0.30, 0.25);
uniform float wind_strength = 0.35;
uniform float wind_speed = 1.4;
uniform float fade_start = 28.0;
uniform float fade_end = 40.0;

varying vec3 v_world;
varying float v_h;
varying float v_t;
varying float v_rand;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float t = vitality_t(origin, 10.0);
	float rnd = hash12(origin.xz * 7.13);
	float h = UV.y;
	// 거리 페이드: 반경 가장자리에서 땅 속으로 줄어든다.
	float cam_d = distance(origin.xz, CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, cam_d);
	float height_scale = mix(0.4, 1.0, t) * fade;
	VERTEX.y *= height_scale;
	// 바람: 시간 + 위치 노이즈, 끝으로 갈수록 크게.
	float ph = origin.x * 0.21 + origin.z * 0.17;
	float w = sin(TIME * wind_speed + ph) * 0.6 + sin(TIME * wind_speed * 2.3 + ph * 1.9 + rnd * 6.28) * 0.4;
	float gust = sin(TIME * 0.45 + origin.x * 0.05) * 0.5 + 0.5;
	float amp = wind_strength * mix(0.25, 1.0, t) * (0.6 + 0.8 * gust);
	vec3 off_world = vec3(w, 0.0, w * 0.5 + cos(TIME * wind_speed * 0.7 + ph) * 0.3) * amp * h * h;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off_world;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_h = h;
	v_t = t;
	v_rand = rnd;
}

void fragment() {
	float t = v_t;
	vec3 col_color = mix(root_color, tip_color, smoothstep(0.0, 1.0, v_h));
	col_color *= 0.9 + 0.2 * v_rand;
	vec3 col_grey = mix(grey_root, grey_tip, smoothstep(0.0, 1.0, v_h));
	vec3 c = mix(col_grey, col_color, t);
	// 꽃: 일부 덩어리의 끝에 흰 점 (회복 후에만).
	float flower = step(0.93, v_rand) * smoothstep(0.88, 0.95, v_h) * t;
	c = mix(c, vec3(0.97, 0.96, 0.9), flower);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	// 뿌리 쪽은 그림자 느낌으로 더 어둡게.
	AO = mix(0.55, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.5;
	// 법선을 위쪽으로 모아 부드러운 조명, 역광은 빛이 비쳐 보이게.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up_view, 0.6));
	BACKLIGHT = c * mix(0.25, 0.7, t) * (0.4 + 0.6 * v_h);
}
