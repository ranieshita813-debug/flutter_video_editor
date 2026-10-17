import 'package:phosphor_icons/phosphor_icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

// ============================================================================
// KEYFRAMES: dark monochrome, CapCut style
// ============================================================================
const double _kfFps = 30;

const Color _kfBg = Color(0xFF0D0D0D);
const Color _kfCard = Color(0xFF171717);
const Color _kfLine = Color(0xFF2A2A2A);
const Color _kfText = Color(0xFFF2F2F2);
const Color _kfMuted = Color(0xFF8A8A8A);
const Color _kfDim = Color(0xFF555555);

String _kfTimecode(double s) {
  final int fps = _kfFps.toInt();
  final int total = ((s < 0 ? 0.0 : s) * _kfFps).round();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(total ~/ (fps * 60))}:${two((total ~/ fps) % 60)}:${two(total % fps)}';
}

T? _kfFind<T>(Iterable<T> items, bool Function(T) test) {
  for (final T i in items) {
    if (test(i)) return i;
  }
  return null;
}

double _kfEval(double t, CurveType type) {
  switch (type) {
    case CurveType.linear:
      return t;
    case CurveType.easeIn:
      return t * t;
    case CurveType.easeOut:
      return t * (2 - t);
    case CurveType.cubicBezier:
      return Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
  }
}

class _CurveOption {
  const _CurveOption(this.label, this.curveType);
  final String label;
  final CurveType curveType;
}

const List<_CurveOption> _kfOptions = <_CurveOption>[
  _CurveOption('Linear', CurveType.linear),
  _CurveOption('Ease in', CurveType.easeIn),
  _CurveOption('Ease out', CurveType.easeOut),
  _CurveOption('Bezier', CurveType.cubicBezier),
];

// ----------------------------------------------------------------------------
// Sheet
// ----------------------------------------------------------------------------
class KeyframeSheet extends StatefulWidget {
  const KeyframeSheet({super.key});

  @override
  State<KeyframeSheet> createState() => _KeyframeSheetState();
}

class _KeyframeSheetState extends State<KeyframeSheet> {
  Object? _selId;
  bool _lockScroll = false; // গ্রাফের হ্যান্ডেল টানার সময় লিস্ট স্ক্রল বন্ধ

