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
// 하늘 천체 (설계서 12장 P21): 거대한 행성 + 작은 위성. 해 쪽이 밝은 구로 음영, 지평선 근처는 대기에 녹는다.
uniform vec3 planet_dir = vec3(0.55, 0.42, -0.72);
uniform float planet_radius = 0.34;        // 각반경 (라디안, 약 20°)
uniform vec3 planet_color : source_color = vec3(0.78, 0.80, 0.84);
uniform vec3 moon_dir = vec3(0.80, 0.30, -0.52);
uniform float moon_radius = 0.035;
uniform vec3 moon_color : source_color = vec3(0.86, 0.86, 0.88);

// 천체 원반: 반환 x = 덮음(0~1), y = 해 쪽 밝기
vec2 body(vec3 eye, vec3 dir, float rad, vec3 sun) {
	vec3 d = normalize(dir);
	vec3 u = normalize(cross(d, abs(d.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 v = cross(u, d);
	float s = sin(rad);
	vec2 p = vec2(dot(eye, u), dot(eye, v)) / s;
	float r2 = dot(p, p);
	if (dot(eye, d) <= 0.0 || r2 >= 1.0) {
		return vec2(0.0);
	}
	vec3 n = normalize(u * p.x + v * p.y - d * sqrt(1.0 - r2));   // 보는 쪽을 향한 구 표면
	float lit = clamp(dot(-n, sun) * 0.5 + 0.5, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.92, 1.0, sqrt(r2));
	return vec2(edge, lit);
}

void sky() {
	float r = recovery_here;
	vec3 zen = mix(zenith_depleted, zenith_restored, r);
	vec3 hor = mix(horizon_depleted, horizon_restored, r);
	float y = max(EYEDIR.y, 0.0);
	vec3 c = mix(hor, zen, 1.0 - exp(-y * horizon_sharpness));
	if (EYEDIR.y < 0.0) {
		c = hor;
	}
	if (!AT_CUBEMAP_PASS) {   // 환경광 계산에는 넣지 않는다
		vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(-0.5, 0.6, 0.6);
		float haze = smoothstep(0.0, 0.25, EYEDIR.y);                    // 지평선에 가까울수록 대기에 묻힘
		float clear = mix(0.35, 0.85, r) * haze;                       // 회복 전 흐릿 → 회복 후 선명
		vec2 pl = body(EYEDIR, planet_dir, planet_radius, sun);
		float bands = 0.92 + 0.08 * sin(EYEDIR.y * 60.0 + EYEDIR.x * 20.0);
		vec3 pc = planet_color * mix(0.18, 1.05, pl.y) * bands;
		c = mix(c, mix(c, pc, 0.85), pl.x * clear);
		vec2 mo = body(EYEDIR, moon_dir, moon_radius, sun);
		c = mix(c, moon_color * mix(0.25, 1.1, mo.y), mo.x * clear);
	}
	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {   // 해 원반은 화면에만 (환경광을 부풀리지 않게)
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disk = smoothstep(cos(sun_size), cos(sun_size * 0.8), d);
		float halo = pow(max(d, 0.0), 64.0) * sun_halo;
		c += sun_color * (disk * 4.0 + halo) * mix(0.5, 1.0, r);
	}
	COLOR = c;
}
