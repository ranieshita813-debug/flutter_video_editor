#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform float uThreshold;
uniform float uRadius;
uniform sampler2D uTexture;
out vec4 fragColor;
void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 base = texture(uTexture, uv);
  vec3 acc = vec3(0.0);
  for (int i = 0; i < 16; i++) {
    float fi = float(i);
    float ang = fi * 2.39996;
    float rad = sqrt((fi + 0.5) / 16.0);
    vec2 o = vec2(cos(ang), sin(ang)) * rad * uRadius * 40.0 / uSize;
    vec3 s = texture(uTexture, clamp(uv + o, vec2(0.0), vec2(1.0))).rgb;
    acc += max(s - uThreshold, vec3(0.0)) / max(1.0 - uThreshold, 0.05);
  }
  vec3 glow = acc / 16.0 * uIntensity * 2.0;
  fragColor = vec4(1.0 - (1.0 - base.rgb) * (1.0 - glow), base.a);
}