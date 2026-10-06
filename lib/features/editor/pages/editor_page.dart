import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';

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

// TODO(project): drive from project settings instead of a constant.
const int _fps = 30;

double _seconds(Duration v) => v.inMilliseconds / 1000.0;
String _two(int n) => n.toString().padLeft(2, '0');

String _tc(double s) {
  final int f = (math.max(s, 0) * _fps).round();
  final int sec = f ~/ _fps;
  return '${_two(sec ~/ 3600)}:${_two(sec % 3600 ~/ 60)}:${_two(sec % 60)}:${_two(f % _fps)}';
}

void _seek(EditorController e, double s) {
  final double total = math.max(_seconds(e.project.totalDuration), 1.0);
  final double c = s.clamp(0.0, total).toDouble();
  final double q = (c * _fps).round() / _fps;
  e.setPlayhead(Duration(milliseconds: (q * 1000).round()));
}

bool _isImagePath(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.jpg') ||
      l.endsWith('.jpeg') ||
      l.endsWith('.png') ||
      l.endsWith('.webp') ||
      l.endsWith('.heic');
}

void _tap() => HapticFeedback.selectionClick();

// ----------------------------------------------------------------------------
// Pluggable media pipelines
//
// Wire these once in main() to unlock real thumbnails / real waveforms:
//
//   thumbGenerator = (path, timeMs, maxW) => VideoThumbnail.thumbnailData(
//         video: path, timeMs: timeMs,
//         imageFormat: ImageFormat.JPEG, maxWidth: maxW, quality: 55);
//
//   waveformDecoder = (path, bars) => MyFFmpegWaveform.decode(path, bars);
//
// Without a generator the UI degrades gracefully (stripes / content-derived
// bars), so this file never hard-depends on extra packages.
// ----------------------------------------------------------------------------
typedef ThumbGenerator = Future<Uint8List?> Function(String path, int timeMs, int maxWidth);
ThumbGenerator? thumbGenerator;

typedef WaveformDecoder = Future<List<double>> Function(String path, int bars);
WaveformDecoder? waveformDecoder;

class ThumbCache {
  static final Map<String, Uint8List> _mem = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};
  static const int _maxEntries = 500;

  static Future<Uint8List?> get(String path, int timeMs, int maxW) {
    final gen = thumbGenerator;
    if (gen == null) return Future<Uint8List?>.value();
    final String key = '$path|$timeMs|$maxW';
    final Uint8List? hit = _mem[key];
    if (hit != null) return Future<Uint8List?>.value(hit);
    Future<Uint8List?>? f = _inflight[key];
    f ??= () async {
      try {
        final Uint8List? b = await gen(path, timeMs, maxW);
        if (b != null && b.isNotEmpty) {
          if (_mem.length >= _maxEntries) _mem.remove(_mem.keys.first);
          _mem[key] = b;
        }
        return b;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(key);
      }
    }();
    _inflight[key] = f;
    return f;
  }
}

final Map<String, Future<List<double>>> _waveCache = <String, Future<List<double>>>{};

Future<List<double>> _waveFuture(String path, int bars) =>
    _waveCache.putIfAbsent('$path|$bars', () async {
      final dec = waveformDecoder;
      if (dec != null) {
        try {
          final List<double> r = await dec(path, bars);
          if (r.isNotEmpty) return r;
        } catch (_) {}
      }
      return _fallbackWave(path, bars);
    });

// Deterministic, content-derived fallback: hashes real file bytes (first 48KB)
// so different audio files look different. Plug `waveformDecoder` for true PCM.
Future<List<double>> _fallbackWave(String path, int bars) async {
  const double flat = 0.4;
  try {
    final RandomAccessFile raf = await File(path).open();
    final List<int> bytes = <int>[];
    int remaining = 48 * 1024;
    while (remaining > 0) {
      final Uint8List b = await raf.read(math.min(remaining, 4096));
      if (b.isEmpty) break;
      bytes.addAll(b);
      remaining -= b.length;
    }
    await raf.close();
    if (bytes.isEmpty) return List<double>.filled(bars, flat);
    final List<double> out = List<double>.filled(bars, flat);
    final int per = math.max(1, bytes.length ~/ bars);
    for (int i = 0; i < bars; i++) {
      int h = 0;
      final int end = math.min(bytes.length, (i + 1) * per);
      for (int j = i * per; j < end; j++) {
        h = (h * 31 + bytes[j]) & 0x7fffffff;
      }
      out[i] = 0.2 + 0.8 * ((h % 997) / 997.0);
    }
    return out;
  } catch (_) {
    return List<double>.filled(bars, flat);
  }
}

