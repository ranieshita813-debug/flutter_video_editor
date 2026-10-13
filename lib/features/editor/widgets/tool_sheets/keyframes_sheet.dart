import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

const Color _danger = Color(0xFFFF4D4F);
const Color _canvasDark = Color(0xFF141414);

Widget _Card({required Widget child, EdgeInsetsGeometry? padding}) {
  return Container(
    padding: padding ?? const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF1F1F24),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}


Widget _ChipRow({
  required List<String> options,
  required String selected,
  required ValueChanged<String> onSelected,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: options.map((opt) {
        final bool isSelected = opt == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(opt),
            selected: isSelected,
            onSelected: (_) => onSelected(opt),
            selectedColor: accentToken,
            backgroundColor: const Color(0xFF26262B),
            labelStyle: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    ),
  );
}

Widget _outlineBtn(String text, VoidCallback? onTap) {
  return OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: _danger,
      side: BorderSide(color: onTap != null ? _danger : Colors.white24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(text),
  );
}

EdgeInsets _listPad(BuildContext context) {
  return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
}

String _cap(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

// ============================================================================
// KEYFRAMES (Premiere Pro style)
// ----------------------------------------------------------------------------
// Drop-in replacement: delete the old "Keyframes" section (_Diamond and
// KeyframeSheet) from your sheets file and paste this block in its place.
// It must stay in the same file because it uses the private helpers
// (_Card, _SectionLabel, _EmptyHint, _cap, _listPad, _outlineBtn, ...).
//
// Features
//  - Prev / next keyframe navigator and a diamond toggle at the playhead
//  - Timeline with one lane per property, ruler, playhead, frame snapping
//  - Tap to select, tap again to deselect, drag a diamond to retime it
//  - Property filter chips, select all, copy, paste at playhead, delete
//  - Interpolation presets with curve thumbnails (applies to the selection)
//  - Value graph and speed graph preview for the selected curve
//  - Timecode readouts (mm:ss:ff) with tabular figures
//
// Assumptions about your models (isolated, easy to adjust):
//  - Keyframe has: id, time (Duration), property, curveType, copyWith(...)
//    including copyWith(time:) and copyWith(id:)   -> used by drag and paste
//  - Keyframe may have a `value`; it is read dynamically in _valueText()
//  - editor.addKeyframe(kf) replaces a keyframe that has the same id
// ============================================================================

const double _kfFps = 30;

String _propName(Keyframe k) => _cap('${k.property}'.split('.').last);

String _timecode(double s) {
  final int totalFrames = (s * _kfFps).round();
  final int f = totalFrames % _kfFps.toInt();
  final int sec = (totalFrames ~/ _kfFps) % 60;
  final int m = totalFrames ~/ (_kfFps * 60).toInt();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(m)}:${two(sec)}:${two(f)}';
}

String _valueText(Keyframe k) {
  try {
    final dynamic v = (k as dynamic).value;
    if (v == null) return '—';
    if (v is num) return v.toStringAsFixed(2);
    return '$v';
  } catch (_) {
    return '—';
  }
}

/// Easing shape used for the thumbnails and graphs, derived from the curve name.
double _ease(CurveType c, double t) {
  final String n = c.name.toLowerCase();
  if (n.contains('hold') || n.contains('step')) return t < 1 ? 0 : 1;
  if (n.contains('inout') || n.contains('smooth') || n.contains('bezier') || n.contains('auto')) {
    return t * t * (3 - 2 * t);
  }
  if (n.contains('in')) return t * t * t;
  if (n.contains('out')) return 1 - math.pow(1 - t, 3).toDouble();
  if (n.contains('bounce')) return Curves.bounceOut.transform(t);
  if (n.contains('elastic')) return Curves.elasticOut.transform(t);
  return t;
}

class KeyframeSectionLabel extends StatelessWidget {
  const KeyframeSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class KeyframeEmptyHint extends StatelessWidget {
  const KeyframeEmptyHint({super.key, this.icon, required this.text});
  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white38, size: 28),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class KeyframeSheet extends StatefulWidget {
  const KeyframeSheet({super.key});

  @override
  State<KeyframeSheet> createState() => _KeyframeSheetState();
}

class _KeyframeSheetState extends State<KeyframeSheet> {
  final Set<dynamic> _sel = <dynamic>{};
  List<Keyframe> _clipboard = const <Keyframe>[];
  String? _filter;
  Keyframe? _drag;

  static const double _rulerH = 22;
  static const double _laneH = 30;

  void _toast(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  int _hit(List<Keyframe> list, List<String> lanes, Offset p, double w, double total) {
    final int lane = ((p.dy - _rulerH) / _laneH).floor();
    if (lane < 0 || lane >= lanes.length) return -1;
    for (int i = 0; i < list.length; i++) {
      if (_propName(list[i]) != lanes[lane]) continue;
      final double x = secondsOf(list[i].time) / total * w;
      if ((x - p.dx).abs() <= 12) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final playhead = context.select<EditorController, Duration>((e) => e.playhead);

    final List<Keyframe> all = <Keyframe>[...?clip?.keyframes]..sort((a, b) => a.time.compareTo(b.time));
    final List<String> props = <String>[];
    for (final k in all) {
      final n = _propName(k);
      if (!props.contains(n)) props.add(n);
    }
    if (_filter != null && !props.contains(_filter)) _filter = null;
    final List<Keyframe> visible = _filter == null ? all : all.where((k) => _propName(k) == _filter).toList();
    final List<String> lanes = _filter == null ? props : <String>[_filter!];

    final double total = clip == null ? 1.0 : math.max(secondsOf(clip.duration), 0.1);
    final double rel = clip == null ? 0.0 : secondsOf(playhead - clip.start);
    final bool inClip = clip != null && rel >= 0 && rel <= total;
    final List<Keyframe> selected = all.where((k) => _sel.contains(k.id)).toList();
    final List<Keyframe> atHead = all.where((k) => (secondsOf(k.time) - rel).abs() < 0.5 / _kfFps).toList();

    void seekTo(double relSeconds) {
      if (clip == null) return;
      seekPlayhead(editor, secondsOf(clip.start) + relSeconds);
    }

    void prev() {
      final c = all.where((k) => secondsOf(k.time) < rel - 0.5 / _kfFps);
      if (c.isNotEmpty) seekTo(secondsOf(c.last.time));
    }

    void next() {
      final c = all.where((k) => secondsOf(k.time) > rel + 0.5 / _kfFps);
      if (c.isNotEmpty) seekTo(secondsOf(c.first.time));
    }

    void toggleAtHead() {
      if (atHead.isNotEmpty) {
        for (final k in atHead) {
          editor.removeKeyframe(k.id);
          _sel.remove(k.id);
        }
        setState(() {});
      } else if (!inClip) {
        _toast('Move the playhead inside the clip first.');
      } else {
        editor.addKeyframeAtPlayhead();
      }
    }

    void paste() {
      if (_clipboard.isEmpty) return;
      if (!inClip) {
        _toast('Move the playhead inside the clip first.');
        return;
      }
      final double base = _clipboard.map((k) => secondsOf(k.time)).reduce(math.min);
      int n = 0;
      for (final k in _clipboard) {
        final double t = (rel + secondsOf(k.time) - base).clamp(0.0, total).toDouble();
        editor.addKeyframe(k.copyWith(
          id: '${DateTime.now().microsecondsSinceEpoch}_${n++}',
          time: Duration(milliseconds: (t * 1000).round()),
        ));
      }
    }

    return ListView(
      padding: _listPad(context),
      children: <Widget>[
        // ---- Navigator + edit toolbar -------------------------------------
        _Card(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: <Widget>[
              _KfAction(icon: Icons.skip_previous_rounded, tooltip: 'Previous keyframe', onTap: clip == null ? null : prev),
              _KfAction(
                icon: atHead.isNotEmpty ? Icons.diamond_rounded : Icons.diamond_outlined,
                tooltip: atHead.isNotEmpty ? 'Remove keyframe at playhead' : 'Add keyframe at playhead',
                active: atHead.isNotEmpty,
                onTap: clip == null ? null : toggleAtHead,
              ),
              _KfAction(icon: Icons.skip_next_rounded, tooltip: 'Next keyframe', onTap: clip == null ? null : next),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _timecode(rel < 0 ? 0 : rel),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: accentToken,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _KfAction(
                icon: Icons.select_all_rounded,
                tooltip: 'Select all',
                onTap: all.isEmpty ? null : () => setState(() => _sel..clear()..addAll(visible.map((k) => k.id))),
              ),
              _KfAction(
                icon: Icons.copy_rounded,
                tooltip: 'Copy',
                onTap: selected.isEmpty
                    ? null
                    : () {
                        _clipboard = List<Keyframe>.of(selected);
                        _toast('${selected.length} keyframe(s) copied');
                        setState(() {});
                      },
              ),
              _KfAction(
                icon: Icons.content_paste_rounded,
                tooltip: 'Paste at playhead',
                onTap: _clipboard.isEmpty || clip == null ? null : paste,
              ),
              _KfAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete selected',
                danger: true,
                onTap: selected.isEmpty
                    ? null
                    : () {
                        for (final k in selected) {
                          editor.removeKeyframe(k.id);
                        }
                        setState(_sel.clear);
                      },
              ),
            ],
          ),
        ),

        // ---- Property filter ---------------------------------------------
        if (props.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _ChipRow(
            options: <String>['All', ...props],
            selected: _filter ?? 'All',
            onSelected: (v) => setState(() => _filter = v == 'All' ? null : v),
          ),
        ],

        // ---- Timeline -----------------------------------------------------
        const KeyframeSectionLabel('Timeline'),
        if (clip == null)
          const KeyframeEmptyHint(icon: Icons.diamond_outlined, text: 'Select a clip to animate it.')
        else if (all.isEmpty)
          const KeyframeEmptyHint(
            icon: Icons.diamond_outlined,
            text: 'No keyframes yet. Move the playhead and tap the diamond.',
          )
        else
          _Card(
            padding: EdgeInsets.zero,
            child: LayoutBuilder(builder: (context, c) {
              final double w = c.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final int i = _hit(visible, lanes, d.localPosition, w, total);
                  if (i >= 0) {
                    tapFeedback();
                    setState(() => _sel.contains(visible[i].id) ? _sel.remove(visible[i].id) : _sel.add(visible[i].id));
                  } else {
                    seekTo((d.localPosition.dx / w * total).clamp(0.0, total).toDouble());
                  }
                },
                onPanStart: (d) {
                  final int i = _hit(visible, lanes, d.localPosition, w, total);
                  if (i >= 0) {
                    _drag = visible[i];
                    setState(() => _sel.add(_drag!.id));
                  }
                },
                onPanUpdate: (d) {
                  final k = _drag;
                  if (k == null) return;
                  double t = (d.localPosition.dx / w * total).clamp(0.0, total).toDouble();
                  t = (t * _kfFps).round() / _kfFps; // snap to frames
                  editor.addKeyframe(k.copyWith(time: Duration(milliseconds: (t * 1000).round())));
                },
                onPanEnd: (_) => _drag = null,
                onPanCancel: () => _drag = null,
                child: CustomPaint(
                  size: Size(w, _rulerH + _laneH * lanes.length),
                  painter: _KfTimelinePainter(
                    keys: visible,
                    lanes: lanes,
                    selected: _sel,
                    total: total,
                    playhead: rel,
                    rulerH: _rulerH,
                    laneH: _laneH,
                  ),
                ),
              );
            }),
          ),

        // ---- Inspector: interpolation + graph -----------------------------
        const KeyframeSectionLabel('Interpolation'),
        if (selected.isEmpty)
          const KeyframeEmptyHint(text: 'Select one or more keyframes to edit their curve.')
        else ...<Widget>[
          _Card(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 112,
                  height: 112,
                  child: CustomPaint(painter: _CurveGraphPainter(selected.first.curveType, speed: true)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        selected.length == 1 ? _propName(selected.first) : '${selected.length} keyframes',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _kv('Time', selected.length == 1 ? _timecode(secondsOf(selected.first.time)) : 'Mixed'),
                      _kv('Value', selected.length == 1 ? _valueText(selected.first) : 'Mixed'),
                      _kv('Curve', _cap(selected.first.curveType.name)),
                      const SizedBox(height: 6),
                      Row(children: const <Widget>[
                        _Legend(color: accentToken, text: 'Value'),
                        SizedBox(width: 10),
                        _Legend(color: Colors.white38, text: 'Speed'),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: CurveType.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final curve = CurveType.values[i];
                final bool on = selected.every((k) => k.curveType == curve);
                return SizedBox(
                  width: 72,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      tapFeedback();
                      for (final k in selected) {
                        editor.addKeyframe(k.copyWith(curveType: curve));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: on ? accentToken.withValues(alpha: 0.18) : cardToken,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: on ? accentToken : Colors.transparent),
                      ),
                      child: Column(
                        children: <Widget>[
                          Expanded(child: CustomPaint(size: Size.infinite, painter: _CurveGraphPainter(curve, mini: true, active: on))),
                          const SizedBox(height: 4),
                          Text(
                            _cap(curve.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: on ? accentToken : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // ---- Keyframe list ------------------------------------------------
        if (visible.isNotEmpty) ...<Widget>[
          KeyframeSectionLabel('Keyframes (${visible.length})'),
          for (final kf in visible)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: cardToken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _sel.contains(kf.id) ? accentToken : Colors.transparent),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        tapFeedback();
                        seekTo(secondsOf(kf.time));
                        setState(() => _sel
                          ..clear()
                          ..add(kf.id));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: <Widget>[
                            Transform.rotate(
                              angle: math.pi / 4,
                              child: Container(width: 8, height: 8, color: _sel.contains(kf.id) ? accentToken : Colors.white70),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_propName(kf),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                            Text(_valueText(kf),
                                style: const TextStyle(
                                  color: accentToken,
                                  fontSize: 12,
                                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                                )),
                            const SizedBox(width: 12),
                            Text(_timecode(secondsOf(kf.time)),
                                style: const TextStyle(
                                  color: mutedToken,
                                  fontSize: 12,
                                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove keyframe',
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: _danger, size: 18),
                    onPressed: () {
                      editor.removeKeyframe(kf.id);
                      setState(() => _sel.remove(kf.id));
                    },
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        _outlineBtn(
          'Clear all keyframes',
          all.isEmpty
              ? null
              : () {
                  for (final k in all) {
                    editor.removeKeyframe(k.id);
                  }
                  setState(_sel.clear);
                },
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: <Widget>[
            SizedBox(width: 44, child: Text(k, style: const TextStyle(color: mutedToken, fontSize: 11))),
            Text(v,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                )),
          ],
        ),
      );
}

class _KfAction extends StatelessWidget {
  const _KfAction({required this.icon, required this.tooltip, this.onTap, this.active = false, this.danger = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color c = onTap == null
        ? Colors.white24
        : active
            ? accentToken
            : danger
                ? _danger
                : Colors.white;
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
        child: SizedBox(width: 38, height: 40, child: Icon(icon, size: 20, color: c)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 10, height: 2, color: color),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: mutedToken, fontSize: 10)),
        ],
      );
}

// ----------------------------------------------------------------------------
// Painters
// ----------------------------------------------------------------------------
class _KfTimelinePainter extends CustomPainter {
  _KfTimelinePainter({
    required this.keys,
    required this.lanes,
    required this.selected,
    required this.total,
    required this.playhead,
    required this.rulerH,
    required this.laneH,
  });

  final List<Keyframe> keys;
  final List<String> lanes;
  final Set<dynamic> selected;
  final double total;
  final double playhead;
  final double rulerH;
  final double laneH;

  void _text(Canvas canvas, String s, Offset o, Color c, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: c, fontSize: size, fontWeight: FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final line = Paint()
      ..color = dividerToken
      ..strokeWidth = 1;

    // Ruler ticks.
    const steps = <double>[0.5, 1, 2, 5, 10, 30, 60];
    double step = steps.last;
    for (final s in steps) {
      if (s / total * w >= 52) {
        step = s;
        break;
      }
    }
    for (double t = 0; t <= total + 0.0001; t += step) {
      final double x = t / total * w;
      canvas.drawLine(Offset(x, rulerH - 6), Offset(x, rulerH), line);
      _text(canvas, '${t.toStringAsFixed(t % 1 == 0 ? 0 : 1)}s', Offset(x + 3, 3), mutedToken, 9);
    }
    canvas.drawLine(Offset(0, rulerH), Offset(w, rulerH), line);

    // Lanes.
    for (int i = 0; i < lanes.length; i++) {
      final double top = rulerH + i * laneH;
      if (i.isOdd) {
        canvas.drawRect(Rect.fromLTWH(0, top, w, laneH), Paint()..color = Colors.white.withValues(alpha: 0.03));
      }
      canvas.drawLine(Offset(0, top + laneH), Offset(w, top + laneH), line);
      _text(canvas, lanes[i], Offset(6, top + 3), mutedToken, 9);
    }

    // Segments between neighbours on the same lane, then diamonds.
    for (int i = 0; i < lanes.length; i++) {
      final double cy = rulerH + i * laneH + laneH / 2 + 3;
      final lane = keys.where((k) => _propName(k) == lanes[i]).toList();
      for (int j = 0; j + 1 < lane.length; j++) {
        final double a = secondsOf(lane[j].time) / total * w;
        final double b = secondsOf(lane[j + 1].time) / total * w;
        canvas.drawLine(
          Offset(a, cy),
          Offset(b, cy),
          Paint()
            ..color = accentToken.withValues(alpha: 0.35)
            ..strokeWidth = 2,
        );
      }
      for (final k in lane) {
        final double x = secondsOf(k.time) / total * w;
        final bool on = selected.contains(k.id);
        final path = Path()
          ..moveTo(x, cy - 7)
          ..lineTo(x + 7, cy)
          ..lineTo(x, cy + 7)
          ..lineTo(x - 7, cy)
          ..close();
        canvas.drawPath(path, Paint()..color = on ? accentToken : Colors.white);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = on ? Colors.white : Colors.black54,
        );
      }
    }

    // Playhead.
    final double px = (playhead / total * w).clamp(0.0, w).toDouble();
    final ph = Paint()
      ..color = _danger
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(px, 0), Offset(px, size.height), ph);
    canvas.drawCircle(Offset(px, 4), 4, ph);
  }

  @override
  bool shouldRepaint(covariant _KfTimelinePainter o) => true;
}

class _CurveGraphPainter extends CustomPainter {
  _CurveGraphPainter(this.curve, {this.mini = false, this.active = false, this.speed = false});
  final CurveType curve;
  final bool mini;
  final bool active;
  final bool speed;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = mini ? Offset.zero & size : Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    if (!mini) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = _canvasDark,
      );
      final grid = Paint()
        ..color = Colors.white10
        ..strokeWidth = 1;
      for (int i = 0; i <= 4; i++) {
        final double x = r.left + r.width * i / 4;
        final double y = r.top + r.height * i / 4;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      }
    }

    Offset at(double t, double v) => Offset(r.left + t * r.width, r.bottom - v.clamp(-0.2, 1.2) * r.height);

    Path build(double Function(double) f) {
      final p = Path()..moveTo(at(0, f(0)).dx, at(0, f(0)).dy);
      for (int i = 1; i <= 48; i++) {
        final double t = i / 48;
        final o = at(t, f(t));
        p.lineTo(o.dx, o.dy);
      }
      return p;
    }

    if (speed) {
      // Numeric derivative, normalised to the graph height.
      final List<double> d = <double>[
        for (int i = 0; i <= 48; i++) ((_ease(curve, math.min(1, (i + 1) / 48)) - _ease(curve, i / 48)) * 48).abs(),
      ];
      final double mx = math.max(d.reduce(math.max), 0.0001);
      final p = Path()..moveTo(r.left, r.bottom - d[0] / mx * r.height);
      for (int i = 1; i <= 48; i++) {
        p.lineTo(r.left + i / 48 * r.width, r.bottom - d[i] / mx * r.height);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white38,
      );
    }

    canvas.drawPath(
      build((t) => _ease(curve, t)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? 1.8 : 2.4
        ..strokeCap = StrokeCap.round
        ..color = (mini && !active) ? Colors.white70 : accentToken,
    );

    if (!mini) {
      for (final o in <Offset>[at(0, 0), at(1, 1)]) {
        canvas.drawCircle(o, 4, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CurveGraphPainter o) =>
      o.curve != curve || o.active != active || o.mini != mini || o.speed != speed;
}