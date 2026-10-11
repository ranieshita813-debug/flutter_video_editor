#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uIntensity;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  float p = fract(uTime * 0.5) * 2.4 - 0.7;
  float d = abs(uv.x + uv.y * 0.35 - p);
  float shine = smoothstep(0.14, 0.0, d) * uIntensity;
  fragColor = vec4(vec3(shine), shine);
  }