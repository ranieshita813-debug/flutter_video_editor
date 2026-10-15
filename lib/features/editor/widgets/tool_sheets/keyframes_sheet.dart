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
const Color _kfLineHi = Color(0xFF3A3A3A);
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

class _CurveOption {
  const _CurveOption(this.label, this.curveType);
  final String label;
  final CurveType curveType;
}

const List<_CurveOption> _kfOptions = <_CurveOption>[
  _CurveOption('Linear', CurveType.linear),
  _CurveOption('Ease in', CurveType.easeIn),
  _CurveOption('Ease out', CurveType.easeOut),
  _CurveOption('Cubic Bezier', CurveType.cubicBezier),
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
        padding: EdgeInsets.fromLTRB(12, 12, 12, 16 + MediaQuery.paddingOf(context).bottom),
        children: <Widget>[
          // ---- prev / diamond / next / timecode / delete --------------------
          _KfCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: <Widget>[
                _KfAction(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous keyframe',
                  onTap: clip == null ? null : prev,
                ),
                _KfAction(
                  icon: atHead != null ? Icons.diamond_rounded : Icons.diamond_outlined,
                  tooltip: atHead != null ? 'Remove keyframe' : 'Add keyframe',
                  active: atHead != null,
                  onTap: clip == null ? null : toggle,
                ),
                _KfAction(
                  icon: Icons.chevron_right_rounded,
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
                  icon: Icons.delete_outline_rounded,
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

          // ---- Track ---------------------------------------------------------
          const SizedBox(height: 10),
          if (clip == null)
            const _KfHint('Select a clip to animate it.')
          else if (all.isEmpty)
            const _KfHint('No keyframes yet. Move the playhead and tap the diamond.')
          else
            _KfCard(
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

          // ---- Curve type tiles & CapCut Curve Graph (when selected) ------------
          if (selected != null) ...<Widget>[
            const SizedBox(height: 12),
            _KfCard(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'ANIMATION GRAPH / CURVE',
                      style: TextStyle(
                        color: _kfMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _CurveGraphPainter(curveType: selected.curveType),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.5,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: <Widget>[
                      for (final _CurveOption o in _kfOptions)
                        _CurveTile(
                          option: o,
                          on: o.curveType == selected.curveType,
                          onTap: () => pick(selected, o),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (all.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: _KfHint('Tap a diamond to edit its curve.'),
            ),

          const SizedBox(height: 16),
          _kfOutlineButton(
            'Clear all keyframes',
            all.isEmpty
                ? null
                : () {
                    for (final Keyframe k in all) {
                      editor.removeKeyframe(k.id);
                    }
                    setState(() {
                      _selId = null;
                      _lockScroll = false;
                    });
                  },
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Small widgets
// ----------------------------------------------------------------------------
class _KfCard extends StatelessWidget {
  const _KfCard({required this.child, this.padding = const EdgeInsets.all(6)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _kfCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kfLine),
        ),
        child: child,
      );
}

class _KfHint extends StatelessWidget {
  const _KfHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kfMuted, fontSize: 13),
        ),
      );
}

Widget _kfOutlineButton(String label, VoidCallback? onTap) => SizedBox(
      height: 44,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kfText,
          disabledForegroundColor: _kfDim,
          side: BorderSide(color: onTap == null ? _kfLine : _kfLineHi),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap == null
            ? null
            : () {
                tapFeedback();
                onTap();
              },
        child: Text(label),
      ),
    );

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
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _kfText : Colors.transparent,
          ),
          child: Icon(icon, size: 22, color: fg),
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
    final BorderRadius r = BorderRadius.circular(10);
    return Material(
      color: on ? _kfText : _kfCard,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: on ? _kfText : _kfLine),
          ),
          child: Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: on ? _kfBg : _kfMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Track (single lane)
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

  static const double _pad = 16;
  static const double _h = 56;

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
    required this.xOf,
    required this.playheadX,
  });

  final List<Keyframe> keys;
  final Object? selectedId;
  final double Function(double) xOf;
  final double playheadX;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;

    canvas.drawLine(
      Offset(16, cy),
      Offset(size.width - 16, cy),
      Paint()
        ..color = _kfLineHi
        ..strokeWidth = 2,
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

    final Paint ph = Paint()
      ..color = _kfText
      ..strokeWidth = 2;
    canvas.drawLine(Offset(playheadX, 6), Offset(playheadX, size.height - 4), ph);
    canvas.drawCircle(Offset(playheadX, 6), 3.5, ph);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter o) => true;
}

// ----------------------------------------------------------------------------
// Curve Graph Painter (CapCut Velocity / Curve Visualization)
// ----------------------------------------------------------------------------
class _CurveGraphPainter extends CustomPainter {
  _CurveGraphPainter({required this.curveType});
  final CurveType curveType;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    const double pad = 16.0;

    // Grid lines
    final Paint gridPaint = Paint()
      ..color = _kfLine
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      final double x = pad + (w - 2 * pad) * (i / 4);
      final double y = pad + (h - 2 * pad) * (i / 4);
      canvas.drawLine(Offset(x, pad), Offset(x, h - pad), gridPaint);
      canvas.drawLine(Offset(pad, y), Offset(w - pad, y), gridPaint);
    }

    // Outer border
    final Rect rect = Rect.fromLTRB(pad, pad, w - pad, h - pad);
    canvas.drawRect(rect, gridPaint);

    // Curve Path
    final Path curvePath = Path();
    curvePath.moveTo(pad, h - pad);

    const int steps = 50;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double val = _evaluateCurve(t, curveType);
      final double px = pad + t * (w - 2 * pad);
      final double py = (h - pad) - val * (h - 2 * pad);
      if (i == 0) {
        curvePath.moveTo(px, py);
      } else {
        curvePath.lineTo(px, py);
      }
    }

    final Paint pathPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(curvePath, pathPaint);

    // Keyframe End Points
    final Paint pointPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(pad, h - pad), 4.0, pointPaint);
    canvas.drawCircle(Offset(w - pad, pad), 4.0, pointPaint);
  }

  double _evaluateCurve(double t, CurveType type) {
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

  @override
  bool shouldRepaint(covariant _CurveGraphPainter oldDelegate) =>
      oldDelegate.curveType != curveType;
}
