import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/audio_tools_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_settings_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/camera_tracking_panel.dart';
import 'package:flutter_video_editor/features/editor/widgets/color_grading_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/crop_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/effects_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/elements_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/keyframe_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/mask_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/plugins_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/stickers_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/text_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/vector_drawing_sheet.dart';

// ----------------------------------------------------------------------------
// Tokens
// ----------------------------------------------------------------------------
const Color _bg = Color(0xFF000000);
const Color _surface = Color(0xFF101014);
const Color _muted = Color(0xFF9A9AA3);
const Color _textTrack = Color(0xFF2A2440);
const Color _fxTrack = Color(0xFF3A2C1C);
const Color _drawTrack = Color(0xFF1C3A30);
const Color _audioTrack = Color(0xFF23333A);
const Color _accent = Color(0xFF5B8CFF);
const Color _divider = Color(0xFF1E1E22);

const double _playheadFrac = 0.42;
const int _fps = 30;

double _seconds(Duration v) => v.inMilliseconds / 1000.0;
double _totalSeconds(EditorController e) =>
    math.max(_seconds(e.project.totalDuration), 1.0);
String _two(int n) => n.toString().padLeft(2, '0');

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

bool _isImagePath(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.jpg') ||
      l.endsWith('.jpeg') ||
      l.endsWith('.png') ||
      l.endsWith('.webp') ||
      l.endsWith('.heic') ||
      l.endsWith('.gif');
}

void _tap() => HapticFeedback.selectionClick();

// ----------------------------------------------------------------------------
// Inline tools (CapCut style)
// ----------------------------------------------------------------------------
enum _Tool {
  audio('Audio', Icons.volume_up_outlined),
  text('Text', Icons.title_rounded),
  stickers('Stickers', Icons.emoji_emotions_rounded),
  filters('Filters', Icons.filter_vintage_rounded),
  effects('Effects', Icons.local_fire_department_outlined),
  adjust('Adjust', Icons.layers_outlined),
  crop('Crop', Icons.crop_rounded),
  speed('Speed', Icons.speed_rounded),
  elements('Elements', Icons.shape_line_outlined),
  draw('Draw', Icons.brush_rounded),
  mask('Mask', Icons.masks_outlined),
  keyframes('Keyframes', Icons.diamond_outlined),
  camera('Camera', Icons.camera_outlined),
  track('Track', Icons.center_focus_strong_rounded),
  plugins('Plug-ins', Icons.extension_outlined);

  const _Tool(this.title, this.icon);
  final String title;
  final IconData icon;

  Widget get body => switch (this) {
        _Tool.audio => const AudioToolsSheet(),
        _Tool.text => const TextAnimationSheet(),
        _Tool.stickers => const StickersSheet(),
        _Tool.filters => const EffectsSheet(isFilterMode: true),
        _Tool.effects => const EffectsSheet(isFilterMode: false),
        _Tool.adjust => const ColorGradingSheet(),
        _Tool.crop => const CropSheet(),
        _Tool.speed => const SpeedSheet(),
        _Tool.elements => const ElementsSheet(),
        _Tool.draw => const VectorDrawingSheet(),
        _Tool.mask => const MaskSheet(),
        _Tool.keyframes => const KeyframeSheet(),
        _Tool.camera => const CameraSettingsSheet(),
        _Tool.track => const CameraTrackingPanel(),
        _Tool.plugins => const PluginsSheet(),
      };
}

