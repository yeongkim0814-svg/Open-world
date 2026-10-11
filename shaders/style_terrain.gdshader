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
uniform float ground_patch = 0.68;     // 노이즈가 이보다 크면 흙 얼룩
uniform float noise_amount = 0.06;
// 색칠 지도 구역·길 (첫 섬 1km). use_zone_map이 꺼져 있으면 기존 색 띠만.
uniform bool use_zone_map = false;
uniform sampler2D zone_map : filter_nearest, repeat_disable;   // R8 = 구역 번호 (MapLegend.ZONES 순서)
uniform sampler2D path_map : filter_nearest, repeat_disable;   // R8 = 0 없음, 1 흙길, 2 포장길, 3 수로
uniform vec4 map_rect = vec4(-512.0, -512.0, 1024.0, 1024.0);
uniform vec3 zone_depleted[7] : source_color;
uniform vec3 zone_restored[7] : source_color;
uniform vec3 path_depleted[2] : source_color;
uniform vec3 path_restored[2] : source_color;
uniform bool flat_shading = false;
uniform float flat_fade_end = 150.0;

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
	float g = smoothstep(ground_patch, ground_patch + 0.06, n);
	g = max(g, smoothstep(cliff_slope + 0.10, cliff_slope + 0.04, v_wn.y));
	if (use_zone_map) {
		vec2 uv = (v_world.xz - map_rect.xy) / map_rect.zw;
		int zi = clamp(int(texture(zone_map, uv).r * 255.0 + 0.5), 0, 6);
		grass = style_color(zone_depleted[zi], zone_restored[zi], r, v_world, noise_amount);
	}
	vec3 c = mix(grass, ground, g);
	c = mix(c, sand, smoothstep(sand_height + 0.4, sand_height - 0.2, v_world.y));
	c = mix(c, rock, smoothstep(cliff_slope + 0.03, cliff_slope - 0.03, v_wn.y));
	if (use_zone_map) {
		vec2 uv = (v_world.xz - map_rect.xy) / map_rect.zw;
		int pi = int(texture(path_map, uv).r * 255.0 + 0.5);
		if (pi == 1 || pi == 2) {
			c = style_color(path_depleted[pi - 1], path_restored[pi - 1], r, v_world, noise_amount * 0.5);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.97;
	if (flat_shading) {
		float k = 1.0 - smoothstep(flat_fade_end * 0.7, flat_fade_end, -VERTEX.z);
		NORMAL = normalize(mix(NORMAL, face_normal(VERTEX), k));
	}
}
