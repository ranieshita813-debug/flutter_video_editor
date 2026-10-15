import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class FxParam {
  const FxParam(this.name, this.min, this.max, this.def);
  final String name;
  final double min, max, def;
}

class FxDef {
  const FxDef(this.id, this.label, this.params, {this.isText = false});
  final String id;
  final String label;
  final List<FxParam> params; // order MUST match the .frag uniforms
  final bool isText;
  String get asset => 'shaders/$id.frag';
}

abstract final class FxShaders {
  static const List<FxDef> all = <FxDef>[
    FxDef('chromatic_aberration', 'Chromatic Aberration', [FxParam('amount', 0, 1, 0.5)]),
    FxDef('digital_glitch', 'Digital Glitch',
        [FxParam('amount', 0, 1, 0.7), FxParam('speed', 0.2, 4, 1.5)]),
    FxDef('vhs_tape', 'VHS Tape',
        [FxParam('amount', 0, 1, 0.7), FxParam('speed', 0.2, 4, 1.0)]),
    FxDef('vhs', 'Classic VHS',
        [FxParam('distortion', 0, 2, 1.0), FxParam('scanlines', 0, 1, 0.5), FxParam('noise', 0, 1, 0.5)]),
    FxDef('film_grain', 'Film Grain',
        [FxParam('amount', 0, 1, 0.5), FxParam('sizePx', 1, 4, 1.5)]),
    FxDef('cinematic_vignette', 'Cinematic Vignette',
        [FxParam('strength', 0, 1, 0.6), FxParam('softness', 0, 1, 0.6)]),
    FxDef('vignette', 'Simple Vignette',
        [FxParam('radius', 0, 1, 0.8), FxParam('softness', 0, 1, 0.5)]),
    FxDef('dream_bloom', 'Dream Bloom', [
      FxParam('intensity', 0, 1, 0.5),
      FxParam('threshold', 0.2, 0.95, 0.6),
      FxParam('radius', 0.1, 1, 0.5),
    ]),
    FxDef('mosaic_pixelate', 'Mosaic Pixelate', [FxParam('sizePx', 2, 64, 12)]),
    FxDef('liquid_wave', 'Liquid Wave', [
      FxParam('amount', 0, 2, 1),
      FxParam('freq', 0.5, 6, 2),
      FxParam('speed', 0.2, 4, 1),
    ]),
    FxDef('wave', 'Wave Distortion', [
      FxParam('frequency', 1, 30, 10.0),
      FxParam('amplitude', 0, 5, 1.0),
    ]),
    FxDef('cinematic_grade', 'Teal & Orange Grade',
        [FxParam('intensity', 0, 1, 0.7), FxParam('warmth', -1, 1, 0)]),
    FxDef('crisp_sharpen', 'Crisp Sharpen', [FxParam('amount', 0, 1, 0.5)]),
    FxDef('lens_distortion', 'Lens Distortion', [FxParam('amount', -1, 1, 0.4)]),
    FxDef('convex_screen_pro', 'Convex Screen Pro', [
      FxParam('progress', 0, 1, 0),
      FxParam('strength', 0, 1, 0.5),
      FxParam('radius', 0.2, 1.5, 0.8),
      FxParam('centerX', 0, 1, 0.5),
      FxParam('centerY', 0, 1, 0.5),
      FxParam('shape', 0, 2, 1),
      FxParam('anim', 0, 4, 0),
    ]),
    FxDef('speed_zoom_blur', 'Speed Zoom Blur', [
      FxParam('amount', 0, 1, 0.5),
      FxParam('centerX', 0, 1, 0.5),
      FxParam('centerY', 0, 1, 0.5),
    ]),
    FxDef('light_leak', 'Light Leak',
        [FxParam('intensity', 0, 1, 0.6), FxParam('speed', 0.2, 3, 1)]),
    FxDef('chroma_key', 'Chroma Key Shader', [
      FxParam('keyR', 0, 1, 0.0),
      FxParam('keyG', 0, 1, 1.0),
      FxParam('keyB', 0, 1, 0.0),
      FxParam('similarity', 0, 1, 0.4),
      FxParam('smoothness', 0, 1, 0.1),
    ]),
    FxDef('text_gold_foil', 'Gold Foil', [FxParam('intensity', 0, 1, 0.8)], isText: true),
    FxDef('text_holographic', 'Holographic', [FxParam('intensity', 0, 1, 0.8)], isText: true),
    FxDef('text_glass_shine', 'Glass Shine', [FxParam('intensity', 0, 1, 0.9)], isText: true),
  ];

