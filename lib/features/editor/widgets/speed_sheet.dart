// lib/features/editor/widgets/speed_sheet.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/speed_settings.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _sheet = Color(0xFF121214);
const Color _card = Color(0xFF232327);
const Color _track = Color(0xFF3A3A40);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8E8E96);
const Color _accent = Color(0xFF2DE2E6);

const Map<String, List<SpeedPoint>> _curvePresets = <String, List<SpeedPoint>>{
  'Custom': <SpeedPoint>[SpeedPoint(0, 1), SpeedPoint(1, 1)],
  'Montage': <SpeedPoint>[
    SpeedPoint(0, 1), SpeedPoint(.25, .3), SpeedPoint(.5, 3),
    SpeedPoint(.75, .3), SpeedPoint(1, 1),
  ],
  'Hero': <SpeedPoint>[
    SpeedPoint(0, 1.5), SpeedPoint(.3, .4), SpeedPoint(.7, .4), SpeedPoint(1, 1.5),
  ],
  'Bullet': <SpeedPoint>[
    SpeedPoint(0, 3), SpeedPoint(.4, .2), SpeedPoint(.6, .2), SpeedPoint(1, 3),
  ],
  'Jumper': <SpeedPoint>[
    SpeedPoint(0, .5), SpeedPoint(.35, 4), SpeedPoint(.65, 4), SpeedPoint(1, .5),
  ],
  'Flash in': <SpeedPoint>[SpeedPoint(0, .3), SpeedPoint(1, 3)],
  'Flash out': <SpeedPoint>[SpeedPoint(0, 3), SpeedPoint(1, .3)],
};

double _toT(double speed) => ((math.log(speed) / math.ln10) + 1) / 2;
double _fromT(double t) => math.pow(10, t * 2 - 1).toDouble();

String _fmtTime(double sec) {
  final int m = sec ~/ 60;
  final double s = sec - m * 60;
  return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
}

String _fmtSpeed(double v) {
  String s = v.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return '${s}x';
}

/// Bottom sheet for constant speed and speed curves.
///
/// Nothing is applied to the clip until the user taps the check mark, so
/// closing the sheet never leaves a half-edited clip or extra undo steps.
///
/// * [initial]: current settings of the clip (so reopening restores a curve).
///   Falls back to the clip's constant speed.
/// * [onApply]: persist the settings in your project model and drive the
///   player / exporter (see [SpeedRamp] and [SpeedFilters]). When omitted, the
///   equivalent average speed is written through
///   `EditorController.updateAudioProperties`.
///
/// Returns the applied settings, or null if cancelled.
class SpeedSheet extends StatefulWidget {
  const SpeedSheet({super.key, this.initial, this.onApply, this.onClose});

  final SpeedSettings? initial;
  final ValueChanged<SpeedSettings>? onApply;

  /// Set this when the sheet is embedded in a panel instead of shown with
  /// [show]. It's called after apply or discard instead of popping the route,
  /// and the footer stays pinned while the content scrolls.
  final VoidCallback? onClose;

