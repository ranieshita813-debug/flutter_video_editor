import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A loading text where a soft "wave" of light travels across the characters.
/// Each character lifts slightly, scales up and brightens as the wave passes.
///
/// Usage:
/// ```dart
/// const TextShimmerWave(
///   'Loading effects...',
///   style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
/// )
/// ```
class TextShimmerWave extends StatefulWidget {
  const TextShimmerWave(
    this.text, {
    super.key,
    this.style,
    this.baseColor = const Color(0xFF6B7280),
    this.waveColor = Colors.white,
    this.duration = const Duration(milliseconds: 1800),
    this.waveHeight = 4.0,
    this.scaleBoost = 0.15,
    this.spread = 2.0,
    this.textAlign = WrapAlignment.center,
  });

  final String text;
  final TextStyle? style;

  /// Color of characters when the wave is not on them.
  final Color baseColor;

  /// Color of characters at the peak of the wave.
  final Color waveColor;

  /// Time for the wave to cross the whole text once.
  final Duration duration;

  /// Max upward lift (logical pixels) at the wave peak.
  final double waveHeight;

  /// Extra scale at the wave peak (0.15 = +15%).
  final double scaleBoost;

  /// Wave width in characters (bigger = softer, wider wave).
  final double spread;

  final WrapAlignment textAlign;

  @override
  State<TextShimmerWave> createState() => _TextShimmerWaveState();
}

class _TextShimmerWaveState extends State<TextShimmerWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant TextShimmerWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      _controller
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters.toList();
    final n = chars.length;
    final baseStyle = DefaultTextStyle.of(context).style.merge(widget.style);

    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // Wave center sweeps from before the first char to after the last.
            final pad = widget.spread * 2;
            final center = -pad + _controller.value * (n - 1 + pad * 2);

            return Wrap(
              alignment: widget.textAlign,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < n; i++)
                  _buildChar(chars[i], i, center, baseStyle),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildChar(String ch, int i, double center, TextStyle baseStyle) {
    // Gaussian falloff around the wave center -> 0..1
    final d = (i - center) / widget.spread;
    final intensity = math.exp(-d * d);

    final color = Color.lerp(widget.baseColor, widget.waveColor, intensity)!;

    return Transform.translate(
      offset: Offset(0, -widget.waveHeight * intensity),
      child: Transform.scale(
        scale: 1 + widget.scaleBoost * intensity,
        child: Text(ch, style: baseStyle.copyWith(color: color)),
      ),
    );
  }
}

/// Quick demo screen.
class TextShimmerWaveDemo extends StatelessWidget {
  const TextShimmerWaveDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Center(
        child: TextShimmerWave(
          'Plz Wait...',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          baseColor: Color(0xFF555555),
          waveColor: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}