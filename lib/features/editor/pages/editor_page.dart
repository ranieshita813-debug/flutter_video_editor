import 'dart:math' as math;

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

// -----------------------------------------------------------------------------
// Design tokens
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF0B0D12);
const Color _panel = Color(0xFF12151C);
const Color _elevated = Color(0xFF181C25);
const Color _border = Color(0xFF232836);
const Color _text = Color(0xFFE8EAF0);
const Color _muted = Color(0xFF8B93A7);
const Color _violet = Color(0xFF7C5CFF);
const Color _cyan = Color(0xFF22D3EE);
const Color _pink = Color(0xFFD4457E);

const LinearGradient _accentGradient = LinearGradient(
  colors: <Color>[_violet, _cyan],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

const double _fps = 30;

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

double _seconds(Duration value) => value.inMilliseconds / 1000.0;

double _totalSeconds(EditorController editor) =>
    math.max(_seconds(editor.project.totalDuration), 1.0);

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _text, size: 28),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  editor.project.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _text,
                  ),
                ),
                const Text(
                  '1080p · 30 fps',
                  style: TextStyle(fontSize: 10.5, color: _muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 22),
            color: _text,
            disabledColor: Colors.white24,
            tooltip: 'Undo',
            onPressed: editor.canUndo ? editor.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded, size: 22),
            color: _text,
            disabledColor: Colors.white24,
            tooltip: 'Redo',
            onPressed: editor.canRedo ? editor.redo : null,
          ),
          const SizedBox(width: 4),
          _GradientPill(
            label: 'Export',
            icon: Icons.ios_share_rounded,
            onTap: () => ExportModal.show(context),
          ),
        ],
      ),
    );
  }
}

