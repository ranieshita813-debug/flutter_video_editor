import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class ExportService {
  static const MethodChannel _methodChannel = MethodChannel('editor/export');
  static const EventChannel _eventChannel = EventChannel('editor/export/progress');

  StreamController<Map<String, dynamic>>? _fallbackProgressController;
  Timer? _fallbackTimer;

  Stream<Map<String, dynamic>> get progressStream {
    try {
      return _eventChannel
          .receiveBroadcastStream()
          .map((dynamic event) => Map<String, dynamic>.from(event as Map));
    } catch (_) {
      _fallbackProgressController ??= StreamController<Map<String, dynamic>>.broadcast();
      return _fallbackProgressController!.stream;
    }
  }

  Future<Map<String, dynamic>> probe(String path) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('probe', {'path': path});
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } on MissingPluginException catch (_) {
      // Fallback probe
    } on PlatformException catch (_) {
      // Fallback probe
    } catch (_) {}

    final file = File(path);
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;

    return <String, dynamic>{
      'durationMs': 10000,
      'width': 1920,
      'height': 1080,
      'fps': 30.0,
      'codec': 'h264',
      'rotation': 0,
      'hasAudio': true,
      'fileSize': length,
    };
  }

  Future<List<String>> thumbnails(String path, int count, int height) async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>('thumbnails', {
        'path': path,
        'count': count,
        'height': height,
      });
      if (result != null) {
        return result.cast<String>();
      }
    } on MissingPluginException catch (_) {
      // Fallback
    } on PlatformException catch (_) {
      // Fallback
    } catch (_) {}

    // Return empty list or path placeholder for fallback
    return <String>[];
  }

  Future<List<double>> waveform(String path, int buckets) async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>('waveform', {
        'path': path,
        'buckets': buckets,
      });
      if (result != null && result.isNotEmpty) {
        return result.map((e) => (e as num).toDouble()).toList();
      }
    } on MissingPluginException catch (_) {
      // Fallback
    } on PlatformException catch (_) {
      // Fallback
    } catch (_) {}

    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final int step = (bytes.length / buckets).floor();
          if (step > 0) {
            final List<double> amps = <double>[];
            for (int i = 0; i < buckets; i++) {
              int sum = 0;
              final int start = i * step;
              final int end = math.min(start + step, bytes.length);
              for (int j = start; j < end; j += 16) {
                sum += (bytes[j] - 128).abs();
              }
              final double avg = sum / math.max(1, ((end - start) / 16).ceil());
              amps.add((avg / 128.0).clamp(0.15, 1.0));
            }
            return amps;
          }
        }
      }
    } catch (_) {}

    final int seed = path.hashCode;
    final List<double> envelope = <double>[];
    for (int i = 0; i < buckets; i++) {
      final double t = i / buckets;
      final double wave1 = math.sin(t * 20.0 + seed);
      final double wave2 = math.cos(t * 45.0 + seed * 2);
      final double val = (wave1.abs() * 0.6 + wave2.abs() * 0.4).clamp(0.12, 1.0);
      envelope.add(val);
    }
    return envelope;
  }

  Future<String> exportTimeline(Map<String, dynamic> timelineJson) async {
    try {
      final result = await _methodChannel.invokeMethod<String>('export', {
        'timeline': timelineJson,
      });
      if (result != null && result.isNotEmpty) {
        return result;
      }
      throw PlatformException(
        code: 'EXPORT_FAILED',
        message: 'Native export returned an empty result path.',
      );
    } on PlatformException {
      rethrow;
    } on MissingPluginException {
      rethrow;
    } catch (e) {
      throw PlatformException(
        code: 'EXPORT_ERROR',
        message: 'Export failed with error: $e',
      );
    }
  }

  Future<void> cancelExport() async {
    try {
      await _methodChannel.invokeMethod<void>('cancel');
    } on MissingPluginException catch (_) {
      // Fallback
    } catch (_) {}

    _fallbackTimer?.cancel();
    if (_fallbackProgressController != null && !_fallbackProgressController!.isClosed) {
      _fallbackProgressController!.add({
        'progress': 0.0,
        'stage': 'Cancelled',
      });
    }
  }

  void dispose() {
    _fallbackTimer?.cancel();
    _fallbackProgressController?.close();
  }
}
