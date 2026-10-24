// lib/features/editor/widgets/speed_sheet.dart
//
// Speed tool: redesigned UI/UX.
//  - Segmented Normal / Curve switch (one tool, two modes).
//  - Result-first hero: big speed value + live "0:12.0 -> 0:06.0" readout.
//  - Normal: one log-scale slider with snap marks, +/- nudge, preset chips.
//  - Curve: preset chips with mini curves, larger graph, keyframe inspector
//    (exact +/- edit and delete) and a slower/faster heat strip.
//  - Options as scrollable toggle chips, labeled Cancel / Apply footer.
//
// Public API, apply/discard behaviour and live clip preview are unchanged:
// nothing is persisted until Apply is tapped; Cancel restores the clip speed.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/speed_settings.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

// ---- Tokens -------------------------------------------------------------------

const Color _sheet = Color(0xFF121214);
const Color _card = Color(0xFF1C1C20);
const Color _cardHi = Color(0xFF2E2E34);
const Color _field = Color(0xFF18181B);
const Color _line = Color(0xFF2C2C31);
const Color _track = Color(0xFF45454C);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8E8E96);
const Color _accent = Color(0xFF2DE2E6);
const Color _onAccent = Color(0xFF04262A);
const Color _slow = Color(0xFF5B9DFF);
const Color _fast = Color(0xFFFF9F43);

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

const List<double> _sliderMarks = <double>[0.25, 0.5, 1, 2, 4, 8];
const List<double> _chipPresets = <double>[0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0];

const TextStyle _tabular = TextStyle(
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

// ---- Helpers ------------------------------------------------------------------

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

String _fmtMark(double v) => v == v.roundToDouble() ? '${v.toInt()}x' : '${v}x';

/// Blue for slower, orange for faster, grey at 1x. Intensity follows |log speed|.
Color _heat(double v) {
  final double k =
      ((math.log(v) / math.ln10).abs() / 0.8).clamp(0.0, 1.0).toDouble();
  final double a = 0.25 + 0.75 * k;
  if (v < 0.995) return Color.fromRGBO(91, 157, 255, a);
  if (v > 1.005) return Color.fromRGBO(255, 159, 67, a);
  return _track;
}

/// Bottom sheet for constant speed and speed curves.
///
/// Nothing is applied to the clip until the user taps Apply, so closing the
/// sheet never leaves a half-edited clip or extra undo steps.
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SpeedSheet(initial: initial, onApply: onApply),
    );
  }

  @override
  State<SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<SpeedSheet> {
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

  // ---- state helpers ----------------------------------------------------------

  void _update(SpeedSettings Function(SpeedSettings) f) =>
      setState(() => _s = f(_s));

  void _setMode(SpeedMode m) {
    if (_s.mode == m) return;
    HapticFeedback.selectionClick();
    _update((s) => s.copyWith(mode: m));
  }

  void _setSpeed(double v) {
    _update((s) => s.copyWith(
        speed: double.parse(v.clamp(kMinSpeed, kMaxSpeed).toStringAsFixed(2))));
    if (mounted) {
      context.read<EditorController>().updateSelectedClipSpeed(v);
    }
  }

  void _loadPreset(String name) {
    HapticFeedback.selectionClick();
    _selected = null;
    _update((s) => s.copyWith(
        points: List<SpeedPoint>.of(_curvePresets[name]!), preset: name));
  }

  void _setPoints(List<SpeedPoint> p) =>
      _update((s) => s.copyWith(points: p, preset: 'Custom'));

  void _nudgeKeyframe(int dir) {
    final int? i = _selected;
    if (i == null || i >= _s.points.length) return;
    HapticFeedback.selectionClick();
    final List<SpeedPoint> p = List<SpeedPoint>.of(_s.points);
    final double v = (p[i].speed + dir * 0.1).clamp(kMinSpeed, kMaxSpeed).toDouble();
    p[i] = SpeedPoint(p[i].x, double.parse(v.toStringAsFixed(2)));
    _setPoints(p);
  }

  bool get _canDelete {
    final int? i = _selected;
    return i != null && i > 0 && i < _s.points.length - 1;
  }

  void _deleteSelected() {
    if (!_canDelete) return;
    HapticFeedback.mediumImpact();
    final List<SpeedPoint> p = List<SpeedPoint>.of(_s.points)
      ..removeAt(_selected!);
    _selected = null;
    _setPoints(p);
  }

  void _reset() {
    HapticFeedback.selectionClick();
    _selected = null;
    _update((s) => SpeedSettings.identity.copyWith(mode: s.mode));
  }

  // ---- close / apply ----------------------------------------------------------

  void _dismiss([SpeedSettings? result]) {
    final VoidCallback? close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).pop(result);
    }
  }

  void _close() {
    if (_dirty && mounted) {
      context.read<EditorController>().updateSelectedClipSpeed(_initial.speed);
    }
    _dismiss();
  }

  void _confirm(EditorController c) {
    if (!_dirty) {
      _dismiss();
      return;
    }
    final SpeedSettings result = _s.normalized();
    c.updateSelectedClipSpeed(result.averageSpeed);
    if (widget.onApply != null) {
      widget.onApply!(result);
    } else {
      c.updateAudioProperties(
        c.selectedClip?.audioProperties.copyWith(
                speed: double.parse(result.averageSpeed.toStringAsFixed(3))) ??
            const AudioProperties(),
      );
    }
    HapticFeedback.lightImpact();
    _dismiss(result);
  }

  // ---- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final EditorController c = context.read<EditorController>();
    final bool embedded = widget.onClose != null;

    final List<Widget> content = <Widget>[
      if (!embedded) _grabber(),
      _header(),
      _modeSwitch(),
      _hero(),
      _curve ? _curveView() : _normalView(),
      _heatStrip(),
      _options(),
      const SizedBox(height: 16),
    ];

    // Embedded in a panel: content scrolls, footer stays pinned.
    if (embedded) {
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
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[...content, _footer(c)],
        ),
      ),
    );
  }

  // ---- Chrome -----------------------------------------------------------------

  Widget _grabber() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: _track, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
      child: Row(
        children: <Widget>[
          const Text('Speed',
              style: TextStyle(
                  color: _text, fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          _roundBtn(Icons.restart_alt_rounded, 'Reset', 36,
              _s.isIdentity ? null : _reset),
        ],
      ),
    );
  }

  Widget _modeSwitch() {
    Widget seg(String label, SpeedMode m) {
      final bool on = _s.mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setMode(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? _cardHi : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: on ? _text : _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(3),
      decoration:
          BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
      child: Row(children: <Widget>[
        seg('Normal', SpeedMode.normal),
        seg('Curve', SpeedMode.curve),
      ]),
    );
  }

  Widget _footer(EditorController c) {
    final bool dirty = _dirty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: _sheet,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _bigBtn('Cancel', primary: false, onTap: _close),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _bigBtn(
              dirty ? 'Apply ${_fmtSpeed(_s.averageSpeed)}' : 'Done',
              primary: dirty,
              onTap: () => _confirm(c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigBtn(String label,
      {required bool primary, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? _accent : _card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                  color: primary ? _onAccent : _text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, String tip, double size, VoidCallback? f) {
    return Semantics(
      button: true,
      label: tip,
      enabled: f != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: f,
        child: Opacity(
          opacity: f == null ? 0.35 : 1,
          child: Container(
            width: size,
            height: size,
            decoration:
                const BoxDecoration(color: _card, shape: BoxShape.circle),
            child: Icon(icon, color: _text, size: size * 0.5),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback f,
      {Widget? leading, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: on,
        label: label,
        child: GestureDetector(
          onTap: f,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? _accent.withAlpha(31) : _card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: on ? _accent.withAlpha(85) : Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: on ? _accent : _text),
                  const SizedBox(width: 6),
                ],
                if (leading != null) ...<Widget>[
                  leading,
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: TextStyle(
                        color: on ? _accent : _text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Hero -------------------------------------------------------------------

  Widget _hero() {
    final double shown = _curve ? _s.averageSpeed : _s.speed;
    final double out = _srcSeconds * _s.durationFactor;
    final double delta = out - _srcSeconds;
    final bool changed = delta.abs() > 0.05;
    final bool hot = (shown - 1).abs() > 0.004;

    final Widget number = Text(
      _fmtSpeed(shown),
      style: _tabular.copyWith(
        color: hot ? _accent : _text,
        fontSize: 44,
        height: 1.1,
        fontWeight: FontWeight.w600,
      ),
    );

    final Widget main = _curve
        ? Column(
            children: <Widget>[
              const Text('AVERAGE',
                  style: TextStyle(
                      color: _muted, fontSize: 11, letterSpacing: 0.8)),
              number,
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _roundBtn(Icons.remove_rounded, 'Slower', 40,
                  _s.speed <= kMinSpeed ? null : () => _setSpeed(_s.speed - 0.1)),
              const SizedBox(width: 18),
              // Drag the value to scrub (log scale), double-tap to return to 1x.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () {
                  HapticFeedback.selectionClick();
                  _setSpeed(1);
                },
                onHorizontalDragUpdate: (d) => _setSpeed(_fromT(
                    (_toT(_s.speed) + d.delta.dx * 0.004)
                        .clamp(0.0, 1.0)
                        .toDouble())),
                child: SizedBox(width: 120, child: Center(child: number)),
              ),
              const SizedBox(width: 18),
              _roundBtn(Icons.add_rounded, 'Faster', 40,
                  _s.speed >= kMaxSpeed ? null : () => _setSpeed(_s.speed + 0.1)),
            ],
          );

    final String tail = changed
        ? ' · ${delta.abs().toStringAsFixed(1)}s ${delta < 0 ? 'shorter' : 'longer'}'
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        children: <Widget>[
          main,
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: _tabular.copyWith(color: _muted, fontSize: 12.5),
              children: <InlineSpan>[
                TextSpan(text: '${_fmtTime(_srcSeconds)}  →  '),
                TextSpan(
                  text: _fmtTime(out),
                  style: TextStyle(color: changed ? _accent : _text),
                ),
                TextSpan(text: tail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Normal mode ------------------------------------------------------------

  Widget _normalView() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: _SpeedSlider(speed: _s.speed, onChanged: _setSpeed),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              for (final double p in _chipPresets)
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

  // ---- Curve mode -------------------------------------------------------------

  Widget _curveView() {
    final List<SpeedPoint> pts = _s.points;
    final int? sel =
        _selected != null && _selected! < pts.length ? _selected : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              for (final e in _curvePresets.entries)
                _chip(
                  e.key,
                  _s.preset == e.key,
                  () => _loadPreset(e.key),
                  leading: CustomPaint(
                    size: const Size(22, 14),
                    painter: _MiniCurvePainter(
                        e.value, _s.preset == e.key ? _accent : _muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(builder: (context, box) {
            final Size size = Size(box.maxWidth, 150);
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
                double sp = _fromT(
                    (1 - o.dy / size.height).clamp(0.0, 1.0).toDouble());
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
                  decoration: BoxDecoration(
                    color: _field,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      size: size,
                      painter: _CurvePainter(pts: pts, selected: sel),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SizedBox(height: 40, child: _inspector(pts, sel)),
        ),
      ],
    );
  }

  Widget _inspector(List<SpeedPoint> pts, int? sel) {
    if (sel == null) {
      return Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Tap the graph to add a keyframe · long-press one to delete',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          _roundBtn(Icons.add_rounded, 'Add keyframe', 36,
              pts.length < kMaxCurvePoints ? _addPoint : null),
        ],
      );
    }
    return Row(
      children: <Widget>[
        _roundBtn(Icons.remove_rounded, 'Slower keyframe', 36,
            () => _nudgeKeyframe(-1)),
        SizedBox(
          width: 72,
          child: Text(_fmtSpeed(pts[sel].speed),
              textAlign: TextAlign.center,
              style: _tabular.copyWith(
                  color: _text, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        _roundBtn(Icons.add_rounded, 'Faster keyframe', 36,
            () => _nudgeKeyframe(1)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Keyframe ${sel + 1}/${pts.length} · at ${(pts[sel].x * 100).round()}%',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        _roundBtn(Icons.add_rounded, 'Add keyframe', 36,
            pts.length < kMaxCurvePoints ? _addPoint : null),
        const SizedBox(width: 8),
        _roundBtn(Icons.delete_outline_rounded, 'Delete keyframe', 36,
            _canDelete ? _deleteSelected : null),
      ],
    );
  }

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

  // ---- Heat strip + options ---------------------------------------------------

  Widget _heatStrip() {
    const int n = 40;
    final List<double> values = <double>[
      for (int i = 0; i < n; i++)
        _curve
            ? SpeedSettings.interpolate(_s.points, (i + .5) / n)
            : _s.speed,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: const <Widget>[
              Text('Result over time',
                  style: TextStyle(color: _muted, fontSize: 11)),
              Spacer(),
              Text('slower', style: TextStyle(color: _slow, fontSize: 11)),
              Text(' · ', style: TextStyle(color: _muted, fontSize: 11)),
              Text('faster', style: TextStyle(color: _fast, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: CustomPaint(painter: _StripPainter(values)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _options() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: <Widget>[
            _chip('Keep pitch', _s.maintainPitch, () {
              HapticFeedback.selectionClick();
              _update((s) => s.copyWith(maintainPitch: !s.maintainPitch));
            }, icon: Icons.music_note_rounded),
            _chip('Smooth motion', _s.smoothSlowMotion, () {
              HapticFeedback.selectionClick();
              _update((s) => s.copyWith(smoothSlowMotion: !s.smoothSlowMotion));
            }, icon: Icons.auto_awesome_rounded),
            _chip('Reverse', _s.reverse, () {
              HapticFeedback.selectionClick();
              _update((s) => s.copyWith(reverse: !s.reverse));
            }, icon: Icons.swap_horiz_rounded),
          ],
        ),
      ),
    );
  }
}

// ---- Log-scale slider with snap marks ------------------------------------------

class _SpeedSlider extends StatefulWidget {
  const _SpeedSlider({required this.speed, required this.onChanged});
  final double speed;
  final ValueChanged<double> onChanged;

  @override
  State<_SpeedSlider> createState() => _SpeedSliderState();
}

class _SpeedSliderState extends State<_SpeedSlider> {
  double? _snap; // mark currently snapped to, for one haptic per entry

  void _at(double dx, double w) {
    final double t = (dx / w).clamp(0.0, 1.0).toDouble();
    double v = _fromT(t);
    double? snap;
    for (final double m in _sliderMarks) {
      if ((_toT(m) - t).abs() < 0.025) {
        v = m;
        snap = m;
      }
    }
    if (snap != null && snap != _snap) HapticFeedback.selectionClick();
    _snap = snap;
    widget.onChanged(v);
  }

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
          onTapDown: (d) => _at(d.localPosition.dx, w),
          onHorizontalDragStart: (d) => _at(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _at(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => _snap = null,
          child: SizedBox(
            height: 44,
            width: w,
            child: CustomPaint(painter: _SliderPainter(widget.speed)),
          ),
        ),
      );
    });
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.speed);
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    const double cy = 13;
    final double t = _toT(speed);
    final double x = t * size.width;

    RRect bar(double w) => RRect.fromLTRBR(
        0, cy - 3, w, cy + 3, const Radius.circular(3));

    canvas.drawRRect(bar(size.width), Paint()..color = _line);
    canvas.drawRRect(bar(x), Paint()..color = _accent);

    for (final double m in _sliderMarks) {
      final double mx = _toT(m) * size.width;
      canvas.drawRect(
          Rect.fromLTWH(mx - 1, cy - 5, 2, 10), Paint()..color = _sheet);
      final bool on = (m - speed).abs() < 0.01;
      final TextPainter tp = TextPainter(
        text: TextSpan(
            text: _fmtMark(m),
            style: TextStyle(color: on ? _text : _muted, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(mx - tp.width / 2, 24));
    }

    canvas.drawCircle(Offset(x, cy), 10, Paint()..color = _accent);
    canvas.drawCircle(Offset(x, cy), 7, Paint()..color = _text);
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.speed != speed;
}

// ---- Heat strip painter --------------------------------------------------------

class _StripPainter extends CustomPainter {
  _StripPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    const double gap = 1;
    final int n = values.length;
    final double w = (size.width - gap * (n - 1)) / n;
    for (int i = 0; i < n; i++) {
      final double left = i * (w + gap);
      canvas.drawRect(Rect.fromLTWH(left, 0, w, size.height),
          Paint()..color = _heat(values[i]));
    }
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) => true;
}

// ---- Curve painters ------------------------------------------------------------

class _MiniCurvePainter extends CustomPainter {
  _MiniCurvePainter(this.pts, this.color);
  final List<SpeedPoint> pts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path();
    for (int i = 0; i <= 24; i++) {
      final double x = i / 24;
      final Offset o = Offset(
          x * size.width,
          1 + (size.height - 2) *
              (1 - _toT(SpeedSettings.interpolate(pts, x))));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
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

  Path _diamond(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r, c.dy)
    ..lineTo(c.dx, c.dy + r)
    ..lineTo(c.dx - r, c.dy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = _line
      ..strokeWidth = 1;

    for (final double f in <double>[.25, .5, .75]) {
      canvas.drawLine(
          Offset(f * size.width, 0), Offset(f * size.width, size.height), grid);
    }

    for (final double v in <double>[0.3, 1, 3]) {
      final double y = size.height * (1 - _toT(v));
      if (v == 1) {
        // Dashed 1x baseline.
        final Paint dash = Paint()
          ..color = Colors.white24
          ..strokeWidth = 1;
        for (double x = 0; x < size.width; x += 8) {
          canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), dash);
        }
      } else {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
      final TextPainter tp = TextPainter(
        text: TextSpan(
            text: _fmtMark(v), style: const TextStyle(color: _muted, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, y - tp.height - 2));
    }

    final Path line = Path();
    final Path fill = Path();
    const int n = 120;
    for (int i = 0; i <= n; i++) {
      final double x = i / n;
      final Offset o = Offset(x * size.width,
          size.height * (1 - _toT(SpeedSettings.interpolate(pts, x))));
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
    canvas.drawPath(fill, Paint()..color = _accent.withAlpha(26));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _accent);

    // Keyframes (diamonds) and the selected keyframe's value bubble.
    for (int i = 0; i < pts.length; i++) {
      final Offset o = _px(pts[i], size);
      final bool sel = i == selected;
      final Path d = _diamond(o, sel ? 10 : 7);
      canvas.drawPath(d, Paint()..color = sel ? _accent : _field);
      canvas.drawPath(
          d,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round
            ..color = _accent);
    }

    if (selected != null) {
      final Offset o = _px(pts[selected!], size);
      final double lx = o.dx.clamp(26.0, size.width - 26).toDouble();
      final double ly = o.dy > 38 ? o.dy - 24 : o.dy + 28;
      final Rect r = Rect.fromCenter(center: Offset(lx, ly), width: 46, height: 20);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(6)),
          Paint()..color = _cardHi);
      final TextPainter tp = TextPainter(
        text: TextSpan(
            text: _fmtSpeed(pts[selected!].speed),
            style: const TextStyle(color: _text, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.pts != pts || old.selected != selected;
}