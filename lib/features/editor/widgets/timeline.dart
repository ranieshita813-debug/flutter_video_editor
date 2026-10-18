import 'package:phosphor_icons/phosphor_icons.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';

// ----------------------------------------------------------------------------
// Constants & helpers
// ----------------------------------------------------------------------------

/// Playhead colour. The name is kept so other files that import it still
/// compile; in the monochrome theme it is plain white.
const Color playheadBlue = Color(0xFFFFFFFF);
const Color _timelineBg = Color(0xFF0A0A0A);
const Color _overlayMediaColor = Color(0xFF454545);
const Color _emptyLaneColor = Color(0xFF141414);
const double _clipRadius = 5;
const int _fps = 30;

/// Pixels per second at zoom 1.0 (CapCut-like: 1s is roughly 48px).
const double _basePps = 48.0;
const double _minZoom = 0.5;
const double _maxZoom = 12.0;

/// HH:MM:SS:FF timecode, used only by the scrub preview card.
String _tcFrames(double t) {
  final int f = (math.max(0.0, t) * _fps).round();
  final int s = f ~/ _fps;
  return '${twoDigits(s ~/ 3600)}:${twoDigits((s ~/ 60) % 60)}:'
      '${twoDigits(s % 60)}:${twoDigits(f % _fps)}';
}

/// Ruler label, CapCut style: 00:00, 1s, 2s ... 59s, 01:00 ... and frame
/// labels (5f, 10f ...) for positions inside a second.
String _rulerLabel(double t) {
  final int fr = (t * _fps).round();
  if (fr % _fps != 0) return '${fr % _fps}f';
  final int s = fr ~/ _fps;
  if (s == 0) return '00:00';
  if (s < 60) return '${s}s';
  return '${twoDigits(s ~/ 60)}:${twoDigits(s % 60)}';
}

String _kindName(ClipType t) {
  switch (t) {
    case ClipType.audio:
      return 'Audio';
    case ClipType.video:
      return 'Video';
    case ClipType.image:
      return 'Image';
    case ClipType.sticker:
    case ClipType.element:
      return 'Sticker';
    case ClipType.drawing:
      return 'Drawing';
    default:
      return 'Text';
  }
}

// ----------------------------------------------------------------------------
// Timeline Model & Snapshots
// ----------------------------------------------------------------------------
class _KfSnap {
  const _KfSnap(this.id, this.ms);
  final String id;
  final int ms; // relative to clip start

  @override
  bool operator ==(Object o) => o is _KfSnap && o.id == id && o.ms == ms;
  @override
  int get hashCode => Object.hash(id, ms);
}

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
    required this.keyframes,
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
  final List<_KfSnap> keyframes;

  double get startSec => startMs / 1000.0;
  double get endSec => endMs / 1000.0;
  double get durSec => (endMs - startMs) / 1000.0;
  bool get isMain => (type == ClipType.video || type == ClipType.image) && layer == 0;

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
      other.path == path &&
      _listEq(other.keyframes, keyframes);

  @override
  int get hashCode => Object.hash(id, startMs, endMs, label, type, layer, locked,
      visible, path, Object.hashAll(keyframes));
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
              keyframes: <_KfSnap>[
                for (final k in c.keyframes) _KfSnap(k.id, k.time.inMilliseconds),
              ],
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
  int get hashCode =>
      Object.hash(zoom, selectedId, totalMs, Object.hashAll(clips));
}

enum _ClipKind { text, video, audio }

/// What a blank (placeholder) lane imports when tapped.
enum _AddKind { none, media, text, sticker, audio }

class _Lane {
  const _Lane(this.h, this.kind, this.clips,
      {this.addKind = _AddKind.none, this.name = ''});
  final double h;
  final _ClipKind kind;
  final List<_ClipSnapshot> clips;
  final _AddKind addKind;
  final String name;

  bool get isPlaceholder => addKind != _AddKind.none && clips.isEmpty;
}

// ----------------------------------------------------------------------------
// Main Timeline Widget
// ----------------------------------------------------------------------------
class TimelineWidget extends StatefulWidget {
  const TimelineWidget({
    super.key,
    required this.editor,
    required this.multiOn,
    required this.multi,
    required this.onClearMulti,
    this.compact = false,
    this.snapEnabled = true,
    this.onAddText,
    this.onAddSticker,
  });

  final EditorController editor;
  final ValueNotifier<bool> multiOn;
  final ValueNotifier<Set<String>> multi;
  final VoidCallback onClearMulti;
  final bool compact;

  /// Snapping is always on in the CapCut-style layout (the toggle chip was
  /// removed). Pass false to disable it from outside.
  final bool snapEnabled;

  /// Called when the blank "Add text" / "Add sticker" lane is tapped. Hook
  /// these to the same actions your toolbar buttons use. "Add audio" and
  /// "Add media" open the media picker directly.
  final VoidCallback? onAddText;
  final VoidCallback? onAddSticker;

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  static const double _minClipW = 16;
  static const double _clipGap = 2; // visual gap between neighbouring clips

  /// Two main-track clips count as "touching" (a transition can sit between
  /// them) when the gap between them is below this many seconds.
  static const double _adjacentEps = 0.05;

