shader_type spatial;
// 물 (바다·저수호 공용). 반투명 알파 혼합 + 깊이 텍스처 1회 읽기.
// 불투명 대신 반투명을 고른 이유: 깊이 색·물가 투명 가장자리를 한 패스로 해결하고, 굴절용 SCREEN_TEXTURE
// (화면 복사 = 타일러 GPU에서 비싼 추가 패스)를 쓰지 않기 위함. 깊이 텍스처는 Forward+가 이미 만들어 둔다.
// 회복 전: 탁한 청회색·반사 약함·거품 약함 / 회복 후: 얕은 청록 #3FA7B5 → 깊은 청, 하늘 반사.
// SSR 없음: 하늘 radiance(ROUGHNESS 기반 반사) + 프레넬로 알파를 올려 반사가 살도록 한다.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;
#include "res://shaders/vitality.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec3 shallow_color : source_color = vec3(0.247, 0.655, 0.710);   // #3FA7B5
uniform vec3 deep_color : source_color = vec3(0.06, 0.26, 0.44);
uniform vec3 grey_shallow : source_color = vec3(0.42, 0.50, 0.55);
uniform vec3 grey_deep : source_color = vec3(0.17, 0.22, 0.28);
uniform float depth_range = 6.0;        // 이 깊이(m)에서 완전히 깊은 색
uniform float clear_depth = 1.2;        // 이 깊이(m)에서 알파가 거의 차오름
uniform float min_alpha = 0.35;
uniform float max_alpha = 0.95;

uniform float wave_scale = 0.12;        // 노멀 무늬 크기 (1/m)
uniform float wave_speed = 0.05;
uniform float wave_strength = 0.5;
uniform float rough_clear = 0.15;
uniform float rough_grey = 0.5;
uniform float spec_clear = 0.4;
uniform float spec_grey = 0.12;

// 원거리: 수평선 쪽 밝은 청록·잔잔한 노멀·높은 거칠기 (탑 꼭대기에서 반짝임이 거슬리지 않게)
uniform vec3 horizon_color : source_color = vec3(0.30, 0.55, 0.66);
uniform vec3 grey_horizon : source_color = vec3(0.45, 0.50, 0.54);
uniform float global_from = 200.0;      // 회복 반경 밖 바다는 이 거리부터 vitality_global(하늘)을 따른다
uniform float global_to = 240.0;
uniform float far_start = 40.0;
uniform float far_end = 400.0;
uniform float far_rough = 0.45;
uniform float far_wave = 0.15;          // 먼 곳 파도 세기 비율
// 얕은 띠 (호수): 이 깊이(m)까지 밝은 청록을 진하게 → 물가에 청록 띠
uniform float shallow_band_depth = 0.0;
uniform float shallow_band_strength = 0.7;

uniform float foam_width = 0.7;
uniform float foam_strength = 0.8;
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 0.98);

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 높이장(2 옥타브) 한 장
float height(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.13 + 17.0) * 0.35;
}

vec2 grad(vec2 p) {
	float e = 0.15;
	float h = height(p);
	return vec2(height(p + vec2(e, 0.0)) - h, height(p + vec2(0.0, e)) - h) / e;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = vitality_t(v_world, 10.0);
	float d_c = distance(v_world.xz, vitality_center.xz);
	t = max(t, vitality_global * smoothstep(global_from, global_to, d_c));

	// 두 겹 노멀: 서로 다른 크기·방향으로 흐른다
	float cam_d = length(v_world - CAMERA_POSITION_WORLD);
	float far_k = smoothstep(far_start, far_end, cam_d);
	vec2 p = v_world.xz * wave_scale;
	vec2 g = grad(p + TIME * wave_speed * vec2(1.0, 0.6));
	g += grad(p * 2.3 - TIME * wave_speed * 1.3 * vec2(0.7, 1.0) + 31.0) * 0.35;
	float ws = wave_strength * mix(1.0, far_wave, far_k);
	vec3 wn = normalize(vec3(-g.x * ws, 1.0, -g.y * ws));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// 장면 깊이와의 차 = 물 두께
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -(ndc.xyz / ndc.w).z;
	float thick = max(scene_z + VERTEX.z, 0.0);

	float dk = clamp(thick / depth_range, 0.0, 1.0);
	dk = sqrt(dk);
	vec3 col_clear = mix(shallow_color, deep_color, dk);
	vec3 col_grey = mix(grey_shallow, grey_deep, dk);
	if (shallow_band_depth > 0.0) {
		float sb = (1.0 - smoothstep(shallow_band_depth * 0.4, shallow_band_depth, thick)) * shallow_band_strength;
		col_clear = mix(col_clear, shallow_color * 1.15, sb);
	}
	col_clear = mix(col_clear, horizon_color, far_k * 0.85);
	col_grey = mix(col_grey, grey_horizon, far_k * 0.7);
	vec3 col = mix(col_grey, col_clear, t);

	// 물가 거품: 얕은 띠 + 일렁이는 노이즈로 끊김
	float fn = vnoise(v_world.xz * 0.9 + TIME * 0.15) * 0.6 + vnoise(v_world.xz * 2.7 - TIME * 0.1) * 0.4;
	float band = 1.0 - smoothstep(0.0, foam_width * (0.6 + 0.8 * fn), thick);
	float foam = band * smoothstep(0.25, 0.55, fn + band * 0.4) * foam_strength * mix(0.5, 1.0, t);
	col = mix(col, foam_color, foam);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	float a = mix(min_alpha, max_alpha, 1.0 - exp(-thick / clear_depth));
	a = max(a, mix(0.9, 1.0, t) * foam);
	if (shallow_band_depth > 0.0) {
		a = max(a, (1.0 - smoothstep(shallow_band_depth * 0.5, shallow_band_depth, thick)) * smoothstep(0.05, 0.3, thick) * 0.75 * t);
	}
	a = clamp(a + fres * 0.5 * t * (1.0 - far_k * 0.6), 0.0, 1.0);

	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = mix(mix(rough_grey, rough_clear, t), max(far_rough, rough_grey * (1.0 - t) + far_rough * t), far_k);
	SPECULAR = mix(spec_grey, spec_clear, t) * (1.0 - foam) * (1.0 - far_k * 0.4);
	METALLIC = 0.0;
}
