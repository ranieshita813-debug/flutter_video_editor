import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/editor_toolbar.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/skeleton_grid.dart';
import 'package:flutter_video_editor/features/editor/widgets/speed_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/clip_animation_sheet.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/text_style_sheet.dart';
import 'package:flutter_video_editor/features/effects/services/effect_preview_service.dart';

// ----------------------------------------------------------------------------
// Tokens
// ----------------------------------------------------------------------------
const Color _bg = Color(0xFF000000);
const Color _surface = Color(0xFF101014);
const Color _card = Color(0xFF232327);
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

/// Overlay clip coordinates are interpreted in a 360-unit-wide design space
/// that scales with the canvas, so layouts look identical on every device.
const double _designW = 360;

// ----------------------------------------------------------------------------
// Responsive helpers
// ----------------------------------------------------------------------------
double _scaleOf(Size size) => (size.shortestSide / 400).clamp(0.9, 1.25).toDouble();

bool _isWide(Size size) =>
    size.width >= 840 || (size.width > size.height && size.width >= 700);

bool _isShort(Size size) => size.height < 520;

int _cols(double width, double tile, {int min = 2, int max = 8}) =>
    (width / tile).floor().clamp(min, max);

// ----------------------------------------------------------------------------
// Canvas aspect ratio (shared between the Canvas tool and the preview)
// ----------------------------------------------------------------------------
enum _CanvasRatio {
  r16x9('16:9', 16 / 9),
  r9x16('9:16', 9 / 16),
  r1x1('1:1', 1),
  r4x5('4:5', 4 / 5),
  r21x9('21:9', 21 / 9);

  const _CanvasRatio(this.label, this.value);
  final String label;
  final double value;
}

final ValueNotifier<_CanvasRatio> _canvasRatio =
    ValueNotifier<_CanvasRatio>(_CanvasRatio.r16x9);

// ----------------------------------------------------------------------------
// Small utils
// ----------------------------------------------------------------------------
double _seconds(Duration v) => v.inMilliseconds / 1000.0;
String _two(int n) => n.toString().padLeft(2, '0');

String _tc(double s) {
  final int f = (math.max(s, 0) * _fps).round();
  final int sec = f ~/ _fps;
  return '${_two(sec ~/ 3600)}:${_two(sec % 3600 ~/ 60)}:${_two(sec % 60)}:${_two(f % _fps)}';
}

