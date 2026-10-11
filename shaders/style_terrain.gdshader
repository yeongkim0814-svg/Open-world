shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// 지형 색 띠: 풀밭 / 흙 얼룩 / 절벽(경사) 바위색 / 낮은 곳 모래. 사진 텍스처 없음.
#include "res://shaders/style_common.gdshaderinc"

uniform vec3 grass_depleted : source_color = vec3(0.37, 0.41, 0.29);
uniform vec3 grass_restored : source_color = vec3(0.16, 0.37, 0.10);
uniform vec3 ground_depleted : source_color = vec3(0.58, 0.54, 0.42);
uniform vec3 ground_restored : source_color = vec3(0.49, 0.36, 0.21);
uniform vec3 rock_depleted : source_color = vec3(0.26, 0.28, 0.27);
uniform vec3 rock_restored : source_color = vec3(0.27, 0.25, 0.22);
uniform vec3 sand_depleted : source_color = vec3(0.62, 0.58, 0.47);
uniform vec3 sand_restored : source_color = vec3(0.69, 0.58, 0.35);
uniform float cliff_slope = 0.62;      // 법선 y가 이보다 작으면 바위색
uniform float sand_height = 1.5;       // 이 높이 아래 모래
uniform float ground_patch = 0.78;     // 노이즈가 이보다 크면 흙 얼룩
uniform float noise_amount = 0.06;
// 색칠 지도 구역·길 (첫 섬 1km). use_zone_map이 꺼져 있으면 기존 색 띠만.
uniform bool use_zone_map = false;
uniform sampler2D zone_map : filter_nearest, repeat_disable;   // R8 = 구역 번호 (MapLegend.ZONES 순서)
uniform sampler2D path_map : filter_nearest, repeat_disable;   // R8 = 0 없음, 1 흙길, 2 포장길, 3 수로
uniform vec4 map_rect = vec4(-512.0, -512.0, 1024.0, 1024.0);
uniform float map_px = 1024.0;   // 구역·길 지도 한 변 픽셀 수
uniform vec3 zone_depleted[7] : source_color;
uniform vec3 zone_restored[7] : source_color;
uniform vec3 path_depleted[2] : source_color;
uniform vec3 path_restored[2] : source_color;
uniform bool flat_shading = false;
uniform float flat_fade_end = 150.0;

// 초원 풀밭 질감 (B2 9.3): 초원 구역 땅색에만 큰 얼룩(파장 ~30 m, ±6 %) + 풀결 얼룩(파장 ~2.5 m, 바람 방향으로 늘임, ±4 %). 결 얼룩은 카메라 40 m 밖에서 끈다.
uniform float meadow_patch_amp = 0.06;
uniform float meadow_grain_amp = 0.04;
uniform float meadow_patch_wavelength = 30.0;
uniform float meadow_grain_wavelength = 2.5;
uniform float meadow_grain_stretch = 4.0;      // 풀결이 바람 방향으로 늘어난 배율
uniform vec2 meadow_grain_dir = vec2(0.8, 0.6);
uniform float meadow_grain_fade_start = 30.0;
uniform float meadow_grain_fade_end = 40.0;

uniform float zone_blend_m = 14.0;   // 구역 경계가 섞이는 폭 (m) — 칠한 경계의 각진 칸이 보이지 않게
uniform float path_edge = 0.18;      // 길 가장자리 부드러움 (0~0.5)

varying vec3 v_world;
varying vec3 v_wn;
varying float v_r;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_r = recovery_at(v_world);
}

