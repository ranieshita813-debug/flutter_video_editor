#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform float uFreq;
  uniform float uSpeed;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  float t = uTime * uSpeed * 4.0;
  vec2 p = uv;
  p.x += sin(uv.y * uFreq * 6.2832 + t) * 0.02 * uAmount;
  p.y += sin(uv.x * uFreq * 4.4 + t * 0.8) * 0.01 * uAmount;
  fragColor = texture(uTexture, clamp(p, vec2(0.0), vec2(1.0)));
  }