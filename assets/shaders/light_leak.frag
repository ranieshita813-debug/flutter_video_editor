#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uIntensity;
  uniform float uSpeed;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 s = texture(uTexture, uv);
  float t = uTime * uSpeed * 0.3;
  float a = smoothstep(0.6, 0.0, length(uv - vec2(0.10 + 0.10 * sin(t), 0.20 + 0.10 * cos(t * 1.3))));
  float b = smoothstep(0.5, 0.0, length(uv - vec2(0.95, 0.85 + 0.08 * sin(t * 0.7))));
  vec3 leak = vec3(1.0, 0.45, 0.15) * a + vec3(1.0, 0.20, 0.40) * b * 0.8;
  fragColor = vec4(1.0 - (1.0 - s.rgb) * (1.0 - leak * uIntensity * 0.7), s.a);
  }