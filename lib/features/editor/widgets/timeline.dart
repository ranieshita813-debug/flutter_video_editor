import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';

// ----------------------------------------------------------------------------
// Timeline Model & Snapshots
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
  static const double _minClipW = 48; // two 24px trim handles

  double _s = 1;
  double get _rulerH => 30 * _s;
  double get _textH => 40 * _s;
  double get _videoH => 52 * _s;
  double get _audioH => 44 * _s;
  double get _hdrW => 76 * _s;

  final ScrollController _sc = ScrollController();
  final ScrollController _vc = ScrollController();
  final ScrollController _hc = ScrollController();
  final ValueNotifier<bool> _snap = ValueNotifier<bool>(true);

  bool _userScrolling = false;
  bool _programmatic = false; // true while WE call jumpTo
  double? _scrubTime;
  int _pointers = 0;
  double _baseZoom = 1;
  double? _lastSnap;

  EditorController get editor => widget.editor;

  void _onEditorChanged() => _syncScroll();

  @override
  void initState() {
    super.initState();
    _vc.addListener(() {
      if (_hc.hasClients && (_hc.offset - _vc.offset).abs() > 0.5) {
        _hc.jumpTo(_vc.offset.clamp(0.0, _hc.position.maxScrollExtent).toDouble());
      }
    });
    editor.addListener(_onEditorChanged);
  }

  @override
  void didUpdateWidget(covariant TimelineWidget old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.removeListener(_onEditorChanged);
      widget.editor.addListener(_onEditorChanged);
    }
  }

  @override
  void dispose() {
    editor.removeListener(_onEditorChanged);
    _snap.dispose();
    _sc.dispose();
    _vc.dispose();
    _hc.dispose();
    super.dispose();
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
      final double pps = 28.0 * editor.zoom;
      final double target = (secondsOf(editor.playhead) * pps)
          .clamp(0.0, _sc.position.maxScrollExtent)
          .toDouble();
      if ((_sc.offset - target).abs() > 0.5) _jump(target);
    });
  }

  bool _isOverlay(_ClipSnapshot c) =>
      c.type != ClipType.audio && c.type != ClipType.video && c.type != ClipType.image;

  /// Track name for an overlay lane, based on what it contains.
  String _overlayName(List<_ClipSnapshot> cs) {
    if (cs.isEmpty) return 'Text';
    final ClipType t = cs.first.type;
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

    // Overlay lanes (top layer first), named Text / Sticker / Drawing and
    // numbered only when more than one lane shares the same name.
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

  void _setZoom(double z) => editor.setZoom(z.clamp(0.5, 8.0).toDouble());

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

  Widget _chip(IconData icon, String tip, bool on, VoidCallback onTap) => Semantics(
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
    if (clip != null && path != null && isImagePath(path)) {
      thumb = Image.file(File(path),
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, __, ___) => const _Stripes());
    } else if (clip != null && path != null && thumbGenerator != null) {
      final int localMs = ((t - clip.startSec).clamp(0.0, clip.durSec) * 1000).round();
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
            border: Border.all(color: dividerToken),
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
                child: Text(formatTimecode(t),
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
    _s = scaleOf(size) * (widget.compact ? 0.85 : 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: bgToken,
        border: Border(top: BorderSide(color: dividerToken)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Keep the playhead (and clip origin) clear of the track header.
          final double half = math.max(c.maxWidth * playheadFracToken, _hdrW + 12);
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
                        if (_pointers < 2) setState(() {});
                      },
                      child: GestureDetector(
                        onScaleStart: (_) => _baseZoom = model.zoom,
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
                                child: SizedBox(
                                  height: contentH,
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
                                                seconds: total + 5,
                                                leftPad: half,
                                                totalSec: total),
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
                          color: bgToken,
                          border: Border(right: BorderSide(color: dividerToken)),
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
                                    child: SizedBox(height: l.h, child: _header(l)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
                                  formatTimecodeShort(secondsOf(p)),
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
                    Positioned(
                      right: 6,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xD9101014),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dividerToken),
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
                                () => _applyZoom(model.zoom - 0.5)),
                            _chip(Icons.add_rounded, 'Zoom in', false,
                                () => _applyZoom(model.zoom + 0.5)),
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

  /// Track header: name (Video / Audio / Text ...) plus visibility and layer
  /// controls. No lock control here.
  Widget _header(_Lane l) {
    final bool empty = l.clips.isEmpty;
    // An empty lane has nothing to hide, so never show the "hidden" state.
    final bool visible = empty || l.clips.any((c) => c.visible);

    Widget btn(dynamic i, bool active, String tip, VoidCallback f) => Tooltip(
          message: tip,
          child: InkResponse(
            radius: 18,
            onTap: () {
              tapFeedback();
              f();
            },
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: HugeIcon(
                icon: i,
                size: 16 * _s,
                color: active ? Colors.white : Colors.white70,
              ),
            ),
          ),
        );

    final bool isTextLane = l.kind == _ClipKind.text && !empty;

    final List<Widget> icons = <Widget>[
      if (!empty)
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

    // FittedBox prevents RenderFlex overflow regardless of lane height/scale.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4 * _s),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l.name,
                maxLines: 1,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
              if (icons.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: icons),
              ],
            ],
          ),
        ),
      ),
    );
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
              tapFeedback();
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
              Positioned(
                key: ValueKey<String>('clip_${list[i].id}'),
                left: half + list[i].startSec * pps,
                top: 0,
                bottom: 0,
                width: math.max(_minClipW, list[i].durSec * pps - 4),
                child: RepaintBoundary(
                  child: _ClipBlock(
                    editor: widget.editor,
                    clip: list[i],
                    kind: l.kind,
                    pps: pps,
                    selected: m.selectedId == list[i].id,
                    multiOn: widget.multiOn,
                    multi: widget.multi,
                    trimLo: isVideo ? _neighbors(list[i], list)[0] : 0.0,
                    trimHi: isVideo ? _neighbors(list[i], list)[1] : 86400.0,
                    trimSnap: (t) =>
                        _snapTime(t, pps, m.clips, excludeId: list[i].id),
                    moveClamp: isVideo
                        ? (desired) => _constrainMove(list[i], desired, pps, list)
                        : (desired) => math.max(
                            0.0,
                            _snapSpan(desired, list[i].durSec, pps, m.clips,
                                excludeId: list[i].id)),
                  ),
                ),
              ),
              if (isVideo && i < list.length - 1)
                Positioned(
                  key: ValueKey<String>('tr_${list[i].id}'),
                  left: half + list[i].endSec * pps - 14 * _s,
                  top: l.h / 2 - 12 * _s,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      tapFeedback();
                      // Select the clip first so the sheet knows which cut it edits.
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

  Widget _trimHandle({required bool left}) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _rawEdge = left ? widget.clip.startSec : widget.clip.endSec;
        },
        onHorizontalDragUpdate: (d) {
          // Accumulate locally: widget.clip can be stale between rebuilds.
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
        final Color bg = drawing ? drawTrackToken : (sticker ? fxTrackToken : textTrackToken);
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
                // Locked clips keep their thumbnails (only editing is disabled).
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
            color: audioTrackToken,
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

    if (widget.selected && !locked && !widget.multiOn.value) {
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
        final bool canMove = !locked && !multiActive && widget.selected;

        return GestureDetector(
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
          onLongPressStart: canMove ? (_) => _startMove() : null,
          onLongPressMoveUpdate:
              canMove ? (d) => _updateMove(d.offsetFromOrigin.dx) : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: clip.visible ? 1 : 0.35,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(child: _buildBody()),
                if (inMulti)
                  const Positioned(
                    top: 4,
                    left: 6,
                    child: Icon(Icons.check_circle_rounded, size: 14, color: accentToken),
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
// Filmstrip thumbnails & Waveform Loader
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
    // Futures are created once per (path, count, duration), not on every build.
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
    final double cellW = widget.width / _n;
    return ClipRect(
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _n; i++)
            SizedBox(
              width: cellW,
              height: double.infinity,
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
        final int bars = math.max(8, (c.maxWidth / 5).floor());
        // Re-request only when the inputs actually change.
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
      ..color = const Color(0xFF7FD6E8)
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
    if (s >= 60) return '${s ~/ 60}:${twoDigits(s % 60)}';
    return '${s}s';
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B0B0E));
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5),
        Paint()..color = const Color(0xFF26262C));

    final double endX = leftPad + totalSec * pps;
    if (endX < size.width) {
      canvas.drawRect(Rect.fromLTRB(endX, 0, size.width, size.height),
          Paint()..color = Colors.white.withValues(alpha: 0.04));
    }
    canvas.drawLine(
        Offset(endX, 0),
        Offset(endX, size.height),
        Paint()
          ..color = accentToken.withValues(alpha: 0.7)
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
      tp.dispose();

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