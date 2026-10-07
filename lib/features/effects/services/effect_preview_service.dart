import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/models/shader_clip_model.dart';

abstract class NativeShaderBackend {
  Future<void> setupEffectRenderer(String effectId, String shaderSource);
  Future<void> applyEffect(ShaderEffectClip clip, Map<String, dynamic> activeParameters);
  Future<void> updateEffectParameters(Map<String, dynamic> parameters);
  Future<void> disposeRenderer();
}

class DefaultNativeShaderBackend implements NativeShaderBackend {
  @override
  Future<void> setupEffectRenderer(String effectId, String shaderSource) async {}

  @override
  Future<void> applyEffect(ShaderEffectClip clip, Map<String, dynamic> activeParameters) async {}

  @override
  Future<void> updateEffectParameters(Map<String, dynamic> parameters) async {}

  @override
  Future<void> disposeRenderer() async {}
}

class FlutterShaderPreviewRenderer {
  static Widget applyShaderEffect({
    required Widget child,
    required ShaderEffectClip clip,
    required Map<String, dynamic> parameters,
    required Duration playheadTime,
  }) {
    if (!clip.isEnabled) return child;

    final double intensity = _getDouble(parameters, 'intensity', 1.0);
    final double brightness = _getDouble(parameters, 'brightness', 0.0);
    final double contrast = _getDouble(parameters, 'contrast', 1.0);
    final double saturation = _getDouble(parameters, 'saturation', 1.0);
    final double blurAmount = _getDouble(parameters, 'blurAmount', 0.0);
    final double glowStrength = _getDouble(parameters, 'glowStrength', 0.0);
    final double distortion = _getDouble(parameters, 'distortionAmount', 0.0);
    final double vignette = _getDouble(parameters, 'vignette', 0.0);
    final double speed = _getDouble(parameters, 'speed', 1.0);
    final Color tintColor = _getColor(parameters, 'tintColor', Colors.transparent);

    Widget result = child;

    if (brightness != 0.0 || contrast != 1.0 || saturation != 1.0 || intensity != 1.0) {
      final matrix = _buildColorMatrix(
        brightness: brightness * intensity,
        contrast: contrast,
        saturation: saturation,
        intensity: intensity,
      );
      result = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: result,
      );
    }

    if (tintColor != Colors.transparent && tintColor.a > 0) {
      result = ColorFiltered(
        colorFilter: ColorFilter.mode(
          tintColor.withValues(alpha: (tintColor.a * intensity).clamp(0.0, 1.0)),
          BlendMode.overlay,
        ),
        child: result,
      );
    }

    final String effectId = clip.effectId.toLowerCase();

    if (effectId.contains('glitch') || distortion > 0) {
      result = _GlitchOverlay(
        distortion: distortion * intensity,
        playheadTime: playheadTime,
        speed: speed,
        child: result,
      );
    }

    if (glowStrength > 0 || effectId.contains('glow') || effectId.contains('bloom')) {
      result = _GlowOverlay(
        glowStrength: glowStrength * intensity,
        color: tintColor != Colors.transparent ? tintColor : const Color(0xFF00E5FF),
        child: result,
      );
    }

    if (blurAmount > 0 || effectId.contains('blur')) {
      result = _BlurOverlay(
        blurAmount: blurAmount * intensity,
        child: result,
      );
    }

    if (vignette > 0 || effectId.contains('vignette')) {
      result = Stack(
        fit: StackFit.expand,
        children: [
          result,
          _VignetteOverlay(vignetteStrength: vignette * intensity),
        ],
      );
    }

    if (effectId.contains('light_leak') || effectId.contains('leak')) {
      result = Stack(
        fit: StackFit.expand,
        children: [
          result,
          _LightLeakOverlay(
            intensity: intensity,
            playheadTime: playheadTime,
            speed: speed,
          ),
        ],
      );
    }

