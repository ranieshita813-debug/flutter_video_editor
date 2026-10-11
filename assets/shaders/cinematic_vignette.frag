#version 460 core
#include <flutter /runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uStrength;
  uniform float uSoftness;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 s = texture(uTexture, uv);
  vec2 c = uv - 0.5;
  c.x *= uSize.x / uSize.y;
  float d = length(c);
  float lo = 0.25 + 0.2 * (1.0 - uSoftness);
  float v = smoothstep(lo, 0.95, d);
  fragColor = vec4(s.rgb * (1.0 - uStrength * v), s.a);
  }#version 460 core
#include <flutter /runtime_effect.glsl>
  uniform vec2 uSize;
  uniform float uTime;
  uniform float uStrength;
  uniform float uSoftness;
  uniform sampler2D uTexture;
  out vec4 fragColor;
  void main(){
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 s = texture(uTexture, uv);
  vec2 c = uv - 0.5;
  c.x *= uSize.x / uSize.y;
  float d = length(c);
  float lo = 0.25 + 0.2 * (1.0 - uSoftness);
  float v = smoothstep(lo, 0.95, d);
  fragColor = vec4(s.rgb * (1.0 - uStrength * v), s.a);
  }