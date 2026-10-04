import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/audio_tools_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_tracking_panel.dart';
import 'package:flutter_video_editor/features/editor/widgets/color_grading_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/text_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/vector_drawing_sheet.dart';

// Premiere Pro style palette
const Color _bg = Color(0xFF1A1A1A);
const Color _panel = Color(0xFF232323);
const Color _panelDark = Color(0xFF1E1E1E);
const Color _line = Color(0xFF111111);
const Color _border = Color(0xFF3A3A3A);
const Color _text = Color(0xFFC8C8C8);
const Color _muted = Color(0xFF8A8A8A);
const Color _blue = Color(0xFF2D8CFF);
const Color _timecodeBlue = Color(0xFF4DA3FF);

const double _fps = 30;

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

double _seconds(Duration value) => value.inMilliseconds / 1000.0;

double _totalSeconds(EditorController editor) {
  return math.max(_seconds(editor.project.totalDuration), 1.0);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _timecode(double seconds) {
  final int fps = _fps.toInt();
  final int frames = (math.max(seconds, 0.0) * _fps).round();
  final int f = frames % fps;
  final int s = (frames ~/ fps) % 60;
  final int m = (frames ~/ (fps * 60)) % 60;
  final int h = frames ~/ (fps * 3600);
  return '${_two(h)}:${_two(m)}:${_two(s)}:${_two(f)}';
}

/// Single place that moves the playhead.
void _seek(EditorController editor, double seconds) {
  final double clamped = seconds.clamp(0.0, _totalSeconds(editor)).toDouble();
  editor.setPlayhead(Duration(milliseconds: (clamped * 1000).round()));
}

TextStyle _timecodeStyle(Color color, {double size = 13}) => TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w600,
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
            Expanded(child: _ProgramMonitor(editor: editor)),
            _TimelinePanel(editor: editor),
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
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: _panelDark,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _text, size: 22),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              editor.project.projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 20),
            color: _text,
            disabledColor: Colors.white24,
            tooltip: 'Undo',
            onPressed: editor.canUndo ? editor.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded, size: 20),
            color: _text,
            disabledColor: Colors.white24,
            tooltip: 'Redo',
            onPressed: editor.canRedo ? editor.redo : null,
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 30,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              onPressed: () => ExportModal.show(context),
              child: const Text('Export'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Program monitor
// -----------------------------------------------------------------------------

class _ProgramMonitor extends StatelessWidget {
  const _ProgramMonitor({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final double total = _totalSeconds(editor);
    final double t = _seconds(editor.playhead);

    return Container(
      color: _panel,
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Program', style: TextStyle(color: _muted, fontSize: 11)),
            ),
          ),
          Expanded(child: _MonitorScreen(editor: editor)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: <Widget>[
                Text(_timecode(t), style: _timecodeStyle(_timecodeBlue, size: 12)),
                const SizedBox(width: 10),
                Expanded(child: _MonitorScrubber(editor: editor, total: total)),
                const SizedBox(width: 10),
                Text(_timecode(total), style: _timecodeStyle(_muted, size: 12)),
              ],
            ),
          ),
          _Transport(editor: editor, total: total),
        ],
      ),
    );
  }
}

