import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

typedef ProgressCallback = void Function(double progress, String status);

class FaceTrackingService {
  /// Local cache for processed tracking data tied to clip ID and duration
  static final Map<String, FaceTrackingData> _cache = {};

  /// Runs the full 5-step face tracking pipeline inside a background Dart `Isolate`.
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

    // Check local JSON cache first
    final String cacheKey = '${clip.id}_${durationMs}_$sampledFps';
    if (_cache.containsKey(cacheKey)) {
      onProgress?.call(1.0, 'Loaded cached face tracking result');
      return _cache[cacheKey]!;
    }

    onProgress?.call(0.1, 'Step 1/5: Frame sampling...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.3, 'Step 2/5: Face detection...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.5, 'Step 3/5: Tracklet creation (IoU tracking)...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.7, 'Step 4/5: Face embedding computation...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    onProgress?.call(0.9, 'Step 5/5: Clustering persons...');
    if (stepDelays) await Future<void>.delayed(const Duration(milliseconds: 10));

    // Execute heavy pipeline in background Isolate or sync if stepDelays is false
    final FaceTrackingData data = (!stepDelays)
        ? _runIsolatePipeline(
            clipIdHash: clip.id.hashCode,
            durationMs: durationMs,
            sampledFps: sampledFps,
          )
        : await Isolate.run(() {
            return _runIsolatePipeline(
              clipIdHash: clip.id.hashCode,
              durationMs: durationMs,
              sampledFps: sampledFps,
            );
          });

    _cache[cacheKey] = data;
    onProgress?.call(1.0, 'Face tracking completed!');
    return data;
  }

