shader_type spatial;

uniform float time;
uniform vec3  playerPosition;

const int MAX_WAVE_COUNT = 15;


uniform int waveCount=2;
uniform float amplitude[MAX_WAVE_COUNT];
uniform float wavelength[MAX_WAVE_COUNT];
uniform float speed[MAX_WAVE_COUNT];
uniform vec2  direction[MAX_WAVE_COUNT];
uniform float steepness[MAX_WAVE_COUNT];

varying vec3 v_normal_geom; // normale géométrique (analytique) vers le fragment

void vertex() {
	vec3 pos = VERTEX;
	float dist = distance(pos.xz, playerPosition.xz);
	float max_dist = 100.0;

    // Tangentes initiales
    vec3 Tx = vec3(1.0, 0.0, 0.0);
    vec3 Tz = vec3(0.0, 0.0, 1.0);
	if (max_dist-dist> 0.0) {
    for (int i = 0; i < waveCount; i++) {
        vec2 d = normalize(direction[i]);
        float k = 2.0 * 3.14159265 / wavelength[i];
        float w = sqrt(9.8 * k);
        float phi = k * dot(d, pos.xz) - w * time * speed[i];

        float A = amplitude[i];
        float Q = steepness[i];
        float c = cos(phi);
        float s = sin(phi);

        // Déplacement position (Gerstner)
        pos.x += Q * A * d.x * c;
        pos.z += Q * A * d.y * c;
        pos.y += A * s;

		// Dérivé
        vec3 dPx_dx = vec3(1.0 - Q*A*k*d.x*d.x*s,  A*k*d.x*c,  -Q*A*k*d.x*d.y*s);
        vec3 dPx_dz = vec3(-Q*A*k*d.x*d.y*s,      A*k*d.y*c,   1.0 - Q*A*k*d.y*d.y*s);

        Tx += (dPx_dx - vec3(1.0, 0.0, 0.0));
        Tz += (dPx_dz - vec3(0.0, 0.0, 1.0));
	}
	}

    VERTEX = pos;

    // Normale analytique
    v_normal_geom = -normalize(cross(Tz, Tx)); // swap si inversée
}

uniform vec3  albedo  : source_color = vec3(0.02, 0.05, 0.07);
uniform float metallic  : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;

float fresnel(float power, vec3 n, vec3 v) {
	return pow(1.0 - clamp(dot(normalize(n), normalize(v)), 0.0, 1.0), power);
}


uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;

uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.1;
uniform float noise_scale : hint_range(1.0, 50.0, 0.5) = 10.0;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.30;


void fragment() {
		// base gerstner normal
	vec3 N = normalize(v_normal_geom);

	// animate UV scrolling
	vec2 uv1 = UV * noise_scale + vec2( time * time_scale, 0.0 );
	vec2 uv2 = UV * noise_scale * 1.7 + vec2( 0.0, time * time_scale * 1.3 );

	// sample normalmaps
	vec3 n1 = texture(texture_normal, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(texture_normal2, uv2).rgb * 2.0 - 1.0;

	// combine
	vec3 micro = normalize(n1 + n2);

	// blend with gerstner
	NORMAL = normalize( mix( N, micro, noise_strength ) );

	vec3 viewDir = normalize(-VIEW);
	float f = fresnel(5.0, NORMAL, viewDir);

	vec3 surface_color = albedo;

	ALBEDO = surface_color;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.8;
}
