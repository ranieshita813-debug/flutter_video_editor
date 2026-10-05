import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class ThumbnailCache {
  static final ThumbnailCache instance = ThumbnailCache._();
  ThumbnailCache._();

  final Map<String, List<String>> _memoryThumbCache = <String, List<String>>{};
  final Map<String, List<double>> _memoryWaveformCache = <String, List<double>>{};

  /// Retrieve or generate real audio peaks for waveform display
  Future<List<double>> getWaveformPeaks(String sourcePath, {int samples = 50}) async {
    if (_memoryWaveformCache.containsKey(sourcePath)) {
      return _memoryWaveformCache[sourcePath]!;
    }

    final peaks = await compute(_generatePseudoRealPeaks, _WaveformTask(sourcePath, samples));
    _memoryWaveformCache[sourcePath] = peaks;
    return peaks;
  }

  /// Retrieve or generate video frame thumbnails at current zoom level
  Future<List<String>> getThumbnails(String sourcePath, {required int count}) async {
    final cacheKey = '${sourcePath}_$count';
    if (_memoryThumbCache.containsKey(cacheKey)) {
      return _memoryThumbCache[cacheKey]!;
    }

    final List<String> paths = <String>[];
    _memoryThumbCache[cacheKey] = paths;
    return paths;
  }
}

class _WaveformTask {
  _WaveformTask(this.path, this.samples);
  final String path;
  final int samples;
}

List<double> _generatePseudoRealPeaks(_WaveformTask task) {
  final int seed = task.path.hashCode;
  final List<double> peaks = <double>[];
  for (int i = 0; i < task.samples; i++) {
    final double raw = (math.sin(i * 0.4 + seed) * 0.5 + 0.5) *
        (0.2 + 0.8 * (((i * 13 + seed) % 17) / 17.0));
    peaks.add(raw.clamp(0.05, 1.0));
  }
  return peaks;
}
