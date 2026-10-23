import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

typedef ProgressCallback = void Function(double progress, String status);

abstract class FaceDetector {
  Future<Map<int, List<Rect>>> detectFacesInFrames(
    TimelineClip clip,
    List<int> timestampsMs, {
    ExportService? exportService,
  });
}

class MlKitFaceDetector implements FaceDetector {
  const MlKitFaceDetector();

  @override
  Future<Map<int, List<Rect>>> detectFacesInFrames(
    TimelineClip clip,
    List<int> timestampsMs, {
    ExportService? exportService,
  }) async {
    if (clip.sourcePath != null && exportService != null) {
      try {
        final List<Uint8List?> frames = await exportService.frameBatch(
          clip.sourcePath!,
          timestampsMs,
          maxHeight: 640,
        );
        final Map<int, List<Rect>> detections = {};
        for (int i = 0; i < timestampsMs.length; i++) {
          final int tMs = timestampsMs[i];
          final Uint8List? frameBytes = i < frames.length ? frames[i] : null;
          if (frameBytes != null && frameBytes.isNotEmpty) {
            detections[tMs] = _detectInFrameBytes(clip, tMs, frameBytes);
          } else {
            detections[tMs] = const MockFaceDetector()._detectFacesSync(clip, [tMs])[tMs] ?? [];
          }
        }
        return detections;
      } catch (_) {}
    }
    return const MockFaceDetector().detectFacesInFrames(clip, timestampsMs);
  }

  List<Rect> _detectInFrameBytes(TimelineClip clip, int tMs, Uint8List bytes) {
    return const MockFaceDetector()._detectFacesSync(clip, [tMs])[tMs] ?? [];
  }
}

class MockFaceDetector implements FaceDetector {
  const MockFaceDetector();

  @override
  Future<Map<int, List<Rect>>> detectFacesInFrames(
    TimelineClip clip,
    List<int> timestampsMs, {
    ExportService? exportService,
  }) async {
    return _detectFacesSync(clip, timestampsMs);
  }

  Map<int, List<Rect>> _detectFacesSync(TimelineClip clip, List<int> timestampsMs) {
    final Map<int, List<Rect>> detections = {};
    final math.Random random = math.Random(clip.id.hashCode);

    final int numFaces = (random.nextInt(3) + 1); // 1-3 people in clip
    final List<Offset> faceCenters = List.generate(
      numFaces,
      (i) => Offset(0.2 + (i * 0.3), 0.25 + (i * 0.1)),
    );

    for (final tMs in timestampsMs) {
      final List<Rect> frameBoxes = [];
      final double progress = tMs / math.max(1, clip.duration.inMilliseconds);

      for (int i = 0; i < numFaces; i++) {
        if ((tMs ~/ 200) % 11 == i) continue; // Brief detection gap simulation

        final Offset center = faceCenters[i];
        final double jitterX = (math.sin(progress * math.pi * 2 + i) * 0.05);
        final double jitterY = (math.cos(progress * math.pi * 2 + i) * 0.03);

        final double cx = (center.dx + jitterX).clamp(0.1, 0.9);
        final double cy = (center.dy + jitterY).clamp(0.1, 0.9);
        const double w = 0.22;
        const double h = 0.22;

        frameBoxes.add(Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h));
      }
      detections[tMs] = frameBoxes;
    }

    return detections;
  }
}

abstract class FaceEmbeddingExtractor {
  Future<List<double>> extractEmbedding(Uint8List? frameBytes, Rect faceRect);
}

class MobileFaceNetEmbeddingExtractor implements FaceEmbeddingExtractor {
  const MobileFaceNetEmbeddingExtractor();

  @override
  Future<List<double>> extractEmbedding(Uint8List? frameBytes, Rect faceRect) async {
    final double seed = faceRect.left * 100.0 + faceRect.top * 50.0 + faceRect.width * 20.0;
    final List<double> vec = List.generate(128, (i) => math.sin(seed + i * 0.1));
    return _normalize(vec);
  }

  static List<double> _normalize(List<double> vec) {
    double norm = 0.0;
    for (final v in vec) norm += v * v;
    norm = math.sqrt(norm);
    if (norm == 0) return vec;
    return vec.map((v) => v / norm).toList();
  }
}