// ----------------------------------------------------------------------------
// Inline tools
// ----------------------------------------------------------------------------
enum _Tool {
  audio('Audio', Icons.volume_up_rounded),
  text('Text', Icons.title_rounded),
  stickers('Stickers', Icons.emoji_emotions_rounded),
  filters('Filters', Icons.filter_vintage_rounded),
  effects('Effects', Icons.local_fire_department_rounded),
  adjust('Adjust', Icons.layers_rounded),
  crop('Crop', Icons.crop_rounded),
  speed('Speed', Icons.speed_rounded),
  elements('Elements', Icons.shape_line_rounded),
  draw('Draw', Icons.brush_rounded),
  mask('Mask', Icons.masks_rounded),
  keyframes('Keyframes', Icons.diamond_rounded),
  camera('Camera', Icons.camera_rounded),
  track('Track', Icons.center_focus_strong_rounded),
  plugins('Plug-ins', Icons.extension_rounded);

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
// Shared timeline ops
// ----------------------------------------------------------------------------
void _splitAllTracks(EditorController editor) {
  final Duration ph = editor.playhead;
  final List<TimelineClip> targets = editor.project.clips
      .where((c) => !c.isLocked && ph > c.start && ph < c.end)
      .toList();
  if (targets.isEmpty) return;
  _tap();
  // TODO(controller): a native splitAllAtPlayhead() would make this a single
  // undo step. Until then we select + split each clip.
  for (final c in targets) {
    editor.selectClip(c.id);
    editor.splitSelectedClip();
  }
}

void _rippleDelete(EditorController editor) {
  final TimelineClip? sel = editor.selectedClip;
  if (sel == null) return;
  _tap();
  final bool isMain =
      sel.clipType == ClipType.video || sel.clipType == ClipType.image;
  final List<TimelineClip> later = isMain
      ? editor.project.clips
          .where((c) =>
              c.id != sel.id &&
              (c.clipType == ClipType.video || c.clipType == ClipType.image) &&
              c.start >= sel.end)
          .toList()
      : const <TimelineClip>[];
  editor.deleteSelectedClip();
  for (final c in later) {
    try {
      editor.selectClip(c.id);
      editor.trimSelectedClip(c.start - sel.duration, c.end - sel.duration);
    } catch (_) {}
  }
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
  double _frac = 0.32;
  bool _dragging = false;

  // Multi-select lives here so both the timeline and the toolbar can share it.
  final ValueNotifier<bool> _multiOn = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> _multi = ValueNotifier<Set<String>>(<String>{});

  void _open(_Tool t) {
    _tap();
    setState(() => _tool = t);
  }

  void _close() => setState(() => _tool = null);

  void _clearMulti() {
    _multiOn.value = false;
    _multi.value = <String>{};
  }

  @override
  void dispose() {
    _multiOn.dispose();
    _multi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final bool keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): editor.togglePlayback,
        const SingleActivator(LogicalKeyboardKey.keyK): editor.togglePlayback,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seek(editor, _seconds(editor.playhead) - 1 / _fps),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seek(editor, _seconds(editor.playhead) + 1 / _fps),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
            _seek(editor, _seconds(editor.playhead) - 1.0),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
            _seek(editor, _seconds(editor.playhead) + 1.0),
        const SingleActivator(LogicalKeyboardKey.keyS): () => _splitAllTracks(editor),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): editor.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): editor.redo,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: _tool == null && !_multiOn.value,
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            if (didPop) return;
            if (_multiOn.value) {
              _clearMulti();
            } else {
              _close();
            }
          },
          child: Scaffold(
            backgroundColor: _bg,
            body: LayoutBuilder(builder: (context, c) {
              final double panelH = math
                  .min(c.maxHeight * _frac, c.maxHeight * 0.65)
                  .clamp(160.0, 520.0)
                  .toDouble();
              return Column(
                children: <Widget>[
                  Expanded(child: _Preview(editor: editor)),
                  if (!(keyboard && _tool != null))
                    _Timeline(
                      editor: editor,
                      compact: _tool != null,
                      multiOn: _multiOn,
                      multi: _multi,
                      onClearMulti: _clearMulti,
                    ),
                  AnimatedSize(
                    duration:
                        _dragging ? Duration.zero : const Duration(milliseconds: 240),
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
                          ? _Toolbar(
                              key: const ValueKey('bar'),
                              onOpen: _open,
                              multiOn: _multiOn,
                              multi: _multi,
                              onClearMulti: _clearMulti,
                            )
                          : _ToolPanel(
                              key: ValueKey<_Tool>(_tool!),
                              tool: _tool!,
                              height: panelH,
                              onClose: _close,
                              onResize: (dy) => setState(() {
                                _frac = (_frac - dy / c.maxHeight)
                                    .clamp(0.22, 0.6)
                                    .toDouble();
                              }),
                              onDrag: (v) => setState(() => _dragging = v),
                            ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => onDrag(true),
                onVerticalDragUpdate: (d) => onResize(d.delta.dy),
                onVerticalDragEnd: (_) => onDrag(false),
                onVerticalDragCancel: () => onDrag(false),
                child: SizedBox(
                  height: 48,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 16),
                            Icon(tool.icon, color: Colors.white70, size: 17),
                            const SizedBox(width: 8),
                            Text(tool.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Done',
                              icon: const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 22),
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
                  child: Material(
                      type: MaterialType.transparency, child: tool.body),
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
    if (!mounted || c == null || clip == null || _loading || !c.value.isInitialized) {
      return;
    }

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

  Widget _placeholder(String text, {IconData icon = Icons.movie_rounded}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_loading)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white38),
            )
          else
            Icon(icon, size: 44, color: Colors.white24),
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
            _placeholder('Can\'t open this image', icon: Icons.broken_image_rounded),
      );
    } else if (ready) {
      child = AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
    } else if (_failed) {
      child = _placeholder('Can\'t play this file', icon: Icons.error_rounded);
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
          if (_loading && ready)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Tracking overlay (normalized coordinates)
//
// Wire `resolveTrackingBox` in main() to map your TrackingData fields to a
// normalized rect, e.g.:
//   resolveTrackingBox = (t) => TrackingBox(t.x, t.y, t.w, t.h); // 0..1
// ----------------------------------------------------------------------------
class TrackingBox {
  const TrackingBox(this.x, this.y, this.w, this.h);
  final double x, y, w, h; // normalized 0..1
}

typedef TrackingBoxResolver = TrackingBox? Function(dynamic tracking);
TrackingBoxResolver? resolveTrackingBox;

class _TrackingOverlay extends StatelessWidget {
  const _TrackingOverlay({required this.box, required this.label});
  final TrackingBox box;
  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final Rect r = Rect.fromLTWH(
            box.x * c.maxWidth, box.y * c.maxHeight, box.w * c.maxWidth, box.h * c.maxHeight);
        return CustomPaint(
          painter: _TrackingPainter(rect: r, label: label),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _TrackingPainter extends CustomPainter {
  _TrackingPainter({required this.rect, required this.label});
  final Rect rect;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        rect, Paint()..color = _accent..style = PaintingStyle.stroke..strokeWidth = 1.5);
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, rect.width));
    final double lw = tp.width + 12;
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top - 16, lw, 16),
        Paint()..color = _accent);
    tp.paint(canvas, Offset(rect.left + 6, rect.top - 14));
  }

  @override
  bool shouldRepaint(covariant _TrackingPainter old) =>
      old.rect != rect || old.label != label;
}

// ----------------------------------------------------------------------------
// Preview (full-bleed) with overlaid controls
// ----------------------------------------------------------------------------
class _Preview extends StatefulWidget {
  const _Preview({required this.editor});
  final EditorController editor;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final TransformationController _tf = TransformationController();
  bool _grid = false;

  @override
  void dispose() {
    _tf.dispose();
    super.dispose();
  }

