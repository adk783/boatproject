shader_type spatial;

uniform float time;
uniform vec3  playerPosition;    // utilisé pour la distance radiale
uniform vec3  globalPosition;    // position du MeshInstance dans le monde

const int MAX_WAVE_COUNT = 15;

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

        // ============================
        // WAVE 0 = Brownian (octaves)
        // ============================
        if (i == 0) {
            float A   = amplitude[i];
            float lam = wavelength[i];
            float Q0  = steepness[i];
            float S0  = speed[i];

            const float amp_mult   = 0.8;
            const float freq_mult  = 1.2;

            // rayon de départ pour l’octave 0
            float current_radius = 1000.0;

            for (int o = 0; o < octaves; o++) {
                // rayon de cette octave
                float radius = current_radius;
                if (radius < 20.0) {
                    radius = 20.0; // en dessous de 20m, on rend tout
                }

                bool active = dist_to_player <= radius;

                if (active) {
                    vec2 d = rand_dir(o + 31);

                    float k = 2.0 * 3.14159265 / max(lam, 1e-4);
                    float w = sqrt(9.8 * k);

                    // Phase basée sur world_xz (ancrée au monde)
                    float phi = k * dot(d, world_xz) - w * time * S0 + float(o) * 1.347;

                    float c = cos(phi);
                    float s = sin(phi);

                    float Q = Q0 * pow(0.55, float(o));

                    // Déplacement Gerstner
                    pos.x += Q * A * d.x * c;
                    pos.z += Q * A * d.y * c;
                    pos.y += A * s;

                    // Dérivées pour la normale analytique
                    vec3 dPx_dx = vec3(
                        1.0 - Q*A*k*d.x*d.x*s,  A*k*d.x*c,  -Q*A*k*d.x*d.y*s
                    );
                    vec3 dPx_dz = vec3(
                        -Q*A*k*d.x*d.y*s,      A*k*d.y*c,   1.0 - Q*A*k*d.y*d.y*s
                    );

                    Tx += (dPx_dx - vec3(1.0, 0.0, 0.0));
                    Tz += (dPx_dz - vec3(0.0, 0.0, 1.0));
                }

                // octave suivante (toujours, même si inactive)
                lam /= freq_mult;
                A   *= amp_mult;
                current_radius *= 0.83;
            }
        }

        // ============================
        // WAVES i >= 1 (classiques)
        // ============================
        else {
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
