#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uFrequency;
uniform float uAmplitude;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 st = FlutterFragCoord().xy / uSize;

    // Wave distortion
    float waveX = sin(st.y * uFrequency + uTime * 4.0) * (uAmplitude * 0.02);
    float waveY = cos(st.x * uFrequency + uTime * 4.0) * (uAmplitude * 0.02);

    vec2 distortedST = clamp(st + vec2(waveX, waveY), 0.0, 1.0);
    fragColor = texture(uTexture, distortedST);
}
