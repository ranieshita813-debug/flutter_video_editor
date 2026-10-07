// lib/features/editor/widgets/audio_waveform.dart
//
// Audio clip body for the timeline: peak + RMS waveform in three styles,
// a volume line with a draggable node, a label pill, and a dim overlay on
// the part of the clip that is still ahead of the playhead.
//
// Plug in real data with [peakRmsDecoder] (preferred) or the old
// [waveformDecoder] (peaks only, RMS is estimated). Without either, a
// byte-hash fallback keeps the UI alive but is NOT a real waveform.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

// ----------------------------------------------------------------------------
// Public knobs
// ----------------------------------------------------------------------------

enum WaveStyle {
  /// The old thin vertical lines.
  classic,

  /// Premiere-style: soft outer peak shape + solid inner RMS shape, mirrored.
  peakRms,

  /// CapCut-style rounded mirrored bars with lighter peak caps.
  bars,
}

/// Change at runtime (e.g. from a settings sheet): `waveStyle.value = WaveStyle.bars`.
final ValueNotifier<WaveStyle> waveStyle = ValueNotifier<WaveStyle>(WaveStyle.peakRms);

/// Normalised 0..1 amplitude envelopes, same length.
class WaveData {
  const WaveData(this.peak, this.rms);
  final Float32List peak;
  final Float32List rms;
  bool get isEmpty => peak.isEmpty;

  factory WaveData.flat(int n, [double v = 0.3]) =>
      WaveData(Float32List(n)..fillRange(0, n, v), Float32List(n)..fillRange(0, n, v * 0.6));
}

/// Preferred: return real peak and RMS envelopes (e.g. from FFmpeg astats or a
/// native PCM decode). [bars] is the number of samples across the whole file.
typedef PeakRmsDecoder = Future<WaveData> Function(String path, int bars);
PeakRmsDecoder? peakRmsDecoder;

/// Legacy: peaks only. RMS is estimated as 60% of the peak.
typedef WaveformDecoder = Future<List<double>> Function(String path, int bars);
WaveformDecoder? waveformDecoder;

// ----------------------------------------------------------------------------
// Data loading (cached by path + resolution, independent of zoom)
// ----------------------------------------------------------------------------

final Map<String, Future<WaveData>> _cache = <String, Future<WaveData>>{};

Future<WaveData> waveFuture(String path, int bars) =>
    _cache.putIfAbsent('$path|$bars', () async {
      final PeakRmsDecoder? pr = peakRmsDecoder;
      if (pr != null) {
        try {
          final WaveData d = await pr(path, bars);
          if (!d.isEmpty) return d;
        } catch (_) {}
      }
      final WaveformDecoder? dec = waveformDecoder;
      if (dec != null) {
        try {
          final List<double> p = await dec(path, bars);
          if (p.isNotEmpty) return _fromPeaks(p);
        } catch (_) {}
      }
      return _fromPeaks(await _fallbackPeaks(path, bars));
    });

WaveData _fromPeaks(List<double> p) {
  final Float32List peak = Float32List(p.length);
  final Float32List rms = Float32List(p.length);
  for (int i = 0; i < p.length; i++) {
    final double v = p[i].clamp(0.0, 1.0).toDouble();
    peak[i] = v;
    rms[i] = v * 0.6;
  }
  return WaveData(peak, rms);
}

Future<List<double>> _fallbackPeaks(String path, int bars) async {
  const double flat = 0.4;
  try {
    final RandomAccessFile raf = await File(path).open();
    final List<int> bytes = <int>[];
    int remaining = 48 * 1024;
    while (remaining > 0) {
      final Uint8List b = await raf.read(math.min(remaining, 4096));
      if (b.isEmpty) break;
      bytes.addAll(b);
      remaining -= b.length;
    }
    await raf.close();
    if (bytes.isEmpty) return List<double>.filled(bars, flat);
    final List<double> out = List<double>.filled(bars, flat);
    final int per = math.max(1, bytes.length ~/ bars);
    for (int i = 0; i < bars; i++) {
      int h = 0;
      final int end = math.min(bytes.length, (i + 1) * per);
      for (int j = i * per; j < end; j++) {
        h = (h * 31 + bytes[j]) & 0x7fffffff;
      }
      out[i] = 0.2 + 0.8 * ((h % 997) / 997.0);
    }
    return out;
  } catch (_) {
    return List<double>.filled(bars, flat);
  }
}

