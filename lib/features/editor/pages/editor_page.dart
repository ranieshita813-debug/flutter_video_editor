import 'package:hugeicons/hugeicons.dart';
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
const Color _textTrack = Color(0xFF1F1F26);
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

// ----------------------------------------------------------------------------
// Page
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// Inline tools (CapCut style): tapping a tool swaps the bottom toolbar for a
// panel that lives INSIDE the editor. Preview and timeline stay visible and
// interactive, and nothing opens as a modal dialog / bottom sheet.
// ----------------------------------------------------------------------------
enum _Tool {
  audio('Audio', HugeIcons.strokeRoundedVolumeHigh),
  text('Text', HugeIcons.strokeRoundedText),
  stickers('Stickers', HugeIcons.strokeRoundedSmile),
  filters('Filters', HugeIcons.strokeRoundedFilter),
  effects('Effects', HugeIcons.strokeRoundedFire),
  adjust('Adjust', HugeIcons.strokeRoundedLayers01),
  crop('Crop', HugeIcons.strokeRoundedCrop),
  speed('Speed', HugeIcons.strokeRoundedDashboardSpeed01),
  elements('Elements', HugeIcons.strokeRoundedShapes),
  draw('Draw', HugeIcons.strokeRoundedPaintBrush01),
  mask('Mask', HugeIcons.strokeRoundedMask),
  keyframes('Keyframes', HugeIcons.strokeRoundedDiamond),
  camera('Camera', HugeIcons.strokeRoundedCamera01),
  track('Track', HugeIcons.strokeRoundedTarget01),
  plugins('Plug-ins', HugeIcons.strokeRoundedGrid);

  const _Tool(this.title, this.icon);
  final String title;
  final List<List<dynamic>> icon;

  // These are the same widgets the old sheets showed, now embedded inline.
  // If a constructor needs arguments in your project, pass them here.
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
// ----------------------------------------------------------------------------
class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  _Tool? _tool;

  void _open(_Tool t) {
    HapticFeedback.selectionClick();
    setState(() => _tool = t);
  }

