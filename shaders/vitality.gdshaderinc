// 회색↔컬러 공용 함수 (03 그래픽 설계서 5장). 모든 지형·소품·풀·바위 셰이더가 include 한다.
// vitality_center/radius: 탑에서 번지는 회복 반경 (탑 정지 시 0 → 220m).
// vitality_global: 하늘·안개처럼 위치가 없는 요소의 회복 정도 0~1.
global uniform vec3 vitality_center;
global uniform float vitality_radius;
global uniform float vitality_global;

// 0 = 잿빛(회복 전), 1 = 원래 색. 경계 폭 edge m.
float vitality_t(vec3 world_pos, float edge) {
	float d = distance(world_pos.xz, vitality_center.xz);
	return 1.0 - smoothstep(vitality_radius - edge, vitality_radius, d);
}

// 잿빛 판: 채도 15% + 약간 푸른 기.
vec3 vitality_grey(vec3 c) {
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(lum), c, 0.15) * vec3(0.95, 0.98, 1.05);
}

vec3 vitality_mix(vec3 c, vec3 world_pos, float edge) {
	return mix(vitality_grey(c), c, vitality_t(world_pos, edge));
}
