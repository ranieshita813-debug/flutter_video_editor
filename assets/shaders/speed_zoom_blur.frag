#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uAmount;
uniform float uCenterX;
uniform float uCenterY;
uniform sampler2D uTexture;
out vec4 fragColor;
void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 dir = (uv - vec2(uCenterX, uCenterY)) * uAmount * 0.15;
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 16; i++) {
    acc += texture(uTexture, clamp(uv - dir * (float(i) / 16.0), vec2(0.0), vec2(1.0)));
  }
  fragColor = acc / 16.0;
}