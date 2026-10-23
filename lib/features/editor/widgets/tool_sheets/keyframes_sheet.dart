import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/utils/keyframe_curves.dart';

// ============================================================================
// KEYFRAMES: dark monochrome, CapCut style
//
// Requires (see keyframe_curves.dart):
//  - CurveType.bounce and CurveType.random
//  - Keyframe fields: bounceCount, bounciness, randomAmount, randomDetail,
//    randomSeed (with copyWith)
// ============================================================================
const double _kfFps = 30;

const Color _kfBg = Color(0xFF0C1014);
const Color _kfCard = Color(0xFF171717);
const Color _kfLine = Color(0xFF2A2A2A);
const Color _kfText = Color(0xFFF2F2F2);
const Color _kfMuted = Color(0xFF8A8A8A);
const Color _kfDim = Color(0xFF555555);
const Color _kfBlue = Color(0xFF5B8CFF);

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

// ----------------------------------------------------------------------------
// Curve presets
// ----------------------------------------------------------------------------
class _CurveOption {
  const _CurveOption(
    this.label,
    this.curveType, [
    this.cp1x = 0.25,
    this.cp1y = 0.10,
    this.cp2x = 0.25,
    this.cp2y = 1.00,
  ]);
  final String label;
  final CurveType curveType;
  final double cp1x;
  final double cp1y;
  final double cp2x;
  final double cp2y;
}

const List<_CurveOption> _kfOptions = <_CurveOption>[
  _CurveOption('Linear', CurveType.linear, 0.0, 0.0, 1.0, 1.0),
  _CurveOption('Ease in', CurveType.easeIn, 0.42, 0.0, 1.0, 1.0),
  _CurveOption('Ease out', CurveType.easeOut, 0.0, 0.0, 0.58, 1.0),
  _CurveOption('Custom', CurveType.cubicBezier, 0.25, 0.10, 0.25, 1.00),
  _CurveOption('Overshoot', CurveType.cubicBezier, 0.34, 1.56, 0.64, 1.00),
  _CurveOption('Bounce', CurveType.bounce),
  _CurveOption('Random', CurveType.random),
  _CurveOption('Fast start', CurveType.cubicBezier, 0.05, 0.70, 0.10, 1.00),
  _CurveOption('Slow down', CurveType.cubicBezier, 0.90, 0.00, 0.95, 0.30),
];

bool _sameCp(_CurveOption o, Keyframe k) =>
    (o.cp1x - k.cp1x).abs() < 0.05 &&
    (o.cp1y - k.cp1y).abs() < 0.05 &&
    (o.cp2x - k.cp2x).abs() < 0.05 &&
    (o.cp2y - k.cp2y).abs() < 0.05;

bool _optionIsOn(_CurveOption o, Keyframe k) {
  if (o.curveType != k.curveType) return false;
  if (o.curveType != CurveType.cubicBezier) return true;
  if (!_sameCp(o, k)) return false;
  if (o.label == 'Custom') {
    // "Custom" lights up only when no named bezier preset matches.
    return !_kfOptions.any((p) =>
        p.label != 'Custom' && p.curveType == CurveType.cubicBezier && _sameCp(p, k));
  }
  return true;
}

// Plot mapping: y range is -0.5..1.5 so overshoot and bounce stay visible.
// 0 and 1 sit at 25% and 75% of the plot height.
const double _plotPadX = 20;
const double _plotPadY = 14;

double _gx(Size s, double v) => _plotPadX + v.clamp(0.0, 1.0) * (s.width - _plotPadX * 2);
double _gy(Size s, double v) =>
    _plotPadY + (1.5 - v.clamp(-0.5, 1.5)) / 2 * (s.height - _plotPadY * 2);