  void _toast(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final playhead = context.select<EditorController, Duration>((e) => e.playhead);

    final List<Keyframe> all = <Keyframe>[...?clip?.keyframes]
      ..sort((a, b) => a.time.compareTo(b.time));

    final double total = clip == null ? 1.0 : math.max(secondsOf(clip.duration), 0.1);
    final double rel = clip == null ? 0.0 : secondsOf(playhead - clip.start);
    final bool inClip = clip != null && rel >= 0 && rel <= total;
    const double tol = 0.5 / _kfFps;

    final Keyframe? atHead = _kfFind(all, (k) => (secondsOf(k.time) - rel).abs() < tol);
    final Keyframe? selected = _selId == null ? null : _kfFind(all, (k) => k.id == _selId);

    void seekTo(double s) {
      if (clip == null) return;
      seekPlayhead(editor, secondsOf(clip.start) + s.clamp(0.0, total).toDouble());
    }

    void prev() {
      final List<Keyframe> c = all.where((k) => secondsOf(k.time) < rel - tol).toList();
      if (c.isEmpty) return;
      seekTo(secondsOf(c.last.time));
      setState(() => _selId = c.last.id);
    }

    void next() {
      final List<Keyframe> c = all.where((k) => secondsOf(k.time) > rel + tol).toList();
      if (c.isEmpty) return;
      seekTo(secondsOf(c.first.time));
      setState(() => _selId = c.first.id);
    }

    void toggle() {
      if (atHead != null) {
        editor.removeKeyframe(atHead.id);
        setState(() => _selId = null);
      } else if (!inClip) {
        _toast('Move the playhead inside the clip first.');
      } else {
        editor.addKeyframeAtPlayhead();
      }
    }

    void pick(Keyframe kf, _CurveOption o) {
      tapFeedback();
      editor.addKeyframe(kf.copyWith(curveType: o.curveType));
    }

    return ColoredBox(
      color: _kfBg,
      child: ListView(
        physics: (_lockScroll && selected != null) ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(0, 4, 0, 12 + MediaQuery.paddingOf(context).bottom),
        children: <Widget>[
          // ---- toolbar: prev / diamond / next | timecode | delete -----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                _KfAction(
                  icon: PhosphorIconsRegular.caretLeft,
                  tooltip: 'Previous keyframe',
                  onTap: clip == null ? null : prev,
                ),
                _KfAction(
                  icon: atHead != null
                      ? PhosphorIcons.diamond(PhosphorIconsStyle.fill)
                      : PhosphorIconsRegular.diamond,
                  tooltip: atHead != null ? 'Remove keyframe' : 'Add keyframe',
                  active: atHead != null,
                  onTap: clip == null ? null : toggle,
                ),
                _KfAction(
                  icon: PhosphorIconsRegular.caretRight,
                  tooltip: 'Next keyframe',
                  onTap: clip == null ? null : next,
                ),
                Expanded(
                  child: Text(
                    _kfTimecode(rel),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _kfText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                _KfAction(
                  icon: PhosphorIconsRegular.trash,
                  tooltip: 'Delete selected keyframe',
                  onTap: selected == null
                      ? null
                      : () {
                          editor.removeKeyframe(selected.id);
                          setState(() => _selId = null);
                        },
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: _kfLine),

          // ---- track ---------------------------------------------------------
          if (clip == null)
            const _KfHint('Select a clip to animate it.')
          else ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _KfTrack(
                keys: all,
                selectedId: selected?.id,
                total: total,
                playhead: rel,
                onSeek: seekTo,
                onSelect: (k) {
                  if (k == null) {
                    setState(() => _selId = null);
                  } else {
                    seekTo(secondsOf(k.time));
                    setState(() => _selId = k.id);
                  }
                },
              ),
            ),
            if (all.isEmpty)
              const _KfHint('No keyframes yet. Move the playhead and tap the diamond.'),
          ],

          // ---- curve editor (when a keyframe is selected) -------------------
          if (selected != null) ...<Widget>[
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Curve',
                style: TextStyle(color: _kfText, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _KfCard(
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _CurveGraphPainter(curveType: selected.curveType),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (int i = 0; i < _kfOptions.length; i++) ...<Widget>[
                    SizedBox(
                      width: 56,
                      child: _CurveTile(
                        option: _kfOptions[i],
                        on: _kfOptions[i].curveType == selected.curveType,
                        onTap: () => pick(selected, _kfOptions[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (all.isNotEmpty)
            const _KfHint('Tap a diamond to edit its curve.'),

          // ---- clear ---------------------------------------------------------
          if (all.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _kfMuted),
                onPressed: () {
                  tapFeedback();
                  for (final Keyframe k in all) {
                    editor.removeKeyframe(k.id);
                  }
                  setState(() {
                    _selId = null;
                    _lockScroll = false;
                  });
                },
                icon: const Icon(PhosphorIconsRegular.trash, size: 16),
                label: const Text('Clear all keyframes', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Small widgets
// ----------------------------------------------------------------------------
class _KfCard extends StatelessWidget {
  const _KfCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _kfCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );
}

class _KfHint extends StatelessWidget {
  const _KfHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kfMuted, fontSize: 12),
        ),
      );
}

class _KfAction extends StatelessWidget {
  const _KfAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color fg = onTap == null ? _kfDim : (active ? _kfBg : _kfText);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                tapFeedback();
                onTap!();
              },
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _kfText : Colors.transparent,
          ),
          child: Icon(icon, size: 21, color: fg),
        ),
      ),
    );
  }
}

class _CurveTile extends StatelessWidget {
  const _CurveTile({required this.option, required this.on, required this.onTap});
  final _CurveOption option;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius r = BorderRadius.circular(8);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: _kfCard,
                borderRadius: r,
                border: Border.all(color: on ? _kfText : Colors.transparent, width: 2),
              ),
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _CurveThumbPainter(curveType: option.curveType, on: on),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: on ? _kfText : _kfMuted,
              fontSize: 11,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurveThumbPainter extends CustomPainter {
  _CurveThumbPainter({required this.curveType, required this.on});
  final CurveType curveType;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path();
    const int steps = 24;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double x = t * size.width;
      final double y = size.height - _kfEval(t, curveType) * size.height;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = on ? _kfText : _kfMuted
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CurveThumbPainter o) => o.curveType != curveType || o.on != on;
}

// ----------------------------------------------------------------------------
// Track: ruler + single lane
// ----------------------------------------------------------------------------
class _KfTrack extends StatelessWidget {
  const _KfTrack({
    required this.keys,
    required this.selectedId,
    required this.total,
    required this.playhead,
    required this.onSeek,
    required this.onSelect,
  });

  final List<Keyframe> keys; // time অনুযায়ী সাজানো
  final Object? selectedId;
  final double total;
  final double playhead;
  final ValueChanged<double> onSeek;
  final ValueChanged<Keyframe?> onSelect;

  static const double _pad = 20;
  static const double _h = 72;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final double w = c.maxWidth;
      final double usable = math.max(w - _pad * 2, 1);
      double xOf(double sec) => _pad + sec / total * usable;
      double secOf(double dx) => ((dx - _pad) / usable * total).clamp(0.0, total).toDouble();

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          Keyframe? hit;
          double best = 22; // সবচেয়ে কাছের ডায়মন্ড, ২২px-এর মধ্যে
          for (final Keyframe k in keys) {
            final double dist = (xOf(secondsOf(k.time)) - d.localPosition.dx).abs();
            if (dist < best) {
              best = dist;
              hit = k;
            }
          }
          tapFeedback();
          if (hit != null) {
            onSelect(hit);
          } else {
            onSeek(secOf(d.localPosition.dx));
            onSelect(null);
          }
        },
        onHorizontalDragUpdate: (d) => onSeek(secOf(d.localPosition.dx)),
        child: CustomPaint(
          size: Size(w, _h),
          painter: _TrackPainter(
            keys: keys,
            selectedId: selectedId,
            total: total,
            xOf: xOf,
            playheadX: xOf(playhead.clamp(0.0, total).toDouble()),
          ),
        ),
      );
    });
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.keys,
    required this.selectedId,
    required this.total,
    required this.xOf,
    required this.playheadX,
  });

  final List<Keyframe> keys;
  final Object? selectedId;
  final double total;
  final double Function(double) xOf;
  final double playheadX;

  @override
  void paint(Canvas canvas, Size size) {
    const double rulerH = 22;
    final double cy = rulerH + (size.height - rulerH) / 2;

    // ruler ticks + labels
    const List<double> steps = <double>[0.5, 1, 2, 5, 10, 30, 60];
    double step = steps.last;
    for (final double s in steps) {
      if ((xOf(s) - xOf(0)) >= 48) {
        step = s;
        break;
      }
    }
    final Paint tick = Paint()
      ..color = _kfDim
      ..strokeWidth = 1;
    for (double t = 0; t <= total + 0.0001; t += step) {
      final double x = xOf(t);
      canvas.drawLine(Offset(x, rulerH - 6), Offset(x, rulerH - 1), tick);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: step < 1 ? '${t.toStringAsFixed(1)}s' : '${t.toInt()}s',
          style: const TextStyle(color: _kfMuted, fontSize: 9.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 0));
      final double mid = xOf(t + step / 2);
      if (t + step / 2 <= total) {
        canvas.drawLine(Offset(mid, rulerH - 4), Offset(mid, rulerH - 1), tick);
      }
    }

    // lane
    canvas.drawLine(
      Offset(xOf(0), cy),
      Offset(xOf(total), cy),
      Paint()
        ..color = _kfLine
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final Paint seg = Paint()
      ..color = _kfDim
      ..strokeWidth = 2;
    for (int i = 0; i + 1 < keys.length; i++) {
      canvas.drawLine(
        Offset(xOf(secondsOf(keys[i].time)), cy),
        Offset(xOf(secondsOf(keys[i + 1].time)), cy),
        seg,
      );
    }

    for (final Keyframe k in keys) {
      final double x = xOf(secondsOf(k.time));
      final bool on = k.id == selectedId;
      final Path p = Path()
        ..moveTo(x, cy - 8)
        ..lineTo(x + 8, cy)
        ..lineTo(x, cy + 8)
        ..lineTo(x - 8, cy)
        ..close();
      canvas.drawPath(p, Paint()..color = on ? _kfText : _kfBg);
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = on ? _kfBg : _kfMuted,
      );
    }

    // playhead
    final Paint ph = Paint()
      ..color = _kfText
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(playheadX, 4), Offset(playheadX, size.height), ph);
    canvas.drawCircle(Offset(playheadX, 4), 3.5, ph);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter o) => true;
}

