#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uRadius;
uniform float uSoftness;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 st = FlutterFragCoord().xy / uSize;
    vec4 col = texture(uTexture, st);

    float dist = distance(st, vec2(0.5));
    float vignette = smoothstep(uRadius, uRadius - uSoftness, dist);

    fragColor = vec4(col.rgb * vignette, col.a);
}