  double _s = 1;
  double get _rulerH => 22 * _s;
  double get _rulerGap => 6 * _s;
  double get _gap => 6 * _s;
  // Overlay lanes are shorter than the main clip lane.
  double get _textH => 24 * _s;
  double get _videoH => 44 * _s;
  double get _audioH => 26 * _s;

  final ScrollController _sc = ScrollController();
  final ScrollController _vc = ScrollController();

  late _TimelineModel _model;

  bool _userScrolling = false;
  bool _programmatic = false; // true while WE call jumpTo
  double? _scrubTime;
  int _pointers = 0;
  double _baseZoom = 1;
  double? _lastSnap;

  EditorController get editor => widget.editor;

  @override
  void initState() {
    super.initState();
    _model = _TimelineModel.from(editor);
    editor.addListener(_onEditorChanged);
    editor.playheadListenable.addListener(_onPlayheadChanged);
  }

  @override
  void didUpdateWidget(covariant TimelineWidget old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_onEditorChanged);
      old.editor.playheadListenable.removeListener(_onPlayheadChanged);
      widget.editor.addListener(_onEditorChanged);
      widget.editor.playheadListenable.addListener(_onPlayheadChanged);
      _model = _TimelineModel.from(widget.editor);
      _syncScroll(force: true);
    }
  }

  @override
  void dispose() {
    editor.removeListener(_onEditorChanged);
    editor.playheadListenable.removeListener(_onPlayheadChanged);
    _sc.dispose();
    _vc.dispose();
    super.dispose();
  }

  /// Structural changes (clips, zoom, selection). Playback ticks do NOT come
  /// through here, so the snapshot is not rebuilt every frame while playing.
  void _onEditorChanged() {
    _refreshModel();
    _syncScroll();
  }

  void _onPlayheadChanged() => _syncScroll();

  void _refreshModel() {
    if (!mounted) return;
    final _TimelineModel next = _TimelineModel.from(editor);
    if (next == _model) return;
    // The controller may notify while the framework is building; defer then.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _model = _TimelineModel.from(editor));
      });
    } else {
      setState(() => _model = next);
    }
  }

  /// Tapping empty timeline space clears the current selection. In multi-select
  /// mode only the picked set is cleared; the mode itself stays on.
  void _deselectAll() {
    if (widget.multiOn.value) {
      widget.multi.value = <String>{};
    } else {
      editor.clearSelection();
    }
  }

  /// Programmatic jumps fire Start/Update/End scroll notifications. Flag them
  /// so they are never mistaken for the user scrubbing.
  void _jump(double target) {
    _programmatic = true;
    try {
      _sc.jumpTo(target);
    } finally {
      _programmatic = false;
    }
  }

  void _syncScroll({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      if (!force && (_userScrolling || _pointers >= 2)) return;
      final double pps = _basePps * editor.zoom;
      final double target = (secondsOf(editor.playhead) * pps)
          .clamp(0.0, _sc.position.maxScrollExtent)
          .toDouble();
      if ((_sc.offset - target).abs() > 0.5) _jump(target);
    });
  }

  // Only rebuild when the pinch state actually changes (1 -> 2 fingers and
  // back), not on every touch-down / touch-up.
  void _pointerDown() {
    _pointers++;
    if (_pointers == 2) setState(() {});
  }

  void _pointerUp() {
    final bool wasMulti = _pointers >= 2;
    _pointers = math.max(0, _pointers - 1);
    if (wasMulti && _pointers < 2) setState(() {});
  }

  bool _isOverlay(_ClipSnapshot c) => c.type != ClipType.audio && !c.isMain;

  bool _isStickerType(ClipType t) =>
      t == ClipType.sticker || t == ClipType.element;

  bool _isTextType(ClipType t) =>
      t != ClipType.audio &&
      t != ClipType.video &&
      t != ClipType.image &&
      t != ClipType.drawing &&
      !_isStickerType(t);

  /// Track name for an overlay lane, based on what it contains.
  String _overlayName(List<_ClipSnapshot> cs) {
    if (cs.isEmpty) return 'Text';
    final ClipType t = cs.first.type;
    if (t == ClipType.video || t == ClipType.image) return 'Overlay';
    if (t == ClipType.sticker || t == ClipType.element) return 'Sticker';
    if (t == ClipType.drawing) return 'Drawing';
    return 'Text';
  }

  List<_Lane> _lanes(List<_ClipSnapshot> clips) {
    final main = clips.where((c) => c.isMain).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final audio = clips.where((c) => c.type == ClipType.audio).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final layers =
        clips.where(_isOverlay).map<int>((c) => c.layer).toSet().toList()..sort();

    // Pack overlapping audio clips into separate rows so they never overdraw.
    final List<List<_ClipSnapshot>> audioRows = <List<_ClipSnapshot>>[];
    final List<int> rowEnds = <int>[];
    for (final c in audio) {
      final int r = rowEnds.indexWhere((e) => e <= c.startMs);
      if (r < 0) {
        rowEnds.add(c.endMs);
        audioRows.add(<_ClipSnapshot>[c]);
      } else {
        rowEnds[r] = c.endMs;
        audioRows[r].add(c);
      }
    }

    final List<List<_ClipSnapshot>> groups = <List<_ClipSnapshot>>[
      for (final l in layers.reversed)
        clips.where((c) => _isOverlay(c) && c.layer == l).toList(),
    ];
    final Map<String, int> totals = <String, int>{};
    for (final g in groups) {
      final String n = _overlayName(g);
      totals[n] = (totals[n] ?? 0) + 1;
    }
    final Map<String, int> seen = <String, int>{};
    final List<_Lane> overlayLanes = <_Lane>[];
    for (final g in groups) {
      final String base = _overlayName(g);
      final int n = (seen[base] ?? 0) + 1;
      seen[base] = n;
      final int total = totals[base]!;
      overlayLanes.add(_Lane(_textH, _ClipKind.text, g,
          name: total > 1 ? '$base ${total - n + 1}' : base));
    }

    // Blank lanes: a kind that has no clips yet gets a tappable placeholder
    // lane instead of an add button. They are only offered once the main
    // track has something in it.
    final bool hasMain = main.isNotEmpty;
    final bool hasText = clips.any((c) => _isOverlay(c) && _isTextType(c.type));
    final bool hasSticker =
        clips.any((c) => _isOverlay(c) && _isStickerType(c.type));

    return <_Lane>[
      ...overlayLanes,
      if (hasMain && !hasText)
        _Lane(_textH, _ClipKind.text, const <_ClipSnapshot>[],
            addKind: _AddKind.text, name: 'Add text'),
      if (hasMain && !hasSticker)
        _Lane(_textH, _ClipKind.text, const <_ClipSnapshot>[],
            addKind: _AddKind.sticker, name: 'Add sticker'),
      _Lane(_videoH, _ClipKind.video, main,
          addKind: _AddKind.media, name: 'Video'),
      for (int i = 0; i < audioRows.length; i++)
        _Lane(_audioH, _ClipKind.audio, audioRows[i],
            name: audioRows.length > 1 ? 'Audio ${i + 1}' : 'Audio'),
      if (hasMain && audioRows.isEmpty)
        _Lane(_audioH, _ClipKind.audio, const <_ClipSnapshot>[],
            addKind: _AddKind.audio, name: 'Add audio'),
    ];
  }

  // ---- Snapping -----------------------------------------------------------
  bool get _snapOn => widget.snapEnabled;

  double? _nearest(double t, double pps, List<_ClipSnapshot> clips, String? excludeId) {
    double? best;
    double bd = 8 / pps;
    void test(double e) {
      final double d = (e - t).abs();
      if (d < bd) {
        bd = d;
        best = e;
      }
    }

    test(secondsOf(editor.playhead));
    test(0.0);
    for (final c in clips) {
      if (c.id == excludeId) continue;
      test(c.startSec);
      test(c.endSec);
    }
    return best;
  }

  void _snapFeedback(double? target) {
    if (target != null && _lastSnap != target) tapFeedback();
    _lastSnap = target;
  }

  double _snapTime(double t, double pps, List<_ClipSnapshot> clips,
      {String? excludeId}) {
    if (!_snapOn) return t;
    final double? b = _nearest(t, pps, clips, excludeId);
    _snapFeedback(b);
    return b ?? t;
  }

  /// Snap a moving clip by either its start or its end edge.
  double _snapSpan(double start, double dur, double pps, List<_ClipSnapshot> clips,
      {String? excludeId}) {
    if (!_snapOn) return start;
    final double? a = _nearest(start, pps, clips, excludeId);
    final double? b = _nearest(start + dur, pps, clips, excludeId);
    double? res;
    if (a != null && (b == null || (a - start).abs() <= (b - (start + dur)).abs())) {
      res = a;
    } else if (b != null) {
      res = b - dur;
    }
    _snapFeedback(res);
    return res ?? start;
  }

  double _constrainMove(_ClipSnapshot clip, double desired, double pps,
      List<_ClipSnapshot> mainClips) {
    double s = _snapSpan(desired, clip.durSec, pps, mainClips, excludeId: clip.id);
    final List<double> b = _neighbors(clip, mainClips);
    final double lo = b[0];
    final double hi = b[1];
    final double maxS = math.max(lo, hi - clip.durSec);
    if (s < lo) s = lo;
    if (s > maxS) s = maxS;
    return s;
  }

  /// [lo, hi] free space around [clip] among non-overlapping neighbours.
  List<double> _neighbors(_ClipSnapshot clip, List<_ClipSnapshot> list) {
    double lo = 0;
    double hi = double.infinity;
    for (final c in list) {
      if (c.id == clip.id) continue;
      if (c.endSec <= clip.startSec + 1e-6) lo = math.max(lo, c.endSec);
      if (c.startSec >= clip.endSec - 1e-6) hi = math.min(hi, c.startSec);
    }
    return <double>[lo, hi];
  }

  void _setZoom(double z) => editor.setZoom(z.clamp(_minZoom, _maxZoom).toDouble());

  /// The playhead is fixed on screen, so zoom always anchors on it and the
  /// scroll offset is re-derived from the playhead after the new layout.
  /// Zoom is pinch-only now (the slider was removed).
  void _applyZoom(double newZoom) {
    _setZoom(newZoom);
    _syncScroll(force: true);
  }

  _ClipSnapshot? _clipAt(double t, List<_ClipSnapshot> clips) {
    for (final c in clips) {
      if (c.isMain && t >= c.startSec && t <= c.endSec) return c;
    }
    return null;
  }

  Widget _scrubCard(double half, double width, List<_ClipSnapshot> clips) {
    final double t = _scrubTime ?? 0;
    final _ClipSnapshot? clip = _clipAt(t, clips);
    final String? path = clip?.path;
    Widget thumb;
    if (clip != null && path != null && isImagePath(path)) {
      thumb = Image.file(File(path),
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, __, ___) => const _Stripes());
    } else if (clip != null && path != null && thumbGenerator != null) {
      // Quantise to 100 ms so scrubbing re-uses cached thumbnails instead of
      // asking the generator for a new frame on every pixel of movement.
      final int rawMs = ((t - clip.startSec).clamp(0.0, clip.durSec) * 1000).round();
      final int localMs = (rawMs ~/ 100) * 100;
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
      top: -78,
      child: IgnorePointer(
        child: Container(
          width: w,
          decoration: BoxDecoration(
            color: surfaceToken,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: SizedBox(height: 46, width: w, child: thumb),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(_tcFrames(t),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
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
    _s = scaleOf(size) * (widget.compact ? 0.85 : 1.0);
    final _TimelineModel model = _model;

    // A timeline always runs left-to-right, even in RTL locales, and its fixed
    // pixel sizes must not grow with the system font scale.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery.withNoTextScaling(
        child: ColoredBox(
          color: _timelineBg,
          child: LayoutBuilder(
            builder: (context, c) {
              final double half = c.maxWidth * playheadFracToken;
              final double total = math.max(model.totalMs / 1000.0, 1.0);
              final double pps = _basePps * model.zoom;
              final List<_Lane> lanes = _lanes(model.clips);
              final double contentH = _rulerH +
                  _rulerGap +
                  lanes.fold<double>(0, (s, l) => s + l.h + _gap) +
                  10 * _s;
              final double h =
                  c.maxHeight.isFinite ? c.maxHeight : math.min(contentH, 240.0 * _s);
              final double contentW = total * pps + c.maxWidth;

              return SizedBox(
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Listener(
                      onPointerDown: (_) => _pointerDown(),
                      onPointerUp: (_) => _pointerUp(),
                      onPointerCancel: (_) => _pointerUp(),
                      child: GestureDetector(
                        onScaleStart: (_) => _baseZoom = editor.zoom,
                        onScaleUpdate: (d) {
                          if (d.pointerCount >= 2) _applyZoom(_baseZoom * d.scale);
                        },
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (_programmatic) return false;
                            if (n.metrics.axis != Axis.horizontal) return false;
                            if (n is ScrollStartNotification && n.dragDetails != null) {
                              _userScrolling = true;
                              setState(() => _scrubTime = n.metrics.pixels / pps);
                            } else if (n is ScrollUpdateNotification && _userScrolling) {
                              final double t =
                                  _snapTime(n.metrics.pixels / pps, pps, model.clips);
                              setState(() => _scrubTime = t);
                              seekPlayhead(editor, t);
                            } else if (n is ScrollEndNotification && _userScrolling) {
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
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _deselectAll,
                                  child: SizedBox(
                                    height: math.max(contentH, h),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTapDown: (d) {
                                            widget.onClearMulti();
                                            seekPlayhead(
                                                editor,
                                                ((d.localPosition.dx - half) / pps)
                                                    .clamp(0.0, total)
                                                    .toDouble());
                                          },
                                          child: SizedBox(
                                            height: _rulerH,
                                            width: contentW,
                                            child: CustomPaint(
                                              painter: _RulerPainter(
                                                pps: pps,
                                                leftPad: half,
                                                totalSec: total,
                                                scroll: _sc,
                                                viewW: c.maxWidth,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: _rulerGap),
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
                    ),
                    // Playhead: a thin 1px white line, no head, fixed on screen.
                    Positioned(
                      left: half - 0.5,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      child: const IgnorePointer(
                        child: ColoredBox(color: playheadBlue),
                      ),
                    ),
                    if (_userScrolling && _scrubTime != null)
                      _scrubCard(half, c.maxWidth, model.clips),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Opens the media picker and adds the returned file to the timeline,
  /// exactly like the toolbar's add-media action.
  Future<void> _pickAndAddMedia() async {
    final NavigatorState nav = Navigator.of(context);
    final Object? result = await nav.pushNamed('/media_picker');
    if (!mounted) return;
    if (result is String) editor.addMediaClip(result);
  }

  void _onAdd(_AddKind kind) {
    tapFeedback();
    switch (kind) {
      case _AddKind.media:
      case _AddKind.audio:
        _pickAndAddMedia();
        break;
      case _AddKind.text:
        widget.onAddText?.call();
        break;
      case _AddKind.sticker:
        widget.onAddSticker?.call();
        break;
      case _AddKind.none:
        break;
    }
  }

  IconData _addIcon(_AddKind k) {
    switch (k) {
      case _AddKind.text:
        return Icons.title_rounded;
      case _AddKind.sticker:
        return Icons.emoji_emotions_rounded;
      case _AddKind.audio:
        return Icons.music_note_rounded;
      case _AddKind.media:
      case _AddKind.none:
        return Icons.video_library_rounded;
    }
  }

  String _addLabel(_AddKind k) {
    switch (k) {
      case _AddKind.text:
        return 'Add text';
      case _AddKind.sticker:
        return 'Add sticker';
      case _AddKind.audio:
        return 'Add audio';
      case _AddKind.media:
      case _AddKind.none:
        return 'Add media';
    }
  }

  /// Blank lane. It starts at 0:00 and runs to the end of the project, so it
  /// scrolls with the timeline instead of staying fixed on screen. Tapping it
  /// imports straight away.
  Widget _placeholder(_Lane l, double pps, double half, double total) {
    return Positioned(
      left: half,
      top: 0,
      bottom: 0,
      width: math.max(total * pps - _clipGap, 60),
      child: Semantics(
        button: true,
        label: _addLabel(l.addKind),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onAdd(l.addKind),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _emptyLaneColor,
              borderRadius: BorderRadius.circular(_clipRadius),
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(_addIcon(l.addKind), size: 13, color: const Color(0xFF8A8A8A)),
                const SizedBox(width: 6),
                Text(
                  _addLabel(l.addKind),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lane(_Lane l, double contentW, double pps, double half, _TimelineModel m) {
    final List<_ClipSnapshot> list = l.clips;
    final bool isVideo = l.kind == _ClipKind.video;
    final double total = math.max(m.totalMs / 1000.0, 1.0);
    return Padding(
      padding: EdgeInsets.only(bottom: _gap),
      child: SizedBox(
        height: l.h,
        width: contentW,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            if (l.isPlaceholder)
              _placeholder(l, pps, half, total)
            else
              for (int i = 0; i < list.length; i++)
                _buildClip(l, list, i, pps, half, m, isVideo),
            // Transitions rendered on top of all clips
            if (isVideo)
              for (int i = 0; i < list.length - 1; i++)
                if ((list[i + 1].startSec - list[i].endSec).abs() <= _adjacentEps)
                  Positioned(
                    key: ValueKey<String>('tr_${list[i].id}'),
                    // Centred exactly on the cut between two clips.
                    left: half + list[i].endSec * pps - 10 * _s - _clipGap / 2,
                    top: l.h / 2 - 10 * _s,
                    child: Semantics(
                      button: true,
                      label: 'Edit transition',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          tapFeedback();
                          editor.selectClip(list[i].id);
                          showTransitionSheet(context);
                        },
                        child: Container(
                          width: 20 * _s,
                          height: 20 * _s,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                          child: Icon(Icons.join_inner_rounded,
                              size: 12 * _s, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildClip(_Lane l, List<_ClipSnapshot> list, int i, double pps,
      double half, _TimelineModel m, bool isVideo) {
    final _ClipSnapshot clip = list[i];
    final List<double> nb =
        isVideo ? _neighbors(clip, list) : const <double>[0.0, 86400.0];
    return Positioned(
      key: ValueKey<String>('clip_${clip.id}'),
      left: half + clip.startSec * pps,
      top: 0,
      bottom: 0,
      width: math.max(_minClipW, clip.durSec * pps - _clipGap),
      child: RepaintBoundary(
        child: _ClipBlock(
          editor: widget.editor,
          clip: clip,
          kind: l.kind,
          pps: pps,
          selected: m.selectedId == clip.id,
          multiOn: widget.multiOn,
          multi: widget.multi,
          trimLo: nb[0],
          trimHi: nb[1],
          trimSnap: (t) => _snapTime(t, pps, m.clips, excludeId: clip.id),
          moveClamp: isVideo
              ? (desired) => _constrainMove(clip, desired, pps, list)
              : (desired) => math.max(
                  0.0,
                  _snapSpan(desired, clip.durSec, pps, m.clips, excludeId: clip.id)),
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
    required this.trimSnap,
    required this.trimLo,
    required this.trimHi,
  });
  final EditorController editor;
  final _ClipSnapshot clip;
  final _ClipKind kind;
  final double pps;
  final bool selected;
  final ValueNotifier<bool> multiOn;
  final ValueNotifier<Set<String>> multi;
  final double Function(double desiredStart) moveClamp;
  final double Function(double t) trimSnap;
  final double trimLo;
  final double trimHi;

  @override
  State<_ClipBlock> createState() => _ClipBlockState();
}

class _ClipBlockState extends State<_ClipBlock> {
  double _originStart = 0;
  double _rawEdge = 0; // un-snapped edge accumulated during a trim drag
  double _kfRawMs = 0; // un-rounded keyframe time accumulated during a drag

  void _startMove() {
    widget.editor.selectClip(widget.clip.id);
    _originStart = widget.clip.startSec;
  }

  void _updateMove(double deltaX) {
    final double s = widget.moveClamp(_originStart + deltaX / widget.pps);
    widget.editor.trimSelectedClip(
      Duration(milliseconds: (s * 1000).round()),
      Duration(milliseconds: ((s + widget.clip.durSec) * 1000).round()),
    );
  }

  // ---- Colours ------------------------------------------------------------
  Color _clipColor(_ClipSnapshot c) {
    switch (c.type) {
      case ClipType.audio:
        return audioTrackToken;
      case ClipType.video:
      case ClipType.image:
        return _overlayMediaColor; // overlay media (main track uses filmstrip)
      case ClipType.sticker:
      case ClipType.element:
        return fxTrackToken;
      case ClipType.drawing:
        return drawTrackToken;
      default:
        return textTrackToken;
    }
  }

  /// Selection border is a foreground decoration, so it never changes the
  /// clip's size or shifts the content inside it. White = the selected clip,
  /// dimmer white = a clip picked in multi-select mode.
  Widget _frame(Widget child, {Color? color, required bool inMulti}) {
    final Color border = widget.selected
        ? Colors.white
        : (inMulti ? Colors.white54 : Colors.transparent);
    final BorderRadius radius = BorderRadius.circular(_clipRadius);
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  /// Handle width shrinks on very short clips (down to 8px) so the clip body
  /// always keeps a tappable / long-pressable middle.
  Widget _trimHandle({required bool left, required double clipW}) {
    final double hw = (clipW / 3).clamp(8.0, 20.0).toDouble();
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: hw,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _rawEdge = left ? widget.clip.startSec : widget.clip.endSec;
        },
        onHorizontalDragUpdate: (d) {
          _rawEdge += d.delta.dx / widget.pps;
          final clip = widget.clip;
          final double snapped = widget.trimSnap(_rawEdge);
          if (left) {
            final double hiLimit = math.max(widget.trimLo, clip.endSec - 0.2);
            final double newStart =
                snapped.clamp(widget.trimLo, hiLimit).toDouble();
            widget.editor.trimSelectedClip(
              Duration(milliseconds: (newStart * 1000).round()),
              Duration(milliseconds: (clip.endSec * 1000).round()),
            );
          } else {
            final double loLimit = clip.startSec + 0.2;
            final double newEnd =
                snapped.clamp(loLimit, math.max(loLimit, widget.trimHi)).toDouble();
            widget.editor.trimSelectedClip(
              Duration(milliseconds: (clip.startSec * 1000).round()),
              Duration(milliseconds: (newEnd * 1000).round()),
            );
          }
        },
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: _Handle(width: math.min(10.0, hw)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(double clipW, bool inMulti) {
    final clip = widget.clip;
    Widget body;

    switch (widget.kind) {
      case _ClipKind.text:
        final bool overlayMedia =
            clip.type == ClipType.video || clip.type == ClipType.image;
        final bool sticker =
            clip.type == ClipType.sticker || clip.type == ClipType.element;
        final bool drawing = clip.type == ClipType.drawing;
        final IconData icon = overlayMedia
            ? (clip.type == ClipType.video
                ? Icons.video_library_rounded
                : PhosphorIconsRegular.image)
            : (drawing
                ? Icons.brush_rounded
                : (sticker ? Icons.emoji_emotions_rounded : Icons.title_rounded));
        // Selected clips leave room for the trim handles.
        final double pad = widget.selected ? 16.0 : 8.0;
        final double inner = clipW - 2 * pad;
        final bool showIcon = inner >= 14;
        final bool showLabel = inner >= 12 + 5 + 30;
        final bool showLock = clip.locked && inner >= 12 + 5 + 30 + 16;
        body = _frame(
          showIcon
              ? ClipRect(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(icon, size: 12, color: Colors.white),
                          if (showLabel) ...<Widget>[
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                clip.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11, height: 1.1),
                              ),
                            ),
                          ],
                          if (showLock)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.lock_rounded, size: 11, color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.expand(),
          color: _clipColor(clip),
          inMulti: inMulti,
        );
      case _ClipKind.video:
        body = _frame(
          Stack(
            fit: StackFit.expand,
            children: <Widget>[
              LayoutBuilder(
                builder: (context, c) => clip.path != null
                    ? _Filmstrip(
                        key: ValueKey<String>(
                            '${clip.id}|${widget.pps.toStringAsFixed(2)}'),
                        path: clip.path!,
                        durationSec: clip.durSec,
                        width: c.maxWidth,
                      )
                    : const _Stripes(),
              ),
              // Hidden on very short clips where it would cover the thumbnails.
              if (clipW >= 76)
                Positioned(
                  left: 6,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                        color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                    child: Text('${clip.durSec.toStringAsFixed(1)}s',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              if (clip.locked)
                const Positioned(
                  right: 6,
                  bottom: 3,
                  child: Icon(Icons.lock_rounded, size: 11, color: Colors.white70),
                ),
            ],
          ),
          inMulti: inMulti,
        );
      case _ClipKind.audio:
        body = _frame(
          clip.path != null
              ? _WaveformLoader(path: clip.path!)
              : const SizedBox.expand(),
          color: _clipColor(clip),
          inMulti: inMulti,
        );
    }

    if (widget.selected && !clip.locked && !widget.multiOn.value) {
      body = Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          _trimHandle(left: true, clipW: clipW),
          _trimHandle(left: false, clipW: clipW),
        ],
      );
    }
    return body;
  }

  // ---- Keyframes ----------------------------------------------------------
  void _moveKeyframe(String id, int ms) {
    for (final c in widget.editor.project.clips) {
      if (c.id != widget.clip.id) continue;
      for (final k in c.keyframes) {
        if (k.id == id) {
          widget.editor.addKeyframe(k.copyWith(time: Duration(milliseconds: ms)));
          return;
        }
      }
    }
  }

  Widget _buildKeyframeOverlay(_ClipSnapshot clip, double clipW) {
    if (clip.keyframes.isEmpty) return const SizedBox.shrink();
    const double hit = 24;
    final int durMs = clip.endMs - clip.startMs;
    final bool canEdit = !clip.locked && !widget.multiOn.value;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final kf in clip.keyframes)
            if (kf.ms >= 0 && kf.ms <= durMs)
              Positioned(
                key: ValueKey<String>('kf_${kf.id}'),
                left: ((kf.ms / 1000.0) * widget.pps)
                        .clamp(12.0, math.max(12.0, clipW - 12.0))
                        .toDouble() -
                    hit / 2,
                bottom: 0,
                width: hit,
                height: hit,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    tapFeedback();
                    seekPlayhead(widget.editor, (clip.startMs + kf.ms) / 1000.0);
                  },
                  onLongPress: canEdit
                      ? () {
                          tapFeedback();
                          widget.editor.removeKeyframe(kf.id);
                        }
                      : null,
                  onHorizontalDragStart:
                      canEdit ? (_) => _kfRawMs = kf.ms.toDouble() : null,
                  onHorizontalDragUpdate: canEdit
                      ? (d) {
                          _kfRawMs += d.delta.dx / widget.pps * 1000.0;
                          _moveKeyframe(
                              kf.id, _kfRawMs.round().clamp(0, durMs).toInt());
                        }
                      : null,
                  child: Center(
                    child: Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 1.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
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
        // Long-press works on any unlocked clip (it selects it first), not
        // only on the already-selected one.
        final bool canMove = !locked && !multiActive;

        return Semantics(
          button: true,
          selected: widget.selected || inMulti,
          label: '${_kindName(clip.type)} clip ${clip.label}, '
              '${clip.durSec.toStringAsFixed(1)} seconds'
              '${locked ? ', locked' : ''}',
          child: GestureDetector(
            onTap: () {
              tapFeedback();
              if (multiActive) {
                final Set<String> next = Set<String>.of(widget.multi.value);
                if (!next.remove(clip.id)) next.add(clip.id);
                widget.multi.value = next;
              } else {
                widget.editor.selectClip(clip.id);
              }
            },
            onLongPressStart: canMove
                ? (_) {
                    tapFeedback();
                    _startMove();
                  }
                : null,
            onLongPressMoveUpdate:
                canMove ? (d) => _updateMove(d.offsetFromOrigin.dx) : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: clip.visible ? 1 : 0.35,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(
                        children: <Widget>[
                          _buildBody(c.maxWidth, inMulti),
                          _buildKeyframeOverlay(clip, c.maxWidth),
                        ],
                      ),
                    ),
                  ),
                  if (inMulti)
                    const Positioned(
                      top: 3,
                      left: 5,
                      child: Icon(Icons.check_circle_rounded,
                          size: 13, color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({this.width = 10});
  final double width;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
        child: const Center(
          child: SizedBox(width: 2, height: 8, child: ColoredBox(color: Colors.black)),
        ),
      );
}

// ----------------------------------------------------------------------------
// Filmstrip thumbnails & Waveform Loader
// ----------------------------------------------------------------------------
class _Stripes extends StatelessWidget {
  const _Stripes();
  @override
  Widget build(BuildContext context) => const CustomPaint(
        painter: _FilmPainter(),
        child: SizedBox.expand(),
      );
}

class _Filmstrip extends StatefulWidget {
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
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  List<Future<Uint8List?>> _futures = const <Future<Uint8List?>>[];
  int _n = 1;

  // One thumbnail per ~44px, matching the shorter 44px main clip.
  int _count(double w) => (w / 44).ceil().clamp(1, 24).toInt();

  bool get _isImage => isImagePath(widget.path);

  void _load() {
    _n = _count(widget.width);
    if (_isImage || thumbGenerator == null) {
      _futures = const <Future<Uint8List?>>[];
      return;
    }
    final double step = widget.durationSec / _n;
    _futures = <Future<Uint8List?>>[
      for (int i = 0; i < _n; i++) ThumbCache.get(widget.path, (i * step * 1000).round(), 96),
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _Filmstrip old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.durationSec != widget.durationSec ||
        _count(widget.width) != _n) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Expanded cells always add up to exactly the available width, so float
    // rounding can never trigger a RenderFlex overflow.
    return ClipRect(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < _n; i++)
            Expanded(
              child: _isImage
                  ? Image.file(File(widget.path),
                      fit: BoxFit.cover,
                      cacheWidth: 96,
                      errorBuilder: (_, __, ___) => const _Stripes())
                  : (_futures.isEmpty
                      ? const _Stripes()
                      : FutureBuilder<Uint8List?>(
                          future: _futures[i],
                          builder: (_, s) {
                            final Uint8List? b = s.data;
                            if (b == null) return const _Stripes();
                            return Image.memory(b,
                                fit: BoxFit.cover, gaplessPlayback: true);
                          },
                        )),
            ),
        ],
      ),
    );
  }
}

class _FilmPainter extends CustomPainter {
  const _FilmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2A2A2A));
    final double fw = math.max(14, size.height * 0.85);
    int i = 0;
    for (double x = 0; x < size.width; x += fw) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, fw - 1, size.height),
        Paint()..color = (i++ % 2 == 0) ? const Color(0xFF383838) : const Color(0xFF424242),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FilmPainter old) => false;
}

class _WaveformLoader extends StatefulWidget {
  const _WaveformLoader({required this.path});
  final String path;

  @override
  State<_WaveformLoader> createState() => _WaveformLoaderState();
}

class _WaveformLoaderState extends State<_WaveformLoader> {
  Future<List<double>>? _future;
  String? _path;
  int _bars = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Bar count is bucketed (multiples of 32) and capped. Before, every
        // pixel of zoom re-ran the waveform job and wide clips asked for
        // thousands of bars.
        final int raw = (c.maxWidth / 4).floor();
        final int bars = ((raw / 32).ceil() * 32).clamp(32, 1200).toInt();
        if (_future == null || _path != widget.path || _bars != bars) {
          _path = widget.path;
          _bars = bars;
          _future = waveFuture(widget.path, bars);
        }
        return FutureBuilder<List<double>>(
          future: _future,
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
    if (amps.isEmpty) return;
    final Paint p = Paint()
      ..color = const Color(0xFFCFCFCF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final double gap = size.width / amps.length;
    for (int i = 0; i < amps.length; i++) {
      final double x = gap * (i + 0.5);
      final double h = math.max(2.0, amps[i].clamp(0.0, 1.0) * (size.height - 8));
      canvas.drawLine(
          Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => !_listEq(old.amps, amps);
}

// ----------------------------------------------------------------------------
// Ruler
// ----------------------------------------------------------------------------

/// CapCut-style ruler: labels (00:00, 1s, 2s ...) with small dots between
/// them, no tick lines and no border. Only the mark nearest the playhead is
/// white; everything else is dimmed.
///
/// Paints only the part of the ruler that is on screen. The canvas is as wide
/// as the whole timeline, so it repaints on scroll and draws just the visible
/// window. The scroll offset equals playhead * pps, so the highlighted mark
/// follows the playhead without any extra listener.
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pps,
    required this.leftPad,
    required this.totalSec,
    required this.scroll,
    required this.viewW,
  }) : super(repaint: scroll);

  final double pps;
  final double leftPad;
  final double totalSec;
  final ScrollController scroll;
  final double viewW;

  static const Color _on = Color(0xFFFFFFFF);
  static const Color _labelDim = Color(0xFF505050);
  static const Color _dotDim = Color(0xFF303030);
  static const Color _labelPast = Color(0xFF3A3A3A);
  static const Color _dotPast = Color(0xFF242424);

  // Frame steps first, then seconds / minutes.
  static const List<double> _steps = <double>[
    1 / 30, 2 / 30, 5 / 30, 10 / 30, 15 / 30,
    1, 2, 5, 10, 15, 30, 60, 120, 300, 600,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double off = scroll.hasClients ? scroll.offset : 0.0;
    final double x0 = math.max(0.0, off - 40);
    final double x1 = math.min(size.width, off + viewW + 40);
    if (x1 <= x0) return;
    final double h = size.height;

    // Pick a major step so labels are at least ~44px apart.
    final double major =
        _steps.firstWhere((s) => s * pps >= 44, orElse: () => _steps.last);
    // One dot between labels when tight, three when there is room.
    final int div = major * pps >= 90 ? 4 : 2;
    final double minor = major / div;

    final int near = ((off / pps) / minor).round();
    final int first = math.max(0, ((x0 - leftPad) / pps / minor).floor() - 1);

    for (int i = first;; i++) {
      final double t = i * minor;
      final double x = leftPad + t * pps;
      if (x > x1) break;
      if (x < x0) continue;

      final bool on = i == near;
      final bool past = t > totalSec + 1e-6;

      if (i % div == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: _rulerLabel(t),
            style: TextStyle(
              color: on ? _on : (past ? _labelPast : _labelDim),
              fontSize: 10,
              height: 1.0,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, (h - tp.height) / 2));
        tp.dispose();
      } else {
        canvas.drawCircle(
          Offset(x, h / 2),
          1.0,
          Paint()..color = on ? _on : (past ? _dotPast : _dotDim),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps ||
      old.leftPad != leftPad ||
      old.totalSec != totalSec ||
      old.viewW != viewW ||
      old.scroll != scroll;
}