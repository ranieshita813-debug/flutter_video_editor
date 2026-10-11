#version 460 core
#include <flutter /runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform float uSizePx;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
  void main(){
  vec2 frag = FlutterFragCoord().xy;
  vec4 s = texture(uTexture, frag / uSize);
  vec2 cell = floor(frag / max(uSizePx, 1.0));
  float n = h21(cell + fract(uTime) * 91.7) - 0.5;
  float lum = dot(s.rgb, vec3(0.299, 0.587, 0.114));
  float w = 1.0 - abs(lum * 2.0 - 1.0) * 0.6;
  fragColor = vec4(s.rgb + n * uAmount * 0.35 * w, s.a);
  }