// ----------------------------------------------------------------------------
// Page
//
// UX changes:
//  - Tool panel is resizable (drag the grabber) and cross-fades between tools.
//  - Timeline shrinks to a compact height while a tool is open so the preview
//    keeps most of the screen; hidden entirely while the keyboard is up.
//  - Layout is computed from real available height (no overflow on small
//    phones / split-screen).
// ----------------------------------------------------------------------------
class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  _Tool? _tool;
  double _frac = 0.32; // panel height as a fraction of the screen
  bool _dragging = false;

  void _open(_Tool t) {
    _tap();
    setState(() => _tool = t);
  }

  void _close() => setState(() => _tool = null);

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final bool keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: _tool == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: LayoutBuilder(builder: (context, c) {
          final double panelH =
              math.min(c.maxHeight * _frac, c.maxHeight * 0.65).clamp(160.0, 520.0).toDouble();
          return Column(
            children: <Widget>[
              Expanded(child: _Preview(editor: editor)),
              if (!(keyboard && _tool != null))
                _Timeline(editor: editor, compact: _tool != null),
              AnimatedSize(
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (cur, prev) => Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[...prev, if (cur != null) cur],
                  ),
                  child: _tool == null
                      ? _Toolbar(key: const ValueKey('bar'), onOpen: _open)
                      : _ToolPanel(
                          key: ValueKey<_Tool>(_tool!),
                          tool: _tool!,
                          height: panelH,
                          onClose: _close,
                          onResize: (dy) => setState(() {
                            _frac = (_frac - dy / c.maxHeight).clamp(0.22, 0.6).toDouble();
                          }),
                          onDrag: (v) => setState(() => _dragging = v),
                        ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    super.key,
    required this.tool,
    required this.height,
    required this.onClose,
    required this.onResize,
    required this.onDrag,
  });
  final _Tool tool;
  final double height;
  final VoidCallback onClose;
  final ValueChanged<double> onResize;
  final ValueChanged<bool> onDrag;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: _divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: <Widget>[
              // Header doubles as a drag handle to resize the panel.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => onDrag(true),
                onVerticalDragUpdate: (d) => onResize(d.delta.dy),
                onVerticalDragEnd: (_) => onDrag(false),
                onVerticalDragCancel: () => onDrag(false),
                child: SizedBox(
                  height: 52,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 16),
                            Icon(tool.icon, color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            Text(tool.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Done',
                              icon: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
                              onPressed: () {
                                _tap();
                                onClose();
                              },
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: _divider),
              Expanded(
                child: ClipRect(
                  child: Material(type: MaterialType.transparency, child: tool.body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Video Player Preview
//
// FIX: the previous clip's last frame now stays on screen while the next
// source loads (no black/spinner flash on every cut), the controller swap
// happens only once the new one is initialised, and there is no synchronous
// file IO inside build().
// ----------------------------------------------------------------------------
class _VideoPlayerPreview extends StatefulWidget {
  const _VideoPlayerPreview({required this.editor});
  final EditorController editor;

  @override
  State<_VideoPlayerPreview> createState() => _VideoPlayerPreviewState();
}

class _VideoPlayerPreviewState extends State<_VideoPlayerPreview> {
  VideoPlayerController? _vc;
  String? _path;
  bool _loading = false;
  bool _failed = false;
  bool _isImg = false;
  int _token = 0;
  bool _busy = false;
  bool _dirty = false;

  EditorController get _e => widget.editor;

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditor);
    _onEditor();
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerPreview old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_onEditor);
      widget.editor.addListener(_onEditor);
      _onEditor();
    }
  }

  @override
  void dispose() {
    _e.removeListener(_onEditor);
    _token++;
    _vc?.dispose();
    _vc = null;
    super.dispose();
  }

  void _onEditor() {
    if (_busy) {
      _dirty = true;
      return;
    }
    _run();
  }

  Future<void> _run() async {
    _busy = true;
    try {
      do {
        _dirty = false;
        await _apply();
      } while (_dirty && mounted);
    } finally {
      _busy = false;
    }
  }

  Future<void> _apply() async {
    if (!mounted) return;
    final clip = _e.activeVideoClip;
    final String? path = clip?.sourcePath;

    if (path != _path) await _load(path);

    final c = _vc;
    if (!mounted || c == null || clip == null || _loading || !c.value.isInitialized) return;

    // If your TimelineClip has a trim offset, add it:
    //   final local = _e.playhead - clip.start + clip.trimStart;
    Duration local = _e.playhead - clip.start;
    if (local.isNegative) local = Duration.zero;
    final Duration dur = c.value.duration;
    if (local > dur) local = dur;

    final Duration drift = (c.value.position - local).abs();

    if (_e.isPlaying) {
      if (!c.value.isPlaying) {
        await c.seekTo(local);
        await c.play();
      } else if (drift > const Duration(milliseconds: 400)) {
        await c.seekTo(local);
      }
    } else {
      if (c.value.isPlaying) await c.pause();
      if (drift > const Duration(milliseconds: 40)) await c.seekTo(local);
    }
  }

  Future<void> _swap(VideoPlayerController? next, {bool failed = false}) async {
    if (!mounted) {
      await next?.dispose();
      return;
    }
    final old = _vc;
    setState(() {
      _vc = next;
      _loading = false;
      _failed = failed;
    });
    if (old != null) {
      // Let the tree drop the old VideoPlayer before disposing its controller.
      await WidgetsBinding.instance.endOfFrame;
      await old.dispose();
    }
  }

  Future<void> _load(String? path) async {
    final int token = ++_token;
    _path = path;
    final bool empty = path == null || path.isEmpty;
    _isImg = !empty && _isImagePath(path);

    if (empty || _isImg) {
      await _swap(null);
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }

    final file = File(path);
    if (!await file.exists()) {
      if (token == _token) await _swap(null, failed: true);
      return;
    }

    final c = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await c.initialize();
      await c.setLooping(false);
    } catch (_) {
      await c.dispose();
      if (token == _token) await _swap(null, failed: true);
      return;
    }

    if (!mounted || token != _token) {
      await c.dispose();
      return;
    }
    await _swap(c);
  }

  Widget _placeholder(String text, {IconData icon = Icons.movie_outlined}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_loading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
            )
          else
            Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = _e.activeVideoClip;
    final c = _vc;
    final bool ready = c != null && c.value.isInitialized;

    Widget child;
    if (_isImg && _path != null) {
      child = Image.file(
        File(_path!),
        key: ValueKey<String>(_path!),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            _placeholder('Can\'t open this image', icon: Icons.broken_image_outlined),
      );
    } else if (ready) {
      child = AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
    } else if (_failed) {
      child = _placeholder('Can\'t play this file', icon: Icons.error_outline_rounded);
    } else {
      child = _placeholder(clip?.label ?? 'Add media to start editing');
    }

    return Container(
      color: const Color(0xFF07080B),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: <Widget>[
          Center(child: child),
          // Subtle spinner on top of the held frame while the next clip loads.
          if (_loading && ready)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              ),
            ),
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

  Widget _step(IconData i, int dir, String tip) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(i, color: Colors.white, size: 26),
        onPressed: () {
          _tap();
          _seek(editor, _seconds(editor.playhead) + dir / _fps);
        },
      );

  Widget _roundBtn(IconData i, String tip, VoidCallback onTap, {double size = 40}) => Semantics(
        button: true,
        label: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _tap();
            onTap();
          },
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: Icon(i, color: Colors.white, size: 20),
          ),
        ),
      );

  Widget _scrim({required bool top}) => Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: top ? 110 : 120,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: const <Color>[Color(0xB3000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: editor.togglePlayback,
          child: _VideoPlayerPreview(editor: editor),
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
                        decoration:
                            BoxDecoration(border: Border.all(color: _accent, width: 1.5)),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: _accent,
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
        _scrim(top: true),
        _scrim(top: false),
        // Top bar: back on the left, resolution + export on the right.
        SafeArea(
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  _roundBtn(Icons.arrow_back_ios_new_rounded, 'Back',
                      () => Navigator.of(context).maybePop()),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text('1080p',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        _tap();
                        ExportModal.show(context);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.ios_share_rounded, color: Colors.black, size: 16),
                            SizedBox(width: 6),
                            Text('Export',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom controls
        Positioned(
          left: 12,
          right: 12,
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Selector<EditorController, Duration>(
                selector: (_, e) => e.playhead,
                builder: (_, p, __) => Text.rich(
                  textAlign: TextAlign.center,
                  TextSpan(children: <TextSpan>[
                    TextSpan(
                        text: _tc(_seconds(p)),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                    TextSpan(
                        text: '  /  ${_tc(_totalSeconds(editor))}',
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  _roundBtn(Icons.undo_rounded, 'Undo', editor.undo),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _step(Icons.skip_previous_rounded, -1, 'Previous frame'),
                        const SizedBox(width: 6),
                        Selector<EditorController, bool>(
                          selector: (_, e) => e.isPlaying,
                          builder: (_, playing, __) => Semantics(
                            button: true,
                            label: playing ? 'Pause' : 'Play',
                            child: GestureDetector(
                              onTap: () {
                                _tap();
                                editor.togglePlayback();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                    color: Colors.white, shape: BoxShape.circle),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(
                                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      key: ValueKey<bool>(playing),
                                      color: Colors.black,
                                      size: 30),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _step(Icons.skip_next_rounded, 1, 'Next frame'),
                      ],
                    ),
                  ),
                  _roundBtn(Icons.redo_rounded, 'Redo', editor.redo),
                ],
              ),
            ],
          ),
        ),
      ],
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
  const _Timeline({required this.editor, this.compact = false});
  final EditorController editor;
  final bool compact;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const double _rulerH = 30, _textH = 34, _videoH = 52, _audioH = 40;
  static const double _gap = 6, _hdrW = 44;

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
    // Keep the scroll position glued to the playhead without needing the
    // build method to schedule a callback every frame.
    editor.addListener(_syncScroll);
  }

  @override
  void dispose() {
    editor.removeListener(_syncScroll);
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

  void _syncScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || !_sc.hasClients) return;
      final double pps = 28.0 * editor.zoom;
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
    if (best != t && _lastSnap != best) _tap();
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
    final double maxH = widget.compact ? 150 : 230;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _divider)),
      ),
      height: math.min(contentH, maxH),
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
                _pointers = math.max(0, _pointers - 1);
                if (_pointers < 2) setState(() {});
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
                      _syncScroll();
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
                              // Tap the ruler to jump the playhead there.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (d) =>
                                    _seek(editor, (d.localPosition.dx - half) / pps),
                                child: SizedBox(
                                  height: _rulerH,
                                  width: contentW,
                                  child: CustomPaint(
                                    painter: _RulerPainter(
                                        pps: pps, seconds: total + 5, leftPad: half),
                                  ),
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
                  border: Border(right: BorderSide(color: _divider)),
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
            // Playhead: centred exactly on x = half (ruler / clips share it).
            Positioned(
              left: half - 5,
              top: 0,
              bottom: 0,
              width: 10,
              child: IgnorePointer(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[BoxShadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                    Expanded(child: Container(width: 2, color: Colors.white)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 2,
              child: Row(
                children: <Widget>[
                  _chip(Icons.align_horizontal_center_rounded, 'Snap', _snap,
                      () => setState(() => _snap = !_snap)),
                  const SizedBox(width: 4),
                  _chip(Icons.remove_rounded, 'Zoom out', false,
                      () => _setZoom(editor.zoom - 0.5)),
                  const SizedBox(width: 4),
                  _chip(Icons.add_rounded, 'Zoom in', false, () => _setZoom(editor.zoom + 0.5)),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _chip(IconData icon, String tip, bool on, VoidCallback onTap) => Semantics(
        button: true,
        label: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _tap();
            onTap();
          },
          // Visual chip is small, tap target is padded to ~44dp wide.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: Container(
              width: 30,
              height: 24,
              decoration: BoxDecoration(
                color: on ? Colors.white : const Color(0xFF26262C),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 15, color: on ? Colors.black : Colors.white),
            ),
          ),
        ),
      );

  Widget _header(_Lane l) {
    final bool locked = l.clips.isNotEmpty && l.clips.every((c) => c.isLocked);
    final bool visible = l.clips.any((c) => c.isVisible);
    Widget btn(IconData i, bool active, String tip, VoidCallback f) => Tooltip(
          message: tip,
          child: InkResponse(
            radius: 16,
            onTap: () {
              _tap();
              f();
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(i, size: 15, color: active ? Colors.white : Colors.white54),
            ),
          ),
        );
    final children = <Widget>[
      btn(locked ? Icons.lock_rounded : Icons.lock_open_rounded, locked,
          locked ? 'Unlock track' : 'Lock track', () {
        for (final c in l.clips) {
          if (c.isLocked == locked) editor.toggleClipLock(c.id);
        }
      }),
      btn(visible ? Icons.visibility_rounded : Icons.visibility_off_rounded, !visible,
          visible ? 'Hide track' : 'Show track', () {
        for (final c in l.clips) {
          if (c.isVisible == visible) editor.toggleClipVisibility(c.id);
        }
      }),
    ];
    // Short lanes stack the buttons side by side, tall lanes vertically.
    return l.h >= 50
        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: children)
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
  }

  Widget _addButton(double left, double h) => Positioned(
        left: left,
        top: h / 2 - 14,
        child: Semantics(
          button: true,
          label: 'Add media',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _tap();
              Navigator.of(context).pushNamed('/media_picker');
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, size: 18, color: Colors.black),
            ),
          ),
        ),
      );

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
                child: _ClipBlock(editor: editor, clip: list[i], kind: l.kind, pps: pps),
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
            // "+" sits at the END of the main track (CapCut style).
            if (l.add)
              _addButton(
                  half + (list.isEmpty ? 0 : _seconds(list.last.end) * pps) + 4, l.h),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Clips
