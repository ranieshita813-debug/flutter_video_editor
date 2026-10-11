#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uIntensity;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 dark = vec3(0.45, 0.28, 0.05);
  vec3 mid = vec3(0.95, 0.72, 0.20);
  vec3 light = vec3(1.0, 0.95, 0.70);
  float band = 0.5 + 0.5 * sin(uv.y * 9.4248 + 0.5);
  vec3 c = mix(dark, mid, smoothstep(0.0, 0.6, band));
  c = mix(c, light, smoothstep(0.7, 1.0, band));
  float p = fract(uTime * 0.4) * 2.0 - 0.5;
  float shine = smoothstep(0.12, 0.0, abs(uv.x + uv.y * 0.3 - p));
  c += shine * 0.6 * uIntensity;
  fragColor = vec4(c, 1.0);
  }