  Widget _step(IconData i, int dir, String tip) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        icon: Icon(i, color: Colors.white, size: 22),
        onPressed: () {
          _tap();
          _seek(widget.editor, _seconds(widget.editor.playhead) + dir / _fps);
        },
      );

  Widget _roundBtn(IconData i, String tip, VoidCallback onTap,
          {double size = 30, double iconSize = 16}) =>
      Semantics(
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
            decoration:
                const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: Icon(i, color: Colors.white, size: iconSize),
          ),
        ),
      );

  Widget _scrim({required bool top}) => Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: top ? 96 : 108,
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
    final editor = widget.editor;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Pinch-zoom / pan on the player; double-tap resets; tap toggles play.
        GestureDetector(
          onTap: editor.togglePlayback,
          onDoubleTap: () => _tf.value = Matrix4.identity(),
          child: InteractiveViewer(
            transformationController: _tf,
            minScale: 1,
            maxScale: 5,
            child: SizedBox.expand(child: _VideoPlayerPreview(editor: editor)),
          ),
        ),
        Consumer<EditorController>(
          builder: (ctx, e, _) {
            final tracking = e.selectedClip?.trackingData;
            final TrackingBox? box =
                (tracking != null) ? resolveTrackingBox?.call(tracking) : null;
            return IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (_grid)
                    const Positioned.fill(
                      child: CustomPaint(painter: _GuidePainter()),
                    ),
                  if (e.activeDrawingStrokes.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                          painter: _DrawingPainter(strokes: e.activeDrawingStrokes)),
                    ),
                  if (box != null)
                    Positioned.fill(
                      child: _TrackingOverlay(
                          box: box, label: tracking?.targetName ?? 'Target'),
                    ),
                ],
              ),
            );
          },
        ),
        _scrim(top: true),
        _scrim(top: false),
        Positioned(
  left: 0,
  right: 0,
  top: 0,
  child: SafeArea(
    bottom: false,
    child: SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _roundBtn(Icons.arrow_back_ios_new_rounded, 'Back',
                () => Navigator.of(context).maybePop(),
                size: 36, iconSize: 17),
            const Spacer(),
            _roundBtn(
              _grid ? Icons.grid_off_rounded : Icons.grid_on_rounded,
              _grid ? 'Hide guides' : 'Show guides',
              () => setState(() => _grid = !_grid),
              size: 36, iconSize: 17,
            ),
            const SizedBox(width: 8),
            Container(
              height: 28,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text('1080p',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  _tap();
                  ExportModal.show(context);
                },
                child: const SizedBox(
                  height: 36,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.ios_share_rounded, color: Colors.black, size: 15),
                        SizedBox(width: 5),
                        Text('Export',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ],
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
        Positioned(
          left: 10,
          right: 10,
          bottom: 6,
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
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                    TextSpan(
                        text:
                            '  /  ${_tc(math.max(_seconds(editor.project.totalDuration), 1.0))}',
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  _roundBtn(Icons.undo_rounded, 'Undo', editor.undo, size: 30),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _step(Icons.skip_previous_rounded, -1, 'Previous frame'),
                        const SizedBox(width: 4),
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
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                    color: Colors.white, shape: BoxShape.circle),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      key: ValueKey<bool>(playing),
                                      color: Colors.black,
                                      size: 24),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _step(Icons.skip_next_rounded, 1, 'Next frame'),
                      ],
                    ),
                  ),
                  _roundBtn(Icons.redo_rounded, 'Redo', editor.redo, size: 30),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.7;
    for (final double f in const <double>[1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), p);
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), p);
    }
    canvas.drawCircle(size.center(Offset.zero), 5,
        Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
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
// Timeline — immutable snapshot model
//
// The whole lane tree only rebuilds when clips/zoom/selection actually change.
// Playhead ticks (30/s during playback) only move the scroll offset — no
// widget rebuilds.
// ----------------------------------------------------------------------------
class _ClipSnapshot {
  const _ClipSnapshot({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.label,
    required this.type,
    required this.layer,
    required this.locked,
    required this.visible,
    required this.path,
  });

  final String id;
  final int startMs;
  final int endMs;
  final String label;
  final ClipType type;
  final int layer;
  final bool locked;
  final bool visible;
  final String? path;

  double get startSec => startMs / 1000.0;
  double get endSec => endMs / 1000.0;
  double get durSec => (endMs - startMs) / 1000.0;
  bool get isMain => type == ClipType.video || type == ClipType.image;

  @override
  bool operator ==(Object other) =>
      other is _ClipSnapshot &&
      other.id == id &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.label == label &&
      other.type == type &&
      other.layer == layer &&
      other.locked == locked &&
      other.visible == visible &&
      other.path == path;

  @override
  int get hashCode =>
      Object.hash(id, startMs, endMs, label, type, layer, locked, visible, path);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _TimelineModel {
  _TimelineModel(this.clips, this.zoom, this.selectedId, this.totalMs);
  final List<_ClipSnapshot> clips;
  final double zoom;
  final String? selectedId;
  final int totalMs;

  static _TimelineModel from(EditorController e) => _TimelineModel(
        <_ClipSnapshot>[
          for (final c in e.project.clips)
            _ClipSnapshot(
              id: c.id,
              startMs: c.start.inMilliseconds,
              endMs: c.end.inMilliseconds,
              label: c.label,
              type: c.clipType,
              layer: c.layerIndex,
              locked: c.isLocked,
              visible: c.isVisible,
              path: c.sourcePath,
            ),
        ],
        e.zoom,
        e.selectedClipId,
        e.project.totalDuration.inMilliseconds,
      );

  @override
  bool operator ==(Object other) =>
      other is _TimelineModel &&
      other.zoom == zoom &&
      other.selectedId == selectedId &&
      other.totalMs == totalMs &&
      _listEq(other.clips, clips);

  @override
  int get hashCode => Object.hash(zoom, selectedId, totalMs, clips.length);
}

class _Lane {
  const _Lane(this.h, this.kind, this.clips, {this.add = false});
  final double h;
  final _ClipKind kind;
  final List<_ClipSnapshot> clips;
  final bool add;
}

enum _ClipKind { text, video, audio }

class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.editor,
    required this.multiOn,
    required this.multi,
    required this.onClearMulti,
    this.compact = false,
  });
  final EditorController editor;
  final ValueNotifier<bool> multiOn;
  final ValueNotifier<Set<String>> multi;
  final VoidCallback onClearMulti;
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
  final ValueNotifier<bool> _snap = ValueNotifier<bool>(true);

  bool _userScrolling = false;
  double? _scrubTime;
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
    editor.addListener(_syncScroll);
  }

  @override
  void dispose() {
    editor.removeListener(_syncScroll);
    _snap.dispose();
    _sc.dispose();
    _vc.dispose();
    _hc.dispose();
    super.dispose();
  }

  // Playhead-follow: pure scroll, no setState → zero widget rebuilds.
  void _syncScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || _pointers >= 2 || !_sc.hasClients) return;
      final double pps = 28.0 * editor.zoom;
      final double target = (_seconds(editor.playhead) * pps)
          .clamp(0.0, _sc.position.maxScrollExtent)
          .toDouble();
      if ((_sc.offset - target).abs() > 0.5) _sc.jumpTo(target);
    });
  }

  bool _isOverlay(_ClipSnapshot c) =>
      c.type != ClipType.audio && c.type != ClipType.video && c.type != ClipType.image;

  List<_Lane> _lanes(List<_ClipSnapshot> clips) {
    final main = clips.where((c) => c.isMain).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final audio = clips.where((c) => c.type == ClipType.audio).toList();
    final layers =
        clips.where(_isOverlay).map<int>((c) => c.layer).toSet().toList()..sort();
    return <_Lane>[
      for (final l in layers.reversed)
        _Lane(_textH, _ClipKind.text,
            clips.where((c) => _isOverlay(c) && c.layer == l).toList()),
      _Lane(_videoH, _ClipKind.video, main, add: true),
      if (audio.isNotEmpty) _Lane(_audioH, _ClipKind.audio, audio),
    ];
  }

  double _snapTime(double t, double pps, List<_ClipSnapshot> clips,
      {String? excludeId}) {
    if (!_snap.value) return t;
    double best = t;
    double bd = 8 / pps;
    final double ph = _seconds(editor.playhead);
    for (final double e in <double>[ph, 0.0]) {
      final double d = (e - t).abs();
      if (d < bd) {
        bd = d;
        best = e;
      }
    }
    for (final c in clips) {
      if (c.id == excludeId) continue;
      for (final double e in <double>[c.startSec, c.endSec]) {
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

  // Neighbour clamp + snap for clip MOVE on the main lane.
  double _constrainMove(_ClipSnapshot clip, double desired, double pps,
      List<_ClipSnapshot> mainClips) {
    double s = _snapTime(desired, pps, mainClips, excludeId: clip.id);
    double lo = 0;
    double hi = double.infinity;
    for (final c in mainClips) {
      if (c.id == clip.id) continue;
      if (c.endSec <= clip.startSec + 1e-6) lo = math.max(lo, c.endSec);
      if (c.startSec >= clip.endSec - 1e-6) hi = math.min(hi, c.startSec);
    }
    final double maxS = math.max(lo, hi - clip.durSec);
    if (s < lo) s = lo;
    if (s > maxS) s = maxS;
    return s;
  }

  void _setZoom(double z) => editor.setZoom(z.clamp(0.5, 8.0).toDouble());

  // Zoom anchored at `anchorX` (viewport px) so the content under the finger
  // (or the playhead, for the buttons) stays put.
  void _applyZoom(double newZoom, double anchorX, double half) {
    final double oldPps = 28.0 * editor.zoom;
    final double total = math.max(_seconds(editor.project.totalDuration), 1.0);
    final double t =
        ((_sc.offset + anchorX - half) / oldPps).clamp(0.0, total).toDouble();
    _setZoom(newZoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sc.hasClients) return;
      final double pps = 28.0 * editor.zoom;
      final double target = (t * pps + half - anchorX)
          .clamp(0.0, _sc.position.maxScrollExtent)
          .toDouble();
      _sc.jumpTo(target);
    });
  }

  _ClipSnapshot? _clipAt(double t, List<_ClipSnapshot> clips) {
    for (final c in clips) {
      if (c.isMain && t >= c.startSec && t <= c.endSec) return c;
    }
    return null;
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

  Widget scrubCard(double half, double width, List<_ClipSnapshot> clips) {
    final double t = _scrubTime ?? 0;
    final _ClipSnapshot? clip = _clipAt(t, clips);
    final String? path = clip?.path;
    Widget thumb;
    if (path != null && _isImagePath(path)) {
      thumb = Image.file(File(path), fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _Stripes());
    } else if (path != null && thumbGenerator != null) {
      final int localMs =
          ((t - clip!.startSec).clamp(0.0, clip.durSec) * 1000).round();
      thumb = FutureBuilder<Uint8List?>(
        future: ThumbCache.get(path, localMs, 160),
        builder: (_, s) {
          final Uint8List? b = s.data;
          if (b == null) return const _Stripes();
          return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
        },
      );
    } else {
      thumb = const _Stripes();
    }
    return Positioned(
      left: (half - 75).clamp(6.0, math.max(6.0, width - 156)).toDouble(),
      top: 4,
      child: IgnorePointer(
        child: Container(
          width: 150,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _divider),
            boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                child: SizedBox(height: 58, width: 150, child: thumb),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(_tc(t),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _divider)),
      ),
      // Height depends only on lane structure + zoom — both inside the model.
      child: LayoutBuilder(
        builder: (context, c) {
          final double half = c.maxWidth * _playheadFrac;
          return Selector<EditorController, _TimelineModel>(
            selector: (_, e) => _TimelineModel.from(e),
            builder: (context, model, _) {
              final double total = math.max(model.totalMs / 1000.0, 1.0);
              final double pps = 28.0 * model.zoom;
              final List<_Lane> lanes = _lanes(model.clips);
              final double contentH =
                  _rulerH + lanes.fold<double>(0, (s, l) => s + l.h + _gap) + 16;
              final double maxH = widget.compact ? 150 : 230;
              final double contentW = total * pps + c.maxWidth;

              return SizedBox(
                height: math.min(contentH, maxH),
                child: Stack(
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
                        onScaleStart: (_) => _baseZoom = model.zoom,
                        onScaleUpdate: (d) {
                          if (d.pointerCount >= 2) {
                            final box = context.findRenderObject();
                            final double ax = box is RenderBox
                                ? box.globalToLocal(d.focalPoint).dx
                                : half;
                            _applyZoom(_baseZoom * d.scale, ax, half);
                          }
                        },
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.axis != Axis.horizontal) return false;
                            if (n is ScrollStartNotification &&
                                n.dragDetails != null) {
                              _userScrolling = true;
                              _scrubTime = n.metrics.pixels / pps;
                            } else if (n is ScrollUpdateNotification &&
                                _userScrolling) {
                              final double t = _snapTime(
                                  n.metrics.pixels / pps, pps, model.clips);
                              setState(() => _scrubTime = t);
                              _seek(editor, t);
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
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (d) {
                                          widget.onClearMulti();
                                          _seek(editor,
                                              (d.localPosition.dx - half) / pps);
                                        },
                                        child: SizedBox(
                                          height: _rulerH,
                                          width: contentW,
                                          child: CustomPaint(
                                            painter: _RulerPainter(
                                                pps: pps,
                                                seconds: total + 5,
                                                leftPad: half),
                                          ),
                                        ),
                                      ),
                                      for (final l in lanes)
                                        _lane(l, contentW, pps, half, model),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
                                    child: SizedBox(
                                        height: l.h,
                                        child: _header(l, model.clips)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
                                boxShadow: <BoxShadow>[
                                  BoxShadow(color: Colors.black54, blurRadius: 4)
                                ],
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
                          ValueListenableBuilder<bool>(
                            valueListenable: _snap,
                            builder: (_, snap, __) => _chip(
                                Icons.align_horizontal_center_rounded,
                                'Snap',
                                snap,
                                () => _snap.value = !_snap.value),
                          ),
                          const SizedBox(width: 4),
                          _chip(Icons.remove_rounded, 'Zoom out', false,
                              () => _applyZoom(model.zoom - 0.5, half, half)),
                          const SizedBox(width: 4),
                          _chip(Icons.add_rounded, 'Zoom in', false,
                              () => _applyZoom(model.zoom + 0.5, half, half)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _header(_Lane l, List<_ClipSnapshot> all) {
    final bool locked = l.clips.isNotEmpty && l.clips.every((c) => c.locked);
    final bool visible = l.clips.any((c) => c.visible);
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
          if (c.locked == locked) editor.toggleClipLock(c.id);
        }
      }),
      btn(visible ? Icons.visibility_rounded : Icons.visibility_off_rounded, !visible,
          visible ? 'Hide track' : 'Show track', () {
        for (final c in l.clips) {
          if (c.visible == visible) editor.toggleClipVisibility(c.id);
        }
      }),
    ];
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
              decoration:
                  const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, size: 18, color: Colors.black),
            ),
          ),
        ),
      );

  Widget _lane(_Lane l, double contentW, double pps, double half, _TimelineModel m) {
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
                left: half + list[i].startSec * pps,
                top: 0,
                bottom: 0,
                width: math.max(44.0, list[i].durSec * pps - 4),
                child: RepaintBoundary(
                  child: _ClipBlock(
                    editor: editor,
                    clip: list[i],
                    kind: l.kind,
                    pps: pps,
                    selected: m.selectedId == list[i].id,
                    multiOn: widget.multiOn,
                    multi: widget.multi,
                    moveClamp: l.kind == _ClipKind.video
                        ? (desired) =>
                            _constrainMove(list[i], desired, pps, list)
                        : (desired) => math.max(
                            0.0,
                            _snapTime(desired, pps, m.clips, excludeId: list[i].id)),
                  ),
                ),
              ),
              // Transition picker between main-track clips (now tappable).
              if (l.kind == _ClipKind.video && i < list.length - 1)
                Positioned(
                  left: half + list[i].endSec * pps - 12,
                  top: l.h / 2 - 10,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _tap();
                      _showTransitionSheet(context);
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.join_inner_rounded,
                          size: 13, color: Colors.black),
                    ),
                  ),
                ),
            ],
            if (l.add)
              _addButton(
                  half + (list.isEmpty ? 0 : list.last.endSec * pps) + 4, l.h),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Clip block (stateful: holds drag origin/accumulator across rebuilds)
