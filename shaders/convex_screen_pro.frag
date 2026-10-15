#version 460 core
#include <flutter/runtime_effect.glsl>

// Convex Screen PRO
// Shapes : 0 circle lens, 1 rounded screen (CRT/TV), 2 cylinder (horizontal bulge)
// Anim   : 0 none, 1 pulse, 2 wobble, 3 ripple, 4 intro/outro (uses uProgress)
// Border : 0 clamp, 1 mirror, 2 black
//
// Float uniform order MUST match setFloat() indices in Dart (0..20).
// When used through ImageFilter.shader, sampler 0 is filled automatically.

uniform vec2  uSize;       // 0,1
uniform float uTime;       // 2   seconds
uniform float uProgress;   // 3   clip progress 0..1
uniform float uStrength;   // 4   0..1
uniform float uRadius;     // 5   0.2..1.5
uniform float uCenterX;    // 6   0..1
uniform float uCenterY;    // 7   0..1
uniform float uShape;      // 8   0,1,2
uniform float uAnim;       // 9   0..4
uniform float uSpeed;      // 10
uniform float uChroma;     // 11  0..1
uniform float uShade;      // 12  0..1 rim darkening
uniform float uReflect;    // 13  0..1 glass highlight
uniform float uBlur;       // 14  0..1 edge blur
uniform float uScan;       // 15  0..1 scanlines
uniform float uVignette;   // 16  0..1
uniform float uTwist;      // 17  -1..1 swirl amount
uniform float uFalloff;    // 18  0.5..3 lens profile
uniform float uZoom;       // 19  0.5..2
uniform float uBorder;     // 20  0,1,2

uniform sampler2D uTexture;
out vec4 fragColor;

const float PI = 3.14159265;

vec2 edgeUV(vec2 uv) {
    if (uBorder > 0.5 && uBorder < 1.5) {
        return 1.0 - abs(1.0 - mod(uv, 2.0));   // mirror
    }
    return clamp(uv, 0.0, 1.0);
}

vec3 tex(vec2 uv) {
    return texture(uTexture, edgeUV(uv)).rgb;
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float easeOutBack(float x) {
    float c1 = 1.70158;
    float c3 = c1 + 1.0;
    return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    float aspect = uSize.x / uSize.y;
    vec2 center = vec2(uCenterX, uCenterY);
    float R = max(uRadius, 0.0001);

    // ---------- animation ----------
    float s = uStrength;
    vec2 shift = vec2(0.0);
    int anim = int(uAnim + 0.5);
    if (anim == 1) {
        s *= 0.65 + 0.35 * sin(uTime * uSpeed);
    } else if (anim == 2) {
        shift = 0.04 * vec2(sin(uTime * uSpeed), cos(uTime * uSpeed * 1.3));
    } else if (anim == 4) {
        float inT  = clamp(uProgress / 0.3, 0.0, 1.0);
        float outT = clamp((1.0 - uProgress) / 0.3, 0.0, 1.0);
        s *= easeOutBack(inT) * smoothstep(0.0, 1.0, outT);
    }

    vec2 p = (uv - center - shift) * vec2(aspect, 1.0);

    // ---------- lens coordinate t (0 centre -> 1 edge) ----------
    int shape = int(uShape + 0.5);
    float t;
    if (shape == 1) {
        vec2 b = vec2(R * 1.25, R * 0.75);
        float sd = sdRoundBox(p, b, 0.25 * min(b.x, b.y));
        t = clamp(1.0 + sd / min(b.x, b.y), 0.0, 1.0);
    } else if (shape == 2) {
        t = clamp(abs(p.x) / R, 0.0, 1.0);
    } else {
        t = clamp(length(p) / R, 0.0, 1.0);
    }

    float profile = pow(max(1.0 - t * t, 0.0), uFalloff);

    // ripple: concentric waves travelling outward
    if (anim == 3) {
        float r = (shape == 2) ? abs(p.x) : length(p);
        profile += 0.12 * sin(r * 28.0 - uTime * uSpeed * 3.0) * (1.0 - t);
    }

    float f = 1.0 - s * profile;

    // ---------- swirl ----------
    vec2 q = p;
    float ang = uTwist * s * profile * 1.2;
    float ca = cos(ang), sa = sin(ang);
    q = mat2(ca, -sa, sa, ca) * q;

    if (shape == 2) {
        q = vec2(q.x * f, q.y);
    } else {
        q *= f;
    }
    q /= max(uZoom, 0.0001);

    vec2 uv2 = center + shift + vec2(q.x / aspect, q.y);

    // ---------- sampling: chroma + edge blur ----------
    vec2 dir = normalize(p + vec2(0.00001));
    float ring = t * (1.0 - t) * 4.0;               // peaks mid-way to the rim
    vec2 off = dir * uChroma * 0.014 * s * ring;
    off.x /= aspect;

    float bl = uBlur * s * smoothstep(0.4, 1.0, t) * (1.0 - t) * 0.02;
    vec3 col;
    if (bl > 0.00005) {
        vec2 o1 = vec2(bl, 0.0), o2 = vec2(0.0, bl);
        vec3 c0 = tex(uv2);
        vec3 c1 = tex(uv2 + o1) + tex(uv2 - o1) + tex(uv2 + o2) + tex(uv2 - o2);
        col = (c0 * 2.0 + c1) / 6.0;
        col.r = (tex(uv2 + off).r + col.r) * 0.5;
        col.b = (tex(uv2 - off).b + col.b) * 0.5;
    } else {
        col = vec3(tex(uv2 + off).r, tex(uv2).g, tex(uv2 - off).b);
    }

    // black border mode: outside the source frame
    if (uBorder > 1.5) {
        if (uv2.x < 0.0 || uv2.x > 1.0 || uv2.y < 0.0 || uv2.y > 1.0) {
            col = vec3(0.0);
        }
    }

    // ---------- glass look ----------
    float inside = 1.0 - t;
    float rim = smoothstep(0.5, 1.0, t) * inside * 4.0;
    col *= 1.0 - uShade * s * 0.38 * rim;

    // soft curved reflection (top-left)
    vec2 pr = p / R;
    float spec = max(0.0, 1.0 - length(pr - vec2(-0.32, -0.42)) * 1.7);
    spec = pow(spec, 3.0) * inside;
    col += uReflect * s * 0.35 * spec;

    // faint centre lift
    col += uShade * s * 0.06 * pow(inside, 3.0);

    // scanlines inside the lens
    float sl = 0.5 + 0.5 * sin(FlutterFragCoord().y * PI);
    col *= 1.0 - uScan * 0.22 * sl * smoothstep(0.0, 0.3, inside);

    // vignette (whole frame)
    vec2 vp = uv - 0.5;
    float vig = 1.0 - uVignette * smoothstep(0.35, 0.9, length(vp * vec2(aspect, 1.0)));
    col *= vig;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
