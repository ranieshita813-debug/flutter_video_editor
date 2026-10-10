#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uDistortion;
uniform float uScanlines;
uniform float uNoise;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 st = FlutterFragCoord().xy / uSize;

    // Chromatic aberration / RGB shift
    float shift = uDistortion * 0.015 * sin(uTime * 3.0 + st.y * 20.0);
    vec2 rUV = vec2(st.x + shift, st.y);
    vec2 gUV = st;
    vec2 bUV = vec2(st.x - shift, st.y);

    float r = texture(uTexture, clamp(rUV, 0.0, 1.0)).r;
    float g = texture(uTexture, clamp(gUV, 0.0, 1.0)).g;
    float b = texture(uTexture, clamp(bUV, 0.0, 1.0)).b;
    float a = texture(uTexture, clamp(st, 0.0, 1.0)).a;

    vec3 col = vec3(r, g, b);

    // Scanlines
    if (uScanlines > 0.0) {
        float scanline = sin(st.y * uSize.y * 1.5) * 0.1 * uScanlines;
        col -= scanline;
    }

    // Vignette
    float dist = distance(st, vec2(0.5));
    col *= smoothstep(0.8, 0.2, dist * 0.6);

    fragColor = vec4(col, a);
}