void fragment() {
	float r = v_r;
	vec3 grass = style_color(grass_depleted, grass_restored, r, v_world, noise_amount);
	vec3 ground = style_color(ground_depleted, ground_restored, r, v_world, noise_amount);
	vec3 rock = style_color(rock_depleted, rock_restored, r, v_world, noise_amount);
	vec3 sand = style_color(sand_depleted, sand_restored, r, v_world, noise_amount);
	float n = big_noise(v_world.xz * 0.045 + 5.3);
	// 흙 얼룩 + 완만→가파른 경사 사이 흙 띠
	// 경계는 넓게 + 노이즈로 흔들어 선이 보이지 않게 (경사 띠가 고도선처럼 산을 가르지 않도록)
	float sn = (big_noise(v_world.xz * 0.09 + 2.4) - 0.5) * 0.10;
	float g = 0.65 * smoothstep(ground_patch, ground_patch + 0.16, n);
	g = max(g, 0.8 * smoothstep(cliff_slope + 0.16, cliff_slope + 0.04, v_wn.y + sn));
	// 지도 픽셀 좌표 (픽셀 중심 = 정수). 굽기 관례: 픽셀 p = p·world/(N−1)
	vec2 pc = (v_world.xz - map_rect.xy) / map_rect.zw * (map_px - 1.0);
	float px_m = map_rect.z / (map_px - 1.0);
	if (use_zone_map) {
		// 구역 색: zone_blend_m 간격 격자의 네 꼭짓점 구역 색을 쌍선형으로 섞고, 노이즈로 격자를 흐트러뜨린다
		float cell = max(zone_blend_m / px_m, 1.0);
		vec2 warp = vec2(big_noise(v_world.xz * 0.031 + 1.7), big_noise(v_world.xz * 0.031 + 9.2)) - 0.5;
		vec2 g0 = pc / cell + warp * 0.9;
		vec2 gi = floor(g0);
		vec2 gf = smoothstep(0.0, 1.0, g0 - gi);
		vec3 zc[4];
		float mw[4];   // 각 꼭짓점이 초원(구역 0)인가
		for (int k = 0; k < 4; k++) {
			vec2 corner = (gi + vec2(float(k & 1), float(k >> 1))) * cell;
			ivec2 t = clamp(ivec2(corner + 0.5), ivec2(0), ivec2(int(map_px) - 1));
			int zi = clamp(int(texelFetch(zone_map, t, 0).r * 255.0 + 0.5), 0, 6);
			zc[k] = mix(zone_depleted[zi], zone_restored[zi], r);
			mw[k] = zi == 0 ? 1.0 : 0.0;
		}
		float meadow = mix(mix(mw[0], mw[1], gf.x), mix(mw[2], mw[3], gf.x), gf.y);
		vec3 zb = mix(mix(zc[0], zc[1], gf.x), mix(zc[2], zc[3], gf.x), gf.y);
		grass = style_color(zb, zb, r, v_world, noise_amount);
		// 풀밭 질감: 물체 없이 "풀밭"으로 읽히게 하는 두 겹 얼룩 (초원 구역 가중 meadow 만큼만)
		vec2 wd = normalize(meadow_grain_dir);
		vec2 wp = vec2(dot(v_world.xz, wd), dot(v_world.xz, vec2(-wd.y, wd.x)));
		float patch_n = (big_noise(v_world.xz / meadow_patch_wavelength + 11.7) - 0.5) * 2.0 * meadow_patch_amp;
		float grain_n = (big_noise(vec2(wp.x / (meadow_grain_wavelength * meadow_grain_stretch), wp.y / meadow_grain_wavelength) + 23.1) - 0.5) * 2.0 * meadow_grain_amp;
		float grain_fade = 1.0 - smoothstep(meadow_grain_fade_start, meadow_grain_fade_end, distance(v_world, CAMERA_POSITION_WORLD));
		grass *= 1.0 + meadow * (patch_n + grain_n * grain_fade);
	}
	vec3 c = mix(grass, ground, g);
	c = mix(c, sand, smoothstep(sand_height + 0.4, sand_height - 0.2, v_world.y));
	c = mix(c, rock, smoothstep(cliff_slope + 0.06, cliff_slope - 0.08, v_wn.y + sn));
	if (use_zone_map) {
		// 길: 네 이웃 픽셀의 "길임"을 쌍선형으로 섞어 가장자리를 매끈하게 (계단 모양 방지)
		vec2 pi0 = floor(pc);
		vec2 pf = pc - pi0;
		float w = 0.0;
		int kind = 0;
		for (int k = 0; k < 4; k++) {
			ivec2 t = clamp(ivec2(pi0) + ivec2(k & 1, k >> 1), ivec2(0), ivec2(int(map_px) - 1));
			int pv = int(texelFetch(path_map, t, 0).r * 255.0 + 0.5);
			float on = (pv == 1 || pv == 2) ? 1.0 : 0.0;
			float bw = ((k & 1) == 1 ? pf.x : 1.0 - pf.x) * ((k >> 1) == 1 ? pf.y : 1.0 - pf.y);
			w += on * bw;
			kind = max(kind, (pv == 1 || pv == 2) ? pv : 0);
		}
		float jitter = (big_noise(v_world.xz * 0.6 + 3.1) - 0.5) * 0.25;
		float pm = smoothstep(0.5 - path_edge, 0.5 + path_edge, w + jitter);
		if (kind > 0 && pm > 0.0) {
			vec3 pcol = style_color(path_depleted[kind - 1], path_restored[kind - 1], r, v_world, noise_amount * 0.5);
			c = mix(c, pcol, pm);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.97;
	if (flat_shading) {
		float k = 1.0 - smoothstep(flat_fade_end * 0.7, flat_fade_end, -VERTEX.z);
		NORMAL = normalize(mix(NORMAL, face_normal(VERTEX), k));
	}
}
