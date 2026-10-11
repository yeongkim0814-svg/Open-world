// 지형 셰이더 (03 그래픽 설계서 6장): 풀·흙·바위·모래 4층 섞기.
// - 바위 = 경사(법선 y, 약 45° 넘으면 전부 바위), 삼면 투영 → 절벽에서 늘어나지 않음.
// - 모래 = 높이 2m 아래(물가·해변).
// - 풀/흙 = 저주파 노이즈 얼룩 + 높이 기반 경계(Spaceship GroundBase 방식: 층마다 밝기를 "높이"로 비교해
//   흙의 돌이 풀 사이로 덩어리째 비친다).
// - 타일 반복 숨김: 층마다 두 배율(near_tile m, far_tile m, 회전)로 샘플 → 거리·노이즈로 섞는다.
// - 법선은 월드 공간에서 직접 합성(whiteout) → 메시에 탄젠트가 필요 없다. UV = 월드 xz.
// - 마지막에 회색↔컬러 공용 함수(vitality_mix, 경계 10m).
shader_type spatial;
render_mode cull_back;

#include "res://shaders/vitality.gdshaderinc"

uniform sampler2D grass_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float near_tile = 4.0;          // m 당 한 장 (가까운 결)
uniform float far_tile = 23.0;          // 큰 배율 (반복 숨김)
uniform float rock_tile = 6.0;

// 색 (회복 후). 풀 텍스처는 가을 낙엽 섞인 색이라 밝기 결만 쓰고 색은 팔레트로 칠한다.
uniform vec3 grass_light : source_color = vec3(0.549, 0.776, 0.247);   // #8CC63F
uniform vec3 grass_dark : source_color = vec3(0.306, 0.561, 0.165);    // #4E8F2A
uniform float grass_tint : hint_range(0.0, 1.0) = 0.85;
uniform float grass_avg_lum = 0.22;
uniform vec3 rock_color : source_color = vec3(0.60, 0.53, 0.45);       // 따뜻한 회갈색
uniform float rock_tint : hint_range(0.0, 1.0) = 0.5;
uniform float rock_avg_lum = 0.075;
uniform vec3 dirt_color : source_color = vec3(0.60, 0.57, 0.41);       // 마른 풀 섞인 흙 (풀색에 가깝게)
uniform float dirt_tint : hint_range(0.0, 1.0) = 0.65;
uniform float dirt_grass_mix : hint_range(0.0, 1.0) = 0.35;              // 흙을 풀 어두운 색 쪽으로
uniform float dirt_avg_lum = 0.10;
uniform vec3 sand_color : source_color = vec3(0.86, 0.80, 0.64);       // 옅은 모래
uniform float sand_tint : hint_range(0.0, 1.0) = 0.8;
uniform float sand_avg_lum = 0.18;

uniform float rock_full_y = 0.70;       // 법선 y 이하 = 전부 바위 (≈45°)
uniform float rock_start_y = 0.82;      // 이 위 = 바위 없음 (≈35°)
uniform float sand_height = 2.0;
uniform float dirt_patch = 0.66;        // 노이즈 문턱 (낮을수록 흙 많음) → 평지의 약 15~20%
uniform float dirt_scale = 14.0;        // 얼룩 크기 m
uniform float blend_depth = 0.25;       // 높이 경계 폭
uniform float height_amount = 0.6;
uniform float normal_strength = 0.9;

varying vec3 wpos;
varying vec3 wnrm;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

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
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s / 0.875;
}