  static final Map<String, FxDef> byId = <String, FxDef>{for (final d in all) d.id: d};
  static final Map<String, ui.FragmentProgram> _programs = <String, ui.FragmentProgram>{};

  /// Maps this library's param names to the names your existing effects use.
  static const Map<String, String> _legacy = <String, String>{
    'amount': 'distortionAmount',
    'intensity': 'glowStrength',
    'strength': 'vignette',
  };

  /// Maps your existing effect ids to the new shaders.
  static const Map<String, String> _idAlias = <String, String>{
    'glitch': 'digital_glitch',
    'vhs': 'vhs_tape',
    'wave': 'liquid_wave',
    'vignette': 'cinematic_vignette',
    'glow': 'dream_bloom',
  };

  /// Call once at startup, before runApp.
  static Future<void> preload() async {
    for (final d in all) {
      try {
        _programs[d.id] = await ui.FragmentProgram.fromAsset(d.asset);
      } catch (e) {
        debugPrint('Shader ${d.id} failed to load: $e');
      }
    }
  }

  static double _val(FxParam p, Map<String, double> m) {
    final double v = m[p.name] ?? m[_legacy[p.name]] ?? p.def;
    return v.clamp(p.min, p.max).toDouble();
  }

  /// Video effect. Needs Impeller (ImageFilter.shader).
  static Widget applyVideo({
    required Widget child,
    required String effectId,
    Map<String, double> params = const <String, double>{},
    Duration time = Duration.zero,
    Size? size,
  }) {
    if (effectId == 'blur') {
      final double s =
          ((params['blurAmount'] ?? params['amount'] ?? 0.5) * 12).clamp(0.0, 40.0).toDouble();
      if (s < 0.1) return child;
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.clamp),
        child: child,
      );
    }
    final FxDef? def = byId[_idAlias[effectId] ?? effectId];
    final ui.FragmentProgram? program = def == null ? null : _programs[def.id];
    if (def == null || program == null || def.isText) return child;

    if (size != null) {
      return _buildVideoShaderWidget(child, program, def, size, params, time);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final Size effectiveSize = Size(
          constraints.hasBoundedWidth && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 1920.0,
          constraints.hasBoundedHeight && constraints.maxHeight > 0
              ? constraints.maxHeight
              : 1080.0,
        );
        return _buildVideoShaderWidget(child, program, def, effectiveSize, params, time);
      },
    );
  }

  static Widget _buildVideoShaderWidget(
    Widget child,
    ui.FragmentProgram program,
    FxDef def,
    Size size,
    Map<String, double> params,
    Duration time,
  ) {
    final ui.FragmentShader shader = program.fragmentShader();
    final double w = math.max(1.0, size.width);
    final double h = math.max(1.0, size.height);
    shader.setFloat(0, w);
    shader.setFloat(1, h);
    int i = 2;
    shader.setFloat(i++, time.inMicroseconds / 1e6);
    for (final p in def.params) {
      shader.setFloat(i++, _val(p, params));
    }
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: child);
  }

  /// Text effect, e.g. FxShaders.applyText(child: textWidget, effectId: 'text_gold_foil', ...)
  static Widget applyText({
    required Widget child,
    required String effectId,
    Duration time = Duration.zero,
    double intensity = 1.0,
  }) {
    final ui.FragmentProgram? program = _programs[effectId];
    if (program == null) return child;
    final double t = time.inMicroseconds / 1e6;
    return ShaderMask(
      blendMode: effectId == 'text_glass_shine' ? BlendMode.srcATop : BlendMode.srcIn,
      shaderCallback: (Rect b) {
        final ui.FragmentShader s = program.fragmentShader();
        final double w = math.max(1.0, b.width);
        final double h = math.max(1.0, b.height);
        s
          ..setFloat(0, w)
          ..setFloat(1, h)
          ..setFloat(2, t)
          ..setFloat(3, intensity.clamp(0.0, 1.0).toDouble());
        return s;
      },
      child: child,
    );
  }
}
