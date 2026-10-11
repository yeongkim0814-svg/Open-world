shader_type spatial;
render_mode cull_back;
#include "res://shaders/vitality.gdshaderinc"

// CC0 Poly Haven 바위: diff / nor_gl / arm(AO·거칠기·금속). 회색↔컬러는 vitality 공용 함수.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec3 moss_color : source_color = vec3(0.30, 0.42, 0.16);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.45;
// 텍스처의 붉은 녹빛을 지형 바위층과 같은 따뜻한 회갈색으로 (밝기는 유지)
uniform vec3 tint : source_color = vec3(0.60, 0.55, 0.48);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.7;
uniform float brightness = 1.15;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb;
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(albedo, tint * lum / dot(tint, vec3(0.2126, 0.7152, 0.0722)), tint_amount) * brightness;
	vec3 arm = texture(arm_tex, UV).rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	// 위를 보는 면에만 이끼: 컬러 판에서만 눈에 띄게 (잿빛 판은 vitality_mix 가 채도를 죽임)
	float up = smoothstep(0.55, 0.95, v_world_normal.y);
	float mask = up * smoothstep(0.25, 0.7, 1.0 - arm.r + albedo.g * 0.5) * moss_amount;
	albedo = mix(albedo, albedo * 0.55 + moss_color * 0.6, mask);
	ALBEDO = vitality_mix(albedo, v_world_pos, 10.0);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = clamp(arm.g, 0.05, 1.0);
	METALLIC = 0.0;
}