class _MonitorScreen extends StatelessWidget {
  const _MonitorScreen({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;
    final tracking = clip?.trackingData;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: _border),
            ),
            child: Stack(
              children: <Widget>[
                if (editor.isCameraActive)
                  const Positioned.fill(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.camera_alt_outlined, size: 36, color: _blue),
                          SizedBox(height: 8),
                          Text('Camera on', style: TextStyle(color: _text, fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                else
                  const Center(
                    child: Icon(Icons.videocam_outlined, size: 40, color: Colors.white24),
                  ),
                if (editor.activeDrawingStrokes.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PreviewCanvasDrawingPainter(
                        strokes: editor.activeDrawingStrokes,
                      ),
                    ),
                  ),
                if (tracking != null && tracking.isEnabled)
                  Positioned(
                    left: 24,
                    top: 60,
                    width: 100,
                    height: 100,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: _timecodeBlue, width: 1.5),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          color: _timecodeBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          child: Text(
                            tracking.targetName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
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
    );
  }
}

class _PreviewCanvasDrawingPainter extends CustomPainter {
  _PreviewCanvasDrawingPainter({required this.strokes});

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

      if (stroke.points.length > 1) {
        for (int i = 0; i < stroke.points.length - 1; i++) {
          canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _MonitorScrubber extends StatelessWidget {
  const _MonitorScrubber({required this.editor, required this.total});

  final EditorController editor;
  final double total;

  @override
  Widget build(BuildContext context) {
    final double t = _seconds(editor.playhead);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth;
        final double x = (t / total).clamp(0.0, 1.0) * w;

        void seekTo(double dx) =>
            _seek(editor, (dx / w).clamp(0.0, 1.0) * total);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
          child: SizedBox(
            height: 24,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  right: 0,
                  top: 10.5,
                  height: 3,
                  child: Container(color: _border),
                ),
                Positioned(
                  left: 0,
                  top: 10.5,
                  height: 3,
                  width: x,
                  child: Container(color: _blue),
                ),
                Positioned(
                  left: x - 5,
                  top: 7,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: _blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.editor, required this.total});

  final EditorController editor;
  final double total;

  Widget _button(IconData icon, VoidCallback onTap, {double size = 24}) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 40),
      icon: Icon(icon, size: size),
      color: _text,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double t = _seconds(editor.playhead);
    const double frame = 1 / _fps;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _button(Icons.skip_previous_rounded, () => _seek(editor, 0)),
          _button(Icons.chevron_left_rounded, () => _seek(editor, t - frame), size: 28),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 52, height: 40),
            icon: Icon(
              editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 34,
            ),
            color: Colors.white,
            tooltip: editor.isPlaying ? 'Pause' : 'Play',
            onPressed: editor.togglePlayback,
          ),
          _button(Icons.chevron_right_rounded, () => _seek(editor, t + frame), size: 28),
          _button(Icons.skip_next_rounded, () => _seek(editor, total)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Timeline
// -----------------------------------------------------------------------------

class _TrackRow {
  const _TrackRow({
    required this.label,
    required this.layer,
    required this.isAudio,
  });

  final String label;
  final int layer;
  final bool isAudio;
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.editor});

  final EditorController editor;

  static const double _height = 250;
  static const double _headerWidth = 84;
  static const double _rulerHeight = 24;
  static const double _trackHeight = 44;
  static const double _leftPad = 8;

  Color _colorFor(ClipType type) {
    return switch (type) {
      ClipType.video => const Color(0xFF6B5BD2),
      ClipType.image => const Color(0xFF2E8B9A),
      ClipType.audio => const Color(0xFF2F9E6B),
      ClipType.text => const Color(0xFFB33F7E),
      ClipType.caption => const Color(0xFFB33F7E),
      ClipType.drawing => const Color(0xFFB33F7E),
      ClipType.sticker => const Color(0xFFB33F7E),
    };
  }

  List<_TrackRow> _buildRows(List<TimelineClip> clips) {
    final List<int> videoLayers = clips
        .where((c) => c.clipType != ClipType.audio)
        .map<int>((c) => c.layerIndex)
        .toSet()
        .toList()
      ..sort();
    final List<int> audioLayers = clips
        .where((c) => c.clipType == ClipType.audio)
        .map<int>((c) => c.layerIndex)
        .toSet()
        .toList()
      ..sort();

    if (videoLayers.isEmpty) videoLayers.add(0);
    if (audioLayers.isEmpty) audioLayers.add(0);

    return <_TrackRow>[
      for (int i = videoLayers.length - 1; i >= 0; i--)
        _TrackRow(label: 'V${i + 1}', layer: videoLayers[i], isAudio: false),
      for (int i = 0; i < audioLayers.length; i++)
        _TrackRow(label: 'A${i + 1}', layer: audioLayers[i], isAudio: true),
    ];
  }

  List<TimelineClip> _clipsOf(List<TimelineClip> clips, _TrackRow row) {
    return clips
        .where((c) =>
            c.layerIndex == row.layer && (c.clipType == ClipType.audio) == row.isAudio)
        .toList();
  }

  void _toggleVisibility(List<TimelineClip> trackClips) {
    final bool allVisible = trackClips.every((c) => c.isVisible);
    for (final c in trackClips) {
      if (allVisible || !(c.isVisible)) {
        editor.toggleClipVisibility(c.id);
      }
    }
  }

  void _toggleLock(List<TimelineClip> trackClips) {
    final bool allLocked = trackClips.every((c) => c.isLocked);
    for (final c in trackClips) {
      if (allLocked || !(c.isLocked)) {
        editor.toggleClipLock(c.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TimelineClip> clips = editor.project.clips;
    final double pps = 24.0 * editor.zoom; // pixels per second
    final double total = _totalSeconds(editor);
    final List<_TrackRow> rows = _buildRows(clips);
    final double playheadX = _leftPad + _seconds(editor.playhead) * pps;

    return Container(
      height: _height,
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _line, width: 2)),
      ),
      child: Column(
        children: <Widget>[
          _buildHeader(context),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double viewport = c.maxWidth - _headerWidth;
                final double contentWidth = math.max(total * pps + 160, viewport);

                return SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Track headers
                      SizedBox(
                        width: _headerWidth,
                        child: Column(
                          children: <Widget>[
                            Container(
                              height: _rulerHeight,
                              decoration: const BoxDecoration(
                                color: _panelDark,
                                border: Border(
                                  bottom: BorderSide(color: _line),
                                  right: BorderSide(color: _line),
                                ),
                              ),
                            ),
                            for (final row in rows) _headerFor(clips, row),
                          ],
                        ),
                      ),

                      // Ruler + tracks
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentWidth,
                            child: Stack(
                              children: <Widget>[
                                Column(
                                  children: <Widget>[
                                    _buildRuler(pps, total, contentWidth),
                                    for (final row in rows)
                                      _buildTrack(clips, row, pps, contentWidth),
                                  ],
                                ),
                                Positioned(
                                  left: playheadX - 0.75,
                                  top: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    child: Container(width: 1.5, color: _blue),
                                  ),
                                ),
                                Positioned(
                                  left: playheadX - 7,
                                  top: 0,
                                  child: const IgnorePointer(
                                    child: Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 14,
                                      color: _blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double t = _seconds(editor.playhead);
    final TimelineClip? selected = editor.selectedClip;
    final bool hasClip = selected != null;
    final bool canSplit = selected != null &&
        editor.playhead > selected.start &&
        editor.playhead < selected.end;

    Widget tool(IconData icon, String tip, VoidCallback? onTap, {bool active = false}) {
      return IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: Icon(icon, size: 18),
        tooltip: tip,
        color: active ? _blue : _text,
        disabledColor: Colors.white24,
        onPressed: onTap,
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _panelDark,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: <Widget>[
          Text(_timecode(t), style: _timecodeStyle(_timecodeBlue, size: 14)),
          const SizedBox(width: 8),
          tool(Icons.near_me_outlined, 'Selection', () {}, active: true),
          tool(
            Icons.content_cut_rounded,
            'Razor (split)',
            canSplit ? editor.splitSelectedClip : null,
          ),
          tool(
            Icons.delete_outline_rounded,
            'Delete',
            hasClip ? editor.deleteSelectedClip : null,
          ),
          const Spacer(),
          const Icon(Icons.zoom_out_rounded, size: 16, color: _muted),
          SizedBox(
            width: 96,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: _text,
                inactiveTrackColor: _border,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: editor.zoom.clamp(0.5, 3.0).toDouble(),
                min: 0.5,
                max: 3.0,
                onChanged: (double v) => editor.setZoom(v),
              ),
            ),
          ),
          const Icon(Icons.zoom_in_rounded, size: 16, color: _muted),
        ],
      ),
    );
  }

  Widget _headerFor(List<TimelineClip> clips, _TrackRow row) {
    final List<TimelineClip> trackClips = _clipsOf(clips, row);
    final bool allVisible = trackClips.every((c) => c.isVisible);
    final bool anyLocked = trackClips.any((c) => c.isLocked);

    return Container(
      height: _trackHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF2B2B2B),
        border: Border(
          bottom: BorderSide(color: Color(0xFF151515)),
          right: BorderSide(color: _line),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF3C3C3C),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              row.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          _MiniToggle(
            icon: row.isAudio
                ? (allVisible ? Icons.volume_up_rounded : Icons.volume_off_rounded)
                : (allVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded),
            color: allVisible ? _text : Colors.white24,
            onTap: trackClips.isEmpty ? null : () => _toggleVisibility(trackClips),
          ),
          _MiniToggle(
            icon: anyLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: anyLocked ? _blue : Colors.white24,
            onTap: trackClips.isEmpty ? null : () => _toggleLock(trackClips),
          ),
        ],
      ),
    );
  }

  Widget _buildRuler(double pps, double total, double contentWidth) {
    void seekFrom(double dx) => _seek(editor, (dx - _leftPad) / pps);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => seekFrom(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => seekFrom(d.localPosition.dx),
      child: Container(
        height: _rulerHeight,
        decoration: const BoxDecoration(
          color: _panelDark,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: CustomPaint(
          size: Size(contentWidth, _rulerHeight),
          painter: _RulerPainter(pps: pps, seconds: total + 20, leftPad: _leftPad),
        ),
      ),
    );
  }

  Widget _buildTrack(
    List<TimelineClip> clips,
    _TrackRow row,
    double pps,
    double contentWidth,
  ) {
    final List<TimelineClip> trackClips = _clipsOf(clips, row);

    return Container(
      height: _trackHeight,
      width: contentWidth,
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(bottom: BorderSide(color: Color(0xFF151515))),
      ),
      child: Stack(
        children: <Widget>[
          for (final clip in trackClips)
            Positioned(
              left: _leftPad + _seconds(clip.start) * pps,
              top: 3,
              bottom: 3,
              width: math.max(40.0, _seconds(clip.duration) * pps - 1),
              child: _ClipBlock(
                editor: editor,
                clip: clip,
                color: _colorFor(clip.clipType),
                isAudio: row.isAudio,
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 22,
        height: 40,
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.editor,
    required this.clip,
    required this.color,
    required this.isAudio,
  });

  final EditorController editor;
  final TimelineClip clip;
  final Color color;
  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    final bool isSelected = editor.selectedClipId == clip.id;
    final bool isVisible = clip.isVisible;
    final bool isLocked = clip.isLocked;
    final ClipType type = clip.clipType;

    final _BodyKind kind = isAudio
        ? _BodyKind.waveform
        : (type == ClipType.video || type == ClipType.image)
            ? _BodyKind.filmstrip
            : _BodyKind.solid;

    return GestureDetector(
      onTap: () => editor.selectClip(clip.id),
      child: Opacity(
        opacity: isVisible ? 1.0 : 0.35,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.black26,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClipBodyPainter(
                      kind: kind,
                      seed: clip.id.hashCode % 97,
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  right: 4,
                  top: 0,
                  height: 14,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          clip.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isLocked)
                        const Icon(Icons.lock_rounded, size: 10, color: Colors.white70),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _BodyKind { filmstrip, waveform, solid }

class _ClipBodyPainter extends CustomPainter {
  _ClipBodyPainter({required this.kind, required this.seed});

  final _BodyKind kind;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    const double strip = 14;

    // Label strip
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, strip),
      Paint()..color = Colors.black.withAlpha(60),
    );

    final double bodyHeight = size.height - strip;
    if (bodyHeight <= 0) return;

    switch (kind) {
      case _BodyKind.filmstrip:
        final Paint frame = Paint()..color = Colors.white.withAlpha(30);
        final double frameWidth = math.max(bodyHeight * 1.2, 16);
        for (double x = 0; x < size.width; x += frameWidth + 2) {
          canvas.drawRect(Rect.fromLTWH(x, strip + 1, frameWidth, bodyHeight - 2), frame);
        }
      case _BodyKind.waveform:
        final Paint wave = Paint()
          ..color = Colors.white.withAlpha(160)
          ..strokeWidth = 1.5;
        final double midY = strip + bodyHeight / 2;
        for (double x = 2; x < size.width; x += 3) {
          final double a = (math.sin(x * 0.35 + seed) * 0.5 + 0.5) *
              (0.35 + 0.65 * (((x.toInt() * 7 + seed) % 11) / 11));
          final double h = a * (bodyHeight - 4);
          canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), wave);
        }
      case _BodyKind.solid:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ClipBodyPainter old) =>
      old.kind != kind || old.seed != seed;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pps,
    required this.seconds,
    required this.leftPad,
  });

  final double pps;
  final double seconds;
  final double leftPad;

  @override
  void paint(Canvas canvas, Size size) {
    const List<double> steps = <double>[1, 2, 5, 10, 15, 30, 60, 120, 300];
    final double step = steps.firstWhere(
      (s) => s * pps >= 64,
      orElse: () => steps.last,
    );

    final Paint major = Paint()
      ..color = _muted
      ..strokeWidth = 1;
    final Paint minor = Paint()
      ..color = _border
      ..strokeWidth = 1;

    final int count = (seconds / step).ceil();
    for (int i = 0; i <= count; i++) {
      final double t = i * step;
      final double x = leftPad + t * pps;
      if (x > size.width) break;

      canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height), major);

      for (int j = 1; j < 5; j++) {
        final double mx = x + j * step * pps / 5;
        canvas.drawLine(Offset(mx, size.height - 5), Offset(mx, size.height), minor);
      }

      final int whole = t.round();
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: '${whole ~/ 60}:${_two(whole % 60)}',
          style: const TextStyle(color: _muted, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 3, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps || old.seconds != seconds || old.leftPad != leftPad;
}

// -----------------------------------------------------------------------------
// Tool dock
// -----------------------------------------------------------------------------

class _ToolDock extends StatelessWidget {
  const _ToolDock({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: _panelDark,
        border: Border(top: BorderSide(color: _line, width: 2)),
      ),
      child: Row(
        children: <Widget>[
          _ToolButton(
            icon: Icons.brush_rounded,
            label: 'Draw',
            onTap: () => VectorDrawingSheet.show(context),
          ),
          _ToolButton(
            icon: Icons.title_rounded,
            label: 'Text',
            onTap: () => TextAnimationSheet.show(context),
          ),
          _ToolButton(
            icon: Icons.tune_rounded,
            label: 'Color',
            onTap: () => ColorGradingSheet.show(context),
          ),
          _ToolButton(
            icon: Icons.graphic_eq_rounded,
            label: 'Audio',
            onTap: () => AudioToolsSheet.show(context),
          ),
          _ToolButton(
            icon: Icons.center_focus_strong_rounded,
            label: 'Track',
            onTap: () => CameraTrackingPanel.show(context),
          ),
          _ToolButton(
            icon: Icons.subtitles_outlined,
            label: 'Captions',
            onTap: editor.generateAutoCaptions,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 22, color: _text),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: _text, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}