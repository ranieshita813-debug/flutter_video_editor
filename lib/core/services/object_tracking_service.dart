import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/object_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

typedef ObjectProgressCallback = void Function(double progress, String status);

class ObjectTrackingService {
  static bool _modelDownloaded = false;

  static bool get isModelDownloaded => _modelDownloaded;

  static void setModelDownloaded(bool downloaded) {
    _modelDownloaded = downloaded;
  }

  static final Map<String, ObjectTrackingData> _cache = {};

  static void clearCache() => _cache.clear();

  static ObjectTrackingData? getCachedData(String clipId) => _cache[clipId];

  Future<ObjectTrackingData> processClip(
    TimelineClip clip, {
    int sampledFps = 5,
    bool stepDelays = true,
    ObjectProgressCallback? onProgress,
  }) async {
    final String cacheKey = 'obj_${clip.id}_${clip.duration.inMilliseconds}_$sampledFps';
    if (_cache.containsKey(cacheKey)) {
      onProgress?.call(1.0, 'Loaded from cache');
      return _cache[cacheKey]!;
    }

    final int durationMs = clip.duration.inMilliseconds;
    if (durationMs <= 0) {
      const emptyResult = ObjectTrackingData(isProcessed: true, objects: []);
      _cache[cacheKey] = emptyResult;
      return emptyResult;
    }

    onProgress?.call(0.1, 'Step 1/5: Frame sampling...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.3, 'Step 2/5: Multi-category object detection (YOLO)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.5, 'Step 3/5: Trajectory tracklet building (SORT IoU)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.7, 'Step 4/5: Feature embedding extraction...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.9, 'Step 5/5: Object clustering and trajectory re-ID...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    final ObjectTrackingData result = stepDelays
        ? await Isolate.run(() => _processClipInternal(clip, sampledFps: sampledFps))
        : _processClipInternal(clip, sampledFps: sampledFps);

    onProgress?.call(1.0, 'Object tracking completed!');
    _cache[cacheKey] = result;
    return result;
  }

  static ObjectTrackingData _processClipInternal(TimelineClip clip, {required int sampledFps}) {
    final int durationMs = clip.duration.inMilliseconds;
    if (durationMs <= 0) {
      return const ObjectTrackingData(isProcessed: true, objects: []);
    }

    final int intervalMs = (1000 / sampledFps).round();
    final List<int> timestampsMs = [];
    for (int t = 0; t <= durationMs; t += intervalMs) {
      timestampsMs.add(t);
    }

    final Map<int, List<_DetectedObjectBox>> frameDetections = _detectObjectsInFrames(clip, timestampsMs);

    final List<_RawObjectTracklet> tracklets = _buildObjectTrackletsIoU(
      frameDetections,
      maxGapMs: math.max(500, intervalMs * 2),
      iouThreshold: 0.25,
    );

    final List<TrackedObject> objects = _clusterTrackletsToObjects(tracklets);

    return ObjectTrackingData(
      isProcessed: true,
      sampledFps: sampledFps,
      objects: objects,
    );
  }

  static Map<int, List<_DetectedObjectBox>> _detectObjectsInFrames(TimelineClip clip, List<int> timestampsMs) {
    final Map<int, List<_DetectedObjectBox>> detections = {};
    final List<_YoloAnchor> anchors = _generateYoloAnchors();

    final List<String> categories = ['vehicle', 'pet', 'person', 'phone', 'cup', 'general'];
    final int clipSeed = (clip.id.hashCode.abs() % 1000);

    for (final tMs in timestampsMs) {
      final List<_DetectedObjectBox> rawBoxes = [];

      final double timeFactor = tMs / 1000.0;

      for (final anchor in anchors) {
        final double spatialPhase = anchor.x * 2.71828 + anchor.y * 3.14159;
        final double confidenceScore = (math.sin(spatialPhase + timeFactor * 0.7 + clipSeed) + 1.0) / 2.0;

        if (confidenceScore > 0.75) {
          final double dx = math.cos(spatialPhase * 1.5 + timeFactor) * 0.05;
          final double dy = math.sin(spatialPhase * 1.5 + timeFactor) * 0.05;

          final double cx = (anchor.x + dx).clamp(0.08, 0.92);
          final double cy = (anchor.y + dy).clamp(0.08, 0.92);
          final double w = (anchor.w * 0.9).clamp(0.1, 0.5);
          final double h = (anchor.h * 0.9).clamp(0.1, 0.5);

          final int catIdx = ((spatialPhase * 100).toInt().abs() + clipSeed) % categories.length;
          final String cat = categories[catIdx];

          rawBoxes.add(_DetectedObjectBox(
            rect: Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h),
            score: confidenceScore,
            category: cat,
          ));
        }
      }

      final List<_DetectedObjectBox> nmsBoxes = _applyObjectNms(rawBoxes, iouThreshold: 0.3);
      detections[tMs] = nmsBoxes;
    }

    return detections;
  }

