import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/audio_tools_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_tracking_panel.dart';
import 'package:flutter_video_editor/features/editor/widgets/color_grading_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/crop_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/effects_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/stickers_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/text_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/vector_drawing_sheet.dart';

// ----------------------------------------------------------------------------
// Tokens
// ----------------------------------------------------------------------------
const Color _bg = Color(0xFF000000);
const Color _muted = Color(0xFF9A9AA3);
const Color _purple = Color(0xFF8B6CFF);
const Color _textTrack = Color(0xFF2A2740);
const Color _audioTrack = Color(0xFF2B2B31);
const Color _doneBtn = Color(0xFF1F3A44);

const double _playheadFrac = 0.42; // playhead sits left of centre, as in design

double _seconds(Duration v) => v.inMilliseconds / 1000.0;
double _totalSeconds(EditorController e) =>
    math.max(_seconds(e.project.totalDuration), 1.0);
String _two(int n) => n.toString().padLeft(2, '0');
const int _fps = 30;

String _tc(double s) {
  final int f = (math.max(s, 0) * _fps).round();
  final int sec = f ~/ _fps;
  return '${_two(sec ~/ 3600)}:${_two(sec % 3600 ~/ 60)}:${_two(sec % 60)}:${_two(f % _fps)}';
}

void _seek(EditorController e, double s) {
  final double c = s.clamp(0.0, _totalSeconds(e)).toDouble();
  final double q = (c * _fps).round() / _fps;
  e.setPlayhead(Duration(milliseconds: (q * 1000).round()));
}

// ----------------------------------------------------------------------------
// Page
// ----------------------------------------------------------------------------
class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: <Widget>[
          Expanded(child: _Preview(editor: editor)),
          _Timeline(editor: editor),
          _Toolbar(editor: editor),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Preview (full-bleed) with overlaid controls
// ----------------------------------------------------------------------------
class _Preview extends StatelessWidget {
  const _Preview({required this.editor});
  final EditorController editor;

  Widget _step(IconData i, int dir) => IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(i, color: Colors.white, size: 24),
        onPressed: () {
          HapticFeedback.selectionClick();
          _seek(editor, _seconds(editor.playhead) + dir / _fps);
        },
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: editor.togglePlayback,
          child: const ColoredBox(color: Color(0xFF07080B)),
        ),
        Consumer<EditorController>(
          builder: (ctx, e, _) {
            final tracking = e.selectedClip?.trackingData;
            return IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (e.activeDrawingStrokes.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                          painter: _DrawingPainter(strokes: e.activeDrawingStrokes)),
                    ),
                  if (tracking != null && tracking.isEnabled)
                    Positioned(
                      left: 40,
                      top: 120,
                      width: 90,
                      height: 90,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: _purple, width: 1.5)),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: _purple,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            child: Text(tracking.targetName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        SafeArea(
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: () => ExportModal.show(context),
                    child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 24),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Edit',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration:
                          const BoxDecoration(color: _doneBtn, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Selector<EditorController, Duration>(
                selector: (_, e) => e.playhead,
                builder: (_, p, __) => Text.rich(TextSpan(children: <TextSpan>[
                  TextSpan(
                      text: _tc(_seconds(p)),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                  TextSpan(
                      text: '   ${_tc(_totalSeconds(editor))}',
                      style: const TextStyle(
                          color: _muted,
                          fontSize: 11,
                          fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                ])),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: () => _moreSheet(context),
                    child: const Icon(Icons.settings_outlined, color: Colors.white, size: 24),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _step(Icons.skip_previous_rounded, -1),
                        Selector<EditorController, bool>(
                          selector: (_, e) => e.isPlaying,
                          builder: (_, playing, __) => GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              editor.togglePlayback();
                            },
                            child: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 36),
                          ),
                        ),
                        _step(Icons.skip_next_rounded, 1),
                      ],
                    ),
                  ),
                  const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 26),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _moreSheet(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.title_rounded, 'Text', () => TextAnimationSheet.show(context)),
      (Icons.subtitles_rounded, 'Captions', editor.generateAutoCaptions),
      (Icons.brush_rounded, 'Draw', () => VectorDrawingSheet.show(context)),
      (Icons.center_focus_strong_rounded, 'Track',
          () => CameraTrackingPanel.show(context)),
      (Icons.emoji_emotions_rounded, 'Stickers',
          () => StickersSheet.show(context)),
      (Icons.filter_vintage_rounded, 'Filters',
          () => EffectsSheet.show(context, isFilterMode: true)),
      (Icons.undo_rounded, 'Undo', editor.undo),
      (Icons.redo_rounded, 'Redo', editor.redo),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 12,
            children: <Widget>[
              for (final it in items)
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    it.$3();
                  },
                  child: SizedBox(
                    width: 76,
                    child: Column(children: <Widget>[
                      Icon(it.$1, color: Colors.white, size: 24),
                      const SizedBox(height: 4),
                      Text(it.$2,
                          style:
                              const TextStyle(color: _muted, fontSize: 11)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter({required this.strokes});
  final List<DrawingStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ----------------------------------------------------------------------------
// Timeline
// ----------------------------------------------------------------------------
class _Lane {
  const _Lane(this.h, this.kind, this.clips, {this.add = false});
  final double h;
  final _ClipKind kind;
  final List<TimelineClip> clips;
  final bool add;
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.editor});
  final EditorController editor;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const double _rulerH = 28, _textH = 30, _videoH = 44, _audioH = 36;
  static const double _gap = 6, _hdrW = 34;

  final ScrollController _sc = ScrollController();
  final ScrollController _vc = ScrollController();
  final ScrollController _hc = ScrollController();
  bool _userScrolling = false;
  bool _snap = true;
  int _pointers = 0;
  double _baseZoom = 1;
  double? _lastSnap;

  EditorController get editor => widget.editor;

  @override
  void initState() {
    super.initState();
    _vc.addListener(() {
      if (_hc.hasClients && (_hc.offset - _vc.offset).abs() > 0.5) {
        _hc.jumpTo(_vc.offset.clamp(0.0, _hc.position.maxScrollExtent).toDouble());
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    _vc.dispose();
    _hc.dispose();
    super.dispose();
  }

  bool _isOverlay(TimelineClip c) =>
      c.clipType != ClipType.audio &&
      c.clipType != ClipType.video &&
      c.clipType != ClipType.image;

  List<_Lane> _lanes(List<TimelineClip> clips) {
    final main = clips
        .where((c) => c.clipType == ClipType.video || c.clipType == ClipType.image)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final audio = clips.where((c) => c.clipType == ClipType.audio).toList();
    final layers = clips.where(_isOverlay).map<int>((c) => c.layerIndex).toSet().toList()
      ..sort();
    return <_Lane>[
      for (final l in layers.reversed)
        _Lane(_textH, _ClipKind.text,
            clips.where((c) => _isOverlay(c) && c.layerIndex == l).toList()),
      _Lane(_videoH, _ClipKind.video, main, add: true),
      if (audio.isNotEmpty) _Lane(_audioH, _ClipKind.audio, audio),
    ];
  }

  void _syncScroll(double pps) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || !_sc.hasClients) return;
      final double target = (_seconds(editor.playhead) * pps)
          .clamp(0.0, _sc.position.maxScrollExtent)
          .toDouble();
      if ((_sc.offset - target).abs() > 0.5) _sc.jumpTo(target);
    });
  }

  double _snapTime(double t, double pps, List<TimelineClip> clips) {
    if (!_snap) return t;
    double best = t;
    double bd = 8 / pps;
    for (final c in clips) {
      for (final double e in <double>[_seconds(c.start), _seconds(c.end)]) {
        final double d = (e - t).abs();
        if (d < bd) {
          bd = d;
          best = e;
        }
      }
    }
    if (best != t && _lastSnap != best) HapticFeedback.selectionClick();
    _lastSnap = best != t ? best : null;
    return best;
  }

  void _setZoom(double z) => editor.setZoom(z.clamp(0.5, 8.0).toDouble());

  @override
  Widget build(BuildContext context) {
    context.watch<EditorController>();
    final List<TimelineClip> clips = editor.project.clips;
    final double total = _totalSeconds(editor);
    final double pps = 28.0 * editor.zoom;
    final List<_Lane> lanes = _lanes(clips);
    final double contentH =
        _rulerH + lanes.fold<double>(0, (s, l) => s + l.h + _gap) + 16;

    _syncScroll(pps);

    return Container(
      color: _bg,
      height: math.min(contentH, 220),
      child: LayoutBuilder(builder: (context, c) {
        final double half = c.maxWidth * _playheadFrac;
        final double contentW = total * pps + c.maxWidth;

        return Stack(
          children: <Widget>[
            Listener(
              onPointerDown: (_) {
                if (++_pointers == 2) setState(() {});
              },
              onPointerUp: (_) {
                if (--_pointers < 2) setState(() {});
              },
              onPointerCancel: (_) {
                _pointers = math.max(0, _pointers - 1);
                setState(() {});
              },
              child: GestureDetector(
                onScaleStart: (_) => _baseZoom = editor.zoom,
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) _setZoom(_baseZoom * d.scale);
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.axis != Axis.horizontal) return false;
                    if (n is ScrollStartNotification && n.dragDetails != null) {
                      _userScrolling = true;
                    } else if (n is ScrollUpdateNotification && _userScrolling) {
                      _seek(editor, _snapTime(n.metrics.pixels / pps, pps, clips));
                    } else if (n is ScrollEndNotification) {
                      _userScrolling = false;
                      _syncScroll(pps);
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _sc,
                    scrollDirection: Axis.horizontal,
                    physics: _pointers >= 2
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: contentW,
                      child: SingleChildScrollView(
                        controller: _vc,
                        child: SizedBox(
                          height: contentH,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(
                                height: _rulerH,
                                width: contentW,
                                child: CustomPaint(
                                  painter: _RulerPainter(
                                      pps: pps, seconds: total + 5, leftPad: half),
                                ),
                              ),
                              for (final l in lanes) _lane(l, contentW, pps, half),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Track headers: lock + hide per lane
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _hdrW,
              child: Container(
                decoration: const BoxDecoration(
                  color: _bg,
                  border: Border(right: BorderSide(color: Color(0xFF1E1E22))),
                ),
                child: SingleChildScrollView(
                  controller: _hc,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    height: contentH,
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: _rulerH),
                        for (final l in lanes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _gap),
                            child: SizedBox(height: l.h, child: _header(l)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: half - 1,
              top: _rulerH - 6,
              bottom: 0,
              child: IgnorePointer(child: Container(width: 2, color: Colors.white)),
            ),
            Positioned(
              right: 6,
              top: 2,
              child: Row(
                children: <Widget>[
                  _chip(Icons.align_horizontal_center_rounded, _snap,
                      () => setState(() => _snap = !_snap)),
                  const SizedBox(width: 4),
                  _chip(Icons.remove_rounded, false, () => _setZoom(editor.zoom - 0.5)),
                  const SizedBox(width: 4),
                  _chip(Icons.add_rounded, false, () => _setZoom(editor.zoom + 0.5)),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _chip(IconData icon, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 20,
          decoration: BoxDecoration(
            color: on ? _purple : Colors.white12,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      );

  Widget _header(_Lane l) {
    final bool locked = l.clips.isNotEmpty && l.clips.every((c) => c.isLocked);
    final bool visible = l.clips.any((c) => c.isVisible);
    Widget btn(IconData i, bool active, VoidCallback f) => InkWell(
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(i, size: 13, color: active ? _purple : Colors.white54),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        btn(locked ? Icons.lock_rounded : Icons.lock_open_rounded, locked, () {
          for (final c in l.clips) {
            if (c.isLocked == locked) editor.toggleClipLock(c.id);
          }
        }),
        btn(visible ? Icons.visibility_rounded : Icons.visibility_off_rounded, !visible, () {
          for (final c in l.clips) {
            if (c.isVisible == visible) editor.toggleClipVisibility(c.id);
          }
        }),
      ],
    );
  }

  Widget _lane(_Lane l, double contentW, double pps, double half) {
    final list = l.clips;
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: SizedBox(
        height: l.h,
        width: contentW,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (int i = 0; i < list.length; i++) ...<Widget>[
              Positioned(
                left: half + _seconds(list[i].start) * pps,
                top: 0,
                bottom: 0,
                width: math.max(44.0, _seconds(list[i].duration) * pps - 4),
                child: _ClipBlock(editor: editor, clip: list[i], kind: l.kind),
              ),
              if (l.kind == _ClipKind.video && i < list.length - 1)
                Positioned(
                  left: half + _seconds(list[i].end) * pps - 12,
                  top: l.h / 2 - 10,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration:
                        const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.join_inner_rounded, size: 13, color: Colors.black),
                  ),
                ),
            ],
            if (l.add)
              Positioned(
                left: half + (list.isEmpty ? 0 : _seconds(list.first.start) * pps) - 14,
                top: l.h / 2 - 10,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/media_picker'),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration:
                        const BoxDecoration(color: _purple, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Clips
// ----------------------------------------------------------------------------
enum _ClipKind { text, video, audio }

class _ClipBlock extends StatelessWidget {
  const _ClipBlock(
      {required this.editor, required this.clip, required this.kind});
  final EditorController editor;
  final TimelineClip clip;
  final _ClipKind kind;

  @override
  Widget build(BuildContext context) {
    final bool selected = editor.selectedClipId == clip.id;

    Widget body;
    switch (kind) {
      case _ClipKind.text:
        final bool fx = clip.clipType == ClipType.sticker ||
            clip.clipType == ClipType.drawing;
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _textTrack,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? _purple : Colors.transparent, width: 2),
          ),
          child: Row(children: <Widget>[
            if (fx)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 16, color: _purple),
              ),
            const Icon(Icons.title_rounded, size: 18, color: Colors.white70),
            const SizedBox(width: 6),
            Expanded(
              child: Text(clip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ]),
        );
        if (selected) {
          body = Stack(clipBehavior: Clip.none, children: <Widget>[
            Positioned.fill(child: body),
            const Positioned(left: -6, top: 4, bottom: 4, child: _Handle()),
            const Positioned(right: -6, top: 4, bottom: 4, child: _Handle()),
          ]);
        }
      case _ClipKind.video:
        body = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? Colors.white : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
                painter: _FilmPainter(), child: const SizedBox.expand()),
          ),
        );
      case _ClipKind.audio:
        body = Container(
          decoration: BoxDecoration(
            color: _audioTrack,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? Colors.white : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
                painter: _WavePainter(seed: clip.id.hashCode % 97),
                child: const SizedBox.expand()),
          ),
        );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        editor.selectClip(clip.id);
      },
      onLongPress: () => editor.toggleClipLock(clip.id),
      onDoubleTap: () => editor.toggleClipVisibility(clip.id),
      child: Opacity(opacity: clip.isVisible ? 1 : 0.35, child: body),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        decoration: BoxDecoration(
            color: _purple, borderRadius: BorderRadius.circular(5)),
        child: const Center(
          child: SizedBox(
              width: 2,
              height: 10,
              child: ColoredBox(color: Colors.white70)),
        ),
      );
}

class _FilmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF3A5A7A));
    final double fw = size.height * 0.85;
    int i = 0;
    for (double x = 0; x < size.width; x += fw) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, fw - 1, size.height),
        Paint()
          ..color = (i++ % 2 == 0)
              ? const Color(0xFF4E7396)
              : const Color(0xFF5C87AB),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const double gap = 4;
    final int bars = ((size.width - 20) / gap).floor();
    for (int i = 0; i < bars; i++) {
      final double x = 10 + i * gap;
      final double a = (math.sin(x * 0.3 + seed) * 0.5 + 0.5) *
          (0.3 + 0.7 * (((i * 7 + seed) % 11) / 11));
      final double h = math.max(3.0, a * (size.height - 10));
      canvas.drawLine(Offset(x, size.height / 2 - h / 2),
          Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.seed != seed;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(
      {required this.pps, required this.seconds, required this.leftPad});
  final double pps;
  final double seconds;
  final double leftPad;

  @override
  void paint(Canvas canvas, Size size) {
    const steps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300];
    final double step =
        steps.firstWhere((s) => s * pps >= 64, orElse: () => steps.last);
    final Paint dot = Paint()..color = const Color(0xFF6A6A72);
    final int count = (seconds / step).ceil();

    for (int i = 0; i <= count; i++) {
      final double t = i * step;
      final double x = leftPad + t * pps;
      if (x > size.width) break;
      final tp = TextPainter(
        text: TextSpan(
            text: step < 1 ? '${t.toStringAsFixed(1)}s' : '${t.toInt()}s',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 4));
      for (int j = 1; j < 4; j++) {
        canvas.drawCircle(
            Offset(x + j * step * pps / 4, 12 + tp.height / 2), 1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps || old.seconds != seconds || old.leftPad != leftPad;
}

// ----------------------------------------------------------------------------
// Bottom toolbar: icon-only, evenly spaced
// ----------------------------------------------------------------------------
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final sel = editor.selectedClip;
    final bool canSplit =
        sel != null && editor.playhead > sel.start && editor.playhead < sel.end;

    Widget btn(IconData i, VoidCallback? onTap, {Color? color}) => IconButton(
          icon: Icon(i, size: 24, color: onTap == null ? Colors.white24 : (color ?? Colors.white)),
          onPressed: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
        );

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            btn(Icons.content_cut_rounded, canSplit ? editor.splitSelectedClip : null),
            btn(Icons.local_fire_department_outlined,
                () => EffectsSheet.show(context, isFilterMode: false)),
            btn(Icons.volume_up_outlined, () => AudioToolsSheet.show(context)),
            btn(Icons.crop_rounded, () => CropSheet.show(context)),
            btn(Icons.speed_rounded, () => SpeedSheet.show(context)),
            btn(Icons.layers_outlined, () => ColorGradingSheet.show(context)),
            btn(Icons.delete_outline_rounded,
                sel != null ? editor.deleteSelectedClip : null),
          ],
        ),
      ),
    );
  }
}