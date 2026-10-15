#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uAmount;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 c = uv - 0.5;
  float r2 = dot(c, c);
  vec2 p = 0.5 + c * (1.0 - uAmount * r2 * 1.2) / (1.0 - uAmount * 0.15);
  if (p.x < 0.0 || p.x> 1.0 || p.y < 0.0 || p.y> 1.0) { fragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
      fragColor = texture(uTexture, p);
      }