    return result;
  }

  static double _getDouble(Map<String, dynamic> params, String key, double defaultValue) {
    final val = params[key];
    if (val is num) return val.toDouble();
    return defaultValue;
  }

  static Color _getColor(Map<String, dynamic> params, String key, Color defaultValue) {
    final val = params[key];
    if (val is Color) return val;
    if (val is int) return Color(val);
    return defaultValue;
  }

  static List<double> _buildColorMatrix({
    required double brightness,
    required double contrast,
    required double saturation,
    required double intensity,
  }) {
    const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final double s = saturation;
    final double sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    final double off = (0.5 * (1 - contrast) + brightness) * 255 * intensity;
    final double c = contrast;

    return <double>[
      c * (sr + s), c * sg, c * sb, 0, off,
      c * sr, c * (sg + s), c * sb, 0, off,
      c * sr, c * sg, c * (sb + s), 0, off,
      0, 0, 0, 1, 0,
    ];
  }
}

class _GlitchOverlay extends StatelessWidget {
  const _GlitchOverlay({
    required this.child,
    required this.distortion,
    required this.playheadTime,
    required this.speed,
  });

  final Widget child;
  final double distortion;
  final Duration playheadTime;
  final double speed;

  @override
  Widget build(BuildContext context) {
    if (distortion <= 0) return child;

    final timeMs = playheadTime.inMilliseconds;
    final seed = (timeMs * speed / 100).floor();
    final random = math.Random(seed);
    final isGlitching = random.nextDouble() < (distortion * 0.4);

    if (!isGlitching) return child;

    final offsetX = (random.nextDouble() - 0.5) * 16 * distortion;
    final offsetY = (random.nextDouble() - 0.5) * 8 * distortion;

    return Transform.translate(
      offset: Offset(offsetX, offsetY),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: CustomPaint(
              painter: _GlitchPainter(distortion: distortion, seed: seed),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlitchPainter extends CustomPainter {
  _GlitchPainter({required this.distortion, required this.seed});
  final double distortion;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final barCount = (distortion * 6).round().clamp(1, 10);

    for (int i = 0; i < barCount; i++) {
      final y = random.nextDouble() * size.height;
      final height = random.nextDouble() * 12 + 2;
      final paint = Paint()
        ..color = (i % 2 == 0)
            ? const Color(0x8000E5FF)
            : const Color(0x80FF0055)
        ..style = PaintingStyle.fill;

      canvas.drawRect(Rect.fromLTWH(0, y, size.width, height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchPainter old) =>
      old.distortion != distortion || old.seed != seed;
}

class _GlowOverlay extends StatelessWidget {
  const _GlowOverlay({
    required this.child,
    required this.glowStrength,
    required this.color,
  });

  final Widget child;
  final double glowStrength;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (glowStrength <= 0) return child;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: (glowStrength * 0.4).clamp(0.0, 1.0)),
            blurRadius: 20 * glowStrength,
            spreadRadius: 4 * glowStrength,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BlurOverlay extends StatelessWidget {
  const _BlurOverlay({
    required this.child,
    required this.blurAmount,
  });

  final Widget child;
  final double blurAmount;

  @override
  Widget build(BuildContext context) {
    if (blurAmount <= 0) return child;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: blurAmount * 4,
        sigmaY: blurAmount * 4,
      ),
      child: child,
    );
  }
}

class _VignetteOverlay extends StatelessWidget {
  const _VignetteOverlay({required this.vignetteStrength});
  final double vignetteStrength;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.85,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: vignetteStrength.clamp(0.0, 0.95)),
          ],
          stops: const [0.5, 1.0],
        ),
      ),
    );
  }
}

class _LightLeakOverlay extends StatelessWidget {
  const _LightLeakOverlay({
    required this.intensity,
    required this.playheadTime,
    required this.speed,
  });

  final double intensity;
  final Duration playheadTime;
  final double speed;

  @override
  Widget build(BuildContext context) {
    final t = (playheadTime.inMilliseconds / 1000.0) * speed;
    final opacity = (0.3 + 0.3 * math.sin(t * 2.0)) * intensity;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9900).withValues(alpha: opacity.clamp(0.0, 0.8)),
            const Color(0xFFFF0066).withValues(alpha: (opacity * 0.6).clamp(0.0, 0.8)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
    );
  }
}