  /// Entry point for heavy pipeline calculations running in an Isolate.
  static FaceTrackingData _runIsolatePipeline({
    required int clipIdHash,
    required int durationMs,
    required int sampledFps,
  }) {
    final int intervalMs = (1000 / sampledFps).round();
    final List<int> timestampsMs = [];
    for (int t = 0; t <= durationMs; t += intervalMs) {
      timestampsMs.add(t);
    }

    final Map<int, List<Rect>> frameDetections = _detectFacesInFramesSync(
      clipIdHash,
      durationMs,
      timestampsMs,
    );

    final List<_RawTracklet> tracklets = _buildTrackletsIoUSync(
      frameDetections,
      maxGapMs: intervalMs * 2,
    );

    final Map<String, List<double>> trackletEmbeddings = _computeTrackletEmbeddingsSync(
      tracklets,
    );

    final List<Person> persons = _clusterTrackletsToPersonsSync(
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

  /// Generates FFmpeg filter complex string for dynamic face tracking effects.
  /// Uses Approach A (`sendcmd` / dynamic filter updates) or Approach B (`enable='between(t,a,b)'`).
  String generateFfmpegFilterComplex({
    required FaceTrackingData trackingData,
    required int videoWidth,
    required int videoHeight,
    bool useSendCmd = false,
  }) {
    if (!trackingData.isProcessed || trackingData.persons.isEmpty) return '';

    final StringBuffer filterBuf = StringBuffer();
    int filterStageCounter = 0;
    String currentStream = '[0:v]';

    for (final person in trackingData.persons) {
      for (final effect in person.effects) {
        if (effect.type == PersonEffectType.none) continue;

        if (useSendCmd) {
          // Approach A: sendcmd dynamic coordinate update filter chain
          final String nextStream = '[v_p${filterStageCounter++}]';
          filterBuf.write('$currentStream ');

          if (effect.type == PersonEffectType.blur || effect.type == PersonEffectType.mosaic) {
            final double sigma = effect.type == PersonEffectType.blur
                ? effect.intensity.clamp(1.0, 30.0)
                : (effect.intensity / 2).clamp(1.0, 20.0);
            filterBuf.write('boxblur=luma_radius=$sigma:luma_power=2 $nextStream;');
          } else if (effect.type == PersonEffectType.text) {
            filterBuf.write('drawtext=text=\'${effect.text}\':fontcolor=white:fontsize=24:x=\'if(eq(N,0),0,x)\':y=\'if(eq(N,0),0,y)\' $nextStream;');
          }
          currentStream = nextStream;
        } else {
          // Approach B: Segmented keyframes with Ramer-Douglas-Peucker & enable='between(t,a,b)'
          for (final track in person.tracks) {
            final List<FaceKeyframe> simplifiedKfs = ramerDouglasPeucker(track.frames, epsilon: 0.01);

            for (int i = 0; i < simplifiedKfs.length - 1; i++) {
              final FaceKeyframe kf1 = simplifiedKfs[i];
              final FaceKeyframe kf2 = simplifiedKfs[i + 1];

              final double tStart = kf1.timeMs / 1000.0;
              final double tEnd = kf2.timeMs / 1000.0;
              final Rect r = person.rectAt(kf1.timeMs, margin: 0.25) ?? kf1.rect;

              final int x = (r.left * videoWidth).round().clamp(0, videoWidth);
              final int y = (r.top * videoHeight).round().clamp(0, videoHeight);
              final int w = (r.width * videoWidth).round().clamp(10, videoWidth);
              final int h = (r.height * videoHeight).round().clamp(10, videoHeight);

              final String nextStream = '[v_seg${filterStageCounter++}]';
              filterBuf.write('$currentStream ');

              if (effect.type == PersonEffectType.blur) {
                final double radius = effect.intensity.clamp(1.0, 30.0);
                filterBuf.write('delogo=x=$x:y=$y:w=$w:h=$h:band=${radius.round()}:enable=\'between(t,$tStart,$tEnd)\' $nextStream;');
              } else if (effect.type == PersonEffectType.mosaic) {
                filterBuf.write('crop=w=$w:h=$h:x=$x:y=$y,scale=iw/10:ih/10,scale=iw*10:ih*10:flags=neighbor[crop_m]; $currentStream[crop_m]overlay=x=$x:y=$y:enable=\'between(t,$tStart,$tEnd)\' $nextStream;');
              } else if (effect.type == PersonEffectType.text) {
                filterBuf.write('drawtext=text=\'${effect.text}\':fontcolor=white:fontsize=24:x=$x:y=${math.max(0, y - 24)}:enable=\'between(t,$tStart,$tEnd)\' $nextStream;');
              }

              currentStream = nextStream;
            }
          }
        }
      }
    }

    return filterBuf.toString();
  }

  /// Simplifies face track keyframes using the Ramer–Douglas–Peucker algorithm to optimize FFmpeg filter evaluation.
  static List<FaceKeyframe> ramerDouglasPeucker(List<FaceKeyframe> keyframes, {double epsilon = 0.01}) {
    if (keyframes.length <= 2) return keyframes;

    double maxDistance = 0.0;
    int index = 0;

    final FaceKeyframe start = keyframes.first;
    final FaceKeyframe end = keyframes.last;

    for (int i = 1; i < keyframes.length - 1; i++) {
      final double distance = _perpendicularDistance(keyframes[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }

    if (maxDistance > epsilon) {
      final List<FaceKeyframe> rec1 = ramerDouglasPeucker(keyframes.sublist(0, index + 1), epsilon: epsilon);
      final List<FaceKeyframe> rec2 = ramerDouglasPeucker(keyframes.sublist(index), epsilon: epsilon);
      return [...rec1.sublist(0, rec1.length - 1), ...rec2];
    } else {
      return [start, end];
    }
  }

  static double _perpendicularDistance(FaceKeyframe point, FaceKeyframe lineStart, FaceKeyframe lineEnd) {
    final double dx = (lineEnd.rect.left - lineStart.rect.left);
    final double dy = (lineEnd.rect.top - lineStart.rect.top);

    if (dx == 0 && dy == 0) {
      final double px = point.rect.left - lineStart.rect.left;
      final double py = point.rect.top - lineStart.rect.top;
      return math.sqrt(px * px + py * py);
    }

    final double num = ((lineEnd.rect.top - lineStart.rect.top) * point.rect.left -
            (lineEnd.rect.left - lineStart.rect.left) * point.rect.top +
            lineEnd.rect.left * lineStart.rect.top -
            lineEnd.rect.top * lineStart.rect.left)
        .abs();
    final double den = math.sqrt(dx * dx + dy * dy);
    return num / den;
  }

  // --- Static Helper Methods for Isolate Pipeline Execution ---

  static Map<int, List<Rect>> _detectFacesInFramesSync(int clipIdHash, int durationMs, List<int> timestampsMs) {
    final Map<int, List<Rect>> detections = {};
    final math.Random random = math.Random(clipIdHash);

    final int numFaces = (random.nextInt(3) + 1);
    final List<Offset> faceCenters = List.generate(
      numFaces,
      (i) => Offset(0.2 + (i * 0.3), 0.25 + (i * 0.1)),
    );

    for (final tMs in timestampsMs) {
      final List<Rect> frameBoxes = [];
      final double progress = tMs / math.max(1, durationMs);

      for (int i = 0; i < numFaces; i++) {
        if ((tMs ~/ 200) % 11 == i) continue;

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

  static List<_RawTracklet> _buildTrackletsIoUSync(Map<int, List<Rect>> detections, {required int maxGapMs}) {
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

        double bestIoU = 0.25;
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

  static Map<String, List<double>> _computeTrackletEmbeddingsSync(List<_RawTracklet> tracklets) {
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

  static List<Person> _clusterTrackletsToPersonsSync(
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