Offset _gp(Size s, double x, double y) => Offset(_gx(s, x), _gy(s, y));

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
  bool _lockScroll = false; // stop list scrolling while dragging a curve handle

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
    final int selIndex = selected == null ? -1 : all.indexWhere((k) => k.id == selected.id);
    final bool hasNext = selIndex >= 0 && selIndex < all.length - 1;
    final Keyframe? nextKf = hasNext ? all[selIndex + 1] : null;

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
      Keyframe updated = kf.copyWith(
        curveType: o.curveType,
        cp1x: o.cp1x,
        cp1y: o.cp1y,
        cp2x: o.cp2x,
        cp2y: o.cp2y,
      );
      if (o.curveType == CurveType.random) {
        // New pattern on every tap.
        updated = updated.copyWith(randomSeed: math.Random().nextInt(9999) + 1);
      }
      editor.addKeyframe(updated);
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
                selectedIndex: selIndex,
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
            const Divider(height: 1, thickness: 0.5, color: _kfLine),
            if (all.isEmpty)
              const _KfHint('No keyframes yet. Move the playhead and tap the diamond.')
            else if (selected == null)
              const _KfHint('Tap a diamond to edit its curve.')
            else if (!hasNext)
              const _KfHint('The last keyframe has no curve. Select an earlier one.'),
          ],

          // ---- curve section (selected keyframe that has a next one) ---------
          if (selected != null && nextKf != null) ...<Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    'Curve to next keyframe',
                    style: TextStyle(color: _kfText, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  _KfChip(
                    '${secondsOf(selected.time).toStringAsFixed(1)}s to '
                    '${secondsOf(nextKf.time).toStringAsFixed(1)}s',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _kfOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final _CurveOption opt = _kfOptions[i];
                  return SizedBox(
                    width: 56,
                    child: _CurveTile(
                      option: opt,
                      on: _optionIsOn(opt, selected),
                      onTap: () => pick(selected, opt),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _CurveEditor(
                keyframe: selected,
                onChanged: editor.addKeyframe,
                onDragStateChanged: (dragging) {
                  if (_lockScroll != dragging) setState(() => _lockScroll = dragging);
                },
              ),
            ),
          ],

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
class _KfChip extends StatelessWidget {
  const _KfChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _kfCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: _kfMuted,
            fontSize: 11,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      );
}

class _KfHint extends StatelessWidget {
  const _KfHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? _kfText : Colors.transparent, width: 2),
              ),
              padding: const EdgeInsets.all(10),
              child: CustomPaint(painter: _CurveThumbPainter(option: option, on: on)),
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
  _CurveThumbPainter({required this.option, required this.on});
  final _CurveOption option;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path();
    const int steps = 40;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double v = evalKeyframeCurve(
        t,
        option.curveType,
        cp1x: option.cp1x,
        cp1y: option.cp1y,
        cp2x: option.cp2x,
        cp2y: option.cp2y,
      ).clamp(-0.2, 1.2);
      // Leave headroom so overshoot and bounce are not clipped.
      final double x = t * size.width;
      final double y = size.height - (v * 0.8 + 0.1) * size.height;
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
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CurveThumbPainter o) => o.option != option || o.on != on;
}

// ----------------------------------------------------------------------------
// Track: ruler + single lane
// ----------------------------------------------------------------------------
class _KfTrack extends StatelessWidget {
  const _KfTrack({
    required this.keys,
    required this.selectedId,
    required this.selectedIndex,
    required this.total,
    required this.playhead,
    required this.onSeek,
    required this.onSelect,
  });