  static Future<SpeedSettings?> show(
    BuildContext context, {
    SpeedSettings? initial,
    ValueChanged<SpeedSettings>? onApply,
  }) {
    return showModalBottomSheet<SpeedSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _sheet,
      barrierColor: Colors.black38,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SpeedSheet(initial: initial, onApply: onApply),
    );
  }

  @override
  State<SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<SpeedSheet> {
  static const List<double> _presets = <double>[0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0];

  late final SpeedSettings _initial;
  late final double _srcSeconds; // captured once so it can't drift
  late SpeedSettings _s;
  int? _selected;
  int? _dragging;

  @override
  void initState() {
    super.initState();
    final clip = context.read<EditorController>().selectedClip;
    _srcSeconds =
        clip == null ? 0 : clip.duration.inMilliseconds / 1000.0 * clip.speed;
    _initial = (widget.initial ??
            SpeedSettings(
              speed: ((clip?.speed ?? 1.0) as num)
                  .clamp(kMinSpeed, kMaxSpeed)
                  .toDouble(),
            ))
        .normalized();
    _s = _initial;
  }

  bool get _dirty => _s.normalized() != _initial;
  bool get _curve => _s.mode == SpeedMode.curve;

  // ---- state helpers --------------------------------------------------------

  void _update(SpeedSettings Function(SpeedSettings) f) => setState(() => _s = f(_s));

  void _setSpeed(double v) => _update((s) => s.copyWith(
      speed: double.parse(v.clamp(kMinSpeed, kMaxSpeed).toStringAsFixed(2))));

  void _loadPreset(String name) {
    HapticFeedback.selectionClick();
    _selected = null;
    _update((s) => s.copyWith(points: List<SpeedPoint>.of(_curvePresets[name]!), preset: name));
  }

  void _setPoints(List<SpeedPoint> p) =>
      _update((s) => s.copyWith(points: p, preset: 'Custom'));

  void _addPoint() {
    final List<SpeedPoint> pts = _s.points;
    if (pts.length >= kMaxCurvePoints) {
      HapticFeedback.heavyImpact();
      return;
    }
    int gi = 0;
    double gw = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final double w = pts[i + 1].x - pts[i].x;
      if (w > gw) {
        gw = w;
        gi = i;
      }
    }
    final double x = pts[gi].x + gw / 2;
    HapticFeedback.selectionClick();
    _selected = gi + 1;
    _setPoints(List<SpeedPoint>.of(pts)
      ..insert(gi + 1, SpeedPoint(x, SpeedSettings.interpolate(pts, x))));
  }

  bool get _canDelete {
    final int? i = _selected;
    return i != null && i > 0 && i < _s.points.length - 1;
  }

  void _deleteSelected() {
    if (!_canDelete) return;
    HapticFeedback.mediumImpact();
    final List<SpeedPoint> p = List<SpeedPoint>.of(_s.points)..removeAt(_selected!);
    _selected = null;
    _setPoints(p);
  }

  void _reset() {
    HapticFeedback.selectionClick();
    _selected = null;
    _update((s) => SpeedSettings.identity.copyWith(mode: s.mode));
  }

  // ---- close / apply --------------------------------------------------------

  void _dismiss([SpeedSettings? result]) {
    final VoidCallback? close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      _dismiss();
      return;
    }
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Discard changes?',
            style: TextStyle(color: _text, fontSize: 17)),
        content: const Text('Your speed changes haven\'t been applied.',
            style: TextStyle(color: _muted, fontSize: 14)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing', style: TextStyle(color: _accent))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard', style: TextStyle(color: _muted))),
        ],
      ),
    );
    if (discard == true && mounted) _dismiss();
  }

  void _confirm(EditorController c) {
    if (!_dirty) {
      _dismiss();
      return;
    }
    final SpeedSettings result = _s.normalized();
    if (widget.onApply != null) {
      widget.onApply!(result);
    } else {
      // Legacy path: only the equivalent constant speed reaches the clip.
      c.updateAudioProperties(
        c.selectedClip?.audioProperties.copyWith(
                speed: double.parse(result.averageSpeed.toStringAsFixed(3))) ??
            const AudioProperties(),
      );
    }
    HapticFeedback.lightImpact();
    _dismiss(result);
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final EditorController c = context.read<EditorController>();
    final double out = _srcSeconds * _s.durationFactor;

    final List<Widget> content = <Widget>[
      const SizedBox(height: 14),
      _tabs(),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _curve ? _curveView() : _normalView(),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _durationRow(out),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: <Widget>[
          _check('Maintain pitch', _s.maintainPitch,
              (v) => _update((s) => s.copyWith(maintainPitch: v))),
          _check('Smooth slow motion', _s.smoothSlowMotion,
              (v) => _update((s) => s.copyWith(smoothSlowMotion: v))),
          _check('Reverse', _s.reverse,
              (v) => _update((s) => s.copyWith(reverse: v))),
        ]),
      ),
      const SizedBox(height: 6),
    ];

    // Embedded in a panel: content scrolls, footer stays pinned.
    if (widget.onClose != null) {
      return Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
          _footer(c),
        ],
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...content, _footer(c)],
        ),
      ),
    );
  }

  Widget _footer(EditorController c) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF222226))),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Close',
            iconSize: 24,
            icon: const Icon(Icons.close_rounded, color: _text),
            onPressed: _close,
          ),
          const Spacer(),
          const Text('Speed',
              style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          TextButton(
            onPressed: _s.isIdentity ? null : _reset,
            style: TextButton.styleFrom(
                minimumSize: const Size(48, 40), foregroundColor: _muted),
            child: const Text('Reset', style: TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Apply',
            iconSize: 26,
            icon: Icon(Icons.check_rounded, color: _dirty ? _accent : _text),
            onPressed: () => _confirm(c),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool on, SpeedMode m) => Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _update((s) => s.copyWith(mode: m)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(
                          color: on ? _text : _muted,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 2.5,
                    width: 22,
                    decoration: BoxDecoration(
                      color: on ? _accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        tab('Normal', !_curve, SpeedMode.normal),
        tab('Curve', _curve, SpeedMode.curve),
      ],
    );
  }

  // ---- Normal tab -----------------------------------------------------------

  Widget _normalView() {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              tooltip: 'Slower',
              icon: const Icon(Icons.remove_rounded, color: _text),
              onPressed: _s.speed <= kMinSpeed ? null : () => _setSpeed(_s.speed - 0.1),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 84),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration:
                  BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8)),
              child: Text(_fmtSpeed(_s.speed),
                  style: const TextStyle(
                      color: _accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
            ),
            IconButton(
              tooltip: 'Faster',
              icon: const Icon(Icons.add_rounded, color: _text),
              onPressed: _s.speed >= kMaxSpeed ? null : () => _setSpeed(_s.speed + 0.1),
            ),
          ],
        ),
        _Ruler(speed: _s.speed, onChanged: _setSpeed),
        const SizedBox(height: 14),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final p in _presets)
                _chip(_fmtSpeed(p), (p - _s.speed).abs() < 0.01, () {
                  HapticFeedback.selectionClick();
                  _setSpeed(p);
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            onTap: f,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? _accent.withAlpha(30) : _card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: on ? _accent : Colors.transparent, width: 1.2),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: on ? _accent : _text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      );

  // ---- Curve tab ------------------------------------------------------------

  Widget _curveView() {
    final List<SpeedPoint> pts = _s.points;
    final int? sel = _selected != null && _selected! < pts.length ? _selected : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final e in _curvePresets.entries) _presetTile(e.key, e.value),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          final Size size = Size(box.maxWidth, 170);
          Offset toPx(SpeedPoint p) =>
              Offset(p.x * size.width, size.height * (1 - _toT(p.speed)));
          int? nearest(Offset o) {
            int? best;
            double bd = 28;
            for (int i = 0; i < _s.points.length; i++) {
              final double d = (toPx(_s.points[i]) - o).distance;
              if (d < bd) {
                bd = d;
                best = i;
              }
            }
            return best;
          }

          return GestureDetector(
            onPanStart: (d) {
              _dragging = nearest(d.localPosition);
              if (_dragging != null) setState(() => _selected = _dragging);
            },
            onPanUpdate: (d) {
              final int? i = _dragging;
              if (i == null || i >= _s.points.length) return;
              final List<SpeedPoint> p = List<SpeedPoint>.of(_s.points);
              final Offset o = d.localPosition;
              double sp = _fromT((1 - o.dy / size.height).clamp(0.0, 1.0).toDouble());
              if ((sp - 1).abs() < 0.06) sp = 1.0;
              double x = p[i].x;
              if (i != 0 && i != p.length - 1) {
                x = (o.dx / size.width)
                    .clamp(p[i - 1].x + 0.02, p[i + 1].x - 0.02)
                    .toDouble();
              }
              p[i] = SpeedPoint(x, sp.clamp(kMinSpeed, kMaxSpeed).toDouble());
              _setPoints(p);
            },
            onPanEnd: (_) => _dragging = null,
            onPanCancel: () => _dragging = null,
            onTapUp: (d) {
              final int? i = nearest(d.localPosition);
              if (i != null) {
                setState(() => _selected = i);
                return;
              }
              if (_s.points.length >= kMaxCurvePoints) {
                HapticFeedback.heavyImpact();
                return;
              }
              final double x =
                  (d.localPosition.dx / size.width).clamp(0.03, 0.97).toDouble();
              HapticFeedback.selectionClick();
              final List<SpeedPoint> p = List<SpeedPoint>.of(_s.points)
                ..add(SpeedPoint(x, SpeedSettings.interpolate(_s.points, x)))
                ..sort((a, b) => a.x.compareTo(b.x));
              _selected = p.indexWhere((q) => q.x == x);
              _setPoints(p);
            },
            onLongPressStart: (d) {
              final int? i = nearest(d.localPosition);
              if (i != null) {
                _selected = i;
                _deleteSelected();
              }
            },
            child: Semantics(
              label: 'Speed curve editor with ${pts.length} points',
              child: Container(
                height: size.height,
                decoration:
                    BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CustomPaint(
                    size: size,
                    painter: _CurvePainter(pts: pts, selected: sel),
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _pill(Icons.add_rounded, 'Add point', pts.length < kMaxCurvePoints, _addPoint),
            const SizedBox(width: 10),
            _pill(Icons.remove_rounded, 'Delete', _canDelete, _deleteSelected),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            sel != null
                ? 'Point ${sel + 1}  ·  ${_fmtSpeed(pts[sel].speed)}'
                : 'Tap the graph to add a point',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _presetTile(String name, List<SpeedPoint> data) {
    final bool on = _s.preset == name;
    return Semantics(
      button: true,
      selected: on,
      label: '$name curve',
      child: GestureDetector(
        onTap: () => _loadPreset(name),
        child: Container(
          width: 64,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? _accent : Colors.transparent, width: 1.5),
          ),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _MiniCurvePainter(data, on ? _accent : _muted),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: on ? _accent : _text,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, bool enabled, VoidCallback f) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? f : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration:
                BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(icon, size: 16, color: _text),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: _text, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- Shared bits ----------------------------------------------------------

  Widget _durationRow(double out) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.timer_outlined, size: 15, color: _muted),
        const SizedBox(width: 6),
        Text(
          '${_fmtTime(_srcSeconds)}  →  ${_fmtTime(out)}'
          '${_curve ? '  ·  avg ${_fmtSpeed(_s.averageSpeed)}' : ''}',
          style: const TextStyle(
              color: _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
        ),
      ],
    );
  }

  Widget _check(String title, bool value, ValueChanged<bool> f) {
    return Semantics(
      checked: value,
      label: title,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          f(!value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? _accent : Colors.transparent,
                  border: Border.all(color: value ? _accent : _track, width: 1.6),
                ),
                child: value
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      color: _text, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Scrolling ruler ----------------------------------------------------------

class _Ruler extends StatefulWidget {
  const _Ruler({required this.speed, required this.onChanged});
  final double speed;
  final ValueChanged<double> onChanged;

  @override
  State<_Ruler> createState() => _RulerState();
}

class _RulerState extends State<_Ruler> {
  double? _raw; // unsnapped position so the 1x magnet never traps the drag
  bool _snapped = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final double w = box.maxWidth;
      return Semantics(
        slider: true,
        label: 'Speed',
        value: _fmtSpeed(widget.speed),
        increasedValue: _fmtSpeed(widget.speed + 0.1),
        decreasedValue: _fmtSpeed(widget.speed - 0.1),
        onIncrease: () => widget.onChanged(widget.speed + 0.1),
        onDecrease: () => widget.onChanged(widget.speed - 0.1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _raw = _toT(widget.speed),
          onHorizontalDragUpdate: (d) {
            final double t = ((_raw ?? _toT(widget.speed)) - d.delta.dx / w * 0.5)
                .clamp(0.0, 1.0)
                .toDouble();
            _raw = t;
            double v = _fromT(t);
            final bool near = (v - 1).abs() < 0.04;
            if (near) {
              v = 1.0;
              if (!_snapped) HapticFeedback.selectionClick();
            }
            _snapped = near;
            widget.onChanged(v);
          },
          onHorizontalDragEnd: (_) => _raw = null,
          onHorizontalDragCancel: () => _raw = null,
          child: SizedBox(
            height: 56,
            width: w,
            child: CustomPaint(painter: _RulerPainter(_toT(widget.speed))),
          ),
        ),
      );
    });
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.t);
  final double t;
  static const double _span = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    double px(double tt) => cx + (tt - t) / _span * size.width;
    final Paint minor = Paint()
      ..color = _track
      ..strokeWidth = 1.2;
    final Paint major = Paint()
      ..color = _muted
      ..strokeWidth = 1.6;

    for (int k = 0; k <= 40; k++) {
      final double x = px(k / 40);
      if (x < -4 || x > size.width + 4) continue;
      canvas.drawLine(Offset(x, 14), Offset(x, 26), minor);
    }
    for (final double v in <double>[0.1, 0.2, 0.5, 1, 2, 5, 10]) {
      final double x = px(_toT(v));
      if (x < -20 || x > size.width + 20) continue;
      canvas.drawLine(Offset(x, 10), Offset(x, 32), major);
      final tp = TextPainter(
        text: TextSpan(text: '${v}x', style: const TextStyle(color: _muted, fontSize: 10.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 36));
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, 22), width: 3, height: 30),
          const Radius.circular(2)),
      Paint()..color = _accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.t != t;
}