class _GradientPill extends StatelessWidget {
  const _GradientPill({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: _accentGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _violet.withAlpha(90),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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

    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: editor.togglePlayback,
                  child: _MonitorScreen(editor: editor, time: t, total: total),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _MonitorScrubber(editor: editor, total: total),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonitorScreen extends StatelessWidget {
  const _MonitorScreen({
    required this.editor,
    required this.time,
    required this.total,
  });

  final EditorController editor;
  final double time;
  final double total;

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(150),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: _timecodeStyle(color, size: 11)),
      );

  @override
  Widget build(BuildContext context) {
    final clip = editor.selectedClip;
    final tracking = clip?.trackingData;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: <Widget>[
          if (editor.isCameraActive)
            const Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.camera_alt_rounded, size: 36, color: _cyan),
                    SizedBox(height: 8),
                    Text('Camera on', style: TextStyle(color: _text, fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: editor.isPlaying ? 0 : 1,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(110),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
                ),
              ),
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
                  border: Border.all(color: _cyan, width: 1.5),
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    color: _cyan,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    child: Text(
                      tracking.targetName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF04202B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(left: 10, top: 10, child: _chip(_timecode(time), _cyan)),
          Positioned(right: 10, top: 10, child: _chip(_timecode(total), _muted)),
        ],
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

        void seekTo(double dx) => _seek(editor, (dx / w).clamp(0.0, 1.0) * total);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
          child: SizedBox(
            height: 20,
            child: Stack(
              children: <Widget>[
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2.5,
                  child: ColoredBox(color: Colors.white24),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  height: 2.5,
                  width: x,
                  child: const ColoredBox(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
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

class _TimelinePanel extends StatefulWidget {
  const _TimelinePanel({required this.editor});

  final EditorController editor;

  @override
  State<_TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<_TimelinePanel> {
  static const double _rulerHeight = 30;
  static const double _laneHeight = 76;
  static const double _leftPad = 14;
  static const double _maxTracksHeight = 250;

  bool _open = true;
  bool _loop = false;

  EditorController get editor => widget.editor;

  String _clock(double seconds) {
    final int whole = math.max(seconds, 0).floor();
    return '${whole ~/ 60}:${_two(whole % 60)}';
  }

  Color _colorFor(ClipType type) {
    return switch (type) {
      ClipType.video => const Color(0xFF5B43D6),
      ClipType.image => const Color(0xFF3B6FE0),
      ClipType.audio => const Color(0xFF14A38B),
      ClipType.text => _pink,
      ClipType.caption => _pink,
      ClipType.drawing => const Color(0xFFE08A2E),
      ClipType.sticker => const Color(0xFF2BA3C7),
    };
  }

  /// Audio lanes first (top), then video/overlay lanes with the top layer first.
  List<_TrackRow> _rows(List<TimelineClip> clips, {required bool audio}) {
    final List<int> layers = clips
        .where((c) => (c.clipType == ClipType.audio) == audio)
        .map<int>((c) => c.layerIndex)
        .toSet()
        .toList()
      ..sort();
    if (layers.isEmpty) layers.add(0);
    final Iterable<int> ordered = audio ? layers : layers.reversed;
    return <_TrackRow>[
      for (final int l in ordered) _TrackRow(label: '', layer: l, isAudio: audio),
    ];
  }

  List<TimelineClip> _clipsOf(List<TimelineClip> clips, _TrackRow row) {
    return clips
        .where((c) =>
            c.layerIndex == row.layer && (c.clipType == ClipType.audio) == row.isAudio)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<TimelineClip> clips = editor.project.clips;
    final double total = _totalSeconds(editor);
    final double t = _seconds(editor.playhead);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _header(t, total),
          _TimelineToolbar(editor: editor),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? _tracks(clips, total)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _header(double t, double total) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            Text(
              '${_clock(t)} / ${_clock(total)}',
              style: _timecodeStyle(_text, size: 15),
            ),
            const Spacer(),
            GestureDetector(
              onTap: editor.togglePlayback,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(28),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  editor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 28,
                  color: _text,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.repeat_rounded, size: 24),
              color: _loop ? _violet : _text,
              tooltip: 'Loop',
              onPressed: () => setState(() => _loop = !_loop),
            ),
            const Spacer(),
            IconButton(
              icon: AnimatedRotation(
                turns: _open ? 0 : 0.5,
                duration: const Duration(milliseconds: 220),
                child: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              ),
              color: _text,
              tooltip: _open ? 'Collapse timeline' : 'Expand timeline',
              onPressed: () => setState(() => _open = !_open),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tracks(List<TimelineClip> clips, double total) {
    final double pps = 24.0 * editor.zoom;
    final List<_TrackRow> audio = _rows(clips, audio: true);
    final List<_TrackRow> visual = _rows(clips, audio: false);
    final double playheadX = _leftPad + _seconds(editor.playhead) * pps;
    final double contentHeight =
        _rulerHeight + (audio.length + visual.length) * _laneHeight + 1;

    // "+" tile sits after the end of the clips on the lowest video lane.
    double visualEnd = 0;
    for (final c in clips.where((c) => c.clipType != ClipType.audio)) {
      visualEnd = math.max(visualEnd, _seconds(c.end));
    }

    return SizedBox(
      height: math.min(contentHeight, _maxTracksHeight),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double contentWidth = math.max(total * pps + 160, c.maxWidth);

          return SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: Stack(
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        _buildRuler(pps, total, contentWidth),
                        for (final row in audio)
                          _lane(clips, row, pps, contentWidth, null),
                        Container(height: 1, color: _border),
                        for (int i = 0; i < visual.length; i++)
                          _lane(
                            clips,
                            visual[i],
                            pps,
                            contentWidth,
                            i == visual.length - 1 ? visualEnd : null,
                          ),
                      ],
                    ),
                    Positioned(
                      left: playheadX - 1,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: _violet,
                            boxShadow: <BoxShadow>[
                              BoxShadow(color: _violet.withAlpha(150), blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRuler(double pps, double total, double contentWidth) {
    void seekFrom(double dx) => _seek(editor, (dx - _leftPad) / pps);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => seekFrom(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => seekFrom(d.localPosition.dx),
      child: SizedBox(
        height: _rulerHeight,
        width: contentWidth,
        child: CustomPaint(
          painter: _RulerPainter(pps: pps, seconds: total + 20, leftPad: _leftPad),
        ),
      ),
    );
  }

  Widget _lane(
    List<TimelineClip> clips,
    _TrackRow row,
    double pps,
    double contentWidth,
    double? addTileAfter,
  ) {
    final List<TimelineClip> trackClips = _clipsOf(clips, row);

    return SizedBox(
      height: _laneHeight,
      width: contentWidth,
      child: Stack(
        children: <Widget>[
          for (final clip in trackClips)
            Positioned(
              left: _leftPad + _seconds(clip.start) * pps,
              top: 8,
              bottom: 8,
              width: math.max(40.0, _seconds(clip.duration) * pps - 2),
              child: _ClipBlock(
                editor: editor,
                clip: clip,
                color: _colorFor(clip.clipType),
                isAudio: row.isAudio,
              ),
            ),
          if (addTileAfter != null)
            Positioned(
              left: _leftPad + addTileAfter * pps + 8,
              top: 8,
              bottom: 8,
              width: 72,
              child: Material(
                color: Colors.white.withAlpha(14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: _border),
                ),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () => ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Add media is coming soon'),
                        duration: Duration(seconds: 1),
                      ),
                    ),
                  child: const Center(
                    child: Icon(Icons.add_rounded, size: 28, color: _text),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineToolbar extends StatefulWidget {
  const _TimelineToolbar({required this.editor});

  final EditorController editor;

  @override
  State<_TimelineToolbar> createState() => _TimelineToolbarState();
}

class _TimelineToolbarState extends State<_TimelineToolbar> {
  // Local UI state for editing modes (hook these to the controller when ready).
  bool _snap = true;
  bool _ripple = false;
  bool _link = true;

  Widget _btn(
    IconData icon,
    String tip,
    VoidCallback? onTap, {
    bool active = false,
  }) {
    final bool enabled = onTap != null;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: active ? _violet.withAlpha(80) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 21,
            color: !enabled ? Colors.white24 : (active ? Colors.white : _text),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: _border,
      );

  @override
  Widget build(BuildContext context) {
    final EditorController ed = widget.editor;
    final TimelineClip? selected = ed.selectedClip;
    final bool canSplit = selected != null &&
        ed.playhead > selected.start &&
        ed.playhead < selected.end;
    final double zoom = ed.zoom.clamp(0.5, 3.0).toDouble();

    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _elevated,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _timecode(_seconds(ed.playhead)),
                style: _timecodeStyle(_cyan, size: 12),
              ),
            ),
            _divider(),
            _btn(Icons.near_me_rounded, 'Select', () {}, active: true),
            _btn(Icons.content_cut_rounded, 'Split at playhead',
                canSplit ? ed.splitSelectedClip : null),
            _btn(Icons.delete_rounded, 'Delete',
                selected != null ? ed.deleteSelectedClip : null),
            _divider(),
            _btn(Icons.vertical_align_center_rounded, 'Snapping',
                () => setState(() => _snap = !_snap),
                active: _snap),
            _btn(Icons.compare_arrows_rounded, 'Ripple edit',
                () => setState(() => _ripple = !_ripple),
                active: _ripple),
            _btn(Icons.link_rounded, 'Link audio and video',
                () => setState(() => _link = !_link),
                active: _link),
            _divider(),
            _btn(Icons.zoom_out_rounded, 'Zoom out',
                () => ed.setZoom((zoom - 0.25).clamp(0.5, 3.0).toDouble())),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: _violet,
                  inactiveTrackColor: _border,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: zoom,
                  min: 0.5,
                  max: 3.0,
                  onChanged: (double v) => ed.setZoom(v),
                ),
              ),
            ),
            _btn(Icons.zoom_in_rounded, 'Zoom in',
                () => ed.setZoom((zoom + 0.25).clamp(0.5, 3.0).toDouble())),
            _btn(Icons.fit_screen_rounded, 'Reset zoom', () => ed.setZoom(1.0)),
          ],
        ),
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
        width: 20,
        height: 40,
        child: Icon(icon, size: 15, color: color),
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
      onLongPress: () => editor.toggleClipLock(clip.id),
      onDoubleTap: () => editor.toggleClipVisibility(clip.id),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: isVisible ? 1.0 : 0.35,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white12,
              width: isSelected ? 1.5 : 0.5,
            ),
            boxShadow: isSelected
                ? <BoxShadow>[BoxShadow(color: color.withAlpha(140), blurRadius: 10)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ClipBodyPainter(
                      kind: kind,
                      seed: clip.id.hashCode % 97,
                      peaks: kind == _BodyKind.waveform ? _peaksFor(clip) : null,
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  top: 0,
                  height: 18,
                  child: Row(
                    children: <Widget>[
                      if (isAudio)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: Icon(Icons.music_note_rounded, size: 13, color: Colors.white),
                        ),
                      Expanded(
                        child: Text(
                          clip.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isLocked)
                        const Icon(Icons.lock_rounded, size: 12, color: Colors.white70),
                    ],
                  ),
                ),
                if (isSelected) ...<Widget>[
                  Positioned(left: 0, top: 0, bottom: 0, child: _TrimHandle()),
                  Positioned(right: 0, top: 0, bottom: 0, child: _TrimHandle()),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      color: Colors.white.withAlpha(200),
      alignment: Alignment.center,
      child: Container(width: 1.5, height: 12, color: Colors.black38),
    );
  }
}

enum _BodyKind { filmstrip, waveform, solid }

/// Reads real waveform peaks from the clip if the model provides them
/// (a `List<num> waveform` field on TimelineClip). Returns null otherwise.
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
  _ClipBodyPainter({required this.kind, required this.seed, this.peaks});

  final _BodyKind kind;
  final int seed;

  /// Normalized (0..1) amplitude peaks of the real audio, or null if unavailable.
  final List<double>? peaks;

  @override
  void paint(Canvas canvas, Size size) {
    const double strip = 18;

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
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, strip + 1, frameWidth, bodyHeight - 2),
              const Radius.circular(3),
            ),
            frame,
          );
        }
      case _BodyKind.waveform:
        final Paint wave = Paint()
          ..color = Colors.white.withAlpha(190)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        final double midY = strip + bodyHeight / 2;
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
          final double h = math.max(2.0, a * (bodyHeight - 8));
          canvas.drawLine(Offset(x, midY - h / 2), Offset(x, midY + h / 2), wave);
        }
      case _BodyKind.solid:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ClipBodyPainter old) =>
      old.kind != kind || old.seed != seed || !identical(old.peaks, peaks);
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

      canvas.drawLine(Offset(x, size.height - 9), Offset(x, size.height), major);

      for (int j = 1; j < 5; j++) {
        final double mx = x + j * step * pps / 5;
        canvas.drawLine(Offset(mx, size.height - 4), Offset(mx, size.height), minor);
      }

      final int whole = t.round();
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: '${whole ~/ 60}:${_two(whole % 60)}',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 4, 4));
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps || old.seconds != seconds || old.leftPad != leftPad;
}

// -----------------------------------------------------------------------------
// Tool dock (full-width, scrollable)
// -----------------------------------------------------------------------------

class _DockItem {
  const _DockItem(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class _ToolDock extends StatelessWidget {
  const _ToolDock({required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    void soon(String name) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$name is coming soon'),
            duration: const Duration(seconds: 1),
          ),
        );
    }

    final TimelineClip? sel = editor.selectedClip;
    final bool canSplit =
        sel != null && editor.playhead > sel.start && editor.playhead < sel.end;

    final List<_DockItem> items = <_DockItem>[
      _DockItem(Icons.content_cut_rounded, 'Split',
          canSplit ? editor.splitSelectedClip : null),
      _DockItem(Icons.delete_rounded, 'Delete',
          sel != null ? editor.deleteSelectedClip : null),
      _DockItem(Icons.brush_rounded, 'Draw', () => VectorDrawingSheet.show(context)),
      _DockItem(Icons.title_rounded, 'Text', () => TextAnimationSheet.show(context)),
      _DockItem(Icons.tune_rounded, 'Color', () => ColorGradingSheet.show(context)),
      _DockItem(Icons.graphic_eq_rounded, 'Audio', () => AudioToolsSheet.show(context)),
      _DockItem(Icons.center_focus_strong_rounded, 'Track',
          () => CameraTrackingPanel.show(context)),
      _DockItem(Icons.subtitles_rounded, 'Captions', editor.generateAutoCaptions),
      _DockItem(Icons.speed_rounded, 'Speed', () => soon('Speed')),
      _DockItem(Icons.crop_rounded, 'Crop', () => soon('Crop')),
      _DockItem(Icons.auto_awesome_rounded, 'Filters', () => soon('Filters')),
      _DockItem(Icons.emoji_emotions_rounded, 'Stickers', () => soon('Stickers')),
    ];

    return Container(
      height: 62,
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) => _ToolButton(item: items[i]),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.item});

  final _DockItem item;

  @override
  Widget build(BuildContext context) {
    final Color color = item.onTap == null ? Colors.white24 : _text;

    return SizedBox(
      width: 68,
      child: InkWell(
        onTap: item.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(item.icon, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              style: TextStyle(color: color == _text ? _muted : color, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}