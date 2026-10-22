import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

typedef ProgressCallback = void Function(double progress, String status);

class FaceTrackingService {
  /// Runs the full 5-step face tracking pipeline on a given timeline clip.
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

    onProgress?.call(0.1, 'Step 1/5: Frame sampling...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    final int intervalMs = (1000 / sampledFps).round();
    final List<int> timestampsMs = [];
    for (int t = 0; t <= durationMs; t += intervalMs) {
      timestampsMs.add(t);
    }

    onProgress?.call(0.3, 'Step 2/5: Face detection...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    // Simulated/on-device face detection across sampled frames
    final Map<int, List<Rect>> frameDetections = _detectFacesInFrames(clip, timestampsMs);

    onProgress?.call(0.5, 'Step 3/5: Tracklet creation (IoU tracking)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    // IoU tracking (SORT algorithm) to build face tracklets
    final List<_RawTracklet> tracklets = _buildTrackletsIoU(frameDetections, maxGapMs: intervalMs * 2);

    onProgress?.call(0.7, 'Step 4/5: Face embedding computation...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    // Compute face embeddings (simulated/feature vector) per tracklet
    final Map<String, List<double>> trackletEmbeddings = _computeTrackletEmbeddings(clip, tracklets);

    onProgress?.call(0.9, 'Step 5/5: Clustering persons...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    // Cosine similarity clustering (threshold 0.55) to group tracklets into unique Persons
    final List<Person> persons = _clusterTrackletsToPersons(tracklets, trackletEmbeddings, cosineThreshold: 0.55);

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

  // --- Pipeline Private Helper Methods ---

  Map<int, List<Rect>> _detectFacesInFrames(TimelineClip clip, List<int> timestampsMs) {
    final Map<int, List<Rect>> detections = {};
    final math.Random random = math.Random(clip.id.hashCode);

    // Generate consistent face movements/positions for simulation
    final int numFaces = (random.nextInt(3) + 1); // 1-3 people in clip
    final List<Offset> faceCenters = List.generate(
      numFaces,
      (i) => Offset(0.2 + (i * 0.3), 0.25 + (i * 0.1)),
    );

    for (final tMs in timestampsMs) {
      final List<Rect> frameBoxes = [];
      final double progress = tMs / math.max(1, clip.duration.inMilliseconds);

      for (int i = 0; i < numFaces; i++) {
        // Face visible in most frames, occasionally missing (gap testing)
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
      // Synthesize 128-d face embedding vector based on spatial center & box proportions
      final Rect firstRect = tr.keyframes.first.rect;
      final double seed = (firstRect.left * 100 + firstRect.top * 50);
      final List<double> vec = List.generate(128, (i) => math.sin(seed + i * 0.1));
      embeddings[tr.id] = vec;
    }
    return embeddings;
  }

  List<Person> _clusterTrackletsToPersons(
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
        // Calculate average similarity to cluster tracklets
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
      final List<FaceTrack> tracks = cluster.map((tr) => FaceTrack(id: tr.id, frames: tr.keyframes)).toList();

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
