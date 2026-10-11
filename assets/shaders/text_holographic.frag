#version 460 core
#include <flutter /runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uIntensity;
  out vec4 fragColor;
  float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
  void main(){
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float h = uv.x * 1.2 + uv.y * 0.6 + uTime * 0.25;
  vec3 c = 0.5 + 0.5 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
  c = mix(vec3(1.0), c, 0.55 + 0.35 * uIntensity);
  float sp = step(0.996, h21(floor(frag / 3.0) + floor(uTime * 8.0)));
  fragColor = vec4(c + sp * 0.5, 1.0);
  }