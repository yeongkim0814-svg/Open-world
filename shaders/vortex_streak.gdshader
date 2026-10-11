// 탑 소용돌이 입자 (03 그래픽 설계서 5장): 속도 방향으로 늘어난 가는 줄.
// GPUParticles3D.transform_align = Z 빌보드 + Y 를 속도 방향 → 세로로 긴 쿼드가 흐름을 따라 눕는다.
// 카메라 가까이(렌즈의 먼지처럼 보이는 것)와 아주 먼 곳은 투명하게.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.26, 0.27, 0.31);
uniform float max_alpha : hint_range(0.0, 1.0) = 0.6;
uniform float near_fade_start = 6.0;
uniform float near_fade_end = 22.0;
uniform float far_fade_start = 160.0;
uniform float far_fade_end = 260.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// 가로로 부드럽게, 세로로 양 끝이 가늘어지는 줄
	float across = 1.0 - smoothstep(0.0, 1.0, abs(p.x));
	float along = 1.0 - smoothstep(0.3, 1.0, abs(p.y));
	float d = length(VERTEX);
	float fade = smoothstep(near_fade_start, near_fade_end, d) * (1.0 - smoothstep(far_fade_start, far_fade_end, d));
	ALBEDO = color;
	ALPHA = across * along * fade * max_alpha * COLOR.a;
}