// ----------------------------------------------------------------------------
// Curve graph
// ----------------------------------------------------------------------------
class _CurveGraphPainter extends CustomPainter {
  _CurveGraphPainter({required this.curveType});
  final CurveType curveType;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    const double pad = 16.0;

    final Paint gridPaint = Paint()
      ..color = _kfLine
      ..strokeWidth = 0.8;

    for (int i = 0; i <= 4; i++) {
      final double x = pad + (w - 2 * pad) * (i / 4);
      final double y = pad + (h - 2 * pad) * (i / 4);
      canvas.drawLine(Offset(x, pad), Offset(x, h - pad), gridPaint);
      canvas.drawLine(Offset(pad, y), Offset(w - pad, y), gridPaint);
    }

    final Path curvePath = Path();
    const int steps = 50;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double px = pad + t * (w - 2 * pad);
      final double py = (h - pad) - _kfEval(t, curveType) * (h - 2 * pad);
      if (i == 0) {
        curvePath.moveTo(px, py);
      } else {
        curvePath.lineTo(px, py);
      }
    }

    final Path fill = Path.from(curvePath)
      ..lineTo(w - pad, h - pad)
      ..lineTo(pad, h - pad)
      ..close();
    canvas.drawPath(fill, Paint()..color = Colors.white.withValues(alpha: 0.06));

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    for (final Offset o in <Offset>[Offset(pad, h - pad), Offset(w - pad, pad)]) {
      canvas.drawCircle(o, 6, Paint()..color = _kfBg);
      canvas.drawCircle(o, 4.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _CurveGraphPainter oldDelegate) =>
      oldDelegate.curveType != curveType;
}