//
// UX: long-press-to-lock and double-tap-to-hide were invisible, easy to
// trigger by accident and are gone; use the lock / eye buttons in the track
// header. Locked clips now show a lock badge, hidden clips are dimmed, and
// each overlay type has its own colour and icon.
// ----------------------------------------------------------------------------
enum _ClipKind { text, video, audio }

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.editor,
    required this.clip,
    required this.kind,
    required this.pps,
  });
  final EditorController editor;
  final TimelineClip clip;
  final _ClipKind kind;
  final double pps;

  @override
  Widget build(BuildContext context) {
    final bool selected = editor.selectedClipId == clip.id;
    final Color border = selected ? Colors.white : Colors.transparent;

    Widget body;
    switch (kind) {
      case _ClipKind.text:
        final bool sticker =
            clip.clipType == ClipType.sticker || clip.clipType == ClipType.element;
        final bool drawing = clip.clipType == ClipType.drawing;
        final Color bg = drawing ? _drawTrack : (sticker ? _fxTrack : _textTrack);
        final IconData icon = drawing
            ? Icons.brush_rounded
            : (sticker ? Icons.emoji_emotions_rounded : Icons.title_rounded);
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 2),
          ),
          child: Row(children: <Widget>[
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Expanded(
              child: Text(clip.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ]),
        );
      case _ClipKind.video:
        body = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(painter: _FilmPainter()),
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text('${_seconds(clip.duration).toStringAsFixed(1)}s',
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
          ),
        );
      case _ClipKind.audio:
        body = Container(
          decoration: BoxDecoration(
            color: _audioTrack,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
                painter: _WavePainter(seed: clip.id.hashCode % 97),
                child: const SizedBox.expand()),
          ),
        );
    }

    if (selected && !clip.isLocked) {
      body = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: body),
          Positioned(
            left: -8,
            top: 2,
            bottom: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                final double deltaSec = details.delta.dx / pps;
                final double newStartSec = (_seconds(clip.start) + deltaSec)
                    .clamp(0.0, _seconds(clip.end) - 0.2);
                editor.trimSelectedClip(
                  Duration(milliseconds: (newStartSec * 1000).round()),
                  clip.end,
                );
              },
              child: const _Handle(),
            ),
          ),
          Positioned(
            right: -8,
            top: 2,
            bottom: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                final double deltaSec = details.delta.dx / pps;
                final double newEndSec = (_seconds(clip.end) + deltaSec)
                    .clamp(_seconds(clip.start) + 0.2, 86400.0);
                editor.trimSelectedClip(
                  clip.start,
                  Duration(milliseconds: (newEndSec * 1000).round()),
                );
              },
              child: const _Handle(),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () {
        _tap();
        editor.selectClip(clip.id);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: clip.isVisible ? 1 : 0.35,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(child: body),
            if (clip.isLocked)
              const Positioned(
                top: 4,
                right: 6,
                child: Icon(Icons.lock_rounded, size: 11, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
        child: const Center(
          child: SizedBox(width: 2, height: 10, child: ColoredBox(color: Colors.black)),
        ),
      );
}

class _FilmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2A2A30));
    final double fw = size.height * 0.85;
    int i = 0;
    for (double x = 0; x < size.width; x += fw) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, fw - 1, size.height),
        Paint()..color = (i++ % 2 == 0) ? const Color(0xFF383840) : const Color(0xFF42424C),
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
      ..color = const Color(0xFF7FD6E8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const double gap = 4;
    final int bars = ((size.width - 20) / gap).floor();
    for (int i = 0; i < bars; i++) {
      final double x = 10 + i * gap;
      final double a = (math.sin(x * 0.3 + seed) * 0.5 + 0.5) *
          (0.3 + 0.7 * (((i * 7 + seed) % 11) / 11));
      final double h = math.max(3.0, a * (size.height - 10));
      canvas.drawLine(
          Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.seed != seed;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.pps, required this.seconds, required this.leftPad});
  final double pps;
  final double seconds;
  final double leftPad;

  @override
  void paint(Canvas canvas, Size size) {
    const steps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300];
    final double step = steps.firstWhere((s) => s * pps >= 64, orElse: () => steps.last);
    final Paint dot = Paint()..color = const Color(0xFF6A6A72);
    final int count = (seconds / step).ceil();

    for (int i = 0; i <= count; i++) {
      final double t = i * step;
      final double x = leftPad + t * pps;
      if (x > size.width) break;
      final tp = TextPainter(
        text: TextSpan(
            text: step < 1 ? '${t.toStringAsFixed(1)}s' : '${t.toInt()}s',
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, 12));
      for (int j = 1; j < 4; j++) {
        canvas.drawCircle(Offset(x + j * step * pps / 4, 12 + tp.height / 2), 1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps || old.seconds != seconds || old.leftPad != leftPad;
}

// ----------------------------------------------------------------------------
// Bottom toolbar
//
// UX: clip actions (Split / Delete) now appear first and only when a clip is
// selected, separated from the global tools; a fade on the right edge hints
// that the bar scrolls.
// ----------------------------------------------------------------------------
class _Toolbar extends StatelessWidget {
  const _Toolbar({super.key, required this.onOpen});
  final void Function(_Tool) onOpen;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final sel = editor.selectedClip;
    final bool canSplit =
        sel != null && editor.playhead > sel.start && editor.playhead < sel.end;

    Widget item(IconData icon, String label, VoidCallback? onTap, {Color? color}) {
      final enabled = onTap != null;
      return Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkWell(
          onTap: enabled
              ? () {
                  _tap();
                  onTap();
                }
              : null,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon,
                      size: 22, color: enabled ? (color ?? Colors.white) : Colors.white24),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white70 : Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget tool(_Tool t) => item(t.icon, t.title, () => onOpen(t));

    return Container(
      color: _surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Stack(
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(left: 6, right: 28),
                child: Row(
                  children: <Widget>[
                    if (sel != null) ...<Widget>[
                      item(Icons.content_cut_rounded, 'Split',
                          canSplit ? editor.splitSelectedClip : null),
                      item(Icons.delete_outline_rounded, 'Delete', editor.deleteSelectedClip,
                          color: Colors.redAccent),
                      Container(
                          width: 1,
                          height: 30,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: _divider),
                    ],
                    tool(_Tool.audio),
                    tool(_Tool.text),
                    item(Icons.subtitles_rounded, 'Captions', editor.generateAutoCaptions),
                    tool(_Tool.stickers),
                    tool(_Tool.filters),
                    tool(_Tool.effects),
                    tool(_Tool.adjust),
                    tool(_Tool.crop),
                    tool(_Tool.speed),
                    tool(_Tool.elements),
                    tool(_Tool.draw),
                    tool(_Tool.mask),
                    tool(_Tool.keyframes),
                    tool(_Tool.camera),
                    tool(_Tool.track),
                    tool(_Tool.plugins),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[_surface.withValues(alpha: 0), _surface],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}