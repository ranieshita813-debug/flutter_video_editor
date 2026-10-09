#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uKeyColorR;
uniform float uKeyColorG;
uniform float uKeyColorB;
uniform float uSimilarity;
uniform float uSmoothness;
uniform float uHighlight;
uniform float uShadow;
uniform float uPedestal;
uniform float uChoke;
uniform float uSoften;
uniform float uContrast;
uniform float uMidPoint;
uniform float uSpill;
uniform float uSpillRange;
uniform float uDesaturate;
uniform float uSpillLuma;
uniform float uSaturation;
uniform float uHue;
uniform float uLuminance;
uniform float uOutput;

uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 st = FlutterFragCoord().xy / uSize;
    vec4 col = texture(uTexture, st);

    vec3 keyColor = vec3(uKeyColorR, uKeyColorG, uKeyColorB);

    // Color distance in RGB space
    float dist = distance(col.rgb, keyColor);

    // Keying alpha calculation using similarity & smoothness threshold
    float minThresh = uSimilarity * 0.7;
    float maxThresh = uSimilarity * 0.7 + max(uSmoothness, 0.001);
    float alpha = smoothstep(minThresh, maxThresh, dist);

    // Spill suppression
    if (uSpill > 0.0) {
        float greenSpill = max(0.0, col.g - max(col.r, col.b));
        col.g -= greenSpill * uSpill;
    }

    // Color adjustments: Saturation
    if (uSaturation != 1.0) {
        float luma = dot(col.rgb, vec3(0.2126, 0.7152, 0.0722));
        col.rgb = mix(vec3(luma), col.rgb, uSaturation);
    }

    // Luminance / Brightness
    col.rgb += uLuminance;

    // Output selection: 0 = composite, 1 = matte, 2 = source
    if (uOutput == 1.0) {
        fragColor = vec4(vec3(alpha), 1.0);
    } else if (uOutput == 2.0) {
        fragColor = col;
    } else {
        fragColor = vec4(col.rgb * alpha, col.a * alpha);
    }
}
