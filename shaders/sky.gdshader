// 절차적 하늘 (03 그래픽 설계서 4·5·7장, 그래픽 개편 Task 1).
// 높이 그라데이션 + FBM 뭉게구름(머리 위 크게, 지평선 쪽 납작하게, 천천히 흐름) + 해 원반(LIGHT0).
// vitality_global 0 = 흐림(납빛 하늘, 낮고 두꺼운 구름층, 탑 쪽 더 어둡게) ↔ 1 = 맑음(#3E7FC4→#BFD6EA, 흰 뭉게구름).
// 성능: 반해상도 패스에서 하늘·구름을 그리고 전해상도 패스는 해 원반만 더한다.
//       radiance(큐브맵) 패스는 옥타브를 줄인 구름을 쓴다.
shader_type sky;
render_mode use_half_res_pass;

#include "res://shaders/vitality.gdshaderinc"

// 맑음 (설계서 4장)
uniform vec3 clear_zenith : source_color = vec3(0.17, 0.44, 0.80);    // #3E7FC4 (ACES 채도 손실 보정)
uniform vec3 clear_horizon : source_color = vec3(0.749, 0.839, 0.918);  // #BFD6EA
uniform vec3 clear_cloud_lit : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 clear_cloud_shade : source_color = vec3(0.60, 0.66, 0.76);
// 흐림 (납빛)
uniform vec3 grey_zenith : source_color = vec3(0.42, 0.44, 0.47);
uniform vec3 grey_horizon : source_color = vec3(0.66, 0.68, 0.70);
uniform vec3 grey_cloud_lit : source_color = vec3(0.62, 0.63, 0.65);
uniform vec3 grey_cloud_shade : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 ground_color : source_color = vec3(0.36, 0.40, 0.44);

uniform float sky_energy = 1.0;
uniform float cloud_scale = 2.0;          // 클수록 구름이 잘다
uniform vec2 wind = vec2(0.006, 0.003);   // 구름 흐름 (UV/초)
uniform float clear_coverage = 0.46;      // fbm 문턱: 클수록 구름이 적다
uniform float grey_coverage = 0.28;
uniform float sun_size = 0.9994;          // cos(반지름)
uniform vec3 tower_cloud_pos = vec3(0.0, 75.0, -10.0);  // 회복 전 탑 위 어두운 구름 방향

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

// 구름 밀도 0~1. 큰 덩어리(저주파) × 뭉실한 가장자리(고주파).
float cloud_density(vec2 uv, float coverage, int octaves) {
	float base = fbm(uv * 0.5, 3);                       // 뭉게구름 덩어리 배치
	float detail = fbm(uv * 2.2 + base * 2.0, octaves);  // 가장자리 뭉실함
	float n = base * 0.80 + detail * 0.38;
	return smoothstep(coverage, coverage + 0.15, n);
}

void sky() {
	float v = clamp(vitality_global, 0.0, 1.0);
	vec3 dir = EYEDIR;
	float up = max(dir.y, 0.0);

	if (AT_HALF_RES_PASS || AT_CUBEMAP_PASS) {
		// --- 하늘 그라데이션 ---
		float g = pow(up, 0.45);
		vec3 zen = mix(grey_zenith, clear_zenith, v);
		vec3 hor = mix(grey_horizon, clear_horizon, v);
		vec3 col = mix(hor, zen, g);
		// 지평선 아래: 지평선 연무 → 어두운 땅빛
		if (dir.y < 0.0) {
			col = mix(hor, ground_color * mix(0.8, 1.0, v), smoothstep(0.0, 0.25, -dir.y));
		}

		// --- 구름 (평면 투영: 지평선 쪽은 자연히 납작해진다) ---
		float cloud = 0.0;
		if (dir.y > 0.0) {
			vec2 uv = dir.xz / (dir.y + 0.12) * cloud_scale + wind * TIME;
			float coverage = mix(grey_coverage, clear_coverage, v);
			int oct = AT_CUBEMAP_PASS ? 2 : 4;
			float d = cloud_density(uv, coverage, oct);
			// 두께로 명암: 바깥쪽(화면 위쪽 = 더 먼 곳)에 구름이 더 있으면 아랫면 → 어둡게,
			// 해 쪽으로 구름이 끝나면 밝은 테두리. 납작한 아랫면·밝은 윗면 느낌.
			vec3 L = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
			vec2 radial = normalize(dir.xz + vec2(1e-4));
			float d_far = cloud_density(uv + radial * 0.25, coverage, 2);
			float d_sun = cloud_density(uv + normalize(L.xz + vec2(1e-4)) * 0.15, coverage, 2);
			float overhead = smoothstep(0.35, 0.9, dir.y);
			float shade = mix(d_far, d * 0.8, overhead);       // 지평선 쪽 = 위로 쌓인 정도, 머리 위 = 두께
			float lit = clamp(1.0 - shade * 0.75 + (d - d_sun) * 0.6, 0.0, 1.0);
			vec3 c_lit = mix(grey_cloud_lit, clear_cloud_lit, v);
			vec3 c_shade = mix(grey_cloud_shade, clear_cloud_shade, v);
			vec3 cc = mix(c_shade, c_lit * mix(1.0, 1.25, v), lit);
			// 해 주변 은빛 테두리
			float sun_dot = max(dot(dir, L), 0.0);
			cc += pow(sun_dot, 12.0) * (1.0 - d) * 0.6 * v * LIGHT0_COLOR;
			// 지평선 가까이 구름은 공기 원근으로 지평선 색에 녹인다
			float fade = smoothstep(0.0, 0.22, dir.y);
			cloud = d * fade;
			col = mix(col, mix(hor, cc, fade * 0.9 + 0.1), cloud);
		}

		// 흐림: 탑 위 어두운 구름 쪽을 더 무겁게
		vec3 to_tower = normalize(tower_cloud_pos - POSITION);
		float tw = smoothstep(0.80, 0.97, dot(dir, to_tower)) * (1.0 - v);
		col *= 1.0 - tw * 0.35;
		// 흐림 전체 아래쪽 하늘 더 무겁게(낮은 구름층)
		col *= mix(0.92 + 0.08 * smoothstep(0.0, 0.4, up), 1.0, v);

		// 해 주변 산란광(맑을 때)
		if (LIGHT0_ENABLED) {
			float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
			col += LIGHT0_COLOR * (pow(sd, 8.0) * 0.18 + pow(sd, 64.0) * 0.25) * mix(0.15, 1.0, v) * (1.0 - cloud * 0.7);
		}
		COLOR = col * sky_energy;
		ALPHA = cloud;
	} else {
		// 전해상도: 해 원반만 날카롭게 더한다 (구름에 가려지면 약해짐)
		vec3 col = HALF_RES_COLOR.rgb;
		if (LIGHT0_ENABLED) {
			float sd = dot(dir, LIGHT0_DIRECTION);
			float disk = smoothstep(sun_size - 0.0002, sun_size, sd);
			float occl = 1.0 - HALF_RES_COLOR.a * 0.95;
			col += LIGHT0_COLOR * LIGHT0_ENERGY * disk * 6.0 * occl * mix(0.1, 1.0, v);
		}
		COLOR = col;
	}
}