// ---- Curve painters -----------------------------------------------------------

class _MiniCurvePainter extends CustomPainter {
  _MiniCurvePainter(this.pts, this.color);
  final List<SpeedPoint> pts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path();
    for (int i = 0; i <= 40; i++) {
      final double x = i / 40;
      final Offset o = Offset(
          x * size.width, size.height * (1 - _toT(SpeedSettings.interpolate(pts, x))));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniCurvePainter old) =>
      old.color != color || old.pts != pts;
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.pts, required this.selected});
  final List<SpeedPoint> pts;
  final int? selected;

  Offset _px(SpeedPoint p, Size s) =>
      Offset(p.x * s.width, s.height * (1 - _toT(p.speed)));

  @override
  void paint(Canvas canvas, Size size) {
    for (final double v in <double>[0.1, 0.3, 1, 3, 10]) {
      final double y = size.height * (1 - _toT(v));
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = v == 1 ? Colors.white30 : _track.withAlpha(120)
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(text: '${v}x', style: const TextStyle(color: _muted, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(6, y - tp.height - 1));
    }

    final Path line = Path();
    final Path fill = Path();
    const int n = 120;
    for (int i = 0; i <= n; i++) {
      final double x = i / n;
      final Offset o = Offset(
          x * size.width, size.height * (1 - _toT(SpeedSettings.interpolate(pts, x))));
      if (i == 0) {
        line.moveTo(o.dx, o.dy);
        fill
          ..moveTo(o.dx, size.height)
          ..lineTo(o.dx, o.dy);
      } else {
        line.lineTo(o.dx, o.dy);
        fill.lineTo(o.dx, o.dy);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = _accent.withAlpha(28));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = _accent);

    for (int i = 0; i < pts.length; i++) {
      final Offset o = _px(pts[i], size);
      final bool sel = i == selected;
      canvas.drawCircle(o, sel ? 8 : 6, Paint()..color = sel ? _accent : _sheet);
      canvas.drawCircle(
          o,
          sel ? 8 : 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _accent);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.pts != pts || old.selected != selected;
}