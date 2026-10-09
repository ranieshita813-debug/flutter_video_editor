import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/chroma_key_preview.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';
import 'package:flutter_video_editor/features/effects/services/effect_preview_service.dart';

// ----------------------------------------------------------------------------
// Video Player Preview
// ----------------------------------------------------------------------------
class VideoPlayerPreview extends StatefulWidget {
  const VideoPlayerPreview({super.key, required this.editor, required this.fill});
  final EditorController editor;
  final bool fill;

  @override
  State<VideoPlayerPreview> createState() => _VideoPlayerPreviewState();
}

class _VideoPlayerPreviewState extends State<VideoPlayerPreview> {
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
  void didUpdateWidget(covariant VideoPlayerPreview old) {
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
    _isImg = !empty && isImagePath(path);

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

  Widget _applyVideoEffectPreset(Widget child, VideoEffect fx, Duration playhead) {
    switch (fx) {
      case VideoEffect.warm:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.2, 0, 0, 0, 10,
            0, 1.1, 0, 0, 5,
            0, 0, 0.9, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.cinematic:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.1, 0, 0, 0, -10,
            0, 1.2, 0, 0, 0,
            0, 0, 1.3, 0, 10,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.noir:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.vibrant:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.3, -0.1, -0.1, 0, 0,
            -0.1, 1.3, -0.1, 0, 0,
            -0.1, -0.1, 1.3, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.vintage:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.9, 0.1, 0.1, 0, 15,
            0.1, 0.8, 0.1, 0, 10,
            0.1, 0.1, 0.6, 0, 5,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.glitch:
        return FlutterShaderPreviewRenderer.applyShaderEffect(
          child: child,
          clip: const ShaderEffectClip(
            id: 'fx_glitch',
            effectId: 'glitch',
            parameterValues: {'distortionAmount': 0.8, 'speed': 2.0},
          ),
          parameters: const {'distortionAmount': 0.8, 'speed': 2.0},
          playheadTime: playhead,
        );
      case VideoEffect.blur:
        return FlutterShaderPreviewRenderer.applyShaderEffect(
          child: child,
          clip: const ShaderEffectClip(
            id: 'fx_blur',
            effectId: 'blur',
            parameterValues: {'blurAmount': 1.5},
          ),
          parameters: const {'blurAmount': 1.5},
          playheadTime: playhead,
        );
      case VideoEffect.glow:
        return FlutterShaderPreviewRenderer.applyShaderEffect(
          child: child,
          clip: const ShaderEffectClip(
            id: 'fx_glow',
            effectId: 'glow',
            parameterValues: {'glowStrength': 1.2},
          ),
          parameters: const {'glowStrength': 1.2},
          playheadTime: playhead,
        );
      case VideoEffect.retro:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.8, 0.2, 0.1, 0, 20,
            0.1, 0.7, 0.2, 0, 15,
            0.1, 0.1, 0.5, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.matrix:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.1, 0.8, 0.1, 0, 0,
            0.1, 1.2, 0.1, 0, 20,
            0.1, 0.8, 0.1, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.flame:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.4, 0, 0, 0, 30,
            0.2, 0.8, 0, 0, 10,
            0, 0, 0.5, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
      case VideoEffect.none:
        return child;
    }
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

    if (clip != null && (_isImg || ready)) {
      final double sc = (clip.scale).clamp(0.2, 5.0).toDouble();
      if (sc != 1.0) child = Transform.scale(scale: sc, child: child);
    }

    if (clip != null && clip.chromaKey.enabled) {
      child = ChromaKeyPreview(
        chroma: clip.chromaKey,
        child: child,
      );
    }

    final cg = clip?.colorGrading;
    if (cg != null) {
      final double b = cg.brightness;
      final double cont = cg.contrast;
      final double s = cg.saturation;
      final double temp = cg.temperature;
      final double tint = cg.tint;
      if (b != 0.0 || cont != 1.0 || s != 1.0 || temp != 0.0 || tint != 0.0) {
        const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
        final double sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
        final double off = (0.5 * (1 - cont) + b) * 255;
        final double redShift = temp * 30.0;
        final double blueShift = -temp * 30.0;
        final double greenShift = tint * 30.0;
        final List<double> matrix = <double>[
          cont * (sr + s), cont * sg, cont * sb, 0, off + redShift,
          cont * sr, cont * (sg + s), cont * sb, 0, off + greenShift,
          cont * sr, cont * sg, cont * (sb + s), 0, off + blueShift,
          0, 0, 0, 1, 0,
        ];
        child = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: child);
      }
    }

    final fxPreset = clip?.effect ?? VideoEffect.none;
    if (fxPreset != VideoEffect.none && clip != null) {
      child = _applyVideoEffectPreset(child, fxPreset, _e.playhead);
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
// Tracking overlay
// ----------------------------------------------------------------------------
class TrackingBox {
  const TrackingBox(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
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
          ..color = accentToken
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
    canvas.drawRect(Rect.fromLTWH(rect.left, top, lw, 16), Paint()..color = accentToken);
    tp.paint(canvas, Offset(rect.left + 6, top + 2));
  }

  @override
  bool shouldRepaint(covariant _TrackingPainter old) =>
      old.rect != rect || old.label != label;
}

// ----------------------------------------------------------------------------
// Preview: top bar + pro canvas
// ----------------------------------------------------------------------------
class PreviewCanvas extends StatefulWidget {
  const PreviewCanvas({super.key, required this.editor});
  final EditorController editor;

  @override
  State<PreviewCanvas> createState() => _PreviewCanvasState();
}

final GlobalKey _canvasBoundaryKey = GlobalKey();

class _PreviewCanvasState extends State<PreviewCanvas> {
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
              tapFeedback();
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
    final double s = scaleOf(size);
    final bool showLogo = size.width >= 430;
    final double btn = 36 * s;

    return Container(
      color: bgToken,
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
                ValueListenableBuilder<CanvasRatio>(
                  valueListenable: canvasRatioNotifier,
                  builder: (_, r, __) => PopupMenuButton<CanvasRatio>(
                    tooltip: 'Canvas ratio',
                    color: surfaceToken,
                    onSelected: (v) {
                      tapFeedback();
                      canvasRatioNotifier.value = v;
                      _tf.value = Matrix4.identity();
                    },
                    itemBuilder: (_) => <PopupMenuEntry<CanvasRatio>>[
                      for (final v in CanvasRatio.values)
                        PopupMenuItem<CanvasRatio>(
                          value: v,
                          child: Text(v.label,
                              style: TextStyle(
                                  color: v == r ? accentToken : Colors.white,
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
                      tapFeedback();
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
      child: RepaintBoundary(
        key: _canvasBoundaryKey,
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
            final double unit = fc.maxWidth / designWToken;
            final double designH = fc.maxHeight / unit;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                VideoPlayerPreview(editor: editor, fill: _fill),
                Consumer<EditorController>(
                  builder: (ctx, e, _) {
                    final dynamic tracking = e.selectedClip?.trackingData;
                    final TrackingBox? box = _trackingBox(tracking);

                    final activeOverlays = e.clips.where((c) {
                      return c.isVisible &&
                          c.clipType != ClipType.audio &&
                          (c.layerIndex > 0 ||
                              (c.clipType != ClipType.video &&
                                  c.clipType != ClipType.image)) &&
                          e.playhead >= c.start &&
                          e.playhead <= c.end;
                    }).toList()
                      ..sort((a, b) => a.layerIndex.compareTo(b.layerIndex));

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
                                positionX: x.clamp(-40.0, designWToken - 24).toDouble(),
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
                if (editor.isEyedropperActive)
                  Positioned.fill(
                    child: _EyedropperOverlay(
                      boundaryKey: _canvasBoundaryKey,
                      editor: editor,
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

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final double pad = 10 * scaleOf(MediaQuery.sizeOf(context));

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
                      child: ValueListenableBuilder<CanvasRatio>(
                        valueListenable: canvasRatioNotifier,
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

class PaneDivider extends StatelessWidget {
  const PaneDivider({super.key, required this.onDrag, required this.onReset});
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
          tapFeedback();
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
                  border: Border.all(color: bgToken, width: 1.5),
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
// Smart snapping
// ----------------------------------------------------------------------------
enum _SnapKind { center, edge, third, safe, object }

class _SnapLine {
  const _SnapLine(this.vertical, this.pos, this.kind);
  final bool vertical;
  final double pos;
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

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

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
        _SnapKind.center || _SnapKind.edge => accentToken,
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
    final double k = size.width / designWToken;
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
// Overlay clip
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
  double _rx = 0, _ry = 0;
  List<double> _ox = <double>[], _oy = <double>[];
  String _sig = '';

  Widget _content() {
    final clip = widget.clip;
    final double u = widget.unit;
    switch (clip.clipType) {
      case ClipType.video:
      case ClipType.image:
        final path = clip.sourcePath;
        final bool isImg = clip.clipType == ClipType.image ||
            (path != null && isImagePath(path));
        Widget mediaWidget;
        if (isImg && path != null && File(path).existsSync()) {
          Widget img = Image.file(
            File(path),
            fit: BoxFit.contain,
          );
          if (clip.chromaKey.enabled) {
            img = ChromaKeyPreview(
              chroma: clip.chromaKey,
              child: img,
            );
          }
          mediaWidget = SizedBox(
            width: 150 * clip.scale * u,
            height: 150 * clip.scale * u,
            child: img,
          );
        } else if (!isImg && path != null && File(path).existsSync()) {
          mediaWidget = _OverlayVideoPlayer(
            clip: clip,
            unit: u,
            editor: context.read<EditorController>(),
          );
        } else {
          mediaWidget = Text(
            clip.label,
            style: TextStyle(color: Colors.white, fontSize: 16 * u),
          );
        }
        return _applyAnimations(mediaWidget, clip);
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
        Widget elWidget;
        final svgStr = clip.elementProperties.svgPath ?? clip.sourcePath;
        if (svgStr != null && svgStr.isNotEmpty) {
          if (svgStr.trim().startsWith('<')) {
            elWidget = SizedBox(
              width: 100 * clip.scale * u,
              height: 100 * clip.scale * u,
              child: SvgPicture.string(
                svgStr,
                fit: BoxFit.contain,
                colorFilter: clip.elementProperties.fillColor != Colors.white
                    ? ColorFilter.mode(clip.elementProperties.fillColor, BlendMode.srcIn)
                    : null,
              ),
            );
          } else if (File(svgStr).existsSync()) {
            elWidget = SizedBox(
              width: 100 * clip.scale * u,
              height: 100 * clip.scale * u,
              child: SvgPicture.file(
                File(svgStr),
                fit: BoxFit.contain,
                colorFilter: clip.elementProperties.fillColor != Colors.white
                    ? ColorFilter.mode(clip.elementProperties.fillColor, BlendMode.srcIn)
                    : null,
              ),
            );
          } else {
            elWidget = Container(
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
          }
        } else {
          elWidget = Container(
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
        }
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
          final double th = 8 / u;
          final (double x, List<_SnapLine> lx) = _snapAxis(_rx, w, designWToken, true, _ox, th);
          final (double y, List<_SnapLine> ly) =
              _snapAxis(_ry, h, widget.designH, false, _oy, th);
          final List<_SnapLine> lines = <_SnapLine>[...lx, ...ly];
          final String sig =
              lines.map((l) => '${l.vertical}${l.pos.toStringAsFixed(1)}').join('|');
          if (sig.isNotEmpty && sig != _sig) tapFeedback();
          _sig = sig;
          widget.onPosition(x, y);
          widget.onGuides(_GuideState(dragging: true, lines: lines));
        },
        onScaleEnd: (_) => widget.onGuides(const _GuideState()),
        child: CustomPaint(
          key: _k,
          foregroundPainter: widget.isSelected ? const _DashedRectPainter() : null,
          child: Padding(
            padding: EdgeInsets.all(6 * u),
            child: _content(),
          ),
        ),
      ),
    );
  }
}

class _OverlayVideoPlayer extends StatefulWidget {
  const _OverlayVideoPlayer({
    required this.clip,
    required this.unit,
    required this.editor,
  });

  final TimelineClip clip;
  final double unit;
  final EditorController editor;

  @override
  State<_OverlayVideoPlayer> createState() => _OverlayVideoPlayerState();
}

class _OverlayVideoPlayerState extends State<_OverlayVideoPlayer> {
  VideoPlayerController? _vc;
  bool _failed = false;

  EditorController get _e => widget.editor;

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditor);
    _load(widget.clip.sourcePath);
  }

  @override
  void didUpdateWidget(covariant _OverlayVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.clip.sourcePath != widget.clip.sourcePath) {
      _load(widget.clip.sourcePath);
    }
  }

  @override
  void dispose() {
    _e.removeListener(_onEditor);
    _vc?.dispose();
    super.dispose();
  }

  void _onEditor() {
    final c = _vc;
    if (!mounted || c == null || !c.value.isInitialized) return;

    Duration local = _e.playhead - widget.clip.start;
    if (local.isNegative) local = Duration.zero;
    final Duration dur = c.value.duration;
    if (local > dur) local = dur;

    final Duration drift = (c.value.position - local).abs();

    if (_e.isPlaying) {
      if (!c.value.isPlaying) {
        c.seekTo(local).then((_) => c.play());
      } else if (drift > const Duration(milliseconds: 400)) {
        c.seekTo(local);
      }
    } else {
      if (c.value.isPlaying) c.pause();
      if (drift > const Duration(milliseconds: 40)) c.seekTo(local);
    }
  }

  Future<void> _load(String? path) async {
    if (path == null || path.isEmpty) return;

    final file = File(path);
    if (!await file.exists()) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    final c = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await c.initialize();
      await c.setLooping(false);
      await c.setVolume(widget.clip.volume);
      if (mounted) {
        setState(() {
          _vc = c;
          _failed = false;
        });
        _onEditor();
      }
    } catch (_) {
      c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final double u = widget.unit;
    final c = _vc;
    final bool ready = c != null && c.value.isInitialized;

    if (!ready || _failed) {
      return Container(
        width: 150 * clip.scale * u,
        height: 100 * clip.scale * u,
        color: Colors.black45,
        child: Center(
          child: Text(
            clip.label,
            style: TextStyle(color: Colors.white, fontSize: 12 * u),
          ),
        ),
      );
    }

    final Size vs = c.value.size;
    final double videoAspect = vs.width > 0 && vs.height > 0 ? vs.width / vs.height : 16 / 9;
    final double w = 150 * clip.scale * u;
    final double h = w / videoAspect;

    Widget playerWidget = SizedBox(
      width: w,
      height: h,
      child: VideoPlayer(c),
    );

    if (clip.chromaKey.enabled) {
      playerWidget = ChromaKeyPreview(
        chroma: clip.chromaKey,
        child: playerWidget,
      );
    }

    return playerWidget;
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
    final Rect safe = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width * 0.9,
        height: size.height * 0.9);
    canvas.drawRect(
        safe,
        Paint()
          ..color = accentToken.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    final Offset c = size.center(Offset.zero);
    canvas.drawLine(c.translate(-8, 0), c.translate(8, 0), p);
    canvas.drawLine(c.translate(0, -8), c.translate(0, 8), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final Rect r = Offset.zero & size;
    const double dashWidth = 5.0;
    const double dashSpace = 4.0;

    void drawDashedLine(Offset p1, Offset p2) {
      final double distance = (p2 - p1).distance;
      if (distance <= 0) return;
      final Offset dir = (p2 - p1) / distance;
      double start = 0;
      while (start < distance) {
        final double end = math.min(start + dashWidth, distance);
        canvas.drawLine(p1 + dir * start, p1 + dir * end, p);
        start += dashWidth + dashSpace;
      }
    }

    drawDashedLine(r.topLeft, r.topRight);
    drawDashedLine(r.topRight, r.bottomRight);
    drawDashedLine(r.bottomRight, r.bottomLeft);
    drawDashedLine(r.bottomLeft, r.topLeft);
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
// Eyedropper frame color picker overlay
// ----------------------------------------------------------------------------
class _EyedropperOverlay extends StatefulWidget {
  const _EyedropperOverlay({
    required this.boundaryKey,
    required this.editor,
  });

  final GlobalKey boundaryKey;
  final EditorController editor;

  @override
  State<_EyedropperOverlay> createState() => _EyedropperOverlayState();
}

class _EyedropperOverlayState extends State<_EyedropperOverlay> {
  Offset? _pos;
  Color? _sampledColor;
  bool _isSampling = false;

  Future<void> _sampleAt(Offset localOffset, Size size) async {
    if (_isSampling || size.width <= 0 || size.height <= 0) return;
    _isSampling = true;
    try {
      final boundary =
          widget.boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        image.dispose();
        return;
      }

      final double px = (localOffset.dx / size.width * image.width).clamp(0, image.width - 1.0);
      final double py = (localOffset.dy / size.height * image.height).clamp(0, image.height - 1.0);

      final int x = px.toInt();
      final int y = py.toInt();
      final int offset = (y * image.width + x) * 4;

      if (offset + 3 < byteData.lengthInBytes) {
        final int r = byteData.getUint8(offset);
        final int g = byteData.getUint8(offset + 1);
        final int b = byteData.getUint8(offset + 2);
        if (mounted) {
          setState(() {
            _pos = localOffset;
            _sampledColor = Color.fromARGB(255, r, g, b);
          });
        }
      }
      image.dispose();
    } catch (_) {
    } finally {
      _isSampling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final color = _sampledColor ?? const Color(0xFF00FF00);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _sampleAt(d.localPosition, size),
          onPanUpdate: (d) => _sampleAt(d.localPosition, size),
          onTapUp: (d) async {
            await _sampleAt(d.localPosition, size);
            widget.editor.completeEyedropper(_sampledColor);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black26),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.colorize_rounded, color: accentToken, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _sampledColor != null
                              ? 'Tap or release to select key color'
                              : 'Tap/drag anywhere on frame to pick color',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_pos != null)
                Positioned(
                  left: _pos!.dx - 36,
                  top: _pos!.dy - 36,
                  child: IgnorePointer(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 16,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => widget.editor.cancelEyedropper(),
                    ),
                    if (_sampledColor != null) ...[
                      const SizedBox(width: 12),
                      FloatingActionButton.extended(
                        elevation: 4,
                        backgroundColor: accentToken,
                        foregroundColor: Colors.black,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Apply Color', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => widget.editor.completeEyedropper(_sampledColor),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