  void _close() => setState(() => _tool = null);

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return PopScope(
      // Back button closes the open tool first, then leaves the editor.
      canPop: _tool == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(
          children: <Widget>[
            Expanded(child: _Preview(editor: editor)),
            _Timeline(editor: editor),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _tool == null
                  ? _Toolbar(editor: editor, onOpen: _open)
                  : _ToolPanel(key: ValueKey<_Tool>(_tool!), tool: _tool!, onClose: _close),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({super.key, required this.tool, required this.onClose});
  final _Tool tool;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final double h = math.min(MediaQuery.of(context).size.height * 0.34, 300.0);
    return Container(
      color: _surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: h,
          child: Column(
            children: <Widget>[
              SizedBox(
                height: 44,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 14),
                    HugeIcon(icon: tool.icon, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(tool.title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedTick01, color: Colors.white, size: 22),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onClose();
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
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
// FIX: the old version never rebuilt (parent used context.read), and it
// created/disposed controllers and called play()/pause() inside build().
// Now it subscribes to the EditorController itself, loads sources
// asynchronously with a race guard, and keeps the video in sync with the
// timeline playhead (play, pause, scrub).
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

  // Coalesce rapid editor notifications into sequential async work.
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
    if (!mounted || c == null || clip == null || !c.value.isInitialized) return;

    // Position inside the source file.
    // If your TimelineClip has an in-point / trim offset, add it here:
    //   final local = _e.playhead - clip.start + clip.trimStart;
    Duration local = (_e.playhead - clip.start) + clip.trimIn;
    if (local.isNegative) local = Duration.zero;
    final Duration dur = c.value.duration;
    if (dur > Duration.zero && local > dur) local = dur;

    try {
      if ((c.value.volume - clip.volume).abs() > 0.01) {
        await c.setVolume(clip.volume.clamp(0.0, 1.0));
      }
      if ((c.value.playbackSpeed - clip.speed).abs() > 0.01 && clip.speed > 0) {
        await c.setPlaybackSpeed(clip.speed.clamp(0.1, 4.0));
      }
    } catch (_) {}

    final Duration drift = (c.value.position - local).abs();

    if (_e.isPlaying) {
      if (!c.value.isPlaying) {
        await c.seekTo(local);
        await c.play();
      } else if (drift > const Duration(milliseconds: 800)) {
        await c.seekTo(local);
      }
    } else {
      if (c.value.isPlaying) await c.pause();
      if (drift > const Duration(milliseconds: 40)) await c.seekTo(local);
    }
  }

  Future<void> _load(String? path) async {
    final int token = ++_token;
    _path = path;
    _failed = false;

    // Detach the old controller from the tree before disposing it.
    final old = _vc;
    _vc = null;
    _loading = path != null && path.isNotEmpty && !_isImagePath(path);
    if (mounted) setState(() {});
    if (old != null) {
      await WidgetsBinding.instance.endOfFrame;
      await old.dispose();
    }

    if (path == null || path.isEmpty || _isImagePath(path)) return;

    final file = File(path);
    if (!await file.exists()) {
      if (mounted && token == _token) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
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
      if (mounted && token == _token) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    if (!mounted || token != _token) {
      await c.dispose();
      return;
    }
    setState(() {
      _vc = c;
      _loading = false;
    });
  }

  Widget _placeholder(String text, {List<List<dynamic>> icon = HugeIcons.strokeRoundedVideo01}) {
    return Container(
      color: const Color(0xFF07080B),
      child: Center(
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
              HugeIcon(icon: icon, size: 48, color: Colors.white24),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = _e.activeVideoClip;
    final String? path = clip?.sourcePath;

    if (path != null && path.isNotEmpty && _isImagePath(path) && File(path).existsSync()) {
      return Container(
        color: const Color(0xFF07080B),
        alignment: Alignment.center,
        child: Image.file(File(path), fit: BoxFit.contain),
      );
    }

    final c = _vc;
    if (c != null && c.value.isInitialized) {
      return Container(
        color: const Color(0xFF07080B),
        alignment: Alignment.center,
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      );
    }

    if (_failed) return _placeholder('Can\'t play this file', icon: HugeIcons.strokeRoundedAlertCircle);
    return _placeholder(clip?.label ?? 'Canvas Preview');
  }
}

// ----------------------------------------------------------------------------
// Preview (full-bleed) with overlaid controls
// ----------------------------------------------------------------------------
class _Preview extends StatelessWidget {
  const _Preview({required this.editor});
  final EditorController editor;

  Widget _step(List<List<dynamic>> i, int dir) => IconButton(
        visualDensity: VisualDensity.compact,
        icon: HugeIcon(icon: i, color: Colors.white, size: 26),
        onPressed: () {
          HapticFeedback.selectionClick();
          _seek(editor, _seconds(editor.playhead) + dir / _fps);
        },
      );

  Widget _roundBtn(List<List<dynamic>> i, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
          child: HugeIcon(icon: i, color: Colors.white, size: 20),
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
            final activeOverlays = e.project.clips.where((c) =>
                c.isVisible &&
                e.playhead >= c.start &&
                e.playhead <= c.end &&
                c.clipType != ClipType.video &&
                c.clipType != ClipType.audio &&
                c.clipType != ClipType.image).toList();

            final tracking = e.selectedClip?.trackingData;
            return IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  for (final clip in activeOverlays)
                    _buildOverlayWidget(clip),
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
                            border: Border.all(color: _accent, width: 1.5)),
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
        // Top bar
        SafeArea(
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: () => ExportModal.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          HugeIcon(icon: HugeIcons.strokeRoundedShare01, color: Colors.black, size: 16),
                          SizedBox(width: 5),
                          Text('Export',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text('1080p',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
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
                          const BoxDecoration(color: Color(0xFF1C1C20), shape: BoxShape.circle),
                      child: const HugeIcon(icon: HugeIcons.strokeRoundedTick01, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom controls
        Positioned(
          left: 16,
          right: 16,
          bottom: 10,
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
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  _roundBtn(HugeIcons.strokeRoundedUndo, editor.undo),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _step(HugeIcons.strokeRoundedPrevious, -1),
                        const SizedBox(width: 6),
                        Selector<EditorController, bool>(
                          selector: (_, e) => e.isPlaying,
                          builder: (_, playing, __) => GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              editor.togglePlayback();
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                              child: HugeIcon(
                                  icon: playing ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay,
                                  color: Colors.black,
                                  size: 30),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _step(HugeIcons.strokeRoundedNext, 1),
                      ],
                    ),
                  ),
                  _roundBtn(HugeIcons.strokeRoundedRedo01, editor.redo),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

  Widget _buildOverlayWidget(TimelineClip clip) {
    Widget content;
    switch (clip.clipType) {
      case ClipType.text:
      case ClipType.caption:
        content = Text(
          clip.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontFamily: clip.fontFamily,
            fontWeight: FontWeight.bold,
            shadows: const <Shadow>[
              Shadow(color: Colors.black, blurRadius: 8, offset: Offset(1, 1)),
            ],
          ),
        );
      case ClipType.element:
        final props = clip.elementProperties;
        content = Container(
          width: props.size,
          height: props.size,
          decoration: BoxDecoration(
            color: props.fillColor,
            border: props.strokeWidth > 0 ? Border.all(color: props.strokeColor, width: props.strokeWidth) : null,
            shape: props.shape == ElementShape.circle ? BoxShape.circle : BoxShape.rectangle,
          ),
        );
      case ClipType.sticker:
        content = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(clip.label, style: const TextStyle(fontSize: 28)),
        );
      case ClipType.drawing:
        content = CustomPaint(
          size: const Size(200, 200),
          painter: _DrawingPainter(strokes: clip.strokes),
        );
      default:
        content = const SizedBox.shrink();
    }

    return Positioned(
      left: 100 + clip.positionX,
      top: 200 + clip.positionY,
      child: Transform.rotate(
        angle: clip.rotation * (math.pi / 180.0),
        child: Transform.scale(
          scale: clip.scale,
          child: Opacity(
            opacity: clip.opacity.clamp(0.0, 1.0),
            child: content,
          ),
        ),
      ),
    );
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
  static const double _gap = 6, _hdrW = 36;

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
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _divider)),
      ),
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
            // Playhead line + head
            Positioned(
              left: half - 1,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 0),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                    ),
                    Expanded(child: Container(width: 2, color: Colors.white)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 4,
              child: Row(
                children: <Widget>[
                  _chip(HugeIcons.strokeRoundedTextAlignCenter, _snap,
                      () => setState(() => _snap = !_snap)),
                  const SizedBox(width: 4),
                  _chip(HugeIcons.strokeRoundedMinusSignCircle, false, () => _setZoom(editor.zoom - 0.5)),
                  const SizedBox(width: 4),
                  _chip(HugeIcons.strokeRoundedAdd01, false, () => _setZoom(editor.zoom + 0.5)),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _chip(List<List<dynamic>> icon, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 22,
          decoration: BoxDecoration(
            color: on ? Colors.white : const Color(0xFF26262C),
            borderRadius: BorderRadius.circular(6),
          ),
          child: HugeIcon(icon: icon, size: 14, color: on ? Colors.black : Colors.white),
        ),
      );

  Widget _header(_Lane l) {
    final bool locked = l.clips.isNotEmpty && l.clips.every((c) => c.isLocked);
    final bool visible = l.clips.any((c) => c.isVisible);
    Widget btn(List<List<dynamic>> i, bool active, VoidCallback f) => InkWell(
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: HugeIcon(icon: i, size: 13, color: active ? Colors.white : Colors.white54),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        btn(locked ? HugeIcons.strokeRoundedLockKeyhole : HugeIcons.strokeRoundedLockKeyholeOpen, locked, () {
          for (final c in l.clips) {
            if (c.isLocked == locked) editor.toggleClipLock(c.id);
          }
        }),
        btn(visible ? HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff, !visible, () {
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
                    child: const HugeIcon(icon: HugeIcons.strokeRoundedLink01, size: 13, color: Colors.black),
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
                        const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 16, color: Colors.black),
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
    final Color border = selected ? Colors.white : Colors.transparent;

    Widget body;
    switch (kind) {
      case _ClipKind.text:
        final bool fx = clip.clipType == ClipType.sticker ||
            clip.clipType == ClipType.drawing ||
            clip.clipType == ClipType.element;
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _textTrack,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 2),
          ),
          child: Row(children: <Widget>[
            if (fx)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: HugeIcon(icon: HugeIcons.strokeRoundedMagicWand01, size: 16, color: Colors.white),
              ),
            const HugeIcon(icon: HugeIcons.strokeRoundedText, size: 18, color: Colors.white70),
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
            border: Border.all(color: border, width: 2),
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
            color: Colors.white, borderRadius: BorderRadius.circular(5)),
        child: const Center(
          child: SizedBox(
              width: 2, height: 10, child: ColoredBox(color: Colors.black)),
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
        Paint()
          ..color = (i++ % 2 == 0)
              ? const Color(0xFF383840)
              : const Color(0xFF42424C),
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
      tp.paint(canvas, Offset(x - tp.width / 2, 12));
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
// Bottom toolbar
// ----------------------------------------------------------------------------
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.editor, required this.onOpen});
  final EditorController editor;
  final void Function(_Tool) onOpen;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final sel = editor.selectedClip;
    final bool canSplit =
        sel != null && editor.playhead > sel.start && editor.playhead < sel.end;

    Widget toolItem(List<List<dynamic>> icon, String label, VoidCallback? onTap, {Color? color}) {
      final enabled = onTap != null;
      return InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 62,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                HugeIcon(icon: icon,
                    size: 22,
                    color: enabled ? (color ?? Colors.white) : Colors.white24),
                const SizedBox(height: 3),
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
      );
    }

    return Container(
      color: _surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: <Widget>[
                toolItem(HugeIcons.strokeRoundedScissors, 'Split',
                    canSplit ? editor.splitSelectedClip : null),
                toolItem(HugeIcons.strokeRoundedVolumeHigh, 'Audio', () => onOpen(_Tool.audio)),
                toolItem(HugeIcons.strokeRoundedText, 'Text', () => onOpen(_Tool.text)),
                toolItem(HugeIcons.strokeRoundedText, 'Captions', editor.generateAutoCaptions),
                toolItem(HugeIcons.strokeRoundedSmile, 'Stickers', () => onOpen(_Tool.stickers)),
                toolItem(HugeIcons.strokeRoundedFilter, 'Filters',
                    () => onOpen(_Tool.filters)),
                toolItem(HugeIcons.strokeRoundedFire, 'Effects',
                    () => onOpen(_Tool.effects)),
                toolItem(HugeIcons.strokeRoundedLayers01, 'Adjust', () => onOpen(_Tool.adjust)),
                toolItem(HugeIcons.strokeRoundedCrop, 'Crop', () => onOpen(_Tool.crop)),
                toolItem(HugeIcons.strokeRoundedDashboardSpeed01, 'Speed', () => onOpen(_Tool.speed)),
                toolItem(HugeIcons.strokeRoundedShapes, 'Elements', () => onOpen(_Tool.elements)),
                toolItem(HugeIcons.strokeRoundedPaintBrush01, 'Draw', () => onOpen(_Tool.draw)),
                toolItem(HugeIcons.strokeRoundedMask, 'Mask', () => onOpen(_Tool.mask)),
                toolItem(HugeIcons.strokeRoundedDiamond, 'Keyframes', () => onOpen(_Tool.keyframes)),
                toolItem(HugeIcons.strokeRoundedCamera01, 'Camera', () => onOpen(_Tool.camera)),
                toolItem(HugeIcons.strokeRoundedTarget01, 'Track', () => onOpen(_Tool.track)),
                toolItem(HugeIcons.strokeRoundedGrid, 'Plug-ins', () => onOpen(_Tool.plugins)),
                toolItem(HugeIcons.strokeRoundedDelete01, 'Delete',
                    sel != null ? editor.deleteSelectedClip : null,
                    color: Colors.redAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}