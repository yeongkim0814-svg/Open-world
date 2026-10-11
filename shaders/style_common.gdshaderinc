// 스타일 공통 함수 (설계서 2026-10-11-stylized-graphics-design.md 6.1·6.2). 사진 텍스처 없이 색면 + 저주파 노이즈.
// recovery_map: 지역 회복 지도 (R = 0 고갈 ~ 1 회복), recovery_map_rect = (x0, z0, 너비, 깊이) 월드 m.
// recovery_here: 카메라가 있는 곳의 회복값 (하늘·안개처럼 위치 없는 요소용).
global uniform sampler2D recovery_map;
global uniform vec4 recovery_map_rect;
global uniform float recovery_here;

// 지도 범위 밖은 0 (반대편 값이 새지 않게).
float recovery_at(vec3 world_pos) {
	vec2 uv = (world_pos.xz - recovery_map_rect.xy) / recovery_map_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return textureLod(recovery_map, uv, 0.0).r;
}

float st_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 값 노이즈 0~1 (부드러운 보간).
float big_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = st_hash(i);
	float b = st_hash(i + vec2(1.0, 0.0));
	float c = st_hash(i + vec2(0.0, 1.0));
	float d = st_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 고갈↔회복 색 + 수십 m 주기의 명도 얼룩 (±amount). 반복 무늬가 생기지 않는 저주파만 쓴다.
vec3 style_color(vec3 depleted, vec3 restored, float r, vec3 world_pos, float amount) {
	vec3 base = mix(depleted, restored, r);
	float n = big_noise(world_pos.xz * 0.02) * 0.7 + big_noise(world_pos.xz * 0.07 + 17.0) * 0.3;
	return base * (1.0 + (n - 0.5) * 2.0 * amount);
}

// 화면 미분으로 얻는 면 법선 (뷰 공간). 메시를 쪼개지 않고 평면 음영을 낸다.
vec3 face_normal(vec3 view_vertex) {
	return normalize(cross(dFdy(view_vertex), dFdx(view_vertex)));
}
