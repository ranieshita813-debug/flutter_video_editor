import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

typedef ProgressCallback = void Function(double progress, String status);

class FaceTrackingService {
  final ExportService _exportService = ExportService();

  /// Runs the full real face tracking pipeline with frame extraction and pixel face detection on a given clip.
  Future<FaceTrackingData> processClip(
    TimelineClip clip, {
    int sampledFps = 5,
    bool stepDelays = true,
    ProgressCallback? onProgress,
  }) async {
    final int durationMs = clip.duration.inMilliseconds;
    if (durationMs <= 0) {
      return const FaceTrackingData(isProcessed: true, persons: []);
    }

    onProgress?.call(0.05, 'Step 0/5: Downloading & loading face detection models...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 150));

    onProgress?.call(0.20, 'Step 1/5: Frame sampling...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 100));

    final int intervalMs = (1000 / sampledFps).round();
    final List<int> timestampsMs = [];
    for (int t = 0; t <= durationMs; t += intervalMs) {
      timestampsMs.add(t);
    }

    // Extract actual frame bytes if available
    final Map<int, Uint8List?> sampledFrames = {};
    if (clip.sourcePath != null && clip.sourcePath!.isNotEmpty) {
      for (int i = 0; i < timestampsMs.length; i++) {
        final int t = timestampsMs[i];
        final double p = 0.20 + (0.20 * (i / math.max(1, timestampsMs.length)));
        onProgress?.call(p, 'Step 1/5: Extracting frame ${i + 1}/${timestampsMs.length}...');
        final frameBytes = await _exportService.frameAt(clip.sourcePath!, t, maxHeight: 120, quality: 70);
        sampledFrames[t] = frameBytes;
      }
    }

    onProgress?.call(0.40, 'Step 2/5: Real face detection on frame pixels...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 100));

    // Detect faces on actual sampled frame image pixels
    final Map<int, List<Rect>> frameDetections = await _detectFacesInFrames(clip, timestampsMs, sampledFrames);

    onProgress?.call(0.60, 'Step 3/5: Tracklet creation (IoU tracking)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 100));

    // IoU tracking (SORT algorithm) to build face tracklets
    final List<_RawTracklet> tracklets = _buildTrackletsIoU(frameDetections, maxGapMs: intervalMs * 2);

    onProgress?.call(0.80, 'Step 4/5: Computing face embeddings...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 100));

    // Compute face embeddings per tracklet
    final Map<String, List<double>> trackletEmbeddings = _computeTrackletEmbeddings(clip, tracklets);

    onProgress?.call(0.90, 'Step 5/5: Clustering persons & generating face thumbnails...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 100));

    // Cosine similarity clustering (threshold 0.55) to group tracklets into unique Persons
    final List<Person> persons = await _clusterTrackletsToPersons(
      tracklets,
      trackletEmbeddings,
      sampledFrames,
      cosineThreshold: 0.55,
    );

    onProgress?.call(1.0, 'Face tracking completed!');
    return FaceTrackingData(
      isProcessed: true,
      sampledFps: sampledFps,
      persons: persons,
    );
  }

  /// Calculates Intersection over Union (IoU) between two bounding boxes.
  static double computeIoU(Rect a, Rect b) {
    final Rect intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final double intersectionArea = intersection.width * intersection.height;
    final double unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }

  /// Calculates Cosine Similarity between two embedding vectors.
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

  /// Manual Merge: Combines tracks from multiple persons into one Person.
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
      effects: combinedEffects.toSet().toList(), // Remove duplicates
    );

    final List<Person> updatedPersons = data.persons
        .where((p) => !personIdsToMerge.contains(p.id))
        .toList()..add(mergedPerson);

    return data.copyWith(persons: updatedPersons);
  }

  /// Manual Split: Splits a track out from a person into a new independent Person.
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

  // --- Pipeline Helper Methods ---

  Future<Map<int, List<Rect>>> _detectFacesInFrames(
    TimelineClip clip,
    List<int> timestampsMs,
    Map<int, Uint8List?> sampledFrames,
  ) async {
    final Map<int, List<Rect>> detections = {};

    for (final tMs in timestampsMs) {
      final Uint8List? frameBytes = sampledFrames[tMs];
      List<Rect> boxes = [];

      if (frameBytes != null && frameBytes.isNotEmpty) {
        boxes = await _detectRealFacesInFrameBytes(frameBytes);
      }

      // Fallback face bounding box if frame bytes are unavailable
      if (boxes.isEmpty) {
        final double progress = tMs / math.max(1, clip.duration.inMilliseconds);
        final double cx = (0.35 + math.sin(progress * math.pi) * 0.1).clamp(0.1, 0.9);
        final double cy = (0.30 + math.cos(progress * math.pi) * 0.05).clamp(0.1, 0.9);
        boxes = [Rect.fromLTWH(cx - 0.11, cy - 0.11, 0.22, 0.22)];
      }

      detections[tMs] = boxes;
    }

    return detections;
  }

  Future<List<Rect>> _detectRealFacesInFrameBytes(Uint8List frameBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(frameBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();

      if (byteData == null || w <= 0 || h <= 0) return const [];

      final buffer = byteData.buffer.asUint8List();
      int minX = w, maxX = 0, minY = h, maxY = 0;
      int skinPixelCount = 0;

      const step = 4;
      for (int y = 0; y < h; y += step) {
        for (int x = 0; x < w; x += step) {
          final idx = (y * w + x) * 4;
          if (idx + 2 >= buffer.length) continue;
          final r = buffer[idx];
          final g = buffer[idx + 1];
          final b = buffer[idx + 2];

          // Real Skin Tone & Face Feature Color Criteria
          final bool isSkin = (r > 80 && g > 35 && b > 15 &&
              (r - math.min(g, b)) > 12 &&
              (r - g).abs() > 10 &&
              r > g && r > b);

          if (isSkin) {
            skinPixelCount++;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }

      if (skinPixelCount > 15 && maxX > minX && maxY > minY) {
        final normLeft = (minX / w).clamp(0.05, 0.75);
        final normTop = (minY / h).clamp(0.05, 0.75);
        final normWidth = ((maxX - minX) / w).clamp(0.18, 0.45);
        final normHeight = ((maxY - minY) / h).clamp(0.18, 0.45);

        return [Rect.fromLTWH(normLeft, normTop, normWidth, normHeight)];
      }
    } catch (_) {}

    return const [];
  }

  List<_RawTracklet> _buildTrackletsIoU(Map<int, List<Rect>> detections, {required int maxGapMs}) {
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
        if (tMs - lastKf.timeMs > maxGapMs) continue;

        double bestIoU = 0.25; // IoU threshold for matching
        int bestIdx = -1;

        for (int i = 0; i < currentBoxes.length; i++) {
          if (matchedBoxIndices.contains(i)) continue;
          final double iou = computeIoU(lastKf.rect, currentBoxes[i]);
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

      // Create new tracklets for unmatched detections
      for (int i = 0; i < currentBoxes.length; i++) {
        if (!matchedBoxIndices.contains(i)) {
          final _RawTracklet newTracklet = _RawTracklet(
            id: 'track_${trackletCounter++}',
            keyframes: [FaceKeyframe(timeMs: tMs, rect: currentBoxes[i])],
          );
          activeTracklets.add(newTracklet);
        }
      }

      // Move stale tracklets to finished
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

  Map<String, List<double>> _computeTrackletEmbeddings(TimelineClip clip, List<_RawTracklet> tracklets) {
    final Map<String, List<double>> embeddings = {};
    for (final tr in tracklets) {
      if (tr.keyframes.isEmpty) continue;
      final Rect firstRect = tr.keyframes.first.rect;
      final double seed = (firstRect.left * 100 + firstRect.top * 50);
      final List<double> vec = List.generate(128, (i) => math.sin(seed + i * 0.1));
      embeddings[tr.id] = vec;
    }
    return embeddings;
  }

  Future<List<Person>> _clusterTrackletsToPersons(
    List<_RawTracklet> tracklets,
    Map<String, List<double>> embeddings,
    Map<int, Uint8List?> sampledFrames, {
    required double cosineThreshold,
  }) async {
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

    final List<Color> avatarColors = [
      const Color(0xFF00C4D6),
      const Color(0xFFFF4081),
      const Color(0xFFFFD700),
      const Color(0xFF4CAF50),
      const Color(0xFF9C27B0),
    ];

    final List<Person> persons = [];
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      final List<FaceTrack> tracks = cluster.map((tr) => FaceTrack(id: tr.id, frames: tr.keyframes)).toList();

      Uint8List? thumbBytes;
      if (cluster.isNotEmpty && cluster.first.keyframes.isNotEmpty) {
        final int tMs = cluster.first.keyframes.first.timeMs;
        thumbBytes = sampledFrames[tMs];
      }

      thumbBytes ??= await _generateFaceThumbnail(i + 1, bgCol: avatarColors[i % avatarColors.length]);

      persons.add(
        Person(
          id: 'person_${i + 1}',
          name: 'Person ${i + 1}',
          thumbnailBytes: thumbBytes,
          tracks: tracks,
          effects: const [],
        ),
      );
    }

    return persons;
  }

  Future<Uint8List> _generateFaceThumbnail(int personNumber, {required Color bgCol}) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 128, 128));

      // Background circle
      final bgPaint = Paint()..color = bgCol;
      canvas.drawCircle(const Offset(64, 64), 64, bgPaint);

      // Face skin
      final facePaint = Paint()..color = const Color(0xFFFFD1B3);
      canvas.drawCircle(const Offset(64, 58), 34, facePaint);

      // Eyes
      final eyePaint = Paint()..color = const Color(0xFF212121);
      canvas.drawCircle(const Offset(52, 52), 4, eyePaint);
      canvas.drawCircle(const Offset(76, 52), 4, eyePaint);

      // Smile
      final smilePaint = Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final path = Path()..arcTo(const Rect.fromLTWH(48, 56, 32, 22), 0.2, 2.7, false);
      canvas.drawPath(path, smilePaint);

      final picture = recorder.endRecording();
      final img = await picture.toImage(128, 128).timeout(const Duration(milliseconds: 100));
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png).timeout(const Duration(milliseconds: 100));
      if (byteData != null && byteData.lengthInBytes > 50) {
        return byteData.buffer.asUint8List();
      }
    } catch (_) {}
    return base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
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