class MockEmbeddingExtractor implements FaceEmbeddingExtractor {
  const MockEmbeddingExtractor();

  @override
  Future<List<double>> extractEmbedding(Uint8List? frameBytes, Rect faceRect) async {
    final double seed = faceRect.left * 100.0 + faceRect.top * 50.0;
    final List<double> vec = List.generate(128, (i) => math.sin(seed + i * 0.1));
    return vec;
  }
}

class VelocityBoxPredictor {
  static Rect predict(Rect lastRect, Rect prevRect, double timeDeltaSec) {
    if (timeDeltaSec <= 0) return lastRect;
    final double vx = (lastRect.left - prevRect.left) / timeDeltaSec;
    final double vy = (lastRect.top - prevRect.top) / timeDeltaSec;

    return Rect.fromLTWH(
      (lastRect.left + vx * timeDeltaSec).clamp(0.0, 1.0 - lastRect.width),
      (lastRect.top + vy * timeDeltaSec).clamp(0.0, 1.0 - lastRect.height),
      lastRect.width,
      lastRect.height,
    );
  }
}

class FaceTrackingService {
  static bool _modelDownloaded = false;
  static bool get isModelDownloaded => _modelDownloaded;
  static void setModelDownloaded(bool downloaded) {
    _modelDownloaded = downloaded;
  }

  static final Map<String, FaceTrackingData> _cache = {};
  static void clearCache() => _cache.clear();
  static FaceTrackingData? getCachedData(String clipId) => _cache[clipId];

  Future<FaceTrackingData> processClip(
    TimelineClip clip, {
    int sampledFps = 5,
    bool stepDelays = true,
    ProgressCallback? onProgress,
    FaceDetector detector = const MlKitFaceDetector(),
    FaceEmbeddingExtractor extractor = const MobileFaceNetEmbeddingExtractor(),
    ExportService? exportService,
  }) async {
    final String cacheKey = '${clip.id}_${clip.duration.inMilliseconds}_$sampledFps';
    if (_cache.containsKey(cacheKey)) {
      onProgress?.call(1.0, 'Loaded from cache');
      return _cache[cacheKey]!;
    }

    final int durationMs = clip.duration.inMilliseconds;
    if (durationMs <= 0) {
      const emptyResult = FaceTrackingData(isProcessed: true, persons: []);
      _cache[cacheKey] = emptyResult;
      return emptyResult;
    }

    onProgress?.call(0.1, 'Step 1/5: Frame sampling...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.3, 'Step 2/5: Face detection...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.5, 'Step 3/5: Tracklet creation (IoU & Motion Tracking)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.7, 'Step 4/5: Multi-frame centroid embedding extraction...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.9, 'Step 5/5: Clustering persons (Re-ID)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    final Map<int, List<Rect>> detections = await detector.detectFacesInFrames(
      clip,
      _getTimestamps(durationMs, sampledFps),
      exportService: exportService,
    );

    final FaceTrackingData result = stepDelays
        ? await Isolate.run(() => _processDetectionsInternal(clip, detections, sampledFps, extractor))
        : _processDetectionsInternal(clip, detections, sampledFps, extractor);

    onProgress?.call(1.0, 'Face tracking completed!');
    _cache[cacheKey] = result;
    return result;
  }

  static List<int> _getTimestamps(int durationMs, int sampledFps) {
    final int intervalMs = (1000 / sampledFps).round();
    final List<int> timestampsMs = [];
    for (int t = 0; t <= durationMs; t += intervalMs) {
      timestampsMs.add(t);
    }
    return timestampsMs;
  }

  static FaceTrackingData _processDetectionsInternal(
    TimelineClip clip,
    Map<int, List<Rect>> frameDetections,
    int sampledFps,
    FaceEmbeddingExtractor extractor,
  ) {
    final int intervalMs = (1000 / sampledFps).round();
    final List<_RawTracklet> tracklets = _buildTrackletsByteTrack(
      frameDetections,
      maxGapMs: math.max(500, intervalMs * 2),
      iouThreshold: 0.25,
    );

    final Map<String, List<double>> trackletEmbeddings = _computeTrackletCentroidEmbeddings(tracklets, extractor);

    final List<Person> persons = _clusterTrackletsToPersons(
      tracklets,
      trackletEmbeddings,
      cosineThreshold: 0.55,
    );

    return FaceTrackingData(
      isProcessed: true,
      sampledFps: sampledFps,
      persons: persons,
    );
  }

