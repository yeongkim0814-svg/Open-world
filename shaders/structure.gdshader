// 구조물 재질 (03 그래픽 설계서 7장): 탑·바위벽·돌길·기둥·집·수문·수로.
// 지형 바위층과 같은 삼면 투영(Ben Golus whiteout 법선)으로 바위 텍스처를 입히고, 색은 tint 로 칠한다.
// - detail: 텍스처 밝기 결을 얼마나 남길지 (회벽 = 낮게, 돌 = 높게).
// - object_space: 움직이는 부품(수문 문짝)은 로컬 좌표로 투영해 무늬가 미끄러지지 않게.
// - keep_color: 코어처럼 항상 고채도. 그 외는 vitality_mix 로 회색↔컬러.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/vitality.gdshaderinc"

uniform sampler2D tex_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 tint : source_color = vec4(0.6, 0.55, 0.48, 1.0);
uniform float tex_avg_lum = 0.075;          // 텍스처 평균 밝기 (지형 rock_avg_lum 과 같은 값)
uniform float detail : hint_range(0.0, 1.0) = 0.8;
uniform float tile = 4.0;                   // m 당 한 장
uniform float normal_strength = 0.9;
uniform float roughness_min = 0.5;
uniform float metallic = 0.0;
uniform float grime = 0.25;                 // 큰 얼룩 (빗물·때) 밝기 변화
uniform float grime_scale = 6.0;
uniform bool object_space = false;
uniform bool keep_color = false;
uniform float edge = 10.0;

varying vec3 wpos;
varying vec3 ppos;
varying vec3 pnrm;

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

vec3 unpack_normal(vec4 t) {
	vec2 xy = t.rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ppos = object_space ? VERTEX : wpos;
	pnrm = object_space ? NORMAL : wn;
}

void fragment() {
	vec3 N = normalize(pnrm);
	vec3 b = pow(abs(N), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 p = ppos / tile;
	vec3 cx = texture(tex_diff, p.zy).rgb, cy = texture(tex_diff, p.xz).rgb, cz = texture(tex_diff, p.xy).rgb;
	vec3 tx = unpack_normal(texture(tex_nor, p.zy));
	vec3 ty = unpack_normal(texture(tex_nor, p.xz));
	vec3 tz = unpack_normal(texture(tex_nor, p.xy));
	vec3 ax = texture(tex_arm, p.zy).rgb, ay = texture(tex_arm, p.xz).rgb, az = texture(tex_arm, p.xy).rgb;
	vec3 c = cx * b.x + cy * b.y + cz * b.z;
	vec3 arm = ax * b.x + ay * b.y + az * b.z;

	tx.y = -tx.y; ty.y = -ty.y; tz.y = -tz.y;
	float s = normal_strength;
	vec3 nx = vec3(tx.xy * s + N.zy, abs(tx.z) * N.x);
	vec3 ny = vec3(ty.xy * s + N.xz, abs(ty.z) * N.y);
	vec3 nz = vec3(tz.xy * s + N.xy, abs(tz.z) * N.z);
	vec3 n = normalize(nx.zyx * b.x + ny.xzy * b.y + nz.xyz * b.z);
	if (object_space) {
		n = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	}

	float lum = dot(c, LUMA);
	float k = clamp(lum / tex_avg_lum, 0.45, 1.6);
	vec3 col = tint.rgb * mix(1.0, k, detail);
	// 큰 얼룩: 세로로 늘어진 노이즈 (빗물 자국처럼)
	vec3 gp = ppos / grime_scale;
	float g = vnoise(vec2(gp.x + gp.z * 0.7, gp.y * 0.35)) * 0.6 + vnoise(vec2(gp.z - gp.x * 0.5, gp.y * 0.8) * 2.1) * 0.4;
	col *= 1.0 - grime * (g - 0.3);

	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = keep_color ? col : vitality_mix(col, wpos, edge);
	AO = mix(1.0, arm.r, 0.8);
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = clamp(arm.g, roughness_min, 1.0);
	METALLIC = metallic;
}
