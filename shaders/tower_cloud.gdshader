// 탑 위 먹구름 (03 그래픽 설계서 5장): 경계가 없는 흐린 구름 덩어리.
// 수평 판 + 반지름 감쇠 + 천천히 흐르는 FBM 노이즈 → 가장자리가 흐린 하늘에 녹아든다.
// opacity = 0 이면 완전히 걷힘 (first_island.gd set_recovered_visuals).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_core : source_color = vec3(0.20, 0.21, 0.24);
uniform vec3 color_edge : source_color = vec3(0.42, 0.44, 0.48);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float inner = 0.15;     // 반지름 비율: 여기까지 진하다
uniform float outer = 0.95;     // 여기서 0
uniform float noise_scale = 3.5;
uniform float speed = 0.012;

varying vec2 local_uv;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.02 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return s / 0.97;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = TIME * speed;
	// 소용돌이처럼 천천히 도는 좌표
	float ang = t * 0.6 * (1.0 - r);
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 q = rot * p * noise_scale;
	float n = fbm(q + vec2(t, -t * 0.7));
	float n2 = fbm(q * 2.3 - vec2(t * 1.3, t * 0.4) + n);
	float dens = n * 0.6 + n2 * 0.4;
	// 가장자리를 노이즈로 들쭉날쭉하게
	float rr = r + (dens - 0.5) * 0.35;
	float falloff = 1.0 - smoothstep(inner, outer, rr);
	float a = falloff * smoothstep(0.25, 0.75, dens + falloff * 0.35);
	// 아래에서 거의 수평으로 볼 때 판의 선이 보이지 않게
	vec3 v = normalize(-VERTEX);
	float facing = abs(dot(NORMAL, v));
	a *= smoothstep(0.03, 0.25, facing);
	ALBEDO = mix(color_core, color_edge, clamp(rr * 0.9 + (1.0 - dens) * 0.3, 0.0, 1.0));
	ALPHA = clamp(a * max_alpha * opacity, 0.0, 1.0);
}