String _tcShort(double s) {
  final int f = (math.max(s, 0) * _fps).round();
  final int sec = f ~/ _fps;
  return '${_two(sec ~/ 60)}:${_two(sec % 60)}.${_two(f % _fps)}';
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

/// True while a text field has focus, so keyboard shortcuts don't hijack typing.
bool _typing() {
  final BuildContext? c = FocusManager.instance.primaryFocus?.context;
  if (c == null) return false;
  return c.widget is EditableText ||
      c.findAncestorWidgetOfExactType<EditableText>() != null;
}

VoidCallback _guard(VoidCallback f) => () {
      if (!_typing()) f();
    };

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
  audio('Audio', HugeIcons.strokeRoundedVolumeHigh),
  text('Text', HugeIcons.strokeRoundedTextFont),
  stickers('Stickers', HugeIcons.strokeRoundedSmile),
  filters('Filters', HugeIcons.strokeRoundedFilter),
  effects('Effects', HugeIcons.strokeRoundedMagicWand01),
  adjust('Adjust', HugeIcons.strokeRoundedLayers01),
  crop('Canvas', HugeIcons.strokeRoundedCrop),
  speed('Speed', HugeIcons.strokeRoundedTime01),
  elements('Elements', HugeIcons.strokeRoundedShapes),
  draw('Draw', HugeIcons.strokeRoundedPencilEdit02),
  mask('Mask', HugeIcons.strokeRoundedSquare),
  camera('Camera', HugeIcons.strokeRoundedCamera01),
  track('Track', HugeIcons.strokeRoundedTarget01),
  plugins('Plug-ins', HugeIcons.strokeRoundedGridView),
  textStyle('Text Style', HugeIcons.strokeRoundedTextFont),
  animation('Animation', HugeIcons.strokeRoundedPlay);

  const _Tool(this.title, this.icon);
  final String title;
  final dynamic icon;

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
        _Tool.camera => const CameraSettingsSheet(),
        _Tool.track => const CameraTrackingPanel(),
        _Tool.plugins => const PluginsSheet(),
        _Tool.textStyle => const TextStyleSheet(),
        _Tool.animation => const ClipAnimationSheet(),
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
  double _frac = 0.34;
  double _splitAdj = 0, _minAdj = -400, _maxAdj = 400;
  bool _dragging = false;

  // Multi-select lives here so both the timeline and the toolbar can share it.
  final ValueNotifier<bool> _multiOn = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> _multi = ValueNotifier<Set<String>>(<String>{});

  void _open(_Tool t) {
    _tap();
    setState(() => _tool = _tool == t ? null : t);
  }

  void _openSheet(String sheetName) {
    _Tool? target;
    switch (sheetName) {
      case 'audio': target = _Tool.audio; break;
      case 'text': target = _Tool.text; break;
      case 'stickers': target = _Tool.stickers; break;
      case 'filters': target = _Tool.filters; break;
      case 'effects': target = _Tool.effects; break;
      case 'adjust': target = _Tool.adjust; break;
      case 'crop': target = _Tool.crop; break;
      case 'speed': target = _Tool.speed; break;
      case 'elements': target = _Tool.elements; break;
      case 'draw': target = _Tool.draw; break;
      case 'mask': target = _Tool.mask; break;
      case 'camera': target = _Tool.camera; break;
      case 'track': target = _Tool.track; break;
      case 'plugins': target = _Tool.plugins; break;
      case 'text_style': target = _Tool.textStyle; break;
      case 'animation': target = _Tool.animation; break;
    }
    if (target != null) {
      _open(target);
    }
  }

  void _close() => setState(() => _tool = null);

  void _clearMulti() {
    _multiOn.value = false;
    _multi.value = <String>{};
  }

  @override
  void initState() {
    super.initState();
    _canvasRatio.addListener(_resetSplit);
  }

  void _resetSplit() {
    if (mounted) setState(() => _splitAdj = 0);
  }

  @override
  void dispose() {
    _canvasRatio.removeListener(_resetSplit);
    _multiOn.dispose();
    _multi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final Size size = MediaQuery.sizeOf(context);
    final bool wide = _isWide(size);
    final bool keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): _guard(editor.togglePlayback),
        const SingleActivator(LogicalKeyboardKey.keyK): _guard(editor.togglePlayback),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            _guard(() => _seek(editor, _seconds(editor.playhead) - 1 / _fps)),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            _guard(() => _seek(editor, _seconds(editor.playhead) + 1 / _fps)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            _guard(() => _seek(editor, _seconds(editor.playhead) - 1.0)),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            _guard(() => _seek(editor, _seconds(editor.playhead) + 1.0)),
        const SingleActivator(LogicalKeyboardKey.keyS):
            _guard(() => _splitAllTracks(editor)),
        const SingleActivator(LogicalKeyboardKey.delete): _guard(() {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        }),
        const SingleActivator(LogicalKeyboardKey.backspace): _guard(() {
          if (editor.selectedClip != null) editor.deleteSelectedClip();
        }),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _guard(editor.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _guard(editor.undo),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _guard(editor.redo),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
            _guard(editor.redo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _guard(editor.redo),
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _multiOn,
          builder: (context, _) => PopScope(
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
              resizeToAvoidBottomInset: true,
              body: LayoutBuilder(builder: (context, c) {
                final double panelH = math
                    .min(c.maxHeight * _frac, c.maxHeight * 0.6)
                    .clamp(160.0, 520.0)
                    .toDouble();
                final double sideW =
                    (c.maxWidth * 0.3).clamp(320.0, 440.0).toDouble();
                final bool hideTimeline = keyboard && _tool != null && !wide;

                final Widget toolbar = EditorToolbar(
                  key: const ValueKey('bar'),
                  onSelectToolSheet: _openSheet,
                  onAddMedia: () async {
                    final nav = Navigator.of(context);
                    final mediaPath = await nav.pushNamed('/media_picker');
                    if (mediaPath != null && mediaPath is String) {
                      editor.addMediaClip(mediaPath);
                    }
                  },
                );

                final Widget main = Column(
                  children: <Widget>[
                    ValueListenableBuilder<_CanvasRatio>(
                      valueListenable: _canvasRatio,
                      builder: (context, ratio, _) {
                        final Widget pv = _Preview(editor: editor);
                        if (hideTimeline) return Expanded(child: pv);
                        final double s = _scaleOf(size);
                        final EdgeInsets safe = MediaQuery.paddingOf(context);
                        final double pad = 10 * s;
                        final double colW = wide
                            ? c.maxWidth - (_tool != null ? sideW : 0)
                            : c.maxWidth;
                        final double topH = 52 * s + safe.top;
                        final double transportH = 52 * s + 16; // transport + divider
                        final double barH = (64 * s).clamp(60.0, 80.0).toDouble();
                        final double bottomH =
                            ((wide || _tool == null) ? barH : panelH) + safe.bottom;
                        final double tlMin = (_isShort(size) ? 90 : 120) * s;
                        final double tlMax = 240 * s;
                        // Canvas height = canvas width / ratio (plus chrome).
                        final double desired =
                            topH + (colW - 2 * pad) / ratio.value + 2 * pad;
                        final double maxP =
                            math.max(80.0, c.maxHeight - transportH - bottomH - tlMin);
                        final double minP = math.min(
                            maxP,
                            math.max(80.0,
                                c.maxHeight - transportH - bottomH - tlMax));
                        final double base = desired.clamp(minP, maxP).toDouble();
                        final double lo = math.min(
                            maxP, math.max(80.0, c.maxHeight - transportH - bottomH - 420 * s));
                        _minAdj = lo - base;
                        _maxAdj = maxP - base;
                        final double hgt =
                            (base + _splitAdj.clamp(_minAdj, _maxAdj)).toDouble();
                        return SizedBox(height: hgt, child: pv);
                      },
                    ),
                    _Transport(editor: editor),
                    if (!hideTimeline)
                      _PaneDivider(
                        onDrag: (dy) => setState(() => _splitAdj =
                            (_splitAdj + dy).clamp(_minAdj, _maxAdj).toDouble()),
                        onReset: () => setState(() => _splitAdj = 0),
                      ),
                    if (!hideTimeline)
                      Expanded(
                        child: _Timeline(
                          editor: editor,
                          compact: _tool != null && !wide,
                          multiOn: _multiOn,
                          multi: _multi,
                          onClearMulti: _clearMulti,
                        ),
                      ),
                    if (wide)
                      toolbar
                    else
                      AnimatedSize(
                        duration: _dragging
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
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
                              ? toolbar
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

                if (!wide) return main;

                // Wide layouts (tablet / desktop / landscape): tools dock on the right.
                return Row(
                  children: <Widget>[
                    Expanded(child: main),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerRight,
                      child: _tool == null
                          ? const SizedBox(width: 0, height: 0)
                          : SizedBox(
                              width: sideW,
                              height: c.maxHeight,
                              child: _ToolPanel(
                                key: ValueKey<_Tool>(_tool!),
                                tool: _tool!,
                                docked: true,
                                onClose: _close,
                              ),
                            ),
                    ),
                  ],
                );
              }),
            ),
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
    required this.onClose,
    this.height,
    this.docked = false,
    this.onResize,
    this.onDrag,
  });
  final _Tool tool;
  final double? height;
  final bool docked;
  final VoidCallback onClose;
  final ValueChanged<double>? onResize;
  final ValueChanged<bool>? onDrag;

  Widget _header() => Row(
        children: <Widget>[
          const SizedBox(width: 16),
          HugeIcon(icon: tool.icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Done',
            icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedTick01, color: Colors.white, size: 22),
            onPressed: () {
              _tap();
              onClose();
            },
          ),
          const SizedBox(width: 4),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final Widget body = Expanded(
      child: ClipRect(
        child: Material(type: MaterialType.transparency, child: tool.body),
      ),
    );

    if (docked) {
      return Container(
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(left: BorderSide(color: _divider)),
        ),
        child: SafeArea(
          left: false,
          child: Column(
            children: <Widget>[
              SizedBox(height: 52, child: _header()),
              const Divider(height: 1, thickness: 0.5, color: _divider),
              body,
            ],
          ),
        ),
      );
    }

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
                onVerticalDragStart: (_) => onDrag?.call(true),
                onVerticalDragUpdate: (d) => onResize?.call(d.delta.dy),
                onVerticalDragEnd: (_) => onDrag?.call(false),
                onVerticalDragCancel: () => onDrag?.call(false),
                child: SizedBox(
                  height: 52,
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
                      Expanded(child: _header()),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: _divider),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Video Player (inside the canvas)
// ----------------------------------------------------------------------------
class _VideoPlayerPreview extends StatefulWidget {
  const _VideoPlayerPreview({required this.editor, required this.fill});
  final EditorController editor;
  final bool fill;

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
    if (!mounted || c == null || !c.value.isInitialized || _loading) return;

    // Playhead is in a gap between clips: make sure we aren't still playing.
    if (clip == null) {
      if (c.value.isPlaying) await c.pause();
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_loading)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
              )
            else
              Icon(icon, size: 40, color: Colors.white24),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = _e.activeVideoClip;
    final c = _vc;
    final bool ready = c != null && c.value.isInitialized;
    final BoxFit fit = widget.fill ? BoxFit.cover : BoxFit.contain;

    Widget child;
    if (_isImg && _path != null) {
      child = SizedBox.expand(
        child: Image.file(
          File(_path!),
          key: ValueKey<String>(_path!),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              _placeholder("Can't open this image", icon: Icons.broken_image_rounded),
        ),
      );
    } else if (ready) {
      final Size vs = c.value.size;
      child = SizedBox.expand(
        child: FittedBox(
          fit: fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: vs.width <= 0 ? 16 : vs.width,
            height: vs.height <= 0 ? 9 : vs.height,
            child: VideoPlayer(c),
          ),
        ),
      );
    } else if (_failed) {
      child = _placeholder("Can't play this file", icon: Icons.error_rounded);
    } else {
      child = _placeholder(clip?.label ?? 'Add media to start editing');
    }

    // Clip transform (scale only; position belongs to overlays).
    if (clip != null && (_isImg || ready)) {
      final double sc = (clip.scale).clamp(0.2, 5.0).toDouble();
      if (sc != 1.0) child = Transform.scale(scale: sc, child: child);
    }

    final cg = clip?.colorGrading;
    if (cg != null) {
      final double b = cg.brightness;
      final double cont = cg.contrast;
      final double s = cg.saturation;
      if (b != 0.0 || cont != 1.0 || s != 1.0) {
        const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
        final double sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
        final double off = (0.5 * (1 - cont) + b) * 255;
        final List<double> matrix = <double>[
          cont * (sr + s), cont * sg, cont * sb, 0, off,
          cont * sr, cont * (sg + s), cont * sb, 0, off,
          cont * sr, cont * sg, cont * (sb + s), 0, off,
          0, 0, 0, 1, 0,
        ];
        child = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child);
      }
    }

    final shaderEffects = clip?.shaderEffects ?? const [];
    for (final fx in shaderEffects) {
      if (fx.isEnabled && clip != null) {
        final relTime = _e.playhead - clip.start;
        final activeParams = fx.getInterpolatedParameters(relTime);
        child = FlutterShaderPreviewRenderer.applyShaderEffect(
          child: child,
          clip: fx,
          parameters: activeParams,
          playheadTime: _e.playhead,
        );
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        if (_loading && ready)
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Tracking overlay (normalized coordinates)
//
// Optional: wire `resolveTrackingBox` in main() for a custom mapping. If it is
// not set, the overlay falls back to `trackingData.rect` (normalized 0..1).
// ----------------------------------------------------------------------------
class TrackingBox {
  const TrackingBox(this.x, this.y, this.w, this.h);
  final double x, y, w, h; // normalized 0..1
}

typedef TrackingBoxResolver = TrackingBox? Function(dynamic tracking);
TrackingBoxResolver? resolveTrackingBox;

TrackingBox? _trackingBox(dynamic tracking) {
  if (tracking == null) return null;
  final TrackingBox? custom = resolveTrackingBox?.call(tracking);
  if (custom != null) return custom;
  try {
    if ((tracking as dynamic).isEnabled != true) return null;
    final dynamic r = (tracking as dynamic).rect;
    if (r is Rect) return TrackingBox(r.left, r.top, r.width, r.height);
  } catch (_) {}
  return null;
}

class _TrackingOverlay extends StatelessWidget {
  const _TrackingOverlay({required this.box, required this.label});
  final TrackingBox box;
  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final Rect r = Rect.fromLTWH(box.x * c.maxWidth, box.y * c.maxHeight,
            box.w * c.maxWidth, box.h * c.maxHeight);
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
        rect,
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
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
    final double top = math.max(0, rect.top - 16);
    canvas.drawRect(Rect.fromLTWH(rect.left, top, lw, 16), Paint()..color = _accent);
    tp.paint(canvas, Offset(rect.left + 6, top + 2));
  }

  @override
  bool shouldRepaint(covariant _TrackingPainter old) =>
      old.rect != rect || old.label != label;
}

// ----------------------------------------------------------------------------
// Preview: top bar + pro canvas
// ----------------------------------------------------------------------------
class _Preview extends StatefulWidget {
  const _Preview({required this.editor});
  final EditorController editor;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final TransformationController _tf = TransformationController();
  final ValueNotifier<_GuideState> _guides =
      ValueNotifier<_GuideState>(const _GuideState());
  bool _grid = false;
  bool _fill = false;

  @override
  void dispose() {
    _guides.dispose();
    _tf.dispose();
    super.dispose();
  }

  Widget _roundBtn(dynamic icon, String tip, VoidCallback onTap,
          {double size = 36, double iconSize = 17, bool on = false}) =>
      Semantics(
        button: true,
        label: tip,
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _tap();
              onTap();
            },
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                  color: on ? Colors.white : const Color(0xFF1B1B20),
                  shape: BoxShape.circle),
              child: Center(
                child: HugeIcon(
                  icon: icon,
                  color: on ? Colors.black : Colors.white,
                  size: iconSize,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _topBar(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double s = _scaleOf(size);
    final bool showLogo = size.width >= 430;
    final double btn = 36 * s;

    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52 * s,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10 * s),
            child: Row(
              children: <Widget>[
                _roundBtn(HugeIcons.strokeRoundedArrowLeft01, 'Back',
                    () => Navigator.of(context).maybePop(),
                    size: btn, iconSize: 16 * s),
                if (showLogo) ...<Widget>[
                  SizedBox(width: 10 * s),
                  Flexible(
                    child: Text(
                      'motionGr',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.unbounded(
                        color: Colors.white,
                        fontSize: 15 * s,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Resolution Badge '1080p'
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '1080p',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11 * s,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: 6 * s),
                ValueListenableBuilder<_CanvasRatio>(
                  valueListenable: _canvasRatio,
                  builder: (_, r, __) => PopupMenuButton<_CanvasRatio>(
                    tooltip: 'Canvas ratio',
                    color: _surface,
                    onSelected: (v) {
                      _tap();
                      _canvasRatio.value = v;
                      _tf.value = Matrix4.identity();
                    },
                    itemBuilder: (_) => <PopupMenuEntry<_CanvasRatio>>[
                      for (final v in _CanvasRatio.values)
                        PopupMenuItem<_CanvasRatio>(
                          value: v,
                          child: Text(v.label,
                              style: TextStyle(
                                  color: v == r ? _accent : Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                    child: Container(
                      height: 30 * s,
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: 10 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(r.label,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5 * s,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(width: 4 * s),
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedArrowDown01,
                            size: 14 * s,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 6 * s),
                _roundBtn(
                    _fill
                        ? HugeIcons.strokeRoundedZoomOut
                        : HugeIcons.strokeRoundedZoomIn,
                    _fill ? 'Fit video' : 'Fill canvas',
                    () => setState(() => _fill = !_fill),
                    size: btn,
                    iconSize: 17 * s,
                    on: _fill),
                SizedBox(width: 6 * s),
                _roundBtn(HugeIcons.strokeRoundedGrid, _grid ? 'Hide guides' : 'Show guides',
                    () => setState(() => _grid = !_grid),
                    size: btn, iconSize: 17 * s, on: _grid),
                SizedBox(width: 8 * s),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      _tap();
                      ExportModal.show(context);
                    },
                    child: SizedBox(
                      height: btn,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12 * s),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedShare01,
                              color: Colors.black,
                              size: 15 * s,
                            ),
                            SizedBox(width: 5 * s),
                            Text('Export',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 12.5 * s,
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
    );
  }

  Widget _canvas(EditorController editor, double ratio) {
    return AspectRatio(
      aspectRatio: ratio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white12),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Colors.black87, blurRadius: 18, spreadRadius: 1),
          ],
        ),
        child: ClipRect(
          child: LayoutBuilder(builder: (context, fc) {
            final double unit = fc.maxWidth / _designW;
            final double designH = fc.maxHeight / unit;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _VideoPlayerPreview(editor: editor, fill: _fill),
                Consumer<EditorController>(
                  builder: (ctx, e, _) {
                    final dynamic tracking = e.selectedClip?.trackingData;
                    final TrackingBox? box = _trackingBox(tracking);

                    final activeOverlays = e.clips.where((c) {
                      return c.isVisible &&
                          c.clipType != ClipType.video &&
                          c.clipType != ClipType.image &&
                          c.clipType != ClipType.audio &&
                          e.playhead >= c.start &&
                          e.playhead <= c.end;
                    }).toList();

                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        for (final clip in activeOverlays)
                          _OverlayClip(
                            key: ValueKey<String>(clip.id),
                            clip: clip,
                            unit: unit,
                            designH: designH,
                            othersOf: () => <Rect>[
                              for (final o in activeOverlays)
                                if (o.id != clip.id) _overlayRect(o)
                            ],
                            isSelected: clip.id == e.selectedClipId,
                            onSelect: () => e.selectClip(clip.id),
                            onGuides: (g) => _guides.value = g,
                            onPosition: (x, y) {
                              e.selectClip(clip.id);
                              e.updateTranslation(
                                positionX: x.clamp(-40.0, _designW - 24).toDouble(),
                                positionY: y.clamp(-40.0, designH - 24).toDouble(),
                              );
                            },
                            onScale: (v) {
                              e.selectClip(clip.id);
                              e.updateTranslation(scale: v);
                            },
                          ),
                        IgnorePointer(
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              if (_grid)
                                const Positioned.fill(
                                    child: CustomPaint(painter: _GuidePainter())),
                              if (e.activeDrawingStrokes.isNotEmpty)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _DrawingPainter(
                                        strokes: e.activeDrawingStrokes, unit: unit),
                                  ),
                                ),
                              if (box != null)
                                Positioned.fill(
                                  child: _TrackingOverlay(
                                    box: box,
                                    label: '${(tracking as dynamic)?.targetName ?? 'Target'}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<_GuideState>(
                      valueListenable: _guides,
                      builder: (_, g, __) => g.dragging
                          ? CustomPaint(painter: _SnapGuidePainter(g))
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final double pad = 10 * _scaleOf(MediaQuery.sizeOf(context));

    return Column(
      children: <Widget>[
        _topBar(context),
        Expanded(
          child: Container(
            color: const Color(0xFF07080B),
            child: ClipRect(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: editor.togglePlayback,
                onDoubleTap: () => _tf.value = Matrix4.identity(),
                child: InteractiveViewer(
                  transformationController: _tf,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(pad),
                      child: ValueListenableBuilder<_CanvasRatio>(
                        valueListenable: _canvasRatio,
                        builder: (_, r, __) => _canvas(editor, r.value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaneDivider extends StatelessWidget {
  const _PaneDivider({required this.onDrag, required this.onReset});
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        onDoubleTap: () {
          _tap();
          onReset();
        },
        child: SizedBox(
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: 7.5,
                child: Container(height: 1, color: const Color(0xFF2A2A30)),
              ),
              Container(
                width: 38,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A44),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: _bg, width: 1.5),
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
// Transport bar (timecode, frame step, play, undo/redo)
// ----------------------------------------------------------------------------
class _Transport extends StatelessWidget {
  const _Transport({required this.editor});
  final EditorController editor;

  Widget _icon(IconData i, String tip, VoidCallback onTap, double s) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 40 * s, height: 40 * s),
        icon: Icon(i, color: Colors.white, size: 22 * s),
        onPressed: () {
          _tap();
          onTap();
        },
      );

  @override
  Widget build(BuildContext context) {
    final double s = _scaleOf(MediaQuery.sizeOf(context));
    const List<FontFeature> tab = <FontFeature>[FontFeature.tabularFigures()];

    return Container(
      color: _bg,
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Selector<EditorController, Duration>(
                selector: (_, e) => e.playhead,
                builder: (_, p, __) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(_tc(_seconds(p)),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFeatures: tab)),
                      Text(
                          _tc(math.max(_seconds(editor.project.totalDuration), 1.0)),
                          style: const TextStyle(
                              color: _muted, fontSize: 9, fontFeatures: tab)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _icon(Icons.skip_previous_rounded, 'Previous frame',
              () => _seek(editor, _seconds(editor.playhead) - 1 / _fps), s),
          Selector<EditorController, bool>(
            selector: (_, e) => e.isPlaying,
            builder: (_, playing, __) => Semantics(
              button: true,
              label: playing ? 'Pause' : 'Play',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _tap();
                  editor.togglePlayback();
                },
                child: Container(
                  width: 48 * s,
                  height: 48 * s,
                  margin: EdgeInsets.symmetric(horizontal: 2 * s),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(playing),
                        color: Colors.white,
                        size: 38 * s),
                  ),
                ),
              ),
            ),
          ),
          _icon(Icons.skip_next_rounded, 'Next frame',
              () => _seek(editor, _seconds(editor.playhead) + 1 / _fps), s),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _icon(Icons.undo_rounded, 'Undo', editor.undo, s),
                  _icon(Icons.redo_rounded, 'Redo', editor.redo, s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Smart snapping: canvas center/edges/thirds/safe margins + other objects
// ----------------------------------------------------------------------------
enum _SnapKind { center, edge, third, safe, object }

class _SnapLine {
  const _SnapLine(this.vertical, this.pos, this.kind);
  final bool vertical;
  final double pos; // design units
  final _SnapKind kind;

  @override
  bool operator ==(Object o) =>
      o is _SnapLine && o.vertical == vertical && o.pos == pos && o.kind == kind;

  @override
  int get hashCode => Object.hash(vertical, pos, kind);
}

class _GuideState {
  const _GuideState({this.dragging = false, this.lines = const <_SnapLine>[]});
  final bool dragging;
  final List<_SnapLine> lines;

  @override
  bool operator ==(Object o) =>
      o is _GuideState && o.dragging == dragging && _listEq(o.lines, lines);

  @override
  int get hashCode => Object.hash(dragging, lines.length);
}

/// Approximate bounds (design units) of an overlay clip, used as snap targets.
Rect _overlayRect(TimelineClip c) {
  double w, h;
  switch (c.clipType) {
    case ClipType.element:
      w = h = 80 * c.scale;
    case ClipType.drawing:
      w = h = 120 * c.scale;
    default:
      final bool big = c.clipType == ClipType.text ||
          c.clipType == ClipType.caption ||
          c.clipType == ClipType.sticker;
      final tp = TextPainter(
        text: TextSpan(
          text: c.label,
          style: TextStyle(
              fontSize: (big ? 24 * c.scale : 16.0),
              fontFamily: c.fontFamily,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      w = tp.width;
      h = tp.height;
  }
  return Rect.fromLTWH(c.positionX, c.positionY, w + 12, h + 12);
}

bool _snapRefOk(_SnapKind k, double t, int i, double canvas) {
  if (k == _SnapKind.edge || k == _SnapKind.safe) {
    if (i == 1) return false;
    return (t < canvas / 2 && i == 0) || (t > canvas / 2 && i == 2);
  }
  return true;
}

(double, List<_SnapLine>) _snapAxis(
    double pos, double size, double canvas, bool vertical, List<double> objT, double th) {
  final List<(double, _SnapKind)> targets = <(double, _SnapKind)>[
    (canvas / 2, _SnapKind.center),
    (0.0, _SnapKind.edge),
    (canvas, _SnapKind.edge),
    (canvas / 3, _SnapKind.third),
    (canvas * 2 / 3, _SnapKind.third),
    (canvas * 0.05, _SnapKind.safe),
    (canvas * 0.95, _SnapKind.safe),
    for (final t in objT) (t, _SnapKind.object),
  ];
  final List<double> refs = <double>[pos, pos + size / 2, pos + size];

  double? best;
  for (final t in targets) {
    for (int i = 0; i < 3; i++) {
      if (!_snapRefOk(t.$2, t.$1, i, canvas)) continue;
      final double d = t.$1 - refs[i];
      if (d.abs() < th && (best == null || d.abs() < best.abs())) best = d;
    }
  }
  if (best == null) return (pos, const <_SnapLine>[]);

  final List<_SnapLine> lines = <_SnapLine>[];
  for (final t in targets) {
    for (int i = 0; i < 3; i++) {
      if (!_snapRefOk(t.$2, t.$1, i, canvas)) continue;
      if ((t.$1 - (refs[i] + best)).abs() < 0.01) {
        final l = _SnapLine(vertical, t.$1, t.$2);
        if (!lines.contains(l)) lines.add(l);
      }
    }
  }
  return (pos + best, lines);
}

class _SnapGuidePainter extends CustomPainter {
  _SnapGuidePainter(this.g);
  final _GuideState g;

  static Color _color(_SnapKind k) => switch (k) {
        _SnapKind.center || _SnapKind.edge => _accent,
        _SnapKind.third => const Color(0xFFFFC857),
        _SnapKind.safe => const Color(0xFF4DD0B5),
        _SnapKind.object => const Color(0xFFFF5FA2),
      };

  static String _label(_SnapLine l) => switch (l.kind) {
        _SnapKind.center => l.vertical ? 'Center' : 'Middle',
        _SnapKind.edge => 'Edge',
        _SnapKind.third => 'Thirds',
        _SnapKind.safe => 'Safe',
        _SnapKind.object => 'Align',
      };

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    final double total = (b - a).distance;
    if (total <= 0) return;
    final Offset dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 6, total), p);
      d += 10;
    }
  }

  void _tag(Canvas canvas, String text, Offset at, Color c) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect r = Rect.fromLTWH(at.dx, at.dy, tp.width + 8, tp.height + 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = Colors.black87);
    tp.paint(canvas, Offset(r.left + 4, r.top + 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double k = size.width / _designW;
    final Paint idle = Paint()
      ..color = Colors.white38
      ..strokeWidth = 0.8;

    final bool vc = g.lines.any((l) => l.vertical && l.kind == _SnapKind.center);
    final bool hc = g.lines.any((l) => !l.vertical && l.kind == _SnapKind.center);
    if (!vc) {
      _dashed(canvas, Offset(size.width / 2, 0), Offset(size.width / 2, size.height), idle);
    }
    if (!hc) {
      _dashed(canvas, Offset(0, size.height / 2), Offset(size.width, size.height / 2), idle);
    }

    for (final l in g.lines) {
      final Color c = _color(l.kind);
      final Paint p = Paint()
        ..color = c
        ..strokeWidth = 1.4;
      if (l.vertical) {
        final double x = (l.pos * k).clamp(0.7, size.width - 0.7).toDouble();
        _dashed(canvas, Offset(x, 0), Offset(x, size.height), p);
        _tag(canvas, _label(l), Offset(math.min(x + 3, size.width - 52), 3), c);
      } else {
        final double y = (l.pos * k).clamp(0.7, size.height - 0.7).toDouble();
        _dashed(canvas, Offset(0, y), Offset(size.width, y), p);
        _tag(canvas, _label(l), Offset(3, math.min(y + 3, size.height - 16)), c);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnapGuidePainter old) => old.g != g;
}

// ----------------------------------------------------------------------------
// Overlay clip (text / sticker / element / drawing): drag + pinch + snapping
// ----------------------------------------------------------------------------
class _OverlayClip extends StatefulWidget {
  const _OverlayClip({
    super.key,
    required this.clip,
    required this.unit,
    required this.designH,
    required this.othersOf,
    required this.isSelected,
    required this.onSelect,
    required this.onPosition,
    required this.onScale,
    required this.onGuides,
  });

  final TimelineClip clip;
  final double unit;
  final double designH;
  final List<Rect> Function() othersOf;
  final bool isSelected;
  final VoidCallback onSelect;
  final void Function(double x, double y) onPosition;
  final ValueChanged<double> onScale;
  final ValueChanged<_GuideState> onGuides;

  @override
  State<_OverlayClip> createState() => _OverlayClipState();
}

class _OverlayClipState extends State<_OverlayClip> {
  final GlobalKey _k = GlobalKey();
  double _baseScale = 1;
  double _rx = 0, _ry = 0; // raw (unsnapped) position so snapping never "sticks"
  List<double> _ox = <double>[], _oy = <double>[];
  String _sig = '';

  Widget _content() {
    final clip = widget.clip;
    final double u = widget.unit;
    switch (clip.clipType) {
      case ClipType.text:
      case ClipType.caption:
      case ClipType.sticker:
        final ts = clip.textStyle;
        final double effectiveSize = ts.fontSize * clip.scale * u;

        List<Shadow> shadows = [];
        if (ts.shadowColor != Colors.transparent &&
            (ts.shadowBlurRadius > 0 || ts.shadowOffsetX != 0 || ts.shadowOffsetY != 0)) {
          shadows.add(
            Shadow(
              color: ts.shadowColor,
              blurRadius: ts.shadowBlurRadius,
              offset: Offset(ts.shadowOffsetX, ts.shadowOffsetY),
            ),
          );
        } else if (ts.textEffect == 'glow' || ts.textEffect == 'neon') {
          shadows.add(
            Shadow(
              color: ts.shadowColor != Colors.transparent
                  ? ts.shadowColor
                  : const Color(0xFF00E5FF),
              blurRadius: ts.shadowBlurRadius > 0 ? ts.shadowBlurRadius : 12.0,
            ),
          );
        } else if (shadows.isEmpty) {
          shadows.add(const Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1)));
        }

        Widget textWidget = Text(
          clip.label,
          textAlign: ts.textAlign,
          style: TextStyle(
            color: ts.textColor,
            fontSize: effectiveSize,
            fontFamily: clip.fontFamily,
            fontWeight: FontWeight.bold,
            height: ts.lineHeight,
            shadows: shadows,
          ),
        );

        if (ts.strokeWidth > 0 && ts.strokeColor != Colors.transparent) {
          textWidget = Stack(
            children: [
              Text(
                clip.label,
                textAlign: ts.textAlign,
                style: TextStyle(
                  fontSize: effectiveSize,
                  fontFamily: clip.fontFamily,
                  fontWeight: FontWeight.bold,
                  height: ts.lineHeight,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = ts.strokeWidth * u
                    ..color = ts.strokeColor,
                ),
              ),
              textWidget,
            ],
          );
        }

        if (ts.backgroundColor != Colors.transparent) {
          textWidget = Container(
            padding: EdgeInsets.all(ts.backgroundPadding * u),
            decoration: BoxDecoration(
              color: ts.backgroundColor,
              borderRadius: BorderRadius.circular(4 * u),
            ),
            child: textWidget,
          );
        }

        return _applyAnimations(textWidget, clip);
      case ClipType.element:
        final elWidget = Container(
          width: 80 * clip.scale * u,
          height: 80 * clip.scale * u,
          decoration: BoxDecoration(
            color: clip.elementProperties.fillColor,
            shape: clip.elementProperties.shape == ElementShape.circle
                ? BoxShape.circle
                : BoxShape.rectangle,
            borderRadius: clip.elementProperties.shape == ElementShape.rectangle
                ? BorderRadius.circular(8 * u)
                : null,
          ),
        );
        return _applyAnimations(elWidget, clip);
      case ClipType.drawing:
        final drWidget = CustomPaint(
          size: Size(120 * clip.scale * u, 120 * clip.scale * u),
          painter: _DrawingPainter(strokes: clip.strokes, unit: u),
        );
        return _applyAnimations(drWidget, clip);
      default:
        return _applyAnimations(
          Text(clip.label, style: TextStyle(color: Colors.white, fontSize: 16 * u)),
          clip,
        );
    }
  }

  Widget _applyAnimations(Widget child, TimelineClip clip) {
    final editor = context.read<EditorController>();
    final playhead = editor.playhead;
    const int durInMs = 500;

    double opacity = clip.opacity;
    double scaleMult = 1.0;
    double transX = 0.0;

    if (clip.inAnimation != ClipAnimation.none && playhead >= clip.start) {
      final elapsed = (playhead - clip.start).inMilliseconds;
      if (elapsed < durInMs) {
        final t = (elapsed / durInMs).clamp(0.0, 1.0);
        switch (clip.inAnimation) {
          case ClipAnimation.fadeIn:
            opacity *= t;
            break;
          case ClipAnimation.zoomIn:
            scaleMult *= (0.3 + 0.7 * t);
            break;
          case ClipAnimation.slideLeft:
            transX -= (1.0 - t) * 60;
            break;
          case ClipAnimation.slideRight:
            transX += (1.0 - t) * 60;
            break;
          default:
            break;
        }
      }
    }

    if (clip.outAnimation != ClipAnimation.none && playhead <= clip.end) {
      final remaining = (clip.end - playhead).inMilliseconds;
      if (remaining < durInMs) {
        final t = (remaining / durInMs).clamp(0.0, 1.0);
        switch (clip.outAnimation) {
          case ClipAnimation.fadeOut:
            opacity *= t;
            break;
          case ClipAnimation.zoomOut:
            scaleMult *= (0.3 + 0.7 * t);
            break;
          case ClipAnimation.slideRight:
            transX += (1.0 - t) * 60;
            break;
          case ClipAnimation.slideLeft:
            transX -= (1.0 - t) * 60;
            break;
          default:
            break;
        }
      }
    }

    Widget result = child;
    if (transX != 0.0) {
      result = Transform.translate(offset: Offset(transX, 0), child: result);
    }
    if (scaleMult != 1.0) {
      result = Transform.scale(scale: scaleMult, child: result);
    }
    if (opacity < 1.0) {
      result = Opacity(opacity: opacity.clamp(0.0, 1.0), child: result);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final double u = widget.unit;
    return Positioned(
      left: clip.positionX * u,
      top: clip.positionY * u,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onScaleStart: (_) {
          _baseScale = clip.scale;
          _rx = clip.positionX;
          _ry = clip.positionY;
          _sig = '';
          _ox = <double>[];
          _oy = <double>[];
          for (final r in widget.othersOf()) {
            _ox.addAll(<double>[r.left, r.center.dx, r.right]);
            _oy.addAll(<double>[r.top, r.center.dy, r.bottom]);
          }
          widget.onSelect();
        },
        onScaleUpdate: (d) {
          if (d.pointerCount >= 2) {
            widget.onScale((_baseScale * d.scale).clamp(0.2, 5.0).toDouble());
            return;
          }
          _rx += d.focalPointDelta.dx / u;
          _ry += d.focalPointDelta.dy / u;
          final Size? sz = _k.currentContext?.size;
          final double w = (sz?.width ?? 0) / u;
          final double h = (sz?.height ?? 0) / u;
          final double th = 8 / u; // 8 screen px of magnetic pull
          final (double x, List<_SnapLine> lx) = _snapAxis(_rx, w, _designW, true, _ox, th);
          final (double y, List<_SnapLine> ly) =
              _snapAxis(_ry, h, widget.designH, false, _oy, th);
          final List<_SnapLine> lines = <_SnapLine>[...lx, ...ly];
          final String sig =
              lines.map((l) => '${l.vertical}${l.pos.toStringAsFixed(1)}').join('|');
          if (sig.isNotEmpty && sig != _sig) _tap();
          _sig = sig;
          widget.onPosition(x, y);
          widget.onGuides(_GuideState(dragging: true, lines: lines));
        },
        onScaleEnd: (_) => widget.onGuides(const _GuideState()),
        child: Container(
          key: _k,
          padding: EdgeInsets.all(6 * u),
          decoration: widget.isSelected
              ? BoxDecoration(
                  border: Border.all(color: _accent, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: _content(),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white30
      ..strokeWidth = 0.7;
    for (final double f in const <double>[1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), p);
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), p);
    }
    // Title-safe area (90%).
    final Rect safe = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width * 0.9,
        height: size.height * 0.9);
    canvas.drawRect(
        safe,
        Paint()
          ..color = _accent.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    final Offset c = size.center(Offset.zero);
    canvas.drawLine(c.translate(-8, 0), c.translate(8, 0), p);
    canvas.drawLine(c.translate(0, -8), c.translate(0, 8), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _DrawingPainter extends CustomPainter {
  _DrawingPainter({required this.strokes, this.unit = 1});
  final List<DrawingStroke> strokes;
  final double unit;

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
  static const double _gap = 6;

  // Device scale, refreshed in build().
  double _s = 1;
  double get _rulerH => 30 * _s;
  double get _textH => 34 * _s;
  double get _videoH => 52 * _s;
  double get _audioH => 40 * _s;
  double get _hdrW => 44 * _s;

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
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _tap();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                width: 34 * _s,
                height: 28 * _s,
                decoration: BoxDecoration(
                  color: on ? Colors.white : const Color(0xFF26262C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16 * _s, color: on ? Colors.black : Colors.white),
              ),
            ),
          ),
        ),
      );

  Widget _scrubCard(double half, double width, List<_ClipSnapshot> clips) {
    final double t = _scrubTime ?? 0;
    final _ClipSnapshot? clip = _clipAt(t, clips);
    final String? path = clip?.path;
    Widget thumb;
    if (path != null && _isImagePath(path)) {
      thumb = Image.file(File(path),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _Stripes());
    } else if (path != null && thumbGenerator != null) {
      final int localMs = ((t - clip!.startSec).clamp(0.0, clip.durSec) * 1000).round();
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
    const double w = 140;
    return Positioned(
      left: (half - w / 2).clamp(6.0, math.max(6.0, width - w - 6)).toDouble(),
      top: -92,
      child: IgnorePointer(
        child: Container(
          width: w,
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
                child: SizedBox(height: 56, width: w, child: thumb),
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
    final Size size = MediaQuery.sizeOf(context);
    _s = _scaleOf(size);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _divider)),
      ),
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
              final double h = c.maxHeight.isFinite
                  ? c.maxHeight
                  : math.min(contentH, 240.0 * _s);
              final double contentW = total * pps + c.maxWidth;

              return SizedBox(
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
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
                            if (n is ScrollStartNotification && n.dragDetails != null) {
                              _userScrolling = true;
                              setState(() => _scrubTime = n.metrics.pixels / pps);
                            } else if (n is ScrollUpdateNotification && _userScrolling) {
                              final double t =
                                  _snapTime(n.metrics.pixels / pps, pps, model.clips);
                              setState(() => _scrubTime = t);
                              _seek(editor, t);
                            } else if (n is ScrollEndNotification) {
                              _userScrolling = false;
                              setState(() => _scrubTime = null);
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
                                          _seek(editor, (d.localPosition.dx - half) / pps);
                                        },
                                        child: SizedBox(
                                          height: _rulerH,
                                          width: contentW,
                                          child: CustomPaint(
                                            painter: _RulerPainter(
                                                pps: pps, seconds: total + 5, leftPad: half, totalSec: total),
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
                    // Lane headers
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
                                SizedBox(height: _rulerH),
                                for (final l in lanes)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: _gap),
                                    child: SizedBox(
                                        height: l.h, child: _header(l, model.clips)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Playhead (time pill + line)
                    Positioned(
                      left: half - 32,
                      top: 0,
                      bottom: 0,
                      width: 64,
                      child: IgnorePointer(
                        child: Column(
                          children: <Widget>[
                            Container(
                              height: 17 * _s,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(color: Colors.black54, blurRadius: 4)
                                ],
                              ),
                              child: Selector<EditorController, Duration>(
                                selector: (_, e) => e.playhead,
                                builder: (_, p, __) => Text(
                                  _tcShort(_seconds(p)),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: <FontFeature>[
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(child: Container(width: 2, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    // Snap + zoom
                    Positioned(
                      right: 6,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xD9101014),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _divider),
                        ),
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
                            _chip(Icons.remove_rounded, 'Zoom out', false,
                                () => _applyZoom(model.zoom - 0.5, half, half)),
                            _chip(Icons.add_rounded, 'Zoom in', false,
                                () => _applyZoom(model.zoom + 0.5, half, half)),
                          ],
                        ),
                      ),
                    ),
                    if (_userScrolling && _scrubTime != null)
                      _scrubCard(half, c.maxWidth, model.clips),
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
    Widget btn(dynamic i, bool active, String tip, VoidCallback f) => Tooltip(
          message: tip,
          child: InkResponse(
            radius: 16,
            onTap: () {
              _tap();
              f();
            },
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: HugeIcon(
                icon: i,
                size: 14 * _s,
                color: active ? Colors.white : Colors.white54,
              ),
            ),
          ),
        );

    final isTextLane = l.kind == _ClipKind.text && l.clips.isNotEmpty;

    final children = <Widget>[
      btn(
        locked ? HugeIcons.strokeRoundedLock : HugeIcons.strokeRoundedLockKey,
        locked,
        locked ? 'Unlock track' : 'Lock track',
        () {
          for (final c in l.clips) {
            if (c.locked == locked) editor.toggleClipLock(c.id);
          }
        },
      ),
      btn(
        visible ? HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff,
        !visible,
        visible ? 'Hide track' : 'Show track',
        () {
          for (final c in l.clips) {
            if (c.visible == visible) editor.toggleClipVisibility(c.id);
          }
        },
      ),
      if (isTextLane)
        btn(HugeIcons.strokeRoundedArrowUp01, true, 'Move layer higher', () {
          final first = l.clips.first;
          editor.reorderClipLayer(first.id, first.layer + 1);
        }),
      if (isTextLane && l.clips.first.layer > 2)
        btn(HugeIcons.strokeRoundedArrowDown01, true, 'Move layer lower', () {
          final first = l.clips.first;
          editor.reorderClipLayer(first.id, first.layer - 1);
        }),
    ];

    return l.h >= 50
        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: children)
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
  }

  Widget _addButton(double left, double h) => Positioned(
        left: left,
        top: h / 2 - 15 * _s,
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
              width: 30 * _s,
              height: 30 * _s,
              decoration:
                  const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.add_rounded, size: 19 * _s, color: Colors.black),
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
                        ? (desired) => _constrainMove(list[i], desired, pps, list)
                        : (desired) => math.max(
                            0.0, _snapTime(desired, pps, m.clips, excludeId: list[i].id)),
                  ),
                ),
              ),
              // Transition picker between main-track clips.
              if (l.kind == _ClipKind.video && i < list.length - 1)
                Positioned(
                  left: half + list[i].endSec * pps - 14 * _s,
                  top: l.h / 2 - 12 * _s,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _tap();
                      _showTransitionSheet(context);
                    },
                    child: Container(
                      width: 24 * _s,
                      height: 24 * _s,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.join_inner_rounded,
                          size: 14 * _s, color: Colors.black),
                    ),
                  ),
                ),
            ],
            if (l.add)
              _addButton(half + (list.isEmpty ? 0 : list.last.endSec * pps) + 16 * _s, l.h),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Clip block
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

  // Trim handles live INSIDE the block so they are actually hit-testable.
  Widget _trimHandle({required bool left}) {
    final clip = widget.clip;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          if (left) {
            final double newStart = (clip.startSec + d.delta.dx / widget.pps)
                .clamp(0.0, math.max(0.0, clip.endSec - 0.2))
                .toDouble();
            widget.editor.trimSelectedClip(
              Duration(milliseconds: (newStart * 1000).round()),
              Duration(milliseconds: (clip.endSec * 1000).round()),
            );
          } else {
            final double newEnd = (clip.endSec + d.delta.dx / widget.pps)
                .clamp(clip.startSec + 0.2, 86400.0)
                .toDouble();
            widget.editor.trimSelectedClip(
              Duration(milliseconds: (clip.startSec * 1000).round()),
              Duration(milliseconds: (newEnd * 1000).round()),
            );
          }
        },
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: _Handle(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
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
                  builder: (context, c) => (clip.path != null && !locked)
                      ? _Filmstrip(
                          key: ValueKey<String>(
                              '${clip.id}|${widget.pps.toStringAsFixed(2)}'),
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
                        color: Colors.black54, borderRadius: BorderRadius.circular(4)),
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

    if (widget.selected && !locked) {
      body = Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          _trimHandle(left: true),
          _trimHandle(left: false),
        ],
      );
    }
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final bool locked = clip.locked;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.multiOn, widget.multi]),
      builder: (context, _) {
        final bool multiActive = widget.multiOn.value;
        final bool inMulti = widget.multi.value.contains(clip.id);
        // Drag-to-move only on an already selected clip; otherwise the drag
        // scrolls the timeline like everywhere else.
        final bool canMove = !locked && !multiActive && widget.selected;

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
          onHorizontalDragStart: canMove ? (_) => _startMove() : null,
          onHorizontalDragUpdate: canMove ? (d) => _updateMove(d.delta.dx) : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: clip.visible ? 1 : 0.35,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(child: _buildBody()),
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
                    child: Icon(Icons.check_circle_rounded, size: 14, color: _accent),
                  ),
              ],
            ),
          ),
        );
      },
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
  _RulerPainter({
    required this.pps,
    required this.seconds,
    required this.leftPad,
    required this.totalSec,
  });
  final double pps;
  final double seconds;
  final double leftPad;
  final double totalSec;

  String _label(double t, double step) {
    if (step < 1) return '${t.toStringAsFixed(1)}s';
    final int s = t.round();
    if (s >= 60) return '${s ~/ 60}:${_two(s % 60)}';
    return '${s}s';
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Strip background + bottom hairline.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B0B0E));
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5),
        Paint()..color = const Color(0xFF26262C));

    // Everything past the project end is dimmed, with an accent end marker.
    final double endX = leftPad + totalSec * pps;
    if (endX < size.width) {
      canvas.drawRect(Rect.fromLTRB(endX, 0, size.width, size.height),
          Paint()..color = Colors.white.withValues(alpha: 0.04));
    }
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height),
        Paint()
          ..color = _accent.withValues(alpha: 0.7)
          ..strokeWidth = 1);

    const steps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300];
    final double step = steps.firstWhere((s) => s * pps >= 72, orElse: () => steps.last);
    final Paint major = Paint()
      ..color = Colors.white60
      ..strokeWidth = 1;
    final Paint minor = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final int count = (seconds / step).ceil();

    for (int i = 0; i <= count; i++) {
      final double t = i * step;
      final double x = leftPad + t * pps;
      if (x > size.width) break;

      canvas.drawLine(Offset(x, size.height - 11), Offset(x, size.height), major);

      final tp = TextPainter(
        text: TextSpan(
          text: _label(t, step),
          style: TextStyle(
            color: t > totalSec + 1e-6 ? Colors.white38 : Colors.white70,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 4, 4));

      // 3 minor ticks between majors (the middle one is taller).
      for (int j = 1; j < 4; j++) {
        final double mx = x + j * step * pps / 4;
        canvas.drawLine(
            Offset(mx, size.height - (j == 2 ? 7 : 4)), Offset(mx, size.height), minor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps ||
      old.seconds != seconds ||
      old.leftPad != leftPad ||
      old.totalSec != totalSec;
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
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
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
                            height: 48,
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
                              style: const TextStyle(color: Colors.white70, fontSize: 10)),
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
// Shared sheet widgets
// ----------------------------------------------------------------------------
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration:
            BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
        child: child,
      );
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? display;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(display ?? value.toStringAsFixed(2),
                  style: const TextStyle(color: _accent, fontSize: 12)),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            activeColor: _accent,
            inactiveColor: _divider,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

Widget _primaryBtn(dynamic icon, String label, VoidCallback? onPressed) => SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                _tap();
                onPressed();
              },
        icon: HugeIcon(icon: icon, color: Colors.black, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );

/// Responsive grid: column count adapts to the available width.
class _ResponsiveGrid extends StatefulWidget {
  const _ResponsiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.minTile = 100,
    this.aspect = 1,
    this.fakeLoad = false,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minTile;
  final double aspect;
  final bool fakeLoad;

  @override
  State<_ResponsiveGrid> createState() => _ResponsiveGridState();
}

class _ResponsiveGridState extends State<_ResponsiveGrid> {
  late bool _loading = widget.fakeLoad;

  @override
  void initState() {
    super.initState();
    if (_loading) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final int cols = _cols(c.maxWidth - 24, widget.minTile);
      if (_loading) {
        return SkeletonGrid(
            itemCount: math.min(widget.itemCount, cols * 2),
            crossAxisCount: cols,
            childAspectRatio: widget.aspect);
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: widget.aspect,
        ),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      );
    });
  }
}

Widget _tile({
  required Widget child,
  required VoidCallback onTap,
  bool selected = false,
}) =>
    InkWell(
      onTap: () {
        _tap();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.2) : _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _accent : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );

// ----------------------------------------------------------------------------
// Tool Sheet Implementations
// ----------------------------------------------------------------------------

class AudioToolsSheet extends StatelessWidget {
  const AudioToolsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final clip = editor.selectedClip;
    final bool hasAudio = clip != null &&
        (clip.clipType == ClipType.audio || clip.clipType == ClipType.video);
    final double volume = clip?.volume ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _Card(
          child: Row(
            children: <Widget>[
              const HugeIcon(icon: HugeIcons.strokeRoundedMusicNote01, color: _accent, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Add Audio Track',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Insert soundtrack clip to timeline',
                        style: TextStyle(color: _muted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _accent, foregroundColor: Colors.black),
                onPressed: () {
                  _tap();
                  editor.addAudioTrack(
                      'Track ${editor.clips.where((c) => c.clipType == ClipType.audio).length + 1}');
                },
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: Colors.black, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (hasAudio) ...<Widget>[
          const SizedBox(height: 12),
          _SliderCard(
            label: 'Volume',
            value: volume,
            min: 0,
            max: 2,
            display: '${(volume * 100).round()}%',
            onChanged: (val) =>
                editor.updateAudioProperties(AudioProperties(volume: val, speed: clip.speed)),
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
  final TextAnimationStyle _anim = TextAnimationStyle.fadeIn;

  static const List<String> _fonts = <String>[
    'Poppins', 'Unbounded', 'Roboto', 'Arial', 'Montserrat', 'Inter'
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final bool editing = editor.selectedClip?.clipType == ClipType.text;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Text Content',
              labelStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _ResponsiveGrid(
            fakeLoad: true,
            itemCount: _fonts.length,
            minTile: 110,
            aspect: 2.2,
            itemBuilder: (context, i) {
              final font = _fonts[i];
              final bool selected = font == _selectedFont;
              return _tile(
                selected: selected,
                onTap: () => setState(() => _selectedFont = font),
                child: Text(
                  font,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _accent : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _primaryBtn(
            HugeIcons.strokeRoundedAdd01,
            editing ? 'Update Selected Text' : 'Add Text Clip',
            () {
              if (editing) {
                editor.updateSelectedTextProperties(
                    text: _ctrl.text, fontFamily: _selectedFont, textAnimationStyle: _anim);
              } else {
                editor.addTextOverlay(_ctrl.text.isEmpty ? 'Text' : _ctrl.text,
                    fontFamily: _selectedFont, animationStyle: _anim);
              }
            },
          ),
        ),
      ],
    );
  }
}

class StickersSheet extends StatelessWidget {
  const StickersSheet({super.key});

  static const List<String> _emojis = <String>[
    '🔥', '✨', '⚡', '🎉', '❤️', '🌟', '🎬', '👏', '🚀', '💯', '💥', '⭐', '🎈', '🏆', '💎'
  ];

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return _ResponsiveGrid(
      fakeLoad: true,
      itemCount: _emojis.length,
      minTile: 64,
      itemBuilder: (context, i) => _tile(
        onTap: () => editor.addTextOverlay(_emojis[i], fontFamily: 'Poppins'),
        child: Text(_emojis[i], style: const TextStyle(fontSize: 24)),
      ),
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

    return _ResponsiveGrid(
      fakeLoad: true,
      itemCount: VideoEffect.values.length,
      minTile: 104,
      aspect: 1.8,
      itemBuilder: (context, i) {
        final fx = VideoEffect.values[i];
        final bool selected = fx == currentEffect;
        return _tile(
          selected: selected,
          onTap: () => editor.applyEffect(fx),
          child: Text(
            fx.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? _accent : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

class ColorGradingSheet extends StatelessWidget {
  const ColorGradingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final cg = editor.selectedClip?.colorGrading;
    final double b = cg?.brightness ?? 0.0;
    final double c = cg?.contrast ?? 1.0;
    final double s = cg?.saturation ?? 1.0;

    void push(double nb, double nc, double ns) => editor.updateColorGrading(
        ColorGradingSettings(brightness: nb, contrast: nc, saturation: ns));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SliderCard(label: 'Brightness', value: b, min: -0.5, max: 0.5,
            onChanged: (v) => push(v, c, s)),
        const SizedBox(height: 10),
        _SliderCard(label: 'Contrast', value: c, min: 0.5, max: 2.0,
            onChanged: (v) => push(b, v, s)),
        const SizedBox(height: 10),
        _SliderCard(label: 'Saturation', value: s, min: 0.0, max: 2.0,
            onChanged: (v) => push(b, c, v)),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _divider),
              minimumSize: const Size.fromHeight(42)),
          onPressed: () {
            _tap();
            push(0.0, 1.0, 1.0);
          },
          child: const Text('Reset', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

/// "Canvas" tool: canvas aspect ratio + zoom of the selected clip.
class CropSheet extends StatelessWidget {
  const CropSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final double scale = editor.selectedClip?.scale ?? 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('Canvas ratio',
            style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ValueListenableBuilder<_CanvasRatio>(
          valueListenable: _canvasRatio,
          builder: (_, cur, __) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final r in _CanvasRatio.values)
                InkWell(
                  onTap: () {
                    _tap();
                    _canvasRatio.value = r;
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 68,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: r == cur ? _accent.withValues(alpha: 0.2) : _card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: r == cur ? _accent : Colors.transparent),
                    ),
                    child: Text(r.label,
                        style: TextStyle(
                            color: r == cur ? _accent : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SliderCard(
          label: 'Clip zoom',
          value: scale,
          min: 0.5,
          max: 3.0,
          display: '${(scale * 100).round()}%',
          onChanged: editor.selectedClip == null
              ? (_) {}
              : (v) => editor.updateTranslation(scale: v),
        ),
      ],
    );
  }
}

class ElementsSheet extends StatelessWidget {
  const ElementsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return _ResponsiveGrid(
      fakeLoad: true,
      itemCount: ElementShape.values.length,
      minTile: 80,
      itemBuilder: (context, i) {
        final shape = ElementShape.values[i];
        return _tile(
          onTap: () =>
              editor.addElementClip(shape, label: shape.name, color: Colors.cyanAccent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const HugeIcon(icon: HugeIcons.strokeRoundedShapes, color: _accent, size: 22),
              const SizedBox(height: 4),
              Text(shape.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
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
        _SliderCard(
          label: 'Stroke width',
          value: _width,
          min: 1,
          max: 20,
          display: _width.toStringAsFixed(0),
          onChanged: (v) {
            setState(() => _width = v);
            editor.setStrokeWidth(v);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 12,
          runSpacing: 8,
          children: <Color>[
            Colors.cyanAccent,
            Colors.redAccent,
            Colors.greenAccent,
            Colors.yellowAccent,
            Colors.white
          ]
              .map((c) => GestureDetector(
                    onTap: () {
                      setState(() => _color = c);
                      editor.setDrawingColor(c);
                    },
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 16,
                      child: _color == c
                          ? const HugeIcon(
                              icon: HugeIcons.strokeRoundedTick01, size: 14, color: Colors.black)
                          : null,
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _divider),
                    minimumSize: const Size.fromHeight(44)),
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
                style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(44)),
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
    return _ResponsiveGrid(
      itemCount: MaskType.values.length,
      minTile: 104,
      aspect: 2.2,
      itemBuilder: (context, i) {
        final type = MaskType.values[i];
        return _tile(
          onTap: () =>
              editor.updateMaskProperties(MaskProperties(type: type, feather: 10.0)),
          child: Text(type.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        );
      },
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
        _primaryBtn(
          HugeIcons.strokeRoundedAdd01,
          'Add Keyframe at Playhead',
          editor.selectedClip == null
              ? null
              : () => editor.addKeyframe(Keyframe(
                    id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
                    time: editor.playhead,
                    property: KeyframeProperty.scale,
                    value: 1.0,
                  )),
        ),
        const SizedBox(height: 12),
        if (keyframes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('No keyframes yet',
                  style: TextStyle(color: _muted, fontSize: 12)),
            ),
          ),
        ...keyframes.map((kf) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration:
                  BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                dense: true,
                title: Text(
                    '${'${kf.property}'.split('.').last} @ ${_seconds(kf.time).toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                trailing: IconButton(
                  tooltip: 'Remove keyframe',
                  icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      color: Colors.redAccent,
                      size: 18),
                  onPressed: () => editor.removeKeyframe(kf.id),
                ),
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
        _SliderCard(
          label: 'Focal length',
          value: props.focalLength,
          min: 10,
          max: 200,
          display: '${props.focalLength.round()} mm',
          onChanged: (v) => editor.updateCameraProperties(props.copyWith(focalLength: v)),
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
    final bool active = tracking?.isEnabled == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _Card(
          child: Row(
            children: <Widget>[
              Icon(Icons.circle, size: 10, color: active ? Colors.greenAccent : Colors.white24),
              const SizedBox(width: 8),
              Text('Tracking status: ${active ? "Active" : "None"}',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _primaryBtn(
          HugeIcons.strokeRoundedTarget01,
          active ? 'Stop Tracking' : 'Start Auto-Tracking',
          editor.selectedClip == null
              ? null
              : () => editor.updateTrackingData(TrackingData(
                    isEnabled: !active,
                    targetName: 'Subject',
                    rect: const Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
                  )),
        ),
      ],
    );
  }
}

class PluginsSheet extends StatelessWidget {
  const PluginsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final plugins = PluginManager().activePlugins;

    if (plugins.isEmpty) {
      return const Center(
        child: Text('No active plug-ins', style: TextStyle(color: _muted, fontSize: 12)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final p = plugins[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedGridView, color: _accent, size: 20),
            title: Text(p.name,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle:
                Text(p.version, style: const TextStyle(color: _muted, fontSize: 11)),
          ),
        );
      },
    );
  }
}