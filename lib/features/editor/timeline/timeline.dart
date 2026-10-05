import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/timeline/clip_block.dart';
import 'package:flutter_video_editor/features/editor/timeline/ruler_painter.dart';
import 'package:flutter_video_editor/features/media_picker/pages/media_picker_page.dart';

class Lane {
  const Lane(this.h, this.kind, this.clips, {this.add = false});
  final double h;
  final ClipKind kind;
  final List<TimelineClip> clips;
  final bool add;
}

class Timeline extends StatefulWidget {
  const Timeline({super.key, required this.editor, this.compact = false});
  final EditorController editor;
  final bool compact;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  static const double _rulerH = 30, _textH = 34, _videoH = 52, _audioH = 40;
  static const double _gap = 6, _hdrW = 44;

  final ScrollController _sc = ScrollController();
  final ScrollController _vc = ScrollController();
  final ScrollController _hc = ScrollController();

  bool _userScrolling = false;
  bool _snap = true;
  double _baseZoom = 1.0;
  double? _lastSnap;

  EditorController get editor => widget.editor;

  @override
  void initState() {
    super.initState();
    _vc.addListener(() {
      if (_hc.hasClients && (_hc.offset - _vc.offset).abs() > 0.5) {
        _hc.jumpTo(_vc.offset.clamp(0.0, _hc.position.maxScrollExtent));
      }
    });
    editor.playheadNotifier.addListener(_syncScroll);
  }

  @override
  void dispose() {
    editor.playheadNotifier.removeListener(_syncScroll);
    _sc.dispose();
    _vc.dispose();
    _hc.dispose();
    super.dispose();
  }

  bool _isOverlay(TimelineClip c) =>
      c.clipType != ClipType.audio &&
      c.clipType != ClipType.video &&
      c.clipType != ClipType.image;

  List<Lane> _lanes(List<TimelineClip> clips) {
    final main = clips
        .where((c) => c.clipType == ClipType.video || c.clipType == ClipType.image)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final audio = clips.where((c) => c.clipType == ClipType.audio).toList();
    final layers = clips.where(_isOverlay).map<int>((c) => c.layerIndex).toSet().toList()..sort();

    return <Lane>[
      for (final l in layers.reversed)
        Lane(_textH, ClipKind.text, clips.where((c) => _isOverlay(c) && c.layerIndex == l).toList()),
      Lane(_videoH, ClipKind.video, main, add: true),
      if (audio.isNotEmpty) Lane(_audioH, ClipKind.audio, audio),
    ];
  }