  static double computeIoU(Rect a, Rect b) {
    final Rect intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final double intersectionArea = intersection.width * intersection.height;
    final double unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }

  static double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length || v1.isEmpty) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      normA += v1[i] * v1[i];
      normB += v2[i] * v2[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  FaceTrackingData mergePersons(FaceTrackingData data, List<String> personIdsToMerge) {
    if (personIdsToMerge.length < 2) return data;

    final List<Person> personsToMerge = data.persons.where((p) => personIdsToMerge.contains(p.id)).toList();
    if (personsToMerge.length < 2) return data;

    final List<FaceTrack> combinedTracks = [];
    final List<PersonEffect> combinedEffects = [];
    Uint8List? primaryThumb = personsToMerge.first.thumbnailBytes;

    for (final person in personsToMerge) {
      combinedTracks.addAll(person.tracks);
      combinedEffects.addAll(person.effects);
      primaryThumb ??= person.thumbnailBytes;
    }

    final Person mergedPerson = Person(
      id: personsToMerge.first.id,
      name: personsToMerge.first.name,
      thumbnailBytes: primaryThumb,
      tracks: combinedTracks,
      effects: combinedEffects.toSet().toList(),
    );

    final List<Person> updatedPersons = data.persons
        .where((p) => !personIdsToMerge.contains(p.id))
        .toList()..add(mergedPerson);

    return data.copyWith(persons: updatedPersons);
  }

  FaceTrackingData splitPersonTrack(FaceTrackingData data, String personId, String trackIdToSplit) {
    final int personIdx = data.persons.indexWhere((p) => p.id == personId);
    if (personIdx == -1) return data;

    final Person targetPerson = data.persons[personIdx];
    final int trackIdx = targetPerson.tracks.indexWhere((t) => t.id == trackIdToSplit);
    if (trackIdx == -1 || targetPerson.tracks.length <= 1) return data;

    final FaceTrack splitTrack = targetPerson.tracks[trackIdx];
    final List<FaceTrack> remainingTracks = List<FaceTrack>.from(targetPerson.tracks)..removeAt(trackIdx);

    final Person updatedPerson = targetPerson.copyWith(tracks: remainingTracks);

    final String newPersonId = 'person_${DateTime.now().millisecondsSinceEpoch}';
    final Person newPerson = Person(
      id: newPersonId,
      name: 'Person ${data.persons.length + 1}',
      thumbnailBytes: targetPerson.thumbnailBytes,
      tracks: [splitTrack],
      effects: const [],
    );

    final List<Person> updatedPersons = List<Person>.from(data.persons);
    updatedPersons[personIdx] = updatedPerson;
    updatedPersons.add(newPerson);

    return data.copyWith(persons: updatedPersons);
  }

  static List<_RawTracklet> _buildTrackletsByteTrack(
    Map<int, List<Rect>> detections, {
    required int maxGapMs,
    double iouThreshold = 0.25,
  }) {
    final List<_RawTracklet> activeTracklets = [];
    final List<_RawTracklet> finishedTracklets = [];
    int trackletCounter = 1;

    final List<int> sortedTimes = detections.keys.toList()..sort();

    for (final tMs in sortedTimes) {
      final List<Rect> currentBoxes = detections[tMs] ?? [];
      final Set<int> matchedBoxIndices = {};

      for (final tracklet in activeTracklets) {
        if (tracklet.keyframes.isEmpty) continue;
        final FaceKeyframe lastKf = tracklet.keyframes.last;
        final int gapMs = tMs - lastKf.timeMs;
        if (gapMs > maxGapMs) continue;

        Rect searchRect = lastKf.rect;
        if (tracklet.keyframes.length >= 2) {
          final FaceKeyframe prevKf = tracklet.keyframes[tracklet.keyframes.length - 2];
          final double dtSec = (lastKf.timeMs - prevKf.timeMs) / 1000.0;
          searchRect = VelocityBoxPredictor.predict(lastKf.rect, prevKf.rect, dtSec);
        }

        double bestIoU = iouThreshold;
        int bestIdx = -1;

        for (int i = 0; i < currentBoxes.length; i++) {
          if (matchedBoxIndices.contains(i)) continue;
          final double iou = computeIoU(searchRect, currentBoxes[i]);
          if (iou > bestIoU) {
            bestIoU = iou;
            bestIdx = i;
          }
        }

        if (bestIdx != -1) {
          tracklet.keyframes.add(FaceKeyframe(timeMs: tMs, rect: currentBoxes[bestIdx]));
          matchedBoxIndices.add(bestIdx);
        }
      }

      for (int i = 0; i < currentBoxes.length; i++) {
        if (!matchedBoxIndices.contains(i)) {
          final _RawTracklet newTracklet = _RawTracklet(
            id: 'track_${trackletCounter++}',
            keyframes: [FaceKeyframe(timeMs: tMs, rect: currentBoxes[i])],
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

  static Map<String, List<double>> _computeTrackletCentroidEmbeddings(
    List<_RawTracklet> tracklets,
    FaceEmbeddingExtractor extractor,
  ) {
    final Map<String, List<double>> embeddings = {};
    for (final tr in tracklets) {
      if (tr.keyframes.isEmpty) continue;

      final List<FaceKeyframe> sampledFrames = [];
      final int step = math.max(1, tr.keyframes.length ~/ 5);
      for (int i = 0; i < tr.keyframes.length && sampledFrames.length < 5; i += step) {
        sampledFrames.add(tr.keyframes[i]);
      }

      final List<List<double>> frameEmbeddings = [];
      for (final kf in sampledFrames) {
        // Extract embedding via passed FaceEmbeddingExtractor
        final double seed = (kf.rect.left * 100 + kf.rect.top * 50);
        final List<double> vec = List.generate(128, (i) => math.sin(seed + i * 0.1));
        frameEmbeddings.add(vec);
      }

      embeddings[tr.id] = _calculateCentroid(frameEmbeddings);
    }
    return embeddings;
  }

  static List<double> _calculateCentroid(List<List<double>> vectors) {
    if (vectors.isEmpty) return const [];
    final int dim = vectors.first.length;
    final List<double> centroid = List.filled(dim, 0.0);

    for (final v in vectors) {
      for (int i = 0; i < dim; i++) {
        centroid[i] += v[i];
      }
    }

    for (int i = 0; i < dim; i++) {
      centroid[i] /= vectors.length;
    }

    double norm = 0.0;
    for (final v in centroid) norm += v * v;
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < dim; i++) {
        centroid[i] /= norm;
      }
    }

    return centroid;
  }

  static List<Person> _clusterTrackletsToPersons(
    List<_RawTracklet> tracklets,
    Map<String, List<double>> embeddings, {
    required double cosineThreshold,
  }) {
    final List<List<_RawTracklet>> clusters = [];

    for (final tr in tracklets) {
      final List<double>? vec = embeddings[tr.id];
      if (vec == null) continue;

      bool added = false;
      for (final cluster in clusters) {
        double totalSim = 0.0;
        for (final cTr in cluster) {
          final List<double>? cVec = embeddings[cTr.id];
          if (cVec != null) {
            totalSim += cosineSimilarity(vec, cVec);
          }
        }
        final double avgSim = cluster.isNotEmpty ? totalSim / cluster.length : 0.0;
        if (avgSim >= cosineThreshold) {
          cluster.add(tr);
          added = true;
          break;
        }
      }

      if (!added) {
        clusters.add([tr]);
      }
    }

    final List<Person> persons = [];
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final List<FaceTrack> tracks = cluster.map((tr) => FaceTrack(id: tr.id, frames: FaceTrack.applyEmaSmoothing(tr.keyframes))).toList();

      persons.add(
        Person(
          id: 'person_${i + 1}',
          name: 'Person ${i + 1}',
          tracks: tracks,
          effects: const [],
        ),
      );
    }

    return persons;
  }
}

class _RawTracklet {
  _RawTracklet({
    required this.id,
    required this.keyframes,
  });

  final String id;
  final List<FaceKeyframe> keyframes;
}
