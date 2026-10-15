#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform float uSpeed;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
  vec4 tex(vec2 p){ return texture(uTexture, clamp(p, vec2(0.0), vec2(1.0))); }
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  float t = uTime * uSpeed;
  float a = uAmount;
  float tr = smoothstep(0.07, 0.0, abs(uv.y - fract(t * 0.12)));
  uv.x += sin(uv.y * uSize.y * 0.35 + t * 20.0) * 0.016 * tr * a;
  uv.x += (sin(uv.y * 35.0 + t * 4.0) * 0.0012 + sin(uv.y * 6.0 - t) * 0.0016) * a;
  float bleed = 0.004 * a;
  float r = tex(uv + vec2(bleed, 0.0)).r;
  vec4 g = tex(uv);
  float b = tex(uv - vec2(bleed, 0.0)).b;
  vec3 c = vec3(r, g.g, b);
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(vec3(l), c, 0.85);
  c = c * 0.92 + 0.04;
  c *= 0.94 + 0.06 * sin(uv.y * uSize.y * 1.5);
  c += (h21(vec2(floor(uv.y * uSize.y * 0.5), floor(t * 30.0))) - 0.5) * 0.08 * a * tr;
  c += tr * 0.05 * a;
  fragColor = vec4(c, g.a);
  }