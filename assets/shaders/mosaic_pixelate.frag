#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uSizePx;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 frag = FlutterFragCoord().xy;
  float cell = max(uSizePx, 1.0);
  vec2 uv = (floor(frag / cell) + 0.5) * cell / uSize;
  fragColor = texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
  }