vec3 unpack_normal(vec4 t) {
	vec2 xy = t.rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

// 두 배율 섞기. mixf = 큰 배율 비율.
void sample_planar(sampler2D d, sampler2D n, sampler2D a, vec2 uv1, vec2 uv2, float mixf,
		out vec3 col, out vec3 nrm, out vec3 arm) {
	col = mix(texture(d, uv1).rgb, texture(d, uv2).rgb, mixf);
	nrm = mix(unpack_normal(texture(n, uv1)), unpack_normal(texture(n, uv2)), mixf);
	arm = mix(texture(a, uv1).rgb, texture(a, uv2).rgb, mixf);
}

// 위에서 투영한 접선 공간 법선 → 월드 (OpenGL 초록+ = 이미지 위쪽 = -z).
vec3 top_to_world(vec3 t, vec3 N, float s) {
	return normalize(vec3(N.x + t.x * s, N.y * mix(1.0, t.z, s), N.z - t.y * s));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 N = normalize(wnrm);
	vec2 xz = wpos.xz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);

	// 저주파 노이즈: 얼룩·배율 섞기·밝기 변화
	float n_patch = fbm(xz / 28.0) + (vnoise(xz / 5.0) - 0.5) * 0.15;   // 풀 밝기 변화용
	float n_dirt = fbm(xz / dirt_scale + vec2(11.7, 3.1)) + (vnoise(xz / 3.0) - 0.5) * 0.12;   // 흙 얼룩 (작게)
	float n_macro = fbm(xz / 90.0 + vec2(5.2, 1.3));

	// 두 배율 UV (큰 배율은 37° 돌려 격자 방향도 깨뜨린다)
	vec2 uv1 = xz / near_tile;
	mat2 rot = mat2(vec2(0.7986, 0.6018), vec2(-0.6018, 0.7986));
	vec2 uv2 = rot * xz / far_tile + vec2(0.37, 0.11);
	float mixf = clamp(0.3 + 0.45 * smoothstep(6.0, 60.0, dist) + (n_macro - 0.5) * 0.8, 0.1, 0.9);

	// 기본 가중치
	float jitter = (vnoise(xz / 4.0) - 0.5) * 0.08 + (n_patch - 0.5) * 0.06;   // 바위 경계를 들쭉날쭉하게
	float w_rock = 1.0 - smoothstep(rock_full_y, rock_start_y, N.y + jitter);
	float w_sand = (1.0 - smoothstep(sand_height - 0.6, sand_height + 0.6, wpos.y)) * (1.0 - w_rock);
	float rest = (1.0 - w_rock) * (1.0 - w_sand);
	float dirtiness = smoothstep(dirt_patch - 0.08, dirt_patch + 0.08, n_dirt);
	dirtiness = max(dirtiness, 0.4 * (1.0 - smoothstep(0.78, 0.86, N.y)));   // 25~37° 경사 = 흙
	float w_dirt = rest * dirtiness;
	float w_grass = rest - w_dirt;

	vec3 c_g = vec3(0.0), n_g = vec3(0.0, 0.0, 1.0), a_g = vec3(1.0, 0.9, 0.0);
	vec3 c_d = vec3(0.0), n_d = vec3(0.0, 0.0, 1.0), a_d = vec3(1.0, 0.9, 0.0);
	vec3 c_s = vec3(0.0), n_s = vec3(0.0, 0.0, 1.0), a_s = vec3(1.0, 0.9, 0.0);
	vec3 c_r = vec3(0.0), n_rw = N, a_r = vec3(1.0, 0.9, 0.0);
	float h_g = 0.0, h_d = 0.0, h_s = 0.0, h_r = 0.0;

	if (w_grass > 0.001) {
		sample_planar(grass_diff, grass_nor, grass_arm, uv1, uv2, mixf, c_g, n_g, a_g);
		float lum = dot(c_g, LUMA);
		h_g = clamp(lum / grass_avg_lum, 0.0, 2.0) * 0.5;
		float k = clamp(n_patch * 1.6 - 0.35 + (n_macro - 0.5) * 0.6, 0.0, 1.0);
		vec3 tinted = mix(grass_dark, grass_light, k) * clamp(pow(lum / grass_avg_lum, 1.4), 0.4, 1.5);
		c_g = mix(c_g, tinted, grass_tint);
	}
	if (w_dirt > 0.001) {
		sample_planar(dirt_diff, dirt_nor, dirt_arm, uv1 * 1.3, uv2 * 1.3, mixf, c_d, n_d, a_d);
		float lum = dot(c_d, LUMA);
		h_d = clamp(lum / dirt_avg_lum, 0.0, 2.0) * 0.5;
		c_d = mix(c_d, dirt_color * clamp(lum / dirt_avg_lum, 0.6, 1.4), dirt_tint);
		c_d = mix(c_d, grass_dark * 1.25 * clamp(lum / dirt_avg_lum, 0.7, 1.3), dirt_grass_mix);
	}
	if (w_sand > 0.001) {
		sample_planar(sand_diff, sand_nor, sand_arm, uv1, uv2, mixf, c_s, n_s, a_s);
		float lum = dot(c_s, LUMA);
		h_s = clamp(lum / sand_avg_lum, 0.0, 2.0) * 0.5;
		c_s = mix(c_s, sand_color * clamp(lum / sand_avg_lum, 0.6, 1.4), sand_tint);
	}
	if (w_rock > 0.001) {
		// 삼면 투영 (가까운 배율 + 큰 배율 색)
		vec3 b = pow(abs(N), vec3(4.0));
		b /= (b.x + b.y + b.z);
		vec3 p = wpos / rock_tile;
		vec3 cx = vec3(0.0), cy = vec3(0.0), cz = vec3(0.0);
		vec3 tx = vec3(0.0, 0.0, 1.0), ty = tx, tz = tx;
		vec3 ax = vec3(0.0), ay = vec3(0.0), az = vec3(0.0);
		float far = rock_tile / far_tile;
		if (b.x > 0.02) {
			cx = mix(texture(rock_diff, p.zy).rgb, texture(rock_diff, p.zy * far + 0.31).rgb, mixf * 0.6);
			tx = unpack_normal(texture(rock_nor, p.zy)); ax = texture(rock_arm, p.zy).rgb;
		}
		if (b.y > 0.02) {
			cy = mix(texture(rock_diff, p.xz).rgb, texture(rock_diff, p.xz * far + 0.53).rgb, mixf * 0.6);
			ty = unpack_normal(texture(rock_nor, p.xz)); ay = texture(rock_arm, p.xz).rgb;
		}
		if (b.z > 0.02) {
			cz = mix(texture(rock_diff, p.xy).rgb, texture(rock_diff, p.xy * far + 0.17).rgb, mixf * 0.6);
			tz = unpack_normal(texture(rock_nor, p.xy)); az = texture(rock_arm, p.xy).rgb;
		}
		c_r = cx * b.x + cy * b.y + cz * b.z;
		a_r = ax * b.x + ay * b.y + az * b.z;
		// whiteout 삼면 법선 (Ben Golus). 초록은 이미지 위쪽(= -v) 이라 뒤집는다.
		tx.y = -tx.y; ty.y = -ty.y; tz.y = -tz.y;
		float s = normal_strength;
		vec3 nx = vec3(tx.xy * s + N.zy, abs(tx.z) * N.x);
		vec3 ny = vec3(ty.xy * s + N.xz, abs(ty.z) * N.y);
		vec3 nz = vec3(tz.xy * s + N.xy, abs(tz.z) * N.z);
		n_rw = normalize(nx.zyx * b.x + ny.xzy * b.y + nz.xyz * b.z);
		float lum = dot(c_r, LUMA);
		h_r = clamp(lum / rock_avg_lum, 0.0, 2.0) * 0.5 + 0.3;
		vec3 grey_brown = rock_color * clamp(lum / rock_avg_lum, 0.45, 1.5);
		c_r = mix(c_r, grey_brown, rock_tint);
	}

	// 높이 기반 경계 (GroundBase): 가중치 + 층 높이 중 가장 높은 것 근처만 남긴다
	vec4 w = vec4(w_grass, w_dirt, w_sand, w_rock);
	vec4 hv = w + vec4(h_g, h_d, h_s, h_r) * height_amount * step(vec4(0.001), w);
	hv = mix(vec4(-10.0), hv, step(vec4(0.001), w));
	float top = max(max(hv.x, hv.y), max(hv.z, hv.w)) - blend_depth;
	vec4 bw = max(hv - vec4(top), vec4(0.0));
	bw /= max(bw.x + bw.y + bw.z + bw.w, 1e-4);

	vec3 albedo = c_g * bw.x + c_d * bw.y + c_s * bw.z + c_r * bw.w;
	vec3 arm = a_g * bw.x + a_d * bw.y + a_s * bw.z + a_r * bw.w;
	// 넓은 변화: 큰 노이즈로 밝기 ±8%
	albedo *= 0.92 + 0.16 * n_macro;

	float ns = normal_strength * (1.0 - 0.5 * smoothstep(30.0, 120.0, dist));
	vec3 t_planar = n_g * bw.x + n_d * bw.y + n_s * bw.z;
	float planar_w = bw.x + bw.y + bw.z;
	vec3 n_world = N;
	if (planar_w > 0.001) {
		n_world = top_to_world(normalize(t_planar / planar_w), N, ns);
	}
	n_world = normalize(mix(n_world, n_rw, bw.w));

	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = vitality_mix(albedo, wpos, 10.0);
	AO = arm.r;
	ROUGHNESS = clamp(arm.g, 0.4, 1.0);
	METALLIC = 0.0;
}
