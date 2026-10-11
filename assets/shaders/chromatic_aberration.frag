#version 460 core
#include <flutter /runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  vec4 tex(vec2 p){ return texture(uTexture, clamp(p, vec2(0.0), vec2(1.0))); }
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 c = uv - 0.5;
  vec2 off = c * dot(c, c) * uAmount * 0.12;
  float r = tex(uv + off).r;
  vec4 g = tex(uv);
  float b = tex(uv - off).b;
  fragColor = vec4(r, g.g, b, g.a);
  }