// 공용 회색↔컬러 셰이더 (03 그래픽 설계서 4장).
// 탑에서 vitality_radius 안쪽 = 원래 색(회복), 바깥 = 바랜 잿빛(채도 15% + 푸른 기). 경계 10m.
shader_type spatial;

global uniform vec3 vitality_center;
global uniform float vitality_radius;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool keep_color = false;      // 생명력·신호·코어처럼 항상 고채도
uniform float edge = 10.0;
uniform float roughness_value = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 grey = mix(vec3(lum), c, 0.15) * vec3(0.95, 0.98, 1.05);
	float d = distance(world_pos.xz, vitality_center.xz);
	float t = keep_color ? 1.0 : 1.0 - smoothstep(vitality_radius - edge, vitality_radius, d);
	ALBEDO = mix(grey, c, t);
	ROUGHNESS = roughness_value;
}
