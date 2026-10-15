#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  vec3 tex(vec2 p){ return texture(uTexture, clamp(p, vec2(0.0), vec2(1.0))).rgb; }
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 px = 1.0 / uSize;
  vec4 s = texture(uTexture, uv);
  vec3 avg = (tex(uv + vec2(px.x, 0.0)) + tex(uv - vec2(px.x, 0.0)) +
  tex(uv + vec2(0.0, px.y)) + tex(uv - vec2(0.0, px.y))) * 0.25;
  fragColor = vec4(s.rgb + (s.rgb - avg) * uAmount * 1.5, s.a);
  }