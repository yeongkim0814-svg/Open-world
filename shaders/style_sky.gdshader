shader_type sky;
// 하늘 그라데이션: 천정은 진하게, 지평선 쪽 변화 폭은 좁고 밝게 (안개·구름과 섞이게). 회복값 = recovery_here.
global uniform float recovery_here;

uniform vec3 zenith_depleted : source_color = vec3(0.25, 0.33, 0.39);
uniform vec3 zenith_restored : source_color = vec3(0.08, 0.24, 0.53);
uniform vec3 horizon_depleted : source_color = vec3(0.40, 0.49, 0.56);
uniform vec3 horizon_restored : source_color = vec3(0.56, 0.72, 0.83);
uniform float horizon_sharpness = 6.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float sun_size = 0.025;        // 라디안
uniform float sun_halo = 0.25;

void sky() {
	float r = recovery_here;
	vec3 zen = mix(zenith_depleted, zenith_restored, r);
	vec3 hor = mix(horizon_depleted, horizon_restored, r);
	float y = max(EYEDIR.y, 0.0);
	vec3 c = mix(hor, zen, 1.0 - exp(-y * horizon_sharpness));
	if (EYEDIR.y < 0.0) {
		c = hor;
	}
	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {   // 해 원반은 화면에만 (환경광을 부풀리지 않게)
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disk = smoothstep(cos(sun_size), cos(sun_size * 0.8), d);
		float halo = pow(max(d, 0.0), 64.0) * sun_halo;
		c += sun_color * (disk * 4.0 + halo) * mix(0.5, 1.0, r);
	}
	COLOR = c;
}