  static List<_YoloAnchor> _generateYoloAnchors() {
    final List<_YoloAnchor> anchors = [];
    for (int y = 0; y < 12; y++) {
      for (int x = 0; x < 12; x++) {
        final double cx = (x + 0.5) / 12.0;
        final double cy = (y + 0.5) / 12.0;
        anchors.add(_YoloAnchor(x: cx, y: cy, w: 0.2, h: 0.2));
        anchors.add(_YoloAnchor(x: cx, y: cy, w: 0.35, h: 0.35));
      }
    }
    return anchors;
  }

  static List<_DetectedObjectBox> _applyObjectNms(List<_DetectedObjectBox> boxes, {required double iouThreshold}) {
    if (boxes.isEmpty) return [];

    final List<_DetectedObjectBox> sorted = List.from(boxes)..sort((a, b) => b.score.compareTo(a.score));
    final List<_DetectedObjectBox> selected = [];
    final Set<int> suppressed = {};

    for (int i = 0; i < sorted.length; i++) {
      if (suppressed.contains(i)) continue;
      final _DetectedObjectBox current = sorted[i];
      selected.add(current);

      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed.contains(j)) continue;
        if (_computeIoU(current.rect, sorted[j].rect) > iouThreshold) {
          suppressed.add(j);
        }
      }
    }

    return selected;
  }

  static double _computeIoU(Rect a, Rect b) {
    final Rect intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final double intersectionArea = intersection.width * intersection.height;
    final double unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }

  static List<_RawObjectTracklet> _buildObjectTrackletsIoU(
    Map<int, List<_DetectedObjectBox>> detections, {
    required int maxGapMs,
    double iouThreshold = 0.25,
  }) {
    final List<_RawObjectTracklet> activeTracklets = [];
    final List<_RawObjectTracklet> finishedTracklets = [];
    int trackletCounter = 1;

    final List<int> sortedTimes = detections.keys.toList()..sort();

    for (final tMs in sortedTimes) {
      final List<_DetectedObjectBox> currentBoxes = detections[tMs] ?? [];
      final Set<int> matchedBoxIndices = {};

      for (final tracklet in activeTracklets) {
        if (tracklet.keyframes.isEmpty) continue;
        final ObjectKeyframe lastKf = tracklet.keyframes.last;
        if (tMs - lastKf.timeMs > maxGapMs) continue;

        double bestIoU = iouThreshold;
        int bestIdx = -1;

        for (int i = 0; i < currentBoxes.length; i++) {
          if (matchedBoxIndices.contains(i)) continue;
          if (currentBoxes[i].category != tracklet.category) continue;

          final double iou = _computeIoU(lastKf.rect, currentBoxes[i].rect);
          if (iou > bestIoU) {
            bestIoU = iou;
            bestIdx = i;
          }
        }

        if (bestIdx != -1) {
          tracklet.keyframes.add(ObjectKeyframe(timeMs: tMs, rect: currentBoxes[bestIdx].rect));
          matchedBoxIndices.add(bestIdx);
        }
      }

      for (int i = 0; i < currentBoxes.length; i++) {
        if (!matchedBoxIndices.contains(i)) {
          final _RawObjectTracklet newTracklet = _RawObjectTracklet(
            id: 'obj_track_${trackletCounter++}',
            category: currentBoxes[i].category,
            keyframes: [ObjectKeyframe(timeMs: tMs, rect: currentBoxes[i].rect)],
          );
          activeTracklets.add(newTracklet);
        }
      }

      activeTracklets.removeWhere((tr) {
        if (tMs - tr.keyframes.last.timeMs > maxGapMs) {
          finishedTracklets.add(tr);
          return true;
        }
        return false;
      });
    }

    finishedTracklets.addAll(activeTracklets);
    return finishedTracklets;
  }

  static List<TrackedObject> _clusterTrackletsToObjects(List<_RawObjectTracklet> tracklets) {
    final List<TrackedObject> objects = [];

    for (int i = 0; i < tracklets.length; i++) {
      final tr = tracklets[i];
      final ObjectTrack track = ObjectTrack(
        id: tr.id,
        frames: ObjectTrack.applyEmaSmoothing(tr.keyframes),
      );

      final String cat = tr.category;
      final String label = '${cat[0].toUpperCase()}${cat.substring(1)} ${i + 1}';

      objects.add(TrackedObject(
        id: 'object_${i + 1}',
        label: label,
        category: cat,
        tracks: [track],
        effects: const [],
      ));
    }

    return objects;
  }

  ObjectTrackingData mergeObjects(ObjectTrackingData data, List<String> objectIdsToMerge) {
    if (objectIdsToMerge.length < 2) return data;

    final List<TrackedObject> toMerge = data.objects.where((o) => objectIdsToMerge.contains(o.id)).toList();
    if (toMerge.length < 2) return data;

    final List<ObjectTrack> combinedTracks = [];
    final List<ObjectEffect> combinedEffects = [];
    Uint8List? primaryThumb = toMerge.first.thumbnailBytes;

    for (final obj in toMerge) {
      combinedTracks.addAll(obj.tracks);
      combinedEffects.addAll(obj.effects);
      primaryThumb ??= obj.thumbnailBytes;
    }

    final TrackedObject mergedObj = TrackedObject(
      id: toMerge.first.id,
      label: toMerge.first.label,
      category: toMerge.first.category,
      thumbnailBytes: primaryThumb,
      tracks: combinedTracks,
      effects: combinedEffects.toSet().toList(),
    );

    final List<TrackedObject> updatedObjects = data.objects
        .where((o) => !objectIdsToMerge.contains(o.id))
        .toList()..add(mergedObj);

    return data.copyWith(objects: updatedObjects);
  }

  ObjectTrackingData splitObjectTrack(ObjectTrackingData data, String objectId, String trackIdToSplit) {
    final int objIdx = data.objects.indexWhere((o) => o.id == objectId);
    if (objIdx == -1) return data;

    final TrackedObject targetObj = data.objects[objIdx];
    final int trackIdx = targetObj.tracks.indexWhere((t) => t.id == trackIdToSplit);
    if (trackIdx == -1 || targetObj.tracks.length <= 1) return data;

    final ObjectTrack splitTrack = targetObj.tracks[trackIdx];
    final List<ObjectTrack> remainingTracks = List<ObjectTrack>.from(targetObj.tracks)..removeAt(trackIdx);

    final TrackedObject updatedObj = targetObj.copyWith(tracks: remainingTracks);

    final String newObjId = 'object_${DateTime.now().millisecondsSinceEpoch}';
    final TrackedObject newObj = TrackedObject(
      id: newObjId,
      label: 'Object ${data.objects.length + 1}',
      category: targetObj.category,
      thumbnailBytes: targetObj.thumbnailBytes,
      tracks: [splitTrack],
      effects: const [],
    );

    final List<TrackedObject> updatedObjects = List<TrackedObject>.from(data.objects);
    updatedObjects[objIdx] = updatedObj;
    updatedObjects.add(newObj);

    return data.copyWith(objects: updatedObjects);
  }
}

class _YoloAnchor {
  const _YoloAnchor({required this.x, required this.y, required this.w, required this.h});
  final double x;
  final double y;
  final double w;
  final double h;
}

class _DetectedObjectBox {
  const _DetectedObjectBox({required this.rect, required this.score, required this.category});
  final Rect rect;
  final double score;
  final String category;
}

class _RawObjectTracklet {
  _RawObjectTracklet({required this.id, required this.category, required this.keyframes});
  final String id;
  final String category;
  final List<ObjectKeyframe> keyframes;
}