  void _syncScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userScrolling || !_sc.hasClients) return;
      final double pps = 28.0 * editor.zoom;
      final double target = ((editor.playhead.inMilliseconds / 1000.0) * pps)
          .clamp(0.0, _sc.position.maxScrollExtent);
      if ((_sc.offset - target).abs() > 0.5) _sc.jumpTo(target);
    });
  }

  double _snapTime(double t, double pps, List<TimelineClip> clips) {
    if (!_snap) return t;
    double best = t;
    double bd = 8 / pps;

    for (final c in clips) {
      final double startSec = c.start.inMilliseconds / 1000.0;
      final double endSec = c.end.inMilliseconds / 1000.0;
      for (final double e in <double>[startSec, endSec]) {
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

  void _showTransitionPicker(TimelineClip clip) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EditorTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        TransitionType currentType = clip.transition.type;
        double durationSec = clip.transition.duration.inMilliseconds / 1000.0;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Select Transition', style: TextStyle(color: EditorTokens.text, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: TransitionType.values.map((t) {
                      final bool sel = currentType == t;
                      return ChoiceChip(
                        label: Text(t.name.toUpperCase()),
                        selected: sel,
                        selectedColor: EditorTokens.text,
                        backgroundColor: EditorTokens.elevated,
                        labelStyle: TextStyle(color: sel ? EditorTokens.bg : EditorTokens.text, fontSize: 12),
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() => currentType = t);
                            editor.setClipTransition(clip.id, ClipTransition(type: currentType, duration: Duration(milliseconds: (durationSec * 1000).round())));
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      const Text('Duration: ', style: TextStyle(color: EditorTokens.muted, fontSize: 13)),
                      Text('${durationSec.toStringAsFixed(1)}s', style: const TextStyle(color: EditorTokens.text, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: durationSec,
                    min: 0.1,
                    max: 2.0,
                    activeColor: EditorTokens.text,
                    inactiveColor: EditorTokens.border,
                    onChanged: (val) {
                      setModalState(() => durationSec = val);
                      editor.setClipTransition(clip.id, ClipTransition(type: currentType, duration: Duration(milliseconds: (durationSec * 1000).round())));
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<TimelineClip> clips = editor.clips;
    final double total = math.max(editor.project.totalDuration.inMilliseconds / 1000.0, 1.0);
    final double pps = 28.0 * editor.zoom;
    final List<Lane> lanes = _lanes(clips);
    final double contentH = _rulerH + lanes.fold<double>(0, (s, l) => s + l.h + _gap) + 16;
    final double maxH = widget.compact ? 150 : 230;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        color: EditorTokens.bg,
        border: Border(top: BorderSide(color: EditorTokens.border)),
      ),
      height: math.min(contentH, maxH),
      child: LayoutBuilder(
        builder: (context, c) {
          final double half = c.maxWidth * 0.42;
          final double contentW = total * pps + c.maxWidth;

          return Stack(
            children: <Widget>[
              RawGestureDetector(
                gestures: <Type, GestureRecognizerFactory>{
                  ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                    () => ScaleGestureRecognizer(),
                    (ScaleGestureRecognizer instance) {
                      instance.onStart = (_) => _baseZoom = editor.zoom;
                      instance.onUpdate = (details) {
                        if (details.pointerCount >= 2) {
                          editor.setZoom(_baseZoom * details.scale);
                        }
                      };
                    },
                  ),
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.axis != Axis.horizontal) return false;
                    if (n is ScrollStartNotification && n.dragDetails != null) {
                      _userScrolling = true;
                    } else if (n is ScrollUpdateNotification && _userScrolling) {
                      final double sec = _snapTime(n.metrics.pixels / pps, pps, clips);
                      editor.setPlayhead(Duration(milliseconds: (sec * 1000).round()));
                    } else if (n is ScrollEndNotification) {
                      _userScrolling = false;
                      _syncScroll();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _sc,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
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
                                  final double sec = (d.localPosition.dx - half) / pps;
                                  editor.setPlayhead(Duration(milliseconds: (sec * 1000).round()));
                                },
                                child: SizedBox(
                                  height: _rulerH,
                                  width: contentW,
                                  child: CustomPaint(
                                    painter: RulerPainter(
                                      pps: pps,
                                      seconds: total + 5,
                                      leftPad: half,
                                      fps: editor.fps,
                                    ),
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

              // Header controls
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _hdrW,
                child: Container(
                  decoration: const BoxDecoration(
                    color: EditorTokens.bg,
                    border: Border(right: BorderSide(color: EditorTokens.border)),
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

              // Centered Playhead Line
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
                          color: EditorTokens.text,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(child: Container(width: 2, color: EditorTokens.text)),
                    ],
                  ),
                ),
              ),

              // Controls overlay
              Positioned(
                right: 6,
                top: 2,
                child: Row(
                  children: <Widget>[
                    _chip(Icons.align_horizontal_center_rounded, 'Snap', _snap, () => setState(() => _snap = !_snap)),
                    const SizedBox(width: 4),
                    _chip(Icons.remove_rounded, 'Zoom out', false, () => editor.setZoom(editor.zoom - 0.5)),
                    const SizedBox(width: 4),
                    _chip(Icons.add_rounded, 'Zoom in', false, () => editor.setZoom(editor.zoom + 0.5)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(IconData icon, String tip, bool on, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Container(
            width: 30,
            height: 24,
            decoration: BoxDecoration(
              color: on ? EditorTokens.text : EditorTokens.elevated,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: on ? EditorTokens.bg : EditorTokens.text),
          ),
        ),
      ),
    );
  }

  Widget _header(Lane l) {
    final bool locked = l.clips.isNotEmpty && l.clips.every((c) => c.isLocked);
    final bool visible = l.clips.any((c) => c.isVisible);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            icon: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 14, color: EditorTokens.text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
            onPressed: () {
              for (final c in l.clips) {
                if (c.isLocked == locked) editor.toggleClipLock(c.id);
              }
            },
          ),
          IconButton(
            icon: Icon(visible ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 14, color: EditorTokens.muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
            onPressed: () {
              for (final c in l.clips) {
                if (c.isVisible == visible) editor.toggleClipVisibility(c.id);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _lane(Lane l, double contentW, double pps, double half) {
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
                left: half + (list[i].start.inMilliseconds / 1000.0) * pps,
                top: 0,
                bottom: 0,
                child: ClipBlock(
                  editor: editor,
                  clip: list[i],
                  kind: l.kind,
                  pps: pps,
                ),
              ),
              if (l.kind == ClipKind.video && i < list.length - 1)
                Positioned(
                  left: half + (list[i].end.inMilliseconds / 1000.0) * pps - 11,
                  top: l.h / 2 - 11,
                  child: GestureDetector(
                    onTap: () => _showTransitionPicker(list[i]),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: EditorTokens.text,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.join_inner_rounded, size: 13, color: EditorTokens.bg),
                    ),
                  ),
                ),
            ],
            if (l.add)
              Positioned(
                left: half + (list.isEmpty ? 0 : (list.last.end.inMilliseconds / 1000.0) * pps) + 6,
                top: l.h / 2 - 14,
                child: Semantics(
                  button: true,
                  label: 'Add media',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).pushNamed('/media_picker', arguments: const MediaPickerArgs(appendToCurrent: true));
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: EditorTokens.text, shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded, size: 18, color: EditorTokens.bg),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
