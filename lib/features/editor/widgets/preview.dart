import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/widgets/loading_wave.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/export_dialog.dart';
import 'package:flutter_video_editor/features/editor/widgets/fx_shader.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/chroma_key_preview.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';

// ----------------------------------------------------------------------------
// Monochrome palette
// ----------------------------------------------------------------------------
const Color _chipBg = Color(0xFF1C1C1C);
const Color _stageBg = Color(0xFF0C1014);

// ----------------------------------------------------------------------------
// Shared helpers
// ----------------------------------------------------------------------------

/// File existence is checked once per path instead of every frame.
final Map<String, bool> _existsCache = <String, bool>{};
bool _fileExists(String? path) {
  if (path == null || path.isEmpty) return false;
  return _existsCache.putIfAbsent(path, () => File(path).existsSync());
}

Widget applyVideoEffectPreset(Widget child, VideoEffect fx, Duration playhead, TimelineClip? clip) {
  final List<double>? m = _VideoPlayerPreviewState._fxMatrices[fx];
  if (m != null) return ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
  final shader = _VideoPlayerPreviewState._fxShaders[fx];
  if (shader != null) {
    final mergedParams = Map<String, double>.from(shader.$2);
    if (clip != null && clip.effectParameters.isNotEmpty) {
      mergedParams.addAll(clip.effectParameters);
    }
    return FxShaders.applyVideo(
      child: child,
      effectId: shader.$1,
      params: mergedParams,
      time: playhead,
    );
  }
  return child;
}

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
  double _speed = -1;
  double _vol = -1;

  EditorController get _e => widget.editor;

  static const Map<VideoEffect, List<double>> _fxMatrices = <VideoEffect, List<double>>{
    VideoEffect.warm: <double>[
      1.2, 0, 0, 0, 10, 0, 1.1, 0, 0, 5, 0, 0, 0.9, 0, 0, 0, 0, 0, 1, 0,
    ],
    VideoEffect.cinematic: <double>[
      1.1, 0, 0, 0, -10, 0, 1.2, 0, 0, 0, 0, 0, 1.3, 0, 10, 0, 0, 0, 1, 0,
    ],
    VideoEffect.noir: <double>[
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
      0, 0, 0, 1, 0,
    ],
    VideoEffect.vibrant: <double>[
      1.3, -0.1, -0.1, 0, 0,
      -0.1, 1.3, -0.1, 0, 0,
      -0.1, -0.1, 1.3, 0, 0,
      0, 0, 0, 1, 0,
    ],
    VideoEffect.vintage: <double>[
      0.9, 0.1, 0.1, 0, 15, 0.1, 0.8, 0.1, 0, 10, 0.1, 0.1, 0.6, 0, 5, 0, 0, 0, 1, 0,
    ],
    VideoEffect.retro: <double>[
      0.8, 0.2, 0.1, 0, 20, 0.1, 0.7, 0.2, 0, 15, 0.1, 0.1, 0.5, 0, 0, 0, 0, 0, 1, 0,
    ],
    VideoEffect.matrix: <double>[
      0.1, 0.8, 0.1, 0, 0, 0.1, 1.2, 0.1, 0, 20, 0.1, 0.8, 0.1, 0, 0, 0, 0, 0, 1, 0,
    ],
    VideoEffect.flame: <double>[
      1.4, 0, 0, 0, 30, 0.2, 0.8, 0, 0, 10, 0, 0, 0.5, 0, 0, 0, 0, 0, 1, 0,
    ],
  };

  static const Map<VideoEffect, (String, Map<String, double>)> _fxShaders =
      <VideoEffect, (String, Map<String, double>)>{
    VideoEffect.glitch: ('digital_glitch', <String, double>{'amount': 0.7, 'speed': 1.5}),
    VideoEffect.blur: ('blur', <String, double>{'blurAmount': 1.5}),
    VideoEffect.glow: ('dream_bloom', <String, double>{'intensity': 0.5, 'threshold': 0.6, 'radius': 0.5}),
    VideoEffect.vhs: ('vhs', <String, double>{'distortion': 1.0, 'scanlines': 0.5, 'noise': 0.5}),
    VideoEffect.vhsTape: ('vhs_tape', <String, double>{'amount': 0.7, 'speed': 1.0}),
    VideoEffect.wave: ('wave', <String, double>{'frequency': 10.0, 'amplitude': 1.0}),
    VideoEffect.liquidWave: ('liquid_wave', <String, double>{'amount': 1.0, 'freq': 2.0, 'speed': 1.0}),
    VideoEffect.vignette: ('vignette', <String, double>{'radius': 0.8, 'softness': 0.5}),
    VideoEffect.cinematicVignette: ('cinematic_vignette', <String, double>{'strength': 0.6, 'softness': 0.6}),
    VideoEffect.chromaticAberration: ('chromatic_aberration', <String, double>{'amount': 0.5}),
    VideoEffect.filmGrain: ('film_grain', <String, double>{'amount': 0.5, 'sizePx': 1.5}),
    VideoEffect.dreamBloom: ('dream_bloom', <String, double>{'intensity': 0.5, 'threshold': 0.6, 'radius': 0.5}),
    VideoEffect.mosaicPixelate: ('mosaic_pixelate', <String, double>{'sizePx': 12.0}),
    VideoEffect.crispSharpen: ('crisp_sharpen', <String, double>{'amount': 0.5}),
    VideoEffect.lensDistortion: ('lens_distortion', <String, double>{'amount': 0.4}),
    VideoEffect.convexScreenPro: ('convex_screen_pro', <String, double>{'progress': 0.0, 'strength': 0.5, 'radius': 0.8, 'centerX': 0.5, 'centerY': 0.5, 'shape': 1.0, 'anim': 0.0}),
    VideoEffect.speedZoomBlur: ('speed_zoom_blur', <String, double>{'amount': 0.5, 'centerX': 0.5, 'centerY': 0.5}),
    VideoEffect.lightLeak: ('light_leak', <String, double>{'intensity': 0.6, 'speed': 1.0}),
  };

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditor);
    _e.playheadListenable.addListener(_onEditor);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEditor());
  }

  @override
  void didUpdateWidget(covariant VideoPlayerPreview old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_onEditor);
      old.editor.playheadListenable.removeListener(_onEditor);
      widget.editor.addListener(_onEditor);
      widget.editor.playheadListenable.addListener(_onEditor);
      _onEditor();
    }
  }

  @override
  void dispose() {
    _e.removeListener(_onEditor);
    _e.playheadListenable.removeListener(_onEditor);
    _token++;
    _vc?.dispose();
    _vc = null;
    super.dispose();
  }

  void _onEditor() {
    if (!mounted) return;
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

    final double speed = clip.speed.clamp(0.1, 10.0).toDouble();
    if (speed != _speed) {
      _speed = speed;
      await c.setPlaybackSpeed(speed);
    }
    final relTime = _e.playhead - clip.start;
    final double baseVol = getInterpolatedKeyframeValue(clip, KeyframeProperty.volume, relTime, clip.volume);
    final double vol = baseVol.clamp(0.0, 1.0).toDouble();
    if (vol != _vol) {
      _vol = vol;
      await c.setVolume(vol);
    }

    Duration local = Duration(
        milliseconds: (clip.trimIn.inMilliseconds +
                (_e.playhead - clip.start).inMilliseconds * speed)
            .round());
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
    _speed = -1;
    _vol = -1;
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

  Widget _applyTransition(Widget child, TimelineClip clip, Duration playhead) {
    if (clip.transitionType.isEmpty || clip.transitionType.toLowerCase() == 'none' || clip.transitionDurationMs <= 0) {
      return child;
    }

    final Duration transDur = Duration(milliseconds: clip.transitionDurationMs);
    if (playhead < clip.end - transDur || playhead > clip.end) {
      return child;
    }

    final double p = ((playhead - (clip.end - transDur)).inMilliseconds / transDur.inMilliseconds).clamp(0.0, 1.0);
    final String type = clip.transitionType.toLowerCase();

    switch (type) {
      case 'fade':
      case 'dissolve':
        return Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: child);
      case 'flash':
        final double flashIntensity = (1.0 - (p - 0.5).abs() * 2.0).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: child),
            ColoredBox(color: Colors.white.withValues(alpha: flashIntensity)),
          ],
        );
      case 'slideleft':
        return Transform.translate(offset: Offset(-p * 360.0, 0), child: child);
      case 'slideright':
        return Transform.translate(offset: Offset(p * 360.0, 0), child: child);
      case 'slideup':
        return Transform.translate(offset: Offset(0, -p * 360.0), child: child);
      case 'slidedown':
        return Transform.translate(offset: Offset(0, p * 360.0), child: child);
      case 'zoomin':
        return Transform.scale(scale: 1.0 + p * 0.8, child: Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: child));
      case 'zoomout':
        return Transform.scale(scale: math.max(0.01, 1.0 - p * 0.8), child: Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: child));
      case 'blur':
        return ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: p * 15.0, sigmaY: p * 15.0), child: child);
      case 'glitch':
        return FxShaders.applyVideo(child: child, effectId: 'digital_glitch', params: <String, double>{'amount': p, 'speed': 2.0}, time: playhead);
      case 'wipe':
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: (1.0 - p).clamp(0.0, 1.0),
            child: child,
          ),
        );
      case 'spin':
        return Transform.rotate(angle: p * math.pi, child: Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: child));
      case 'fliphorizontal':
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(p * math.pi / 2),
          child: child,
        );
      case 'flipvertical':
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateX(p * math.pi / 2),
          child: child,
        );
      default:
        return Opacity(opacity: (1.0 - p).clamp(0.0, 1.0), child: child);
    }
  }

  Widget _placeholder(String text, {IconData icon = PhosphorIconsRegular.filmStrip}) {
    if (_loading) {
      return const Center(
        child: TextShimmerWave(
          'Loading clip…',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          baseColor: Colors.white38,
          waveColor: Colors.white,
        ),
      );
    }
    final bool showMessage = _failed || _e.clips.isEmpty;
    return ColoredBox(
      color: Colors.black,
      child: showMessage
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, color: Colors.white24, size: 28),
                  const SizedBox(height: 6),
                  Text(text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            )
          : const SizedBox.expand(),
    );
  }

  Widget _applyVideoEffectPreset(Widget child, VideoEffect fx, Duration playhead, TimelineClip? clip) {
    return applyVideoEffectPreset(child, fx, playhead, clip);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_e, _e.playheadListenable]),
      builder: (_, __) => _buildPreview(),
    );
  }

  Widget _buildPreview() {
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
              _placeholder("Can't open this image", icon: PhosphorIconsRegular.imageBroken),
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
      child = _placeholder("Can't play this file", icon: PhosphorIconsRegular.warningCircle);
    } else {
      child = _placeholder('Add media to start editing');
    }

    if (clip != null && (_isImg || ready)) {
      final relTime = _e.playhead - clip.start;
      final double kScale = getInterpolatedKeyframeValue(clip, KeyframeProperty.scale, relTime, clip.scale);
      final double kRot = getInterpolatedKeyframeValue(clip, KeyframeProperty.rotation, relTime, clip.rotation);
      final double kOpacity = getInterpolatedKeyframeValue(clip, KeyframeProperty.opacity, relTime, clip.opacity);

      final double sc = kScale.clamp(0.2, 5.0).toDouble();
      if (sc != 1.0) child = Transform.scale(scale: sc, child: child);
      if (kRot != 0.0) child = Transform.rotate(angle: kRot * math.pi / 180, child: child);
      if (kOpacity < 1.0) child = Opacity(opacity: kOpacity.clamp(0.0, 1.0).toDouble(), child: child);
    }

    if (clip != null && clip.chromaKey.enabled) {
      child = ChromaKeyPreview(chroma: clip.chromaKey, child: child);
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
      child = _applyVideoEffectPreset(child, fxPreset, _e.playhead, clip);
    }

    final shaderEffects = clip?.shaderEffects ?? const [];
    for (final fx in shaderEffects) {
      if (fx.isEnabled && clip != null) {
        final relTime = _e.playhead - clip.start;
        final activeParams = fx.getInterpolatedParameters(relTime);
        final Map<String, double> doubleParams = <String, double>{};
        activeParams.forEach((k, v) {
          if (v is num) doubleParams[k] = v.toDouble();
        });
        child = FxShaders.applyVideo(
          child: child,
          effectId: fx.effectId,
          params: doubleParams,
          time: _e.playhead,
        );
      }
    }

    if (clip != null) {
      child = _applyTransition(child, clip, _e.playhead);
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        if (_loading && ready)
          const Center(
            child: TextShimmerWave(
              'Loading clip…',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              baseColor: Colors.white38,
              waveColor: Colors.white,
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
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    // Accent is white now, so the label text is black for contrast.
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 10, color: Colors.black, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, rect.width));
    final double lw = tp.width + 12;
    final double top = math.max(0, rect.top - 16);
    canvas.drawRect(Rect.fromLTWH(rect.left, top, lw, 16), Paint()..color = Colors.white);
    tp.paint(canvas, Offset(rect.left + 6, top + 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant _TrackingPainter old) =>
      old.rect != rect || old.label != label;
}

// ----------------------------------------------------------------------------
// Face Tracking Effects Overlay
// ----------------------------------------------------------------------------
class _FaceTrackingEffectsOverlay extends StatelessWidget {
  const _FaceTrackingEffectsOverlay({
    required this.editor,
    required this.unit,
  });

  final EditorController editor;
  final double unit;

  @override
  Widget build(BuildContext context) {
    final trackingClips = editor.clips.where((c) =>
      c.isVisible &&
      c.faceTrackingData.isProcessed &&
      c.faceTrackingData.persons.isNotEmpty &&
      editor.playhead >= c.start &&
      editor.playhead < c.end
    );

    if (trackingClips.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double canvasW = constraints.maxWidth;
        final double canvasH = constraints.maxHeight;

        final List<Widget> personWidgets = [];

        for (final clip in trackingClips) {
          final FaceTrackingData ftData = clip.faceTrackingData;
          final int relTimeMs = (editor.playhead - clip.start).inMilliseconds;

          for (final person in ftData.persons) {
            final Rect? faceRect = person.rectAt(relTimeMs, margin: 0.25);
          if (faceRect == null) continue;

          final Rect scaledRect = Rect.fromLTWH(
            faceRect.left * canvasW,
            faceRect.top * canvasH,
            faceRect.width * canvasW,
            faceRect.height * canvasH,
          );

          for (final effect in person.effects) {
            switch (effect.type) {
              case PersonEffectType.blur:
                personWidgets.add(
                  Positioned.fromRect(
                    rect: scaledRect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(scaledRect.width * 0.2),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: effect.intensity.clamp(1.0, 30.0),
                          sigmaY: effect.intensity.clamp(1.0, 30.0),
                        ),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                  ),
                );
                break;

              case PersonEffectType.mosaic:
                personWidgets.add(
                  Positioned.fromRect(
                    rect: scaledRect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(scaledRect.width * 0.1),
                      child: CustomPaint(
                        painter: _MosaicPainter(pixelSize: effect.intensity),
                      ),
                    ),
                  ),
                );
                break;

              case PersonEffectType.text:
                personWidgets.add(
                  Positioned(
                    left: scaledRect.left,
                    top: math.max(0.0, scaledRect.top - 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accentToken, width: 1),
                      ),
                      child: Text(
                        effect.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
                break;

              case PersonEffectType.sticker:
                personWidgets.add(
                  Positioned.fromRect(
                    rect: scaledRect,
                    child: Center(
                      child: Text(
                        effect.stickerAsset,
                        style: TextStyle(
                          fontSize: math.min(scaledRect.width, scaledRect.height) * 0.8,
                        ),
                      ),
                    ),
                  ),
                );
                break;

              case PersonEffectType.none:
                break;
            }
          }
        }
        }

        return Stack(
          fit: StackFit.expand,
          children: personWidgets,
        );
      },
    );
  }
}

