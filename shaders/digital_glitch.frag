#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform float uSpeed;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  float hash(float n){ return fract(sin(n * 127.1) * 43758.5453); }
  vec4 tex(vec2 p){ return texture(uTexture, clamp(p, vec2(0.0), vec2(1.0))); }
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  float t = floor(uTime * uSpeed * 8.0);
  float band = floor(uv.y * 14.0);
  float trig = step(1.0 - 0.35 * uAmount, hash(t * 1.7 + band * 0.31));
  float shift = (hash(band + t) - 0.5) * 0.18 * uAmount * trig;
  float split = 0.012 * uAmount * trig;
  vec2 p = vec2(uv.x + shift, uv.y);
  float r = tex(p + vec2(split, 0.0)).r;
  vec4 g = tex(p);
  float b = tex(p - vec2(split, 0.0)).b;
  vec3 c = vec3(r, g.g, b);
  c += 0.05 * uAmount * trig * hash(floor(uv.y * uSize.y * 0.5) + t);
  fragColor = vec4(c, g.a);
  }