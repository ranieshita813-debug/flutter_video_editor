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
const double _clipRadius = 6;
const int _fps = 30;

/// Pixels per second at zoom 1.0.
const double _basePps = 28.0;
const double _minZoom = 0.5;
const double _maxZoom = 12.0;

/// HH:MM:SS:FF timecode (Premiere style).
String _tcFrames(double t) {
  final int f = (math.max(0.0, t) * _fps).round();
  final int s = f ~/ _fps;
  return '${twoDigits(s ~/ 3600)}:${twoDigits((s ~/ 60) % 60)}:'
      '${twoDigits(s % 60)}:${twoDigits(f % _fps)}';
}

/// Zoom is multiplicative, so the slider is logarithmic: every slider step
/// changes the zoom by the same factor instead of feeling dead at the low end.
double _zoomToSlider(double z) =>
    math.log(z.clamp(_minZoom, _maxZoom) / _minZoom) /
    math.log(_maxZoom / _minZoom);

double _sliderToZoom(double v) =>
    _minZoom * math.pow(_maxZoom / _minZoom, v.clamp(0.0, 1.0));

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

class _Lane {
  const _Lane(this.h, this.kind, this.clips, {this.add = false, this.name = ''});
  final double h;
  final _ClipKind kind;
  final List<_ClipSnapshot> clips;
  final bool add;
  final String name;
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
  });

  final EditorController editor;
  final ValueNotifier<bool> multiOn;
  final ValueNotifier<Set<String>> multi;
  final VoidCallback onClearMulti;
  final bool compact;

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  static const double _gap = 14;
  static const double _minClipW = 20;
  static const double _clipGap = 2; // visual gap between neighbouring clips

  /// Two main-track clips count as "touching" (a transition can sit between
  /// them) when the gap between them is below this many seconds.
  static const double _adjacentEps = 0.05;

  double _s = 1;
  double get _rulerH => 30 * _s;
  double get _textH => 38 * _s;
  double get _videoH => 52 * _s;
  double get _audioH => 44 * _s;
  double get _topH => 30 * _s;
  double get _botH => 28 * _s;

  final ScrollController _sc = ScrollController();
  final ScrollController _vc = ScrollController();
  final ValueNotifier<bool> _snap = ValueNotifier<bool>(true);

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
    _snap.dispose();
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

    return <_Lane>[
      ...overlayLanes,
      _Lane(_videoH, _ClipKind.video, main, add: true, name: 'Video'),
      for (int i = 0; i < audioRows.length; i++)
        _Lane(_audioH, _ClipKind.audio, audioRows[i],
            name: audioRows.length > 1 ? 'Audio ${i + 1}' : 'Audio'),
    ];
  }

  // ---- Snapping -----------------------------------------------------------
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
    if (!_snap.value) return t;
    final double? b = _nearest(t, pps, clips, excludeId);
    _snapFeedback(b);
    return b ?? t;
  }

  /// Snap a moving clip by either its start or its end edge.
  double _snapSpan(double start, double dur, double pps, List<_ClipSnapshot> clips,
      {String? excludeId}) {
    if (!_snap.value) return start;
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

  /// Snap toggle. The visible chip is small, but the tap target is 48 wide and
  /// as tall as the whole top row.
  Widget _snapChip(bool on) => Semantics(
        button: true,
        toggled: on,
        label: 'Snap to clips',
        excludeSemantics: true,
        child: Tooltip(
          message: 'Snap',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapFeedback();
              _snap.value = !_snap.value;
            },
            child: SizedBox(
              width: 48,
              height: _topH,
              child: Center(
                child: Container(
                  width: 34 * _s,
                  height: 22 * _s,
                  decoration: BoxDecoration(
                    color: on ? Colors.white : const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(11 * _s),
                  ),
                  child: Icon(Icons.align_horizontal_center_rounded,
                      size: 15 * _s, color: on ? Colors.black : Colors.white),
                ),
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
      top: -92,
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
                child: SizedBox(height: 56, width: w, child: thumb),
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

  Widget _topRow() => SizedBox(
        height: _topH,
        child: Padding(
          padding: EdgeInsets.only(left: 14 * _s, right: 6 * _s),
          child: Row(
            children: <Widget>[
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: _snap,
                builder: (_, snap, __) => _snapChip(snap),
              ),
            ],
          ),
        ),
      );

  Widget _zoomBar(double zoom) => SizedBox(
        height: _botH,
        child: Padding(
          // Keeps the thumb fully inside the bar at both ends.
          padding: EdgeInsets.symmetric(horizontal: 12 * _s),
          child: Row(
            children: <Widget>[
              Icon(Icons.zoom_out_rounded, size: 15 * _s, color: Colors.white38),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: const Color(0xFF555555),
                      inactiveTrackColor: const Color(0xFF222222),
                      thumbColor: const Color(0xFFBDBDBD),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: SliderComponentShape.noOverlay,
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      value: _zoomToSlider(zoom),
                      semanticFormatterCallback: (v) =>
                          'Timeline zoom ${_sliderToZoom(v).toStringAsFixed(1)} times',
                      onChanged: (v) => _applyZoom(_sliderToZoom(v)),
                    ),
                  ),
                ),
              ),
              Icon(Icons.zoom_in_rounded, size: 15 * _s, color: Colors.white38),
            ],
          ),
        ),
      );

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
              final double chrome = _topH + _botH;
              final double contentH =
                  _rulerH + lanes.fold<double>(0, (s, l) => s + l.h + _gap) + 16 * _s;
              final double h = c.maxHeight.isFinite
                  ? c.maxHeight
                  : math.min(contentH + chrome, 240.0 * _s);
              final double midH = math.max(0.0, h - chrome);
              final double contentW = total * pps + c.maxWidth;

              return SizedBox(
                height: h,
                child: Column(
                  children: <Widget>[
                    _topRow(),
                    SizedBox(
                      height: midH,
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
                                          height: math.max(contentH, midH),
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
                                              SizedBox(height: 10 * _s),
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
                          // Playhead: white rounded head + hairline, fixed on screen.
                          Positioned(
                            left: half - 8,
                            top: 0,
                            bottom: 0,
                            width: 16,
                            child: const IgnorePointer(
                              child: CustomPaint(painter: _PlayheadPainter()),
                            ),
                          ),
                          if (_userScrolling && _scrubTime != null)
                            _scrubCard(half, c.maxWidth, model.clips),
                        ],
                      ),
                    ),
                    _zoomBar(model.zoom),
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

  Widget _addButton(double left, double h) => Positioned(
        left: left,
        top: h / 2 - 15 * _s,
        child: Semantics(
          button: true,
          label: 'Add media',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapFeedback();
              _pickAndAddMedia();
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
    final List<_ClipSnapshot> list = l.clips;
    final bool isVideo = l.kind == _ClipKind.video;
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: SizedBox(
        height: l.h,
        width: contentW,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (int i = 0; i < list.length; i++) ...<Widget>[
              _buildClip(l, list, i, pps, half, m, isVideo),
              // A transition only makes sense between clips that touch.
              if (isVideo &&
                  i < list.length - 1 &&
                  (list[i + 1].startSec - list[i].endSec).abs() <= _adjacentEps)
                Positioned(
                  key: ValueKey<String>('tr_${list[i].id}'),
                  // Centred exactly on the cut between two clips.
                  left: half + list[i].endSec * pps - 12 * _s - _clipGap / 2,
                  top: l.h / 2 - 12 * _s,
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
                        width: 24 * _s,
                        height: 24 * _s,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: Icon(Icons.join_inner_rounded,
                            size: 14 * _s, color: Colors.black),
                      ),
                    ),
                  ),
                ),
            ],
            if (l.add)
              _addButton(half + (list.isEmpty ? 0 : list.last.endSec * pps) + 16 * _s, l.h),
            if (l.add && list.isEmpty)
              Positioned(
                left: half + 16 * _s + 30 * _s + 10 * _s,
                top: 0,
                bottom: 0,
                child: const IgnorePointer(
                  child: Center(
                    child: Text('Add media to start',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
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
    // Computed once per clip (it was computed twice before).
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
        border: Border.all(color: border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  /// Handle width shrinks on very short clips (down to 8px) so the clip body
  /// always keeps a tappable / long-pressable middle.
  Widget _trimHandle({required bool left, required double clipW}) {
    final double hw = (clipW / 3).clamp(8.0, 24.0).toDouble();
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
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _Handle(width: math.min(12.0, hw)),
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
                : Icons.image_rounded)
            : (drawing
                ? Icons.brush_rounded
                : (sticker ? Icons.emoji_emotions_rounded : Icons.title_rounded));
        // Selected clips leave room for the trim handles.
        final double pad = widget.selected ? 16.0 : 10.0;
        final double inner = clipW - 2 * pad;
        final bool showIcon = inner >= 15;
        final bool showLabel = inner >= 15 + 6 + 30;
        final bool showLock = clip.locked && inner >= 15 + 6 + 30 + 16;
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
                          Icon(icon, size: 14, color: Colors.white),
                          if (showLabel) ...<Widget>[
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                clip.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.1),
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
                  right: 6,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text('${clip.durSec.toStringAsFixed(1)}s',
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              if (clip.locked)
                const Positioned(
                  left: 6,
                  bottom: 4,
                  child: Icon(Icons.lock_rounded, size: 12, color: Colors.white70),
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
                        width: 10,
                        height: 10,
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
        // Long-press now works on any unlocked clip (it selects it first), not
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
                      top: 4,
                      left: 6,
                      child: Icon(Icons.check_circle_rounded,
                          size: 14, color: Colors.white),
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
  const _Handle({this.width = 12});
  final double width;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
        child: const Center(
          child: SizedBox(width: 2, height: 10, child: ColoredBox(color: Colors.black)),
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

  int _count(double w) => (w / 48).ceil().clamp(1, 24).toInt();

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
        final int raw = (c.maxWidth / 5).floor();
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
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double gap = size.width / amps.length;
    for (int i = 0; i < amps.length; i++) {
      final double x = gap * (i + 0.5);
      final double h = math.max(3.0, amps[i].clamp(0.0, 1.0) * (size.height - 8));
      canvas.drawLine(
          Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => !_listEq(old.amps, amps);
}

// ----------------------------------------------------------------------------
// Ruler & playhead
// ----------------------------------------------------------------------------

/// Paints only the part of the ruler that is on screen. The canvas is as wide
/// as the whole timeline (tens of thousands of px for long projects), so
/// painting every tick and label made long projects slow; it now repaints on
/// scroll and draws just the visible window.
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

  static const Color _bg = Color(0xFF0A0A0A);

  @override
  void paint(Canvas canvas, Size size) {
    final double off = scroll.hasClients ? scroll.offset : 0.0;
    // Extra margin on the left so a label that starts just off-screen but
    // reaches into view is still drawn.
    final double x0 = math.max(0.0, off - 100);
    final double x1 = math.min(size.width, off + viewW + 100);
    if (x1 <= x0) return;
    final double h = size.height;

    canvas.drawRect(Rect.fromLTRB(x0, 0, x1, h), Paint()..color = _bg);

    // Dim everything after the sequence end and mark it.
    final double endX = leftPad + totalSec * pps;
    if (endX < x1) {
      canvas.drawRect(Rect.fromLTRB(math.max(endX, x0), 0, x1, h),
          Paint()..color = Colors.white.withValues(alpha: 0.04));
    }
    if (endX >= x0 && endX <= x1) {
      canvas.drawLine(
          Offset(endX, 0),
          Offset(endX, h),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5)
            ..strokeWidth = 1);
    }

    // Pick a major step that keeps labels roughly 90px apart.
    const List<double> steps = <double>[
      1 / 30, 1 / 15, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600
    ];
    final double major = steps.firstWhere((s) => s * pps >= 90, orElse: () => steps.last);
    const int div = 4;
    final double minor = major / div;

    final Paint pMajor = Paint()
      ..color = const Color(0xFF8A8A8A)
      ..strokeWidth = 1;
    final Paint pMid = Paint()
      ..color = const Color(0xFF5E5E5E)
      ..strokeWidth = 1;
    final Paint pSmall = Paint()
      ..color = const Color(0xFF3E3E3E)
      ..strokeWidth = 1;

    final int first = math.max(0, ((x0 - leftPad) / pps / minor).floor());
    for (int i = first;; i++) {
      final double t = i * minor;
      final double x = leftPad + t * pps;
      if (x > x1) break;

      if (i % div == 0) {
        canvas.drawLine(Offset(x, h * 0.45), Offset(x, h), pMajor);
        final tp = TextPainter(
          text: TextSpan(
            text: _tcFrames(t),
            style: TextStyle(
              color: t > totalSec + 1e-6 ? Colors.white38 : const Color(0xFF9A9A9A),
              fontSize: 11,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, h * 0.10));
        tp.dispose();
      } else if (i % div == div ~/ 2) {
        canvas.drawLine(Offset(x, h * 0.68), Offset(x, h), pMid);
      } else {
        canvas.drawLine(Offset(x, h * 0.82), Offset(x, h), pSmall);
      }
    }

    canvas.drawLine(Offset(x0, h - 0.5), Offset(x1, h - 0.5),
        Paint()..color = const Color(0xFF1C1C1C));
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.pps != pps ||
      old.leftPad != leftPad ||
      old.totalSec != totalSec ||
      old.viewW != viewW ||
      old.scroll != scroll;
}

class _PlayheadPainter extends CustomPainter {
  const _PlayheadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = playheadBlue;
    final double w = size.width;
    // Rounded head, CapCut style.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, w, 12),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomLeft: const Radius.circular(8),
        bottomRight: const Radius.circular(8),
      ),
      p,
    );
    canvas.drawRect(Rect.fromLTWH(w / 2 - 1, 12, 2, size.height - 12), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}