// ----------------------------------------------------------------------------
// Waveform widget + painter
// ----------------------------------------------------------------------------

class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.path,
    required this.durationSec,
    required this.color,
    required this.volume,
  });

  final String path;
  final double durationSec;
  final Color color;
  final double volume;

  @override
  Widget build(BuildContext context) {
    // ~40 samples per second of audio, resampled at paint time, so the data
    // (and cache entry) does not change when the user zooms.
    final int bars = (durationSec * 40).round().clamp(64, 3000).toInt();
    return ValueListenableBuilder<WaveStyle>(
      valueListenable: waveStyle,
      builder: (context, style, _) => FutureBuilder<WaveData>(
        future: waveFuture(path, bars),
        builder: (context, s) => CustomPaint(
          painter: WavePainter(
            data: s.data ?? WaveData.flat(64),
            color: color,
            style: style,
            volume: volume,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  WavePainter({
    required this.data,
    required this.color,
    required this.style,
    required this.volume,
  });

  final WaveData data;
  final Color color;
  final WaveStyle style;
  final double volume;

  static const Color _clip = Color(0xFFFF5A5A);

  @override
  void paint(Canvas canvas, Size size) {
    final int n = data.peak.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final double w = size.width, h = size.height;
    final bool tall = h >= 46;
    final double mid = h / 2 + (tall ? 4 : 0);
    final double amp = h / 2 - (tall ? 9 : 4);

    // Max (peak) or mean (rms) of the samples that fall inside [x0, x1].
    double bucket(Float32List a, double x0, double x1, {required bool max}) {
      final int i0 = math.min(n - 1, math.max(0, (x0 / w * n).floor()));
      final int i1 = math.min(n, math.max(i0 + 1, (x1 / w * n).ceil()));
      double m = 0, sum = 0;
      for (int i = i0; i < i1; i++) {
        final double v = a[i];
        if (v > m) m = v;
        sum += v;
      }
      return max ? m : sum / (i1 - i0);
    }

    double lvl(double v) => math.min(1.0, v * volume);

    switch (style) {
      case WaveStyle.classic:
        final Paint p = Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        for (double x = 2.5; x < w; x += 5) {
          final double a =
              math.max(3.0, lvl(bucket(data.peak, x - 2.5, x + 2.5, max: true)) * (h - 8));
          canvas.drawLine(Offset(x, mid - a / 2), Offset(x, mid + a / 2), p);
        }

      case WaveStyle.peakRms:
        const double step = 1.5;
        final int count = (w / step).ceil() + 1;
        final List<double> xs = List<double>.generate(count, (i) => math.min(w, i * step));
        final List<double> pk = <double>[
          for (final x in xs) bucket(data.peak, x - step, x + step, max: true),
        ];
        final List<double> rm = <double>[
          for (final x in xs) bucket(data.rms, x - step, x + step, max: false),
        ];

        Path shape(List<double> v) {
          final Path path = Path()..moveTo(0, mid);
          for (int i = 0; i < count; i++) {
            path.lineTo(xs[i], mid - lvl(v[i]) * amp);
          }
          for (int i = count - 1; i >= 0; i--) {
            path.lineTo(xs[i], mid + lvl(v[i]) * amp);
          }
          return path..close();
        }

        canvas.drawPath(shape(pk), Paint()..color = color.withAlpha(97));
        canvas.drawPath(shape(rm), Paint()..color = color);
        canvas.drawLine(
          Offset(0, mid),
          Offset(w, mid),
          Paint()
            ..color = Colors.white.withAlpha(70)
            ..strokeWidth = 1,
        );
        final Paint clip = Paint()..color = _clip;
        for (int i = 0; i < count; i++) {
          if (pk[i] * volume > 1.0) {
            canvas.drawRect(Rect.fromLTWH(xs[i], mid - amp - 1, step, 3), clip);
            canvas.drawRect(Rect.fromLTWH(xs[i], mid + amp - 2, step, 3), clip);
          }
        }

      case WaveStyle.bars:
        const double bw = 3, gap = 2;
        final Paint soft = Paint()..color = color.withAlpha(100);
        final Paint solid = Paint()..color = color;
        for (double x = 1; x + bw <= w; x += bw + gap) {
          final double r = lvl(bucket(data.rms, x, x + bw, max: false) * 1.25) * amp;
          final double a = math.max(2.0, r);
          final double pe = math.max(a, lvl(bucket(data.peak, x, x + bw, max: true)) * amp);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, mid - pe, bw, pe * 2), const Radius.circular(1.5)),
            soft,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, mid - a, bw, a * 2), const Radius.circular(1.5)),
            solid,
          );
        }
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter old) =>
      old.data != data ||
      old.color != color ||
      old.style != style ||
      old.volume != volume;
}

// ----------------------------------------------------------------------------
// Audio clip body (waveform + volume line + label + played dim)
// ----------------------------------------------------------------------------

/// Y position of the volume line for a 0..2 gain, as a fraction of height.
double _volumeY(double v, double h) => h * (0.9 - 0.76 * (v.clamp(0.0, 2.0) / 2));

class AudioClipBody extends StatefulWidget {
  const AudioClipBody({
    super.key,
    required this.editor,
    required this.path,
    required this.label,
    required this.startMs,
    required this.endMs,
    required this.volume,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    required this.selected,
    required this.locked,
    required this.border,
    required this.background,
    required this.waveColor,
    this.isVoiceover = false,
  });

  final EditorController editor;
  final String path;
  final String label;
  final int startMs;
  final int endMs;
  final double volume;
  final int fadeInMs;
  final int fadeOutMs;
  final bool selected;
  final bool locked;
  final Color border;
  final Color background;
  final Color waveColor;
  final bool isVoiceover;

  @override
  State<AudioClipBody> createState() => _AudioClipBodyState();
}

class _AudioClipBodyState extends State<AudioClipBody> {
  double? _dragVol;
  double _dragY = 0;

  double get _vol => _dragVol ?? widget.volume;

  void _commit(double v) {
    final sc = widget.editor.selectedClip;
    if (sc == null) return;
    widget.editor.updateAudioProperties(
      AudioProperties(
        volume: v,
        speed: sc.speed,
        fadeIn: Duration(milliseconds: widget.fadeInMs),
        fadeOut: Duration(milliseconds: widget.fadeOutMs),
      ),
    );
  }

  String _db(double v) {
    if (v <= 0.001) return '-∞ dB';
    final double db = 20 * math.log(v) / math.ln10;
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  @override
  Widget build(BuildContext context) {
    final double v = _vol;
    final int durMs = math.max(1, widget.endMs - widget.startMs);
    final double durSec = durMs / 1000.0;

    return Container(
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.border, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(builder: (context, c) {
          final double w = c.maxWidth, h = c.maxHeight;
          final double ny = _volumeY(v, h);
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: WaveformView(
                  path: widget.path,
                  durationSec: durSec,
                  color: widget.waveColor,
                  volume: v,
                ),
              ),
              ValueListenableBuilder<WaveStyle>(
                valueListenable: waveStyle,
                builder: (context, style, _) {
                  return Positioned.fill(
                    child: _PlayedDim(
                      editor: widget.editor,
                      startMs: widget.startMs,
                      endMs: widget.endMs,
                      style: style,
                    ),
                  );
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _VolumeLinePainter(
                      volume: v,
                      fadeInMs: widget.fadeInMs,
                      fadeOutMs: widget.fadeOutMs,
                      durationMs: durMs,
                      emphasised: widget.selected,
                    ),
                  ),
                ),
              ),
              if (w >= 50)
                Positioned(
                  left: 8,
                  top: 4,
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: math.max(20.0, w - 16)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0x73000000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            HugeIcon(
                              icon: widget.isVoiceover
                                  ? HugeIcons.strokeRoundedMic01
                                  : HugeIcons.strokeRoundedMusicNote01,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.selected && !widget.locked && w >= 80)
                Positioned(
                  left: 14,
                  top: ny - 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _dragVol = widget.volume;
                        _dragY = _volumeY(widget.volume, h);
                      });
                    },
                    onVerticalDragUpdate: (d) {
                      _dragY += d.delta.dy;
                      double nv = ((0.9 - _dragY / h) / 0.76) * 2;
                      nv = nv.clamp(0.0, 2.0).toDouble();
                      if ((nv - 1.0).abs() < 0.05) {
                        if (_dragVol != 1.0) HapticFeedback.selectionClick();
                        nv = 1.0;
                      }
                      nv = (nv * 100).round() / 100;
                      setState(() => _dragVol = nv);
                      _commit(nv);
                    },
                    onVerticalDragEnd: (_) => setState(() => _dragVol = null),
                    onVerticalDragCancel: () => setState(() => _dragVol = null),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF121214), width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_dragVol != null)
                Positioned(
                  left: 52,
                  top: math.max(2.0, ny - 20),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xA6000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _db(_dragVol!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// Dims the part of the clip that is still ahead of the playhead.
class _PlayedDim extends StatelessWidget {
  const _PlayedDim({
    required this.editor,
    required this.startMs,
    required this.endMs,
    required this.style,
  });

  final EditorController editor;
  final int startMs;
  final int endMs;
  final WaveStyle style;

  @override
  Widget build(BuildContext context) {
    if (style == WaveStyle.bars) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Selector<EditorController, Duration>(
        selector: (_, e) => e.playhead,
        builder: (context, p, _) {
          final int dur = math.max(1, endMs - startMs);
          final double f =
              ((p.inMilliseconds - startMs) / dur).clamp(0.0, 1.0).toDouble();
          return LayoutBuilder(
            builder: (context, c) => Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: c.maxWidth * (1 - f),
                height: double.infinity,
                child: const ColoredBox(color: Color(0x6B0A0E10)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VolumeLinePainter extends CustomPainter {
  _VolumeLinePainter({
    required this.volume,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.durationMs,
    required this.emphasised,
  });

  final double volume;
  final int fadeInMs;
  final int fadeOutMs;
  final int durationMs;
  final bool emphasised;

  @override
  void paint(Canvas canvas, Size size) {
    if (!emphasised && (volume - 1).abs() < 0.005 && fadeInMs == 0 && fadeOutMs == 0) return;
    final double y = _volumeY(volume, size.height);
    final double w = size.width;
    final double h = size.height;

    final double inFrac = (fadeInMs / math.max(1, durationMs)).clamp(0.0, 0.5);
    final double outFrac = (fadeOutMs / math.max(1, durationMs)).clamp(0.0, 0.5);

    final double inX = w * inFrac;
    final double outX = w * (1.0 - outFrac);

    final Path path = Path();
    if (inFrac > 0) {
      path.moveTo(0, h);
      path.lineTo(inX, y);
    } else {
      path.moveTo(0, y);
    }

    path.lineTo(outX, y);

    if (outFrac > 0) {
      path.lineTo(w, h);
    } else {
      path.lineTo(w, y);
    }

    final Paint paint = Paint()
      ..color = Colors.white.withAlpha(emphasised ? 217 : 90)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _VolumeLinePainter old) =>
      old.volume != volume ||
      old.fadeInMs != fadeInMs ||
      old.fadeOutMs != fadeOutMs ||
      old.durationMs != durationMs ||
      old.emphasised != emphasised;
}