class _MosaicPainter extends CustomPainter {
  const _MosaicPainter({this.pixelSize = 12.0});

  final double pixelSize;

  @override
  void paint(Canvas canvas, Size size) {
    final double step = math.max(4.0, pixelSize);
    final Paint paint1 = Paint()..color = const Color(0x99202020);
    final Paint paint2 = Paint()..color = const Color(0x99505050);

    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final bool alt = (((x / step).floor() + (y / step).floor()) % 2) == 0;
        final Rect r = Rect.fromLTWH(x, y, math.min(step, size.width - x), math.min(step, size.height - y));
        canvas.drawRect(r, alt ? paint1 : paint2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MosaicPainter old) => old.pixelSize != pixelSize;
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

class _PreviewCanvasState extends State<PreviewCanvas> {
  final TransformationController _tf = TransformationController();
  final GlobalKey _boundaryKey = GlobalKey();
  final ValueNotifier<_GuideState> _guides =
      ValueNotifier<_GuideState>(const _GuideState());
  final bool _grid = false;
  final bool _fill = false;
  String _selectedQuality = 'HD';

  @override
  void dispose() {
    _guides.dispose();
    _tf.dispose();
    super.dispose();
  }

  Widget _roundBtn(PhosphorIconData icon, String tip, VoidCallback onTap,
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
                  color: on ? Colors.white : _chipBg, shape: BoxShape.circle),
              child: Center(
                child: PhosphorIcon(
                  icon,
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
                _roundBtn(PhosphorIconsRegular.arrowLeft, 'Back',
                    () => Navigator.of(context).maybePop(),
                    size: btn, iconSize: 16 * s),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Quality',
                  color: surfaceToken,
                  initialValue: _selectedQuality,
                  onSelected: (v) {
                    tapFeedback();
                    setState(() => _selectedQuality = v);
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    for (final q in const <String>['HD', '4M', 'UHD'])
                      PopupMenuItem<String>(
                        value: q,
                        child: Text(
                          q,
                          style: TextStyle(
                            color: q == _selectedQuality ? Colors.white : Colors.white54,
                            fontWeight: q == _selectedQuality ? FontWeight.w700 : FontWeight.w500,
                            fontFamily: 'Google Sans',
                          ),
                        ),
                      ),
                  ],
                  child: Container(
                    height: 30 * s,
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(horizontal: 10 * s),
                    decoration: BoxDecoration(
                      color: _chipBg,
                      borderRadius: BorderRadius.circular(6 * s),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _selectedQuality,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5 * s,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Google Sans',
                          ),
                        ),
                        SizedBox(width: 4 * s),
                        PhosphorIcon(
                          PhosphorIconsRegular.caretDown,
                          size: 12 * s,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8 * s),
                Material(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      tapFeedback();
                      ExportModal.show(context);
                    },
                    child: SizedBox(
                      height: btn,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14 * s),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            PhosphorIcon(
                              PhosphorIconsBold.export,
                              color: Colors.black,
                              size: 15 * s,
                            ),
                            SizedBox(width: 5 * s),
                            Text('Export',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 12.5 * s,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Google Sans')),
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
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            key: _boundaryKey,
            child: ValueListenableBuilder<Color>(
              key: const ValueKey('canvasColorBox'),
              valueListenable: canvasColorNotifier,
              builder: (_, canvasColor, __) {
                final bool isTransparent = canvasColor == Colors.transparent;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: isTransparent ? null : canvasColor,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: CustomPaint(
                    painter: isTransparent ? const _PreviewCheckerboardPainter() : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: LayoutBuilder(builder: (context, fc) {
                        final double unit = fc.maxWidth / designWToken;
                        final double designH = fc.maxHeight / unit;
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            VideoPlayerPreview(editor: editor, fill: _fill),
                            _AudioClipsPreview(editor: editor),
                            Positioned(
                              right: 14 * unit,
                              bottom: 14 * unit,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.85,
                                  child: SvgPicture.asset(
                                    'assets/logo_white.svg',
                                    height: 32 * unit,
                                  ),
                                ),
                              ),
                            ),
                            ValueListenableBuilder<Duration>(
                              valueListenable: editor.playheadListenable,
                              builder: (ctx, playhead, _) {
                                return Consumer<EditorController>(
                                  builder: (ctx, e, _) {
                                    final dynamic tracking = e.selectedClip?.trackingData;
                                    final TrackingBox? box = _trackingBox(tracking);

                                    final activeOverlays = e.clips.where((c) {
                                      return c.isVisible &&
                                          c.clipType != ClipType.audio &&
                                          (c.layerIndex > 0 ||
                                              (c.clipType != ClipType.video &&
                                                  c.clipType != ClipType.image)) &&
                                          playhead >= c.start &&
                                          playhead < c.end;
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
                                            viewScale: () => _tf.value.getMaxScaleOnAxis(),
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
                                                positionX:
                                                    x.clamp(-40.0, designWToken - 24).toDouble(),
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
                                                        strokes: e.activeDrawingStrokes,
                                                        unit: unit),
                                                  ),
                                                ),
                                              if (box != null)
                                                Positioned.fill(
                                                  child: _TrackingOverlay(
                                                    box: box,
                                                    label:
                                                        '${(tracking as dynamic)?.targetName ?? 'Target'}',
                                                  ),
                                                ),
                                              Positioned.fill(
                                                child: _FaceTrackingEffectsOverlay(
                                                  editor: editor,
                                                  unit: unit,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
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
              },
            ),
          ),
          // Outside the RepaintBoundary so its tint and magnifier are never sampled.
          ListenableBuilder(
            listenable: editor,
            builder: (_, __) => editor.isEyedropperActive
                ? _EyedropperOverlay(boundaryKey: _boundaryKey, editor: editor)
                : const SizedBox.shrink(),
          ),
        ],
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
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Container(
                  color: _stageBg,
                  child: ClipRect(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: editor.togglePlayback,
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
              Positioned(
                right: 10,
                bottom: 10,
                child: ListenableBuilder(
                  listenable: _tf,
                  builder: (_, __) => _tf.value.getMaxScaleOnAxis() > 1.01
                      ? Material(
                          color: _chipBg,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              tapFeedback();
                              _tf.value = Matrix4.identity();
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(PhosphorIconsRegular.arrowsOut,
                                      size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('Reset',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewCheckerboardPainter extends CustomPainter {
  const _PreviewCheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double sq = 12.0;
    final Paint p1 = Paint()..color = const Color(0xFF1E1E1E);
    final Paint p2 = Paint()..color = const Color(0xFF2C2C2C);

    canvas.drawRect(Offset.zero & size, p1);

    for (double y = 0; y < size.height; y += sq) {
      for (double x = 0; x < size.width; x += sq) {
        if (((x / sq).floor() + (y / sq).floor()) % 2 == 1) {
          canvas.drawRect(Rect.fromLTWH(x, y, sq, sq), p2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
        child: Container(
          height: 14,
          color: bgToken,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              const Divider(
                height: 2,
                thickness: 2,
                color: Color(0xFF383838),
              ),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF777777),
                  borderRadius: BorderRadius.circular(2),
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
  int get hashCode => Object.hash(dragging, Object.hashAll(lines));
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Bounding rect (design units) of an overlay, matching what _OverlayClip draws.
Rect _overlayRect(TimelineClip c) {
  double w, h;
  switch (c.clipType) {
    case ClipType.video:
      w = 150 * c.scale;
      h = 84 * c.scale;
    case ClipType.image:
      w = h = 150 * c.scale;
    case ClipType.element:
      final String? svg = c.elementProperties.svgPath ?? c.sourcePath;
      w = h = ((svg != null && svg.isNotEmpty) ? 100 : 80) * c.scale;
    case ClipType.drawing:
      w = h = 120 * c.scale;
    default:
      final bool text = c.clipType == ClipType.text ||
          c.clipType == ClipType.caption ||
          c.clipType == ClipType.sticker;
      final tp = TextPainter(
        text: TextSpan(
          text: c.label,
          style: TextStyle(
              fontSize: text ? c.textStyle.fontSize * c.scale : 16.0,
              fontFamily: c.fontFamily,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      w = tp.width;
      h = tp.height;
      tp.dispose();
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

  @override
  void paint(Canvas canvas, Size size) {
    final double k = size.width / designWToken;
    final Paint p = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 0.5;

    final bool vc = g.lines.any((l) => l.vertical && l.kind == _SnapKind.center);
    final bool hc = g.lines.any((l) => !l.vertical && l.kind == _SnapKind.center);
    if (!vc) {
      _dashed(canvas, Offset(size.width / 2, 0), Offset(size.width / 2, size.height), p);
    }
    if (!hc) {
      _dashed(canvas, Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
    }

    for (final l in g.lines) {
      if (l.vertical) {
        final double x = (l.pos * k).clamp(0.5, size.width - 0.5).toDouble();
        _dashed(canvas, Offset(x, 0), Offset(x, size.height), p);
      } else {
        final double y = (l.pos * k).clamp(0.5, size.height - 0.5).toDouble();
        _dashed(canvas, Offset(0, y), Offset(size.width, y), p);
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
    required this.viewScale,
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
  final double Function() viewScale;
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

  Widget _applyEffectsAndGrading(Widget content, TimelineClip clip) {
    Widget child = content;
    final editor = context.read<EditorController>();
    final Duration playhead = editor.playhead;

    final cg = clip.colorGrading;
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

    final fxPreset = clip.effect;
    if (fxPreset != VideoEffect.none) {
      child = applyVideoEffectPreset(child, fxPreset, playhead, clip);
    }

    for (final fx in clip.shaderEffects) {
      if (fx.isEnabled) {
        final relTime = playhead - clip.start;
        final activeParams = fx.getInterpolatedParameters(relTime);
        final Map<String, double> doubleParams = <String, double>{};
        activeParams.forEach((k, v) {
          if (v is num) doubleParams[k] = v.toDouble();
        });
        child = FxShaders.applyVideo(
          child: child,
          effectId: fx.effectId,
          params: doubleParams,
          time: playhead,
        );
      }
    }

    return child;
  }

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
        if (isImg && _fileExists(path)) {
          Widget img = Image.file(
            File(path!),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
          if (clip.chromaKey.enabled) {
            img = ChromaKeyPreview(chroma: clip.chromaKey, child: img);
          }
          mediaWidget = SizedBox(
            width: 150 * clip.scale * u,
            height: 150 * clip.scale * u,
            child: img,
          );
        } else if (!isImg && _fileExists(path)) {
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
        mediaWidget = _applyEffectsAndGrading(mediaWidget, clip);
        return _applyAnimations(mediaWidget, clip);
      case ClipType.text:
      case ClipType.caption:
      case ClipType.sticker:
        final ts = clip.textStyle;
        final double effectiveSize = ts.fontSize * clip.scale * u;

        final List<Shadow> shadows = <Shadow>[];
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
        } else {
          shadows.add(const Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1)));
        }

        Widget textWidget;
        final bool isCaption = clip.clipType == ClipType.caption;
        if (isCaption && ts.enableHighlight) {
          textWidget = _buildHighlightedCaptionText(
            clip: clip,
            playhead: context.read<EditorController>().playhead,
            effectiveSize: effectiveSize,
            shadows: shadows,
            u: u,
          );
        } else {
          textWidget = Text(
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
        }

        if (ts.strokeWidth > 0 && ts.strokeColor != Colors.transparent) {
          textWidget = Stack(
            children: <Widget>[
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

        textWidget = _applyEffectsAndGrading(textWidget, clip);
        return _applyAnimations(textWidget, clip);
      case ClipType.element:
        final elWidget = _applyEffectsAndGrading(_elementWidget(clip, u), clip);
        return _applyAnimations(elWidget, clip);
      case ClipType.drawing:
        final drWidget = CustomPaint(
          size: Size(120 * clip.scale * u, 120 * clip.scale * u),
          painter: _DrawingPainter(strokes: clip.strokes, unit: u),
        );
        final fxDrWidget = _applyEffectsAndGrading(drWidget, clip);
        return _applyAnimations(fxDrWidget, clip);
      default:
        return _applyAnimations(
          Text(clip.label, style: TextStyle(color: Colors.white, fontSize: 16 * u)),
          clip,
        );
    }
  }

  Widget _elementWidget(TimelineClip clip, double u) {
    final props = clip.elementProperties;
    final String? svgStr = props.svgPath ?? clip.sourcePath;
    final ColorFilter? tint = props.fillColor != Colors.white
        ? ColorFilter.mode(props.fillColor, BlendMode.srcIn)
        : null;

    Widget shape() => Container(
          width: 80 * clip.scale * u,
          height: 80 * clip.scale * u,
          decoration: BoxDecoration(
            color: props.fillColor,
            shape: props.shape == ElementShape.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: props.shape == ElementShape.rectangle
                ? BorderRadius.circular(8 * u)
                : null,
          ),
        );

    if (svgStr == null || svgStr.isEmpty) return shape();
    final double side = 100 * clip.scale * u;
    if (svgStr.trim().startsWith('<')) {
      return SizedBox(
        width: side,
        height: side,
        child: SvgPicture.string(svgStr, fit: BoxFit.contain, colorFilter: tint),
      );
    }
    if (_fileExists(svgStr)) {
      return SizedBox(
        width: side,
        height: side,
        child: SvgPicture.file(File(svgStr), fit: BoxFit.contain, colorFilter: tint),
      );
    }
    return shape();
  }

  Widget _buildHighlightedCaptionText({
    required TimelineClip clip,
    required Duration playhead,
    required double effectiveSize,
    required List<Shadow> shadows,
    required double u,
  }) {
    final ts = clip.textStyle;
    final text = clip.label.trim();
    if (text.isEmpty) {
      return Text('', style: TextStyle(fontSize: effectiveSize));
    }

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return Text(text, style: TextStyle(fontSize: effectiveSize, color: ts.textColor));
    }

    int activeIndex = -1;

    if (clip.words.isNotEmpty) {
      for (int i = 0; i < clip.words.length; i++) {
        final w = clip.words[i];
        if (playhead >= w.start && playhead <= w.end) {
          activeIndex = i;
          break;
        }
      }
    }

    if (activeIndex == -1 && words.isNotEmpty) {
      final clipDurationMs = clip.duration.inMilliseconds;
      if (clipDurationMs > 0) {
        final elapsedMs = (playhead - clip.start).inMilliseconds.clamp(0, clipDurationMs);
        final fraction = elapsedMs / clipDurationMs;
        activeIndex = (fraction * words.length).floor().clamp(0, words.length - 1);
      }
    }

    final spans = <TextSpan>[];
    for (int i = 0; i < words.length; i++) {
      final isWordActive = (i == activeIndex);
      final wordStr = words[i];

      final Color textColor = isWordActive ? ts.highlightColor : ts.textColor;
      final Color bg = (isWordActive && ts.highlightBackgroundColor != Colors.transparent)
          ? ts.highlightBackgroundColor
          : Colors.transparent;
      final double fontSize = (isWordActive && ts.highlightStyle == 'scale')
          ? effectiveSize * 1.15
          : effectiveSize;

      spans.add(
        TextSpan(
          text: wordStr + (i == words.length - 1 ? '' : ' '),
          style: TextStyle(
            color: textColor,
            backgroundColor: bg,
            fontSize: fontSize,
            fontFamily: clip.fontFamily,
            fontWeight: isWordActive ? FontWeight.w900 : FontWeight.bold,
            height: ts.lineHeight,
            shadows: shadows,
          ),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: ts.textAlign,
    );
  }

  Widget _applyAnimations(Widget child, TimelineClip clip) {
    final editor = context.read<EditorController>();
    final playhead = editor.playhead;
    final int durInMs = math.max(1, math.min(500, clip.duration.inMilliseconds ~/ 2));

    double opacity = clip.opacity;
    double scaleMult = 1.0;
    double transX = 0.0;
    double rot = 0.0;
    double flipX = 0.0; // radians around Y
    double flipY = 0.0; // radians around X
    double blur = 0.0;

    if (clip.inAnimation != ClipAnimation.none && playhead >= clip.start) {
      final int elapsed = (playhead - clip.start).inMilliseconds;
      if (elapsed < durInMs) {
        final double t = (elapsed / durInMs).clamp(0.0, 1.0).toDouble();
        switch (clip.inAnimation) {
          case ClipAnimation.fadeIn:
            opacity *= t;
          case ClipAnimation.zoomIn:
            scaleMult *= (0.3 + 0.7 * t);
          case ClipAnimation.slideLeft:
            transX -= (1.0 - t) * 60;
          case ClipAnimation.slideRight:
            transX += (1.0 - t) * 60;
          case ClipAnimation.rotateIn:
            rot = -(1.0 - t) * math.pi / 2;
            scaleMult *= (0.5 + 0.5 * t);
            opacity *= t;
          case ClipAnimation.flipHorizontal:
            flipX = (1.0 - t) * math.pi / 2;
            scaleMult *= (0.4 + 0.6 * t);
          case ClipAnimation.flipVertical:
            flipY = (1.0 - t) * math.pi / 2;
            scaleMult *= (0.4 + 0.6 * t);
          case ClipAnimation.elasticBounce:
            scaleMult *= math.max(0.01, Curves.elasticOut.transform(t));
          case ClipAnimation.blurFade:
            opacity *= t;
            blur = (1.0 - t) * 8.0;
          case ClipAnimation.shakeSlide:
            transX += math.sin(t * math.pi * 4.0) * 12.0 * (1.0 - t);
          case ClipAnimation.zoomRotate:
            rot = (1.0 - t) * math.pi;
            scaleMult *= (0.2 + 0.8 * t);
            opacity *= t;
          default:
            break;
        }
      }
    }

    if (clip.outAnimation != ClipAnimation.none && playhead <= clip.end) {
      final int remaining = (clip.end - playhead).inMilliseconds;
      if (remaining < durInMs) {
        final double t = (remaining / durInMs).clamp(0.0, 1.0).toDouble();
        switch (clip.outAnimation) {
          case ClipAnimation.fadeOut:
            opacity *= t;
          case ClipAnimation.zoomOut:
            scaleMult *= (0.3 + 0.7 * t);
          case ClipAnimation.slideRight:
            transX += (1.0 - t) * 60;
          case ClipAnimation.slideLeft:
            transX -= (1.0 - t) * 60;
          default:
            break;
        }
      }
    }

    final relTime = playhead - clip.start;
    final double kScale = getInterpolatedKeyframeValue(clip, KeyframeProperty.scale, relTime, clip.scale);
    final double kRot = getInterpolatedKeyframeValue(clip, KeyframeProperty.rotation, relTime, clip.rotation);
    final double kOpacity = getInterpolatedKeyframeValue(clip, KeyframeProperty.opacity, relTime, clip.opacity);

    if (clip.scale > 0) scaleMult *= (kScale / clip.scale);
    rot += kRot * math.pi / 180;
    opacity *= kOpacity;

    Widget result = child;
    if (blur > 0.1) {
      result = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: result,
      );
    }
    if (flipX != 0.0 || flipY != 0.0) {
      result = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(flipX)
          ..rotateX(flipY),
        child: result,
      );
    }
    if (rot != 0.0) result = Transform.rotate(angle: rot, child: result);
    if (transX != 0.0) {
      result = Transform.translate(offset: Offset(transX, 0), child: result);
    }
    if (scaleMult != 1.0) {
      result = Transform.scale(scale: math.max(0.01, scaleMult), child: result);
    }
    if (opacity < 1.0) {
      result = Opacity(opacity: opacity.clamp(0.0, 1.0).toDouble(), child: result);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final double u = widget.unit;
    final editor = context.watch<EditorController>();
    final relTime = editor.playhead - clip.start;
    final double activeX = getInterpolatedKeyframeValue(clip, KeyframeProperty.positionX, relTime, clip.positionX);
    final double activeY = getInterpolatedKeyframeValue(clip, KeyframeProperty.positionY, relTime, clip.positionY);

    return Positioned(
      left: activeX * u,
      top: activeY * u,
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
          // Divide by the InteractiveViewer zoom so the overlay tracks the finger.
          final double vs = math.max(1.0, widget.viewScale());
          _rx += d.focalPointDelta.dx / u / vs;
          _ry += d.focalPointDelta.dy / u / vs;
          final Size? sz = _k.currentContext?.size;
          final double w = (sz?.width ?? 0) / u;
          final double h = (sz?.height ?? 0) / u;
          final double th = 8 / u / vs;
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
  int _token = 0;
  bool _seeking = false;
  double _speed = -1;
  double _vol = -1;

  EditorController get _e => widget.editor;

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditor);
    _e.playheadListenable.addListener(_onEditor);
    _load(widget.clip.sourcePath);
  }

  @override
  void didUpdateWidget(covariant _OverlayVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_onEditor);
      old.editor.playheadListenable.removeListener(_onEditor);
      widget.editor.addListener(_onEditor);
      widget.editor.playheadListenable.addListener(_onEditor);
    }
    if (old.clip.sourcePath != widget.clip.sourcePath) {
      _load(widget.clip.sourcePath);
    }
  }

  @override
  void dispose() {
    _token++;
    _e.removeListener(_onEditor);
    _e.playheadListenable.removeListener(_onEditor);
    _vc?.dispose();
    _vc = null;
    super.dispose();
  }

  Future<void> _onEditor() async {
    final c = _vc;
    if (!mounted || c == null || !c.value.isInitialized) return;

    final double speed = widget.clip.speed.clamp(0.1, 10.0).toDouble();
    if (speed != _speed) {
      _speed = speed;
      c.setPlaybackSpeed(speed);
    }
    final double vol = widget.clip.volume.clamp(0.0, 1.0).toDouble();
    if (vol != _vol) {
      _vol = vol;
      c.setVolume(vol);
    }

    Duration local = Duration(
        milliseconds: (widget.clip.trimIn.inMilliseconds +
                (_e.playhead - widget.clip.start).inMilliseconds * speed)
            .round());
    if (local.isNegative) local = Duration.zero;
    final Duration dur = c.value.duration;
    if (local > dur) local = dur;

    final Duration drift = (c.value.position - local).abs();

    if (_seeking) return;
    if (_e.isPlaying) {
      if (!c.value.isPlaying) {
        _seeking = true;
        try {
          await c.seekTo(local);
          if (mounted && _e.isPlaying) await c.play();
        } finally {
          _seeking = false;
        }
      } else if (drift > const Duration(milliseconds: 400)) {
        _seeking = true;
        try {
          await c.seekTo(local);
        } finally {
          _seeking = false;
        }
      }
    } else {
      if (c.value.isPlaying) c.pause();
      if (drift > const Duration(milliseconds: 40)) {
        _seeking = true;
        try {
          await c.seekTo(local);
        } finally {
          _seeking = false;
        }
      }
    }
  }

  Future<void> _load(String? path) async {
    final int token = ++_token;
    final old = _vc;
    if (old != null) {
      _vc = null;
      _speed = -1;
      _vol = -1;
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      await old.dispose();
    }
    if (path == null || path.isEmpty) return;

    final file = File(path);
    if (!await file.exists()) {
      _existsCache[path] = false;
      if (mounted && token == _token) setState(() => _failed = true);
      return;
    }

    final c = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await c.initialize();
      await c.setLooping(false);
      await c.setVolume(widget.clip.volume.clamp(0.0, 1.0).toDouble());
    } catch (_) {
      await c.dispose();
      if (mounted && token == _token) setState(() => _failed = true);
      return;
    }

    if (!mounted || token != _token) {
      await c.dispose();
      return;
    }
    setState(() {
      _vc = c;
      _failed = false;
    });
    _onEditor();
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

    Widget playerWidget = SizedBox(width: w, height: h, child: VideoPlayer(c));

    if (clip.chromaKey.enabled) {
      playerWidget = ChromaKeyPreview(chroma: clip.chromaKey, child: playerWidget);
    }

    return playerWidget;
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (final double f in const <double>[1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), p);
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 1.5
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
// Audio Clips Preview Engine
// ----------------------------------------------------------------------------
class _AudioClipsPreview extends StatefulWidget {
  const _AudioClipsPreview({required this.editor});
  final EditorController editor;

  @override
  State<_AudioClipsPreview> createState() => _AudioClipsPreviewState();
}

class _AudioClipsPreviewState extends State<_AudioClipsPreview> {
  final Map<String, VideoPlayerController> _audioControllers =
      <String, VideoPlayerController>{};
  bool _busy = false;
  bool _dirty = false;
  bool _disposed = false;

  EditorController get _e => widget.editor;

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditorChange);
    _e.playheadListenable.addListener(_onEditorChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEditorChange());
  }

  @override
  void didUpdateWidget(covariant _AudioClipsPreview old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_onEditorChange);
      old.editor.playheadListenable.removeListener(_onEditorChange);
      widget.editor.addListener(_onEditorChange);
      widget.editor.playheadListenable.addListener(_onEditorChange);
      _onEditorChange();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _e.removeListener(_onEditorChange);
    _e.playheadListenable.removeListener(_onEditorChange);
    for (final controller in _audioControllers.values) {
      controller.dispose();
    }
    _audioControllers.clear();
    super.dispose();
  }

  /// One sync at a time; if something changes meanwhile, run once more.
  Future<void> _onEditorChange() async {
    if (_disposed) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    _busy = true;
    try {
      do {
        _dirty = false;
        await _syncAudioPlayers();
      } while (_dirty && !_disposed);
    } finally {
      _busy = false;
    }
  }

  Future<void> _syncAudioPlayers() async {
    final activeAudioClips = _e.clips.where((c) {
      return c.isVisible &&
          c.clipType == ClipType.audio &&
          c.sourcePath != null &&
          c.sourcePath!.isNotEmpty &&
          _e.playhead >= c.start &&
          _e.playhead < c.end;
    }).toList();

    final activeClipIds = activeAudioClips.map((c) => c.id).toSet();

    final toRemove =
        _audioControllers.keys.where((id) => !activeClipIds.contains(id)).toList();
    for (final id in toRemove) {
      final controller = _audioControllers.remove(id);
      await controller?.pause();
      await controller?.dispose();
    }

    for (final clip in activeAudioClips) {
      if (_disposed) return;
      final path = clip.sourcePath!;
      VideoPlayerController? controller = _audioControllers[clip.id];

      if (controller == null) {
        if (!_fileExists(path)) continue;

        controller = VideoPlayerController.file(
          File(path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        try {
          await controller.initialize();
          await controller.setLooping(false);
        } catch (_) {
          await controller.dispose();
          continue;
        }
        if (_disposed) {
          await controller.dispose();
          return;
        }
        _audioControllers[clip.id] = controller;
      }

      if (!controller.value.isInitialized) continue;

      final double speed = clip.speed.clamp(0.1, 10.0).toDouble();
      final relTime = _e.playhead - clip.start;
      final double kVol = getInterpolatedKeyframeValue(clip, KeyframeProperty.volume, relTime, clip.volume);
      final double vol =
          (kVol * clip.audioProperties.volume).clamp(0.0, 1.0).toDouble();
      await controller.setPlaybackSpeed(speed);
      await controller.setVolume(vol);

      Duration local = Duration(
        milliseconds: (clip.trimIn.inMilliseconds +
                (_e.playhead - clip.start).inMilliseconds * speed)
            .round(),
      );
      if (local.isNegative) local = Duration.zero;
      final Duration dur = controller.value.duration;
      if (local > dur) local = dur;

      final Duration drift = (controller.value.position - local).abs();

      if (_e.isPlaying) {
        if (!controller.value.isPlaying) {
          await controller.seekTo(local);
          await controller.play();
        } else if (drift > const Duration(milliseconds: 400)) {
          await controller.seekTo(local);
        }
      } else {
        if (controller.value.isPlaying) await controller.pause();
        if (drift > const Duration(milliseconds: 40)) await controller.seekTo(local);
      }
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
  ByteData? _bytes;
  int _imgW = 0;
  int _imgH = 0;

  @override
  void initState() {
    super.initState();
    // Snapshot the clean frame once; sampling then reads from memory.
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    try {
      final boundary =
          widget.boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int w = image.width, h = image.height;
      image.dispose();
      if (!mounted || data == null) return;
      setState(() {
        _bytes = data;
        _imgW = w;
        _imgH = h;
      });
    } catch (_) {}
  }

  void _sampleAt(Offset local, Size size) {
    final ByteData? data = _bytes;
    if (data == null || size.width <= 0 || size.height <= 0 || _imgW == 0) return;
    final int x = (local.dx / size.width * _imgW).floor().clamp(0, _imgW - 1).toInt();
    final int y = (local.dy / size.height * _imgH).floor().clamp(0, _imgH - 1).toInt();
    final int o = (y * _imgW + x) * 4;
    if (o + 3 >= data.lengthInBytes) return;
    setState(() {
      _pos = local;
      _sampledColor =
          Color.fromARGB(255, data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
    });
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
          onTapUp: (d) {
            _sampleAt(d.localPosition, size);
            widget.editor.completeEyedropper(_sampledColor);
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: Colors.black26),
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
                      children: <Widget>[
                        const Icon(PhosphorIconsRegular.eyedropper, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _sampledColor != null
                                ? 'Tap or release to select key color'
                                : 'Tap/drag anywhere on frame to pick color',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5),
                          ),
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
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                  children: <Widget>[
                    IconButton.filledTonal(
                      tooltip: 'Cancel',
                      icon: const Icon(PhosphorIconsRegular.x, color: Colors.white),
                      onPressed: () => widget.editor.cancelEyedropper(),
                    ),
                    if (_sampledColor != null) ...<Widget>[
                      const SizedBox(width: 12),
                      FloatingActionButton.extended(
                        elevation: 4,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        icon: const Icon(PhosphorIconsRegular.check),
                        label: const Text('Apply Color',
                            style: TextStyle(fontWeight: FontWeight.bold)),
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