// ----------------------------------------------------------------------------
class _ClipBlock extends StatefulWidget {
  const _ClipBlock({
    required this.editor,
    required this.clip,
    required this.kind,
    required this.pps,
    required this.selected,
    required this.multiOn,
    required this.multi,
    required this.moveClamp,
  });
  final EditorController editor;
  final _ClipSnapshot clip;
  final _ClipKind kind;
  final double pps;
  final bool selected;
  final ValueNotifier<bool> multiOn;
  final ValueNotifier<Set<String>> multi;
  final double Function(double desiredStart) moveClamp;

  @override
  State<_ClipBlock> createState() => _ClipBlockState();
}

class _ClipBlockState extends State<_ClipBlock> {
  double _originStart = 0;
  double _accum = 0;

  void _startMove() {
    widget.editor.selectClip(widget.clip.id);
    _originStart = widget.clip.startSec;
    _accum = 0;
  }

  void _updateMove(double dx) {
    _accum += dx / widget.pps;
    final double s = widget.moveClamp(_originStart + _accum);
    widget.editor.trimSelectedClip(
      Duration(milliseconds: (s * 1000).round()),
      Duration(milliseconds: ((s + widget.clip.durSec) * 1000).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final bool locked = clip.locked;
    final Color border = widget.selected ? Colors.white : Colors.transparent;

    Widget body;
    switch (widget.kind) {
      case _ClipKind.text:
        final bool sticker =
            clip.type == ClipType.sticker || clip.type == ClipType.element;
        final bool drawing = clip.type == ClipType.drawing;
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
            Icon(icon, size: 15, color: Colors.white70),
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
                LayoutBuilder(
                  builder: (context, c) => (clip.path != null &&
                          !locked)
                      ? _Filmstrip(
                          key: ValueKey<String>('${clip.id}|${widget.pps.toStringAsFixed(2)}'),
                          path: clip.path!,
                          durationSec: clip.durSec,
                          width: c.maxWidth,
                        )
                      : const _Stripes(),
                ),
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('${clip.durSec.toStringAsFixed(1)}s',
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
            child: (clip.path != null)
                ? _WaveformLoader(path: clip.path!)
                : const SizedBox.expand(),
          ),
        );
    }

    // Trim handles (guarded clamps — no more inverted-clamp crash).
    if (widget.selected && !locked) {
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
              onHorizontalDragUpdate: (d) {
                final double newStart = (clip.startSec + d.delta.dx / widget.pps)
                    .clamp(0.0, math.max(0.0, clip.endSec - 0.2))
                    .toDouble();
                widget.editor.trimSelectedClip(
                  Duration(milliseconds: (newStart * 1000).round()),
                  Duration(milliseconds: (clip.endSec * 1000).round()),
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
              onHorizontalDragUpdate: (d) {
                final double newEnd = (clip.endSec + d.delta.dx / widget.pps)
                    .clamp(clip.startSec + 0.2, 86400.0)
                    .toDouble();
                widget.editor.trimSelectedClip(
                  Duration(milliseconds: (clip.startSec * 1000).round()),
                  Duration(milliseconds: (newEnd * 1000).round()),
                );
              },
              child: const _Handle(),
            ),
          ),
        ],
      );
    }

    final bool multiActive = widget.multiOn.value;
    final bool inMulti = widget.multi.value.contains(clip.id);

    return GestureDetector(
      onTap: () {
        _tap();
        if (multiActive) {
          final Set<String> next = Set<String>.of(widget.multi.value);
          if (!next.remove(clip.id)) next.add(clip.id);
          widget.multi.value = next;
        } else {
          widget.editor.selectClip(clip.id);
        }
      },
      onLongPress: () {
        _tap();
        widget.multiOn.value = true;
        widget.multi.value = <String>{clip.id};
      },
      onHorizontalDragStart: locked || multiActive ? null : (_) => _startMove(),
      onHorizontalDragUpdate: locked || multiActive ? null : (d) => _updateMove(d.delta.dx),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: clip.visible ? 1 : 0.35,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(child: body),
            if (locked)
              const Positioned(
                top: 4,
                right: 6,
                child: Icon(Icons.lock_rounded, size: 11, color: Colors.white70),
              ),
            if (inMulti)
              const Positioned(
                top: 4,
                left: 6,
                child: Icon(Icons.check_circle_rounded,
                    size: 14, color: _accent),
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

// ----------------------------------------------------------------------------
// Filmstrip thumbnails (async, cached; stripes until a generator is wired)
// ----------------------------------------------------------------------------
class _Stripes extends StatelessWidget {
  const _Stripes();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => CustomPaint(
        painter: _FilmPainter(),
        child: SizedBox(width: c.maxWidth, height: c.maxHeight),
      ),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    super.key,
    required this.path,
    required this.durationSec,
    required this.width,
  });
  final String path;
  final double durationSec;
  final double width;

  @override
  Widget build(BuildContext context) {
    final int n = (width / 48).ceil().clamp(1, 24);
    final double step = durationSec / n;
    final double cellW = width / n;
    return ClipRect(
      child: Row(
        children: <Widget>[
          for (int i = 0; i < n; i++)
            SizedBox(
              width: cellW,
              height: double.infinity,
              child: FutureBuilder<Uint8List?>(
                future: ThumbCache.get(path, (i * step * 1000).round(), 96),
                builder: (_, s) {
                  final Uint8List? b = s.data;
                  if (b == null) return const _Stripes();
                  return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FilmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2A2A30));
    final double fw = math.max(14, size.height * 0.85);
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

class _WaveformLoader extends StatelessWidget {
  const _WaveformLoader({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final int bars = math.max(8, (c.maxWidth / 5).floor());
        return FutureBuilder<List<double>>(
          future: _waveFuture(path, bars),
          builder: (_, s) => CustomPaint(
            painter: _WavePainter(amps: s.data ?? List<double>.filled(bars, 0.4)),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.amps});
  final List<double> amps;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0xFF7FD6E8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double gap = size.width / amps.length;
    for (int i = 0; i < amps.length; i++) {
      final double x = gap * (i + 0.5);
      final double h = math.max(3.0, amps[i] * (size.height - 8));
      canvas.drawLine(
          Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.amps != amps;
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
// Transition picker (join icon)
// TODO(controller): persist the chosen transition on the clip (e.g.
// editor.setTransition(leftClipId, type)).
// ----------------------------------------------------------------------------
enum _TransitionType { none, fade, slide, zoom, blur }

void _showTransitionSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Transition',
                style: TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                for (final t in _TransitionType.values)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _tap();
                        // TODO(controller): apply `t` to the clip pair.
                        Navigator.of(context).pop();
                      },
                      child: Column(
                        children: <Widget>[
                          Container(
                            height: 46,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF26262C),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                                switch (t) {
                                  _TransitionType.none => Icons.block_rounded,
                                  _TransitionType.fade => Icons.blur_on_rounded,
                                  _TransitionType.slide => Icons.swipe_rounded,
                                  _TransitionType.zoom => Icons.zoom_in_rounded,
                                  _TransitionType.blur => Icons.blur_circular_rounded,
                                },
                                color: Colors.white70,
                                size: 20),
                          ),
                          const SizedBox(height: 6),
                          Text(t.name,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ----------------------------------------------------------------------------
// Bottom toolbar (icon-only; titles exposed via tooltips for a11y)
// ----------------------------------------------------------------------------
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    super.key,
    required this.onOpen,
    required this.multiOn,
    required this.multi,
    required this.onClearMulti,
  });
  final void Function(_Tool) onOpen;
  final ValueNotifier<bool> multiOn;
  final ValueNotifier<Set<String>> multi;
  final VoidCallback onClearMulti;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final TimelineClip? sel = editor.selectedClip;
    final bool canSplit =
        sel != null && editor.playhead > sel.start && editor.playhead < sel.end;
    final bool selIsMain =
        sel != null && (sel.clipType == ClipType.video || sel.clipType == ClipType.image);

    Widget item(IconData icon, String tip, VoidCallback? onTap, {Color? color}) {
      final bool enabled = onTap != null;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: enabled
              ? () {
                  _tap();
                  onTap();
                }
              : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 50,
            child: Icon(icon,
                size: 22, color: enabled ? (color ?? Colors.white) : Colors.white24),
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
          height: 54,
          child: Stack(
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: multiOn,
                builder: (context, multiActive, _) => ValueListenableBuilder<Set<String>>(
                  valueListenable: multi,
                  builder: (context, multiSet, _) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(left: 4, right: 28),
                      child: Row(
                        children: <Widget>[
                          if (multiActive) ...<Widget>[
                            item(Icons.check_rounded, 'Done', onClearMulti),
                            item(
                              Icons.content_cut_rounded,
                              'Split selected',
                              multiSet.isEmpty
                                  ? null
                                  : () {
                                      final ids = multiSet.toList();
                                      for (final id in ids) {
                                        editor.selectClip(id);
                                        editor.splitSelectedClip();
                                      }
                                      onClearMulti();
                                    },
                            ),
                            item(
                              Icons.delete_rounded,
                              'Delete selected',
                              multiSet.isEmpty
                                  ? null
                                  : () {
                                      final ids = multiSet.toList();
                                      for (final id in ids) {
                                        editor.selectClip(id);
                                        editor.deleteSelectedClip();
                                      }
                                      onClearMulti();
                                    },
                              color: Colors.redAccent,
                            ),
                            _vDivider(),
                          ] else ...<Widget>[
                            item(
                              Icons.content_cut_rounded,
                              'Split all tracks',
                              canSplit ? () => _splitAllTracks(editor) : null,
                            ),
                            item(Icons.delete_rounded, 'Delete',
                                sel != null ? editor.deleteSelectedClip : null,
                                color: Colors.redAccent),
                            item(Icons.delete_sweep_rounded, 'Ripple delete',
                                selIsMain ? () => _rippleDelete(editor) : null,
                                color: Colors.redAccent),
                            _vDivider(),
                          ],
                          tool(_Tool.audio),
                          tool(_Tool.text),
                          item(Icons.subtitles_rounded, 'Auto captions',
                              editor.generateAutoCaptions),
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
                    );
                  },
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

  Widget _vDivider() => Container(
      width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 2),
      color: _divider);
}

// ----------------------------------------------------------------------------
// Tool Sheet Implementations
// ----------------------------------------------------------------------------

class AudioToolsSheet extends StatelessWidget {
  const AudioToolsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final clip = editor.selectedClip;
    final bool hasAudio = clip != null && (clip.clipType == ClipType.audio || clip.clipType == ClipType.video);
    final double volume = clip?.volume ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.music_note_rounded, color: _accent),
          title: const Text('Add Audio Track', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Insert soundtrack clip to timeline', style: TextStyle(color: _muted, fontSize: 11)),
          trailing: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
            onPressed: () {
              _tap();
              editor.addAudioTrack('Track ${editor.clips.where((c) => c.clipType == ClipType.audio).length + 1}');
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
          ),
        ),
        if (hasAudio) ...<Widget>[
          const Divider(color: _divider, height: 24),
          Row(
            children: <Widget>[
              const Text('Volume', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${(volume * 100).round()}%', style: const TextStyle(color: _accent, fontSize: 12)),
            ],
          ),
          Slider(
            value: volume,
            min: 0.0,
            max: 2.0,
            activeColor: _accent,
            inactiveColor: _divider,
            onChanged: (val) {
              editor.updateAudioProperties(AudioProperties(volume: val, speed: clip.speed));
            },
          ),
        ],
      ],
    );
  }
}

class TextAnimationSheet extends StatefulWidget {
  const TextAnimationSheet({super.key});

  @override
  State<TextAnimationSheet> createState() => _TextAnimationSheetState();
}

class _TextAnimationSheetState extends State<TextAnimationSheet> {
  final TextEditingController _ctrl = TextEditingController(text: 'Sample Text');
  String _selectedFont = 'Poppins';
  TextAnimationStyle _anim = TextAnimationStyle.fadeIn;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Text Content',
            labelStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedFont,
                dropdownColor: _surface,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Font Family',
                  labelStyle: const TextStyle(color: _muted),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                items: const <String>['Poppins', 'Unbounded', 'Roboto', 'Arial']
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedFont = v);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<TextAnimationStyle>(
                initialValue: _anim,
                dropdownColor: _surface,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Animation',
                  labelStyle: const TextStyle(color: _muted),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                items: TextAnimationStyle.values
                    .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _anim = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(44)),
          onPressed: () {
            _tap();
            if (editor.selectedClip?.clipType == ClipType.text) {
              editor.updateSelectedTextProperties(text: _ctrl.text, fontFamily: _selectedFont, textAnimationStyle: _anim);
            } else {
              editor.addTextOverlay(_ctrl.text.isEmpty ? 'Text' : _ctrl.text, fontFamily: _selectedFont, animationStyle: _anim);
            }
          },
          icon: const Icon(Icons.add),
          label: Text(editor.selectedClip?.clipType == ClipType.text ? 'Update Selected Text' : 'Add Text Clip'),
        ),
      ],
    );
  }
}

class StickersSheet extends StatelessWidget {
  const StickersSheet({super.key});

  static const List<String> _emojis = <String>['🔥', '✨', '⚡', '🎉', '❤️', '🌟', '🎬', '👏', '🚀', '💯'];

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: _emojis.length,
      itemBuilder: (context, index) {
        final emoji = _emojis[index];
        return InkWell(
          onTap: () {
            _tap();
            editor.addTextOverlay(emoji, fontFamily: 'Poppins');
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
        );
      },
    );
  }
}

class EffectsSheet extends StatelessWidget {
  const EffectsSheet({super.key, required this.isFilterMode});
  final bool isFilterMode;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final currentEffect = editor.selectedClip?.effect ?? VideoEffect.none;

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      children: VideoEffect.values.map((fx) {
        final selected = fx == currentEffect;
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ChoiceChip(
            selected: selected,
            selectedColor: _accent,
            backgroundColor: _surface,
            labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
            label: Text(fx.name.toUpperCase()),
            onSelected: (_) {
              _tap();
              editor.applyEffect(fx);
            },
          ),
        );
      }).toList(),
    );
  }
}

class ColorGradingSheet extends StatefulWidget {
  const ColorGradingSheet({super.key});

  @override
  State<ColorGradingSheet> createState() => _ColorGradingSheetState();
}

class _ColorGradingSheetState extends State<ColorGradingSheet> {
  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _sliderRow('Brightness', _brightness, -0.5, 0.5, (v) {
          setState(() => _brightness = v);
          editor.updateColorGrading(ColorGradingSettings(brightness: _brightness, contrast: _contrast, saturation: _saturation));
        }),
        _sliderRow('Contrast', _contrast, 0.5, 2.0, (v) {
          setState(() => _contrast = v);
          editor.updateColorGrading(ColorGradingSettings(brightness: _brightness, contrast: _contrast, saturation: _saturation));
        }),
        _sliderRow('Saturation', _saturation, 0.0, 2.0, (v) {
          setState(() => _saturation = v);
          editor.updateColorGrading(ColorGradingSettings(brightness: _brightness, contrast: _contrast, saturation: _saturation));
        }),
      ],
    );
  }

  Widget _sliderRow(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
            const Spacer(),
            Text(val.toStringAsFixed(2), style: const TextStyle(color: _accent, fontSize: 12)),
          ],
        ),
        Slider(value: val, min: min, max: max, activeColor: _accent, inactiveColor: _divider, onChanged: onChanged),
      ],
    );
  }
}

class CropSheet extends StatelessWidget {
  const CropSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _ratioBtn(context, '16:9', () => editor.updateTranslation(scale: 1.0)),
        _ratioBtn(context, '9:16', () => editor.updateTranslation(scale: 1.2)),
        _ratioBtn(context, '1:1', () => editor.updateTranslation(scale: 1.1)),
        _ratioBtn(context, '4:5', () => editor.updateTranslation(scale: 1.05)),
      ],
    );
  }

  Widget _ratioBtn(BuildContext context, String label, VoidCallback onTap) {
    return ActionChip(
      backgroundColor: Colors.white10,
      label: Text(label, style: const TextStyle(color: Colors.white)),
      onPressed: () {
        _tap();
        onTap();
      },
    );
  }
}

class ElementsSheet extends StatelessWidget {
  const ElementsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: ElementShape.values.length,
      itemBuilder: (context, index) {
        final shape = ElementShape.values[index];
        return InkWell(
          onTap: () {
            _tap();
            editor.addElementClip(shape, label: shape.name, color: Colors.cyanAccent);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.category_rounded, color: _accent, size: 24),
                const SizedBox(height: 4),
                Text(shape.name, style: const TextStyle(color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class VectorDrawingSheet extends StatefulWidget {
  const VectorDrawingSheet({super.key});

  @override
  State<VectorDrawingSheet> createState() => _VectorDrawingSheetState();
}

class _VectorDrawingSheetState extends State<VectorDrawingSheet> {
  Color _color = Colors.cyanAccent;
  double _width = 4.0;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('Stroke Width', style: TextStyle(color: Colors.white, fontSize: 13)),
            Expanded(
              child: Slider(
                value: _width,
                min: 1.0,
                max: 20.0,
                activeColor: _accent,
                inactiveColor: _divider,
                onChanged: (v) {
                  setState(() => _width = v);
                  editor.setStrokeWidth(v);
                },
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Color>[Colors.cyanAccent, Colors.redAccent, Colors.greenAccent, Colors.yellowAccent, Colors.white]
              .map((c) => GestureDetector(
                    onTap: () {
                      setState(() => _color = c);
                      editor.setDrawingColor(c);
                    },
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 14,
                      child: _color == c ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _tap();
                  editor.clearActiveDrawing();
                },
                child: const Text('Clear', style: TextStyle(color: Colors.white70)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
                onPressed: () {
                  _tap();
                  editor.saveVectorDrawingAsClip();
                },
                child: const Text('Save Clip'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MaskSheet extends StatelessWidget {
  const MaskSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      children: MaskType.values.map((type) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ActionChip(
            backgroundColor: Colors.white10,
            label: Text(type.name.toUpperCase(), style: const TextStyle(color: Colors.white)),
            onPressed: () {
              _tap();
              editor.updateMaskProperties(MaskProperties(type: type, feather: 10.0));
            },
          ),
        );
      }).toList(),
    );
  }
}

class KeyframeSheet extends StatelessWidget {
  const KeyframeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final keyframes = editor.selectedClip?.keyframes ?? <Keyframe>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
          onPressed: () {
            _tap();
            editor.addKeyframe(Keyframe(
              id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
              time: editor.playhead,
              property: KeyframeProperty.scale,
              value: 1.0,
            ));
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Keyframe at Playhead'),
        ),
        const SizedBox(height: 12),
        ...keyframes.map((kf) => ListTile(
              dense: true,
              title: Text('${kf.property} @ ${_seconds(kf.time).toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white)),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                onPressed: () => editor.removeKeyframe(kf.id),
              ),
            )),
      ],
    );
  }
}

class CameraSettingsSheet extends StatelessWidget {
  const CameraSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final props = editor.selectedClip?.cameraProperties ?? const CameraProperties();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('Focal Length', style: TextStyle(color: Colors.white, fontSize: 13)),
            Expanded(
              child: Slider(
                value: props.focalLength,
                min: 10.0,
                max: 200.0,
                activeColor: _accent,
                inactiveColor: _divider,
                onChanged: (v) => editor.updateCameraProperties(props.copyWith(focalLength: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class CameraTrackingPanel extends StatelessWidget {
  const CameraTrackingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final tracking = editor.selectedClip?.trackingData;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Tracking Status: ${tracking?.isEnabled == true ? "Active" : "None"}', style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
            onPressed: () {
              _tap();
              editor.updateTrackingData(const TrackingData(
                isEnabled: true,
                targetName: 'Subject',
                rect: Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
              ));
            },
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Start Auto-Tracking'),
          ),
        ],
      ),
    );
  }
}

class PluginsSheet extends StatelessWidget {
  const PluginsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final plugins = PluginManager().activePlugins;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final p = plugins[index];
        return ListTile(
          leading: const Icon(Icons.extension_rounded, color: _accent),
          title: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(p.version, style: const TextStyle(color: _muted, fontSize: 11)),
        );
      },
    );
  }
}