  final List<Keyframe> keys; // sorted by time
  final Object? selectedId;
  final int selectedIndex;
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
          double best = 24; // nearest diamond within 24px
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
            selectedIndex: selectedIndex,
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
    required this.selectedIndex,
    required this.total,
    required this.xOf,
    required this.playheadX,
  });

  final List<Keyframe> keys;
  final Object? selectedId;
  final int selectedIndex;
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

    // segments: the one the curve editor controls is thicker and brighter
    for (int i = 0; i + 1 < keys.length; i++) {
      final bool on = i == selectedIndex;
      canvas.drawLine(
        Offset(xOf(secondsOf(keys[i].time)), cy),
        Offset(xOf(secondsOf(keys[i + 1].time)), cy),
        Paint()
          ..color = on ? _kfText : _kfDim
          ..strokeWidth = on ? 3 : 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // diamonds
    for (final Keyframe k in keys) {
      final double x = xOf(secondsOf(k.time));
      final bool on = k.id == selectedId;
      final double r = on ? 10 : 8;
      final Path p = Path()
        ..moveTo(x, cy - r)
        ..lineTo(x + r, cy)
        ..lineTo(x, cy + r)
        ..lineTo(x - r, cy)
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
  bool shouldRepaint(covariant _TrackPainter o) {
    if (o.playheadX != playheadX ||
        o.selectedId != selectedId ||
        o.selectedIndex != selectedIndex ||
        o.total != total ||
        o.keys.length != keys.length) {
      return true;
    }
    for (int i = 0; i < keys.length; i++) {
      if (o.keys[i].id != keys[i].id || o.keys[i].time != keys[i].time) return true;
    }
    return false;
  }
}

// ----------------------------------------------------------------------------
// Curve editor: graph + controls that depend on the curve type
// ----------------------------------------------------------------------------
class _CurveEditor extends StatefulWidget {
  const _CurveEditor({
    required this.keyframe,
    required this.onChanged,
    required this.onDragStateChanged,
  });

  final Keyframe keyframe;
  final ValueChanged<Keyframe> onChanged;
  final ValueChanged<bool> onDragStateChanged;

  @override
  State<_CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<_CurveEditor> {
  int? _activeHandle;

  void _endDrag() {
    if (_activeHandle != null) {
      _activeHandle = null;
      widget.onDragStateChanged(false);
    }
  }

  @override
  void dispose() {
    // Never leave the parent list locked.
    if (_activeHandle != null) widget.onDragStateChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Keyframe kf = widget.keyframe;
    final bool isBezier = kf.curveType == CurveType.cubicBezier;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kfCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final Size size = Size(constraints.maxWidth, constraints.maxHeight);

                void updateHandle(Offset pos) {
                  final double nx =
                      ((pos.dx - _plotPadX) / (size.width - _plotPadX * 2)).clamp(0.0, 1.0);
                  final double ny =
                      (1.5 - (pos.dy - _plotPadY) / (size.height - _plotPadY * 2) * 2)
                          .clamp(-0.5, 1.5);
                  if (_activeHandle == 1) {
                    widget.onChanged(kf.copyWith(
                      curveType: CurveType.cubicBezier,
                      cp1x: nx,
                      cp1y: ny,
                    ));
                  } else if (_activeHandle == 2) {
                    widget.onChanged(kf.copyWith(
                      curveType: CurveType.cubicBezier,
                      cp2x: nx,
                      cp2y: ny,
                    ));
                  }
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Handles exist only for cubic bezier curves.
                  onPanStart: !isBezier
                      ? null
                      : (d) {
                          final Offset p1 = _gp(size, kf.cp1x, kf.cp1y);
                          final Offset p2 = _gp(size, kf.cp2x, kf.cp2y);
                          final double d1 = (p1 - d.localPosition).distance;
                          final double d2 = (p2 - d.localPosition).distance;

                          if (d1 < 32 && d1 <= d2) {
                            _activeHandle = 1;
                          } else if (d2 < 32) {
                            _activeHandle = 2;
                          } else if (d1 < 60 && d1 <= d2) {
                            _activeHandle = 1;
                          } else if (d2 < 60) {
                            _activeHandle = 2;
                          } else {
                            _activeHandle = null;
                          }
                          if (_activeHandle != null) {
                            widget.onDragStateChanged(true);
                            updateHandle(d.localPosition);
                          }
                        },
                  onPanUpdate: !isBezier
                      ? null
                      : (d) {
                          if (_activeHandle != null) updateHandle(d.localPosition);
                        },
                  onPanEnd: (_) => _endDrag(),
                  onPanCancel: _endDrag,
                  child: CustomPaint(
                    size: size,
                    painter: _CurvePainter(keyframe: kf),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (isBezier)
          _BezierControls(
            keyframe: kf,
            onReset: () => widget.onChanged(kf.copyWith(
              curveType: CurveType.cubicBezier,
              cp1x: 0.25,
              cp1y: 0.10,
              cp2x: 0.25,
              cp2y: 1.00,
            )),
          )
        else if (kf.curveType == CurveType.bounce) ...<Widget>[
          _ParamSlider(
            label: 'Bounces',
            value: kf.bounceCount.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            display: '${kf.bounceCount}',
            onChanged: (v) => widget.onChanged(kf.copyWith(bounceCount: v.round())),
          ),
          _ParamSlider(
            label: 'Bounciness',
            value: kf.bounciness.clamp(0.2, 0.8).toDouble(),
            min: 0.2,
            max: 0.8,
            display: kf.bounciness.toStringAsFixed(2),
            onChanged: (v) => widget.onChanged(kf.copyWith(bounciness: v)),
          ),
        ] else if (kf.curveType == CurveType.random) ...<Widget>[
          _ParamSlider(
            label: 'Intensity',
            value: kf.randomAmount.clamp(0.05, 1.0).toDouble(),
            min: 0.05,
            max: 1.0,
            display: '${(kf.randomAmount * 100).round()}%',
            onChanged: (v) => widget.onChanged(kf.copyWith(randomAmount: v)),
          ),
          _ParamSlider(
            label: 'Detail',
            value: kf.randomDetail.clamp(3, 24).toDouble(),
            min: 3,
            max: 24,
            divisions: 21,
            display: '${kf.randomDetail}',
            onChanged: (v) => widget.onChanged(kf.copyWith(randomDetail: v.round())),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kfText,
              side: const BorderSide(color: _kfDim),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              tapFeedback();
              widget.onChanged(kf.copyWith(randomSeed: math.Random().nextInt(9999) + 1));
            },
            icon: const Icon(Icons.casino_outlined, size: 16),
            label: const Text('Shuffle', style: TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

class _BezierControls extends StatelessWidget {
  const _BezierControls({required this.keyframe, required this.onReset});
  final Keyframe keyframe;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final Keyframe k = keyframe;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _KfChip('P1 ${k.cp1x.toStringAsFixed(2)}, ${k.cp1y.toStringAsFixed(2)}'),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: _kfMuted,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () {
            tapFeedback();
            onReset();
          },
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('Reset', style: TextStyle(fontSize: 12)),
        ),
        _KfChip('P2 ${k.cp2x.toStringAsFixed(2)}, ${k.cp2y.toStringAsFixed(2)}'),
      ],
    );
  }
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: _kfMuted, fontSize: 12)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _kfText,
              inactiveTrackColor: _kfLine,
              thumbColor: _kfText,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _kfText,
              fontSize: 11,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.keyframe});
  final Keyframe keyframe;

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const double dash = 4, gap = 4;
    final double dist = (b - a).distance;
    if (dist == 0) return;
    final Offset dir = (b - a) / dist;
    double d = 0;
    while (d < dist) {
      final double e = math.min(d + dash, dist);
      c.drawLine(a + dir * d, a + dir * e, p);
      d += dash + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Keyframe k = keyframe;
    final bool isBezier = k.curveType == CurveType.cubicBezier;

    // grid
    final Paint grid = Paint()
      ..color = _kfLine
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 4; i++) {
      final double x = _gx(size, i / 4);
      canvas.drawLine(Offset(x, _gy(size, 1.5)), Offset(x, _gy(size, -0.5)), grid);
    }
    // start (0) and end (1) value lines
    final Paint ref = Paint()
      ..color = _kfDim
      ..strokeWidth = 1;
    for (final double v in <double>[0, 1]) {
      _dashed(canvas, Offset(_gx(size, 0), _gy(size, v)), Offset(_gx(size, 1), _gy(size, v)), ref);
    }

    final Offset start = _gp(size, 0, 0);
    final Offset end = _gp(size, 1, 1);
    final Offset p1 = _gp(size, k.cp1x, k.cp1y);
    final Offset p2 = _gp(size, k.cp2x, k.cp2y);

    if (isBezier) {
      final Paint handleLine = Paint()
        ..color = Colors.white38
        ..strokeWidth = 1.2;
      canvas.drawLine(start, p1, handleLine);
      canvas.drawLine(end, p2, handleLine);
    }

    // curve
    final Path path = Path();
    const int steps = 160;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final Offset pt = _gp(size, t, k.ease(t));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // bezier handles
    if (isBezier) {
      for (final Offset pt in <Offset>[p1, p2]) {
        canvas.drawCircle(pt, 10, Paint()..color = _kfBg);
        canvas.drawCircle(pt, 7, Paint()..color = _kfBlue);
        canvas.drawCircle(pt, 3, Paint()..color = Colors.white);
      }
    }

    // end points
    for (final Offset o in <Offset>[start, end]) {
      canvas.drawCircle(o, 6, Paint()..color = _kfBg);
      canvas.drawCircle(o, 4.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) {
    final Keyframe a = old.keyframe;
    final Keyframe b = keyframe;
    return a.curveType != b.curveType ||
        a.cp1x != b.cp1x ||
        a.cp1y != b.cp1y ||
        a.cp2x != b.cp2x ||
        a.cp2y != b.cp2y ||
        a.bounceCount != b.bounceCount ||
        a.bounciness != b.bounciness ||
        a.randomAmount != b.randomAmount ||
        a.randomDetail != b.randomDetail ||
        a.randomSeed != b.randomSeed;
  }
}