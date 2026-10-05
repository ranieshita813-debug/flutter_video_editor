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

// -----------------------------------------------------------------------------
// Design tokens (CapCut-like: near-black canvas, white accents, one bright accent)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF000000);
const Color _surface = Color(0xFF0E0F13);
const Color _elevated = Color(0xFF1A1C22);
const Color _border = Color(0xFF26282F);
const Color _text = Color(0xFFF2F3F7);
const Color _muted = Color(0xFF8A8F9C);
const Color _violet = Color(0xFF7C5CFF);
const Color _cyan = Color(0xFF22D3EE);
const Color _pink = Color(0xFFE0457E);

const LinearGradient _accentGradient = LinearGradient(
  colors: <Color>[_violet, _cyan],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

double _seconds(Duration v) => v.inMilliseconds / 1000.0;

double _totalSeconds(EditorController e) =>
    math.max(_seconds(e.project.totalDuration), 1.0);

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(double seconds) {
  final int whole = math.max(seconds, 0).floor();
  return '${_two(whole ~/ 60)}:${_two(whole % 60)}';
}

void _seek(EditorController e, double seconds) {
  final double c = seconds.clamp(0.0, _totalSeconds(e)).toDouble();
  e.setPlayhead(Duration(milliseconds: (c * 1000).round()));
}

TextStyle _mono(Color c, {double size = 12, FontWeight w = FontWeight.w600}) =>
    TextStyle(
      color: c,
      fontSize: size,
      fontWeight: w,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

// -----------------------------------------------------------------------------
// Page
// -----------------------------------------------------------------------------

class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(editor: editor),
            Expanded(child: _Preview(editor: editor)),
            _PlaybackBar(editor: editor),
            _Timeline(editor: editor),
            _ToolDock(editor: editor),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Top bar
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _text),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Center(
                child: Text(
                  editor.project.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: _text),
                ),
              ),
            ),
            _ResolutionChip(onTap: () => ExportModal.show(context)),
            const SizedBox(width: 8),
            _ExportButton(onTap: () => ExportModal.show(context)),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _ResolutionChip extends StatelessWidget {
  const _ResolutionChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('1080p',
                style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: _accentGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text('Export',
                style: TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Preview
// -----------------------------------------------------------------------------

class _Preview extends StatelessWidget {
  const _Preview({required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;
    final tracking = clip?.trackingData;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editor.togglePlayback,
              child: ColoredBox(
                color: const Color(0xFF07080B),
                child: Stack(
                  children: <Widget>[
                    if (editor.isCameraActive)
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.videocam_rounded, size: 34, color: _cyan),
                            SizedBox(height: 6),
                            Text('Camera on',
                                style: TextStyle(color: _text, fontSize: 12)),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: editor.isPlaying ? 0 : 1,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(120),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                size: 36, color: Colors.white),
                          ),
                        ),
                      ),
                    if (editor.activeDrawingStrokes.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DrawingPainter(strokes: editor.activeDrawingStrokes),
                        ),
                      ),
                    if (tracking != null && tracking.isEnabled)
                      Positioned(
                        left: 24,
                        top: 24,
                        width: 90,
                        height: 90,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: _cyan, width: 1.5),
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              color: _cyan,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              child: Text(
                                tracking.targetName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF04202B),
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// Playback bar: time, play, undo/redo
// -----------------------------------------------------------------------------

class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar({required this.editor});
  final EditorController editor;

  void _showFullScreenPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: const Color(0xFF07080B),
                    child: const Center(
                      child: Icon(Icons.play_circle_outline_rounded,
                          size: 64, color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double t = _seconds(editor.playhead);
    final double total = _totalSeconds(editor);

    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: <TextSpan>[
                    TextSpan(text: _clock(t), style: _mono(_text, size: 13)),
                    TextSpan(text: '  /  ${_clock(total)}', style: _mono(_muted, size: 13)),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                editor.togglePlayback();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: _accentGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 26,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _iconBtn(Icons.undo_rounded, 'Undo', editor.canUndo ? editor.undo : null),
                  _iconBtn(Icons.redo_rounded, 'Redo', editor.canRedo ? editor.redo : null),
                  _iconBtn(Icons.fullscreen_rounded, 'Full screen',
                      () => _showFullScreenPreview(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 21, color: onTap != null ? _text : Colors.white24),
        tooltip: tip,
        onPressed: onTap,
      );
}

// -----------------------------------------------------------------------------
// Timeline: fixed centre playhead, content scrolls beneath it (CapCut style)
// -----------------------------------------------------------------------------

class _TrackRow {
  const _TrackRow({required this.layer, required this.isAudio, required this.isMain});
  final int layer;
  final bool isAudio;
  final bool isMain;
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.editor});
  final EditorController editor;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const double _rulerH = 26;
  static const double _mainH = 60;
  static const double _subH = 40;
  static const double _maxH = 220;

  final ScrollController _sc = ScrollController();
  bool _userScrolling = false;

  EditorController get editor => widget.editor;

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Color _colorFor(ClipType type) => switch (type) {
        ClipType.video => const Color(0xFF4B3BB8),
        ClipType.image => const Color(0xFF2F5FC9),
        ClipType.audio => const Color(0xFF138A77),
        ClipType.text => _pink,
        ClipType.caption => _pink,
        ClipType.drawing => const Color(0xFFD2791F),
        ClipType.sticker => const Color(0xFF2290B0),
      };

  List<_TrackRow> _rows(List<TimelineClip> clips) {
    final List<int> visual = clips
        .where((c) => c.clipType != ClipType.audio)
        .map<int>((c) => c.layerIndex)
        .toSet()
        .toList()
      ..sort();
    final List<int> audio = clips
        .where((c) => c.clipType == ClipType.audio)
        .map<int>((c) => c.layerIndex)
        .toSet()
        .toList()
      ..sort();
    if (visual.isEmpty) visual.add(0);

    final int mainLayer = visual.first;
    return <_TrackRow>[
      for (final int l in visual.reversed)
        _TrackRow(layer: l, isAudio: false, isMain: l == mainLayer),
      for (final int l in audio) _TrackRow(layer: l, isAudio: true, isMain: false),
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

  @override
  Widget build(BuildContext context) {
    final List<TimelineClip> clips = editor.project.clips;
    final double total = _totalSeconds(editor);
    final double pps = 28.0 * editor.zoom;
    final List<_TrackRow> rows = _rows(clips);
    final double lanesH =
        rows.fold<double>(0, (s, r) => s + (r.isMain ? _mainH : _subH)) + rows.length * 4;
    final double contentH = _rulerH + lanesH + 8;

    _syncScroll(pps);

    double visualEnd = 0;
    for (final c in clips.where((c) => c.clipType != ClipType.audio)) {
      visualEnd = math.max(visualEnd, _seconds(c.end));
    }

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: math.min(contentH, _maxH),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double half = c.maxWidth / 2;
                final double contentW = total * pps + c.maxWidth;

                return Stack(
                  children: <Widget>[
                    NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollStartNotification && n.dragDetails != null) {
                          _userScrolling = true;
                        } else if (n is ScrollUpdateNotification && _userScrolling) {
                          _seek(editor, n.metrics.pixels / pps);
                        } else if (n is ScrollEndNotification) {
                          _userScrolling = false;
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _sc,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: contentW,
                          child: SingleChildScrollView(
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
                                        pps: pps,
                                        seconds: total + 5,
                                        leftPad: half,
                                      ),
                                    ),
                                  ),
                                  for (final row in rows)
                                    _lane(clips, row, pps, half, contentW,
                                        row.isMain ? visualEnd : null),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: half - 1,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Column(
                          children: <Widget>[
                            Container(
                              width: 10,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.vertical(bottom: Radius.circular(5)),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                width: 2,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                        color: Colors.black.withAlpha(180), blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 2,
                      child: Row(
                        children: <Widget>[
                          _zoomBtn(Icons.remove_rounded,
                              () => editor.setZoom((editor.zoom - 0.25).clamp(0.5, 3.0).toDouble())),
                          const SizedBox(width: 4),
                          _zoomBtn(Icons.add_rounded,
                              () => editor.setZoom((editor.zoom + 0.25).clamp(0.5, 3.0).toDouble())),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 24,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: _text),
        ),
      );

  Widget _lane(List<TimelineClip> clips, _TrackRow row, double pps, double half,
      double contentW, double? addTileAfter) {
    final double h = row.isMain ? _mainH : _subH;
    final List<TimelineClip> trackClips = clips
        .where((c) =>
            c.layerIndex == row.layer && (c.clipType == ClipType.audio) == row.isAudio)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        height: h,
        width: contentW,
        child: Stack(
          children: <Widget>[
            for (final clip in trackClips)
              Positioned(
                left: half + _seconds(clip.start) * pps,
                top: 0,
                bottom: 0,
                width: math.max(36.0, _seconds(clip.duration) * pps - 2),
                child: _ClipBlock(
                  editor: editor,
                  clip: clip,
                  color: _colorFor(clip.clipType),
                  isAudio: row.isAudio,
                  compact: !row.isMain,
                ),
              ),
            if (addTileAfter != null)
              Positioned(
                left: half + addTileAfter * pps + 8,
                top: 0,
                bottom: 0,
                width: 52,
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(context).pushNamed('/media_picker'),
                    child: const Center(
                      child: Icon(Icons.add_rounded, size: 26, color: Colors.black),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Clip block
// -----------------------------------------------------------------------------

enum _BodyKind { filmstrip, waveform, solid }

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.editor,
    required this.clip,
    required this.color,
    required this.isAudio,
    required this.compact,
  });

  final EditorController editor;
  final TimelineClip clip;
  final Color color;
  final bool isAudio;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool selected = editor.selectedClipId == clip.id;
    final ClipType type = clip.clipType;
    final _BodyKind kind = isAudio
        ? _BodyKind.waveform
        : (type == ClipType.video || type == ClipType.image)
            ? _BodyKind.filmstrip
            : _BodyKind.solid;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        editor.selectClip(clip.id);
      },
      onLongPress: () => editor.toggleClipLock(clip.id),
      onDoubleTap: () => editor.toggleClipVisibility(clip.id),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: clip.isVisible ? 1.0 : 0.35,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: selected ? 2 : 0,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 5 : 6),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClipBodyPainter(
                      kind: kind,
                      seed: clip.id.hashCode % 97,
                      peaks: kind == _BodyKind.waveform ? _peaksFor(clip) : null,
                      showLabelStrip: !compact,
                    ),
                  ),
                ),
                Positioned(
                  left: selected ? 14 : 6,
                  right: 6,
                  top: 0,
                  bottom: compact ? 0 : null,
                  height: compact ? null : 16,
                  child: Row(
                    children: <Widget>[
                      if (isAudio)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: Icon(Icons.music_note_rounded, size: 12, color: Colors.white),
                        ),
                      Expanded(
                        child: Text(
                          clip.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (clip.isLocked)
                        const Icon(Icons.lock_rounded, size: 11, color: Colors.white70),
                    ],
                  ),
                ),
                if (selected) ...<Widget>[
                  const Positioned(left: 0, top: 0, bottom: 0, child: _TrimHandle(left: true)),
                  const Positioned(right: 0, top: 0, bottom: 0, child: _TrimHandle(left: false)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({required this.left});
  final bool left;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(left ? 5 : 0),
          right: Radius.circular(left ? 0 : 5),
        ),
      ),
      child: Icon(
        left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        size: 14,
        color: Colors.black87,
      ),
    );
  }
}

List<double>? _peaksFor(TimelineClip clip) {
  try {
    final dynamic raw = (clip as dynamic).waveform;
    if (raw is List && raw.isNotEmpty) {
      final List<double> out =
          raw.map<double>((dynamic e) => (e as num).toDouble().abs()).toList();
      final double peak = out.fold<double>(0.0, (double m, double v) => math.max(m, v));
      if (peak == 0) return null;
      return out.map<double>((double v) => v / peak).toList();
    }
  } catch (_) {}
  return null;
}

class _ClipBodyPainter extends CustomPainter {
  _ClipBodyPainter({
    required this.kind,
    required this.seed,
    required this.showLabelStrip,
    this.peaks,
  });

  final _BodyKind kind;
  final int seed;
  final bool showLabelStrip;
  final List<double>? peaks;

  @override
  void paint(Canvas canvas, Size size) {
    final double strip = showLabelStrip ? 16 : 0;
    if (showLabelStrip) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, strip),
          Paint()..color = Colors.black.withAlpha(70));
    }
    final double bodyH = size.height - strip;
    if (bodyH <= 0) return;

    switch (kind) {
      case _BodyKind.filmstrip:
        final Paint frame = Paint()..color = Colors.white.withAlpha(34);
        final double fw = math.max(bodyH * 1.4, 16);
        for (double x = 0; x < size.width; x += fw + 1.5) {
          canvas.drawRect(Rect.fromLTWH(x, strip, fw, bodyH), frame);
        }
      case _BodyKind.waveform:
        final Paint wave = Paint()
          ..color = Colors.white.withAlpha(200)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        final double midY = size.height / 2 + 4;
        const double gap = 3.5;
        final int bars = ((size.width - 6) / gap).floor();
        final List<double>? p = peaks;
        for (int i = 0; i < bars; i++) {
          final double x = 3 + i * gap;
          double a;
          if (p != null && p.isNotEmpty) {
            final int idx = (i / math.max(bars - 1, 1) * (p.length - 1)).round();
            a = p[idx].clamp(0.0, 1.0).toDouble();
          } else {
            a = (math.sin(x * 0.35 + seed) * 0.5 + 0.5) *
                (0.35 + 0.65 * (((x.toInt() * 7 + seed) % 11) / 11));
          }
          final double h = math.max(2.0, a * (size.height - 14));
          canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), wave);
        }
      case _BodyKind.solid:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ClipBodyPainter old) =>
      old.kind != kind ||
      old.seed != seed ||
      old.showLabelStrip != showLabelStrip ||
      !identical(old.peaks, peaks);
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.pps, required this.seconds, required this.leftPad});

  final double pps;
  final double seconds;
  final double leftPad;

  @override
  void paint(Canvas canvas, Size size) {
    const List<double> steps = <double>[1, 2, 5, 10, 15, 30, 60, 120, 300];
    final double step = steps.firstWhere((s) => s * pps >= 64, orElse: () => steps.last);

    final Paint dot = Paint()..color = _muted;
    final Paint tick = Paint()
      ..color = _border
      ..strokeWidth = 1;

    final int count = (seconds / step).ceil();
    for (int i = 0; i <= count; i++) {
      final double t = i * step;
      final double x = leftPad + t * pps;
      if (x > size.width) break;

      final TextPainter label = TextPainter(
        text: TextSpan(
          text: _clock(t),
          style: const TextStyle(color: _muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, 3));

      for (int j = 1; j < 4; j++) {
        final double mx = x + j * step * pps / 4;
        canvas.drawCircle(Offset(mx, size.height - 6), 1, dot);
      }
      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height - 3), tick);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps || old.seconds != seconds || old.leftPad != leftPad;
}

// -----------------------------------------------------------------------------
// Contextual tool dock: main tools <-> selected-clip tools
// -----------------------------------------------------------------------------

class _DockItem {
  const _DockItem(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
}

class _ToolDock extends StatefulWidget {
  const _ToolDock({required this.editor});
  final EditorController editor;

  @override
  State<_ToolDock> createState() => _ToolDockState();
}

class _ToolDockState extends State<_ToolDock> {
  bool _clipMode = false;

  @override
  void didUpdateWidget(covariant _ToolDock old) {
    super.didUpdateWidget(old);
    final String? before = old.editor.selectedClipId;
    final String? now = widget.editor.selectedClipId;
    if (now != null && now != before) _clipMode = true;
    if (now == null) _clipMode = false;
  }

  List<_DockItem> _mainItems(BuildContext context) => <_DockItem>[
        _DockItem(Icons.content_cut_rounded, 'Edit', () {
          if (widget.editor.selectedClip != null) {
            setState(() => _clipMode = true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Select a clip on timeline first')),
            );
          }
        }),
        _DockItem(Icons.graphic_eq_rounded, 'Audio', () => AudioToolsSheet.show(context)),
        _DockItem(Icons.title_rounded, 'Text', () => TextAnimationSheet.show(context)),
        _DockItem(Icons.subtitles_rounded, 'Captions', widget.editor.generateAutoCaptions),
        _DockItem(Icons.brush_rounded, 'Draw', () => VectorDrawingSheet.show(context)),
        _DockItem(Icons.tune_rounded, 'Adjust', () => ColorGradingSheet.show(context)),
        _DockItem(Icons.center_focus_strong_rounded, 'Track',
            () => CameraTrackingPanel.show(context)),
        _DockItem(Icons.emoji_emotions_rounded, 'Stickers', () => StickersSheet.show(context)),
        _DockItem(Icons.auto_awesome_rounded, 'Effects',
            () => EffectsSheet.show(context, isFilterMode: false)),
        _DockItem(Icons.filter_vintage_rounded, 'Filters',
            () => EffectsSheet.show(context, isFilterMode: true)),
      ];

  List<_DockItem> _clipItems(BuildContext context) {
    final e = widget.editor;
    final sel = e.selectedClip;
    final bool canSplit = sel != null && e.playhead > sel.start && e.playhead < sel.end;
    return <_DockItem>[
      _DockItem(Icons.call_split_rounded, 'Split', canSplit ? e.splitSelectedClip : null),
      _DockItem(Icons.speed_rounded, 'Speed', () => SpeedSheet.show(context)),
      _DockItem(Icons.volume_up_rounded, 'Volume', () => AudioToolsSheet.show(context)),
      _DockItem(Icons.tune_rounded, 'Adjust', () => ColorGradingSheet.show(context)),
      _DockItem(Icons.crop_rounded, 'Crop', () => CropSheet.show(context)),
      _DockItem(Icons.title_rounded, 'Text', () => TextAnimationSheet.show(context)),
      _DockItem(Icons.delete_rounded, 'Delete', sel != null ? e.deleteSelectedClip : null,
          danger: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool clipMode = _clipMode && widget.editor.selectedClip != null;
    final List<_DockItem> items = clipMode ? _clipItems(context) : _mainItems(context);

    return Container(
      height: 66,
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: <Widget>[
          if (clipMode)
            InkWell(
              onTap: () => setState(() => _clipMode = false),
              child: Container(
                width: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: _border)),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _text),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: ListView.builder(
                key: ValueKey<bool>(clipMode),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: items.length,
                itemBuilder: (BuildContext context, int i) => _ToolButton(item: items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.item});
  final _DockItem item;

  @override
  Widget build(BuildContext context) {
    final bool enabled = item.onTap != null;
    final Color iconColor =
        !enabled ? Colors.white24 : (item.danger ? const Color(0xFFFF5A6E) : _text);

    return SizedBox(
      width: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: item.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                item.onTap!();
              },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(item.icon, size: 24, color: iconColor),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              style: TextStyle(
                color: enabled ? _muted : Colors.white24,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
