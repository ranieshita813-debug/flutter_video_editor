#version 460 core
#include <flutter/runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uIntensity;
  uniform float uWarmth;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 s = texture(uTexture, uv);
  vec3 c = clamp(s.rgb, 0.0, 1.0);
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(c, c * c * (3.0 - 2.0 * c), 0.6 * uIntensity);
  float sh = (1.0 - l) * (1.0 - l);
  float hi = l * l;
  c = mix(c, c * vec3(0.85, 1.0, 1.10), sh * uIntensity * 0.6);
  c = mix(c, c * vec3(1.12, 1.02, 0.88), hi * uIntensity * 0.6);
  c.r += uWarmth * 0.05;
  c.b -= uWarmth * 0.05;
  float l2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(l2), c, 1.0 + 0.15 * uIntensity);
  fragColor = vec4(clamp(c, 0.0, 1.0), s.a);
  }