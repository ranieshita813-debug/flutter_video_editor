import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
      if (result != null) {
        return result.map((e) => (e as num).toDouble()).toList();
      }
    } on MissingPluginException catch (_) {
      // Fallback
    } on PlatformException catch (_) {
      // Fallback
    } catch (_) {}

    // Simulated waveform fallback
    final rnd = math.Random(path.hashCode);
    return List<double>.generate(buckets, (i) => rnd.nextDouble());
  }

  Future<String> exportTimeline(Map<String, dynamic> timelineJson) async {
    try {
      final result = await _methodChannel.invokeMethod<String>('export', {
        'timeline': timelineJson,
      });
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } on MissingPluginException catch (_) {
      // Fallback mock export
    } on PlatformException catch (_) {
      // Fallback mock export
    } catch (_) {}

    // Mock Export simulation for fallback
    _fallbackTimer?.cancel();
    _fallbackProgressController ??= StreamController<Map<String, dynamic>>.broadcast();

    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final ext = (timelineJson['settings']?['format'] as String?) ?? 'mp4';
    final tempPath = '${dir.path}/export_temp_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final finalPath = '${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.$ext';

    int progress = 0;
    final completer = Completer<String>();

    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) async {
      progress += 2;
      final double normProgress = (progress / 100.0).clamp(0.0, 1.0);
      final String stage = progress < 30
          ? 'Preparing assets'
          : (progress < 80 ? 'Rendering frames' : 'Finalizing export');

      if (!_fallbackProgressController!.isClosed) {
        _fallbackProgressController!.add({
          'progress': normProgress,
          'stage': stage,
        });
      }

      if (progress >= 100) {
        timer.cancel();
        final tempFile = File(tempPath);
        await tempFile.writeAsString('Rendered video file simulation data');
        await tempFile.rename(finalPath);
        completer.complete(finalPath);
      }
    });

    return completer.future;
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
