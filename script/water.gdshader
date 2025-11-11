shader_type spatial;

uniform float time;
uniform vec3  playerPosition;    // utilisé pour la distance radiale
uniform vec3  globalPosition;    // position du MeshInstance dans le monde

const int MAX_WAVE_COUNT = 30;

uniform int   waveCount = 2;
uniform float amplitude[MAX_WAVE_COUNT];
uniform float wavelength[MAX_WAVE_COUNT];
uniform float speed[MAX_WAVE_COUNT];
uniform vec2  direction[MAX_WAVE_COUNT];
uniform float steepness[MAX_WAVE_COUNT];

varying vec3 v_normal_geom;
uniform int   octaves    = 1;

// Direction pseudo-aléatoire stable à partir d'un "seed" entier
vec2 rand_dir(int seed) {
    float a = fract(sin(float(seed) * 12.9898) * 43758.5453123) * 6.283185307;
    return vec2(cos(a), sin(a));
}

void vertex() {
    vec3 pos = VERTEX;

    // position MONDE du vertex (plane placé à globalPosition)
    vec2 world_xz = pos.xz + globalPosition.xz;

    // distance au joueur (pour décider si on calcule les octaves)
    float dist_to_player = length(world_xz - playerPosition.xz);

    // tangentes pour la normale géométrique
    vec3 Tx = vec3(1.0, 0.0, 0.0);
    vec3 Tz = vec3(0.0, 0.0, 1.0);

    for (int i = 0; i < waveCount; i++) {
            vec2 d = normalize(direction[i]);
            float k = 2.0 * 3.14159265 / max(wavelength[i], 1e-4);
            float w = sqrt(9.8 * k);

            float phi = k * dot(d, world_xz) - w * time * speed[i];

            float A = amplitude[i];
            float Q = steepness[i];
            float c = cos(phi);
            float s = sin(phi);

            pos.x += Q * A * d.x * c;
            pos.z += Q * A * d.y * c;
            pos.y += A * s;

            vec3 dPx_dx = vec3(1.0 - Q*A*k*d.x*d.x*s,  A*k*d.x*c,  -Q*A*k*d.x*d.y*s);
            vec3 dPx_dz = vec3(-Q*A*k*d.x*d.y*s,      A*k*d.y*c,   1.0 - Q*A*k*d.y*d.y*s);

            Tx += (dPx_dx - vec3(1.0, 0.0, 0.0));
            Tz += (dPx_dz - vec3(0.0, 0.0, 1.0));
        
    }

    VERTEX = pos;
    v_normal_geom = -normalize(cross(Tz, Tx));
}

// ===== Matériau =====
uniform vec3  albedo  : source_color = vec3(0.02, 0.05, 0.07);
uniform float metallic  : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;

float fresnel(float power, vec3 n, vec3 v) {
    return pow(1.0 - clamp(dot(normalize(n), normalize(v)), 0.0, 1.0), power);
}

uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;

void fragment() {
    vec3 N = normalize(v_normal_geom);
    NORMAL = N;

    ALBEDO   = albedo;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    SPECULAR = 0.8;
}
