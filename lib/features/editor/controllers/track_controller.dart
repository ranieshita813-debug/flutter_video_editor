import 'package:flutter_video_editor/core/models/project_model.dart';

class TrackController {
  bool isOverlay(TimelineClip c) =>
      c.clipType != ClipType.audio &&
      (c.layerIndex > 0 ||
          (c.clipType != ClipType.video && c.clipType != ClipType.image));

  int freeOverlayLayer(List<TimelineClip> clips, int base, Duration start, Duration end) {
    int layer = base;
    while (clips.any((c) =>
        isOverlay(c) &&
        c.layerIndex == layer &&
        c.start < end &&
        c.end > start)) {
      layer++;
    }
    return layer;
  }

  Duration mainTrackEnd(List<TimelineClip> clips) {
    Duration end = Duration.zero;
    for (final c in clips) {
      if ((c.clipType == ClipType.video || c.clipType == ClipType.image) && c.end > end) {
        end = c.end;
      }
    }
    return end;
  }

  List<int> overlayLayers(List<TimelineClip> clips) {
    final List<int> ls =
        clips.where(isOverlay).map((c) => c.layerIndex).toSet().toList()
          ..sort();
    return ls;
  }

  bool canMoveClipLayer(List<TimelineClip> clips, String clipId, {required bool up}) {
    final int index = clips.indexWhere((c) => c.id == clipId);
    if (index == -1 || !isOverlay(clips[index])) return false;
    final List<int> ls = overlayLayers(clips);
    final int i = ls.indexOf(clips[index].layerIndex);
    if (i < 0) return false;
    return up ? i < ls.length - 1 : i > 0;
  }

  void moveClipLayer(List<TimelineClip> clips, String clipId, {required bool up, bool toEdge = false}) {
    if (!canMoveClipLayer(clips, clipId, up: up)) return;
    final TimelineClip clip = clips.firstWhere((c) => c.id == clipId);
    final List<int> ls = overlayLayers(clips);
    final int i = ls.indexOf(clip.layerIndex);
    final int j = up ? (toEdge ? ls.length - 1 : i + 1) : (toEdge ? 0 : i - 1);

    final List<int> order = List<int>.of(ls)
      ..removeAt(i)
      ..insert(j, clip.layerIndex);

    final Map<int, int> remap = <int, int>{
      for (int k = 0; k < ls.length; k++) order[k]: ls[k],
    };
    for (int n = 0; n < clips.length; n++) {
      final TimelineClip c = clips[n];
      if (!isOverlay(c)) continue;
      final int? target = remap[c.layerIndex];
      if (target != null && target != c.layerIndex) {
        clips[n] = c.copyWith(layerIndex: target);
      }
    }
  }
}
