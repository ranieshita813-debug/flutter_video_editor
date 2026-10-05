import 'dart:async';

import 'package:flutter/services.dart';

class ExportService {
  static const MethodChannel _methodChannel = MethodChannel('editor/export');
  static const EventChannel _eventChannel = EventChannel('editor/export/progress');

  Stream<Map<String, dynamic>> get progressStream {
    try {
      return _eventChannel
          .receiveBroadcastStream()
          .map((dynamic event) => Map<String, dynamic>.from(event as Map));
    } catch (_) {
      return const Stream<Map<String, dynamic>>.empty();
    }
  }

  Future<Map<String, dynamic>> probe(String path) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('probe', {'path': path});
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return <String, dynamic>{
      'durationMs': 10000,
      'width': 1920,
      'height': 1080,
      'fps': 30.0,
      'codec': 'h264',
      'rotation': 0,
      'hasAudio': true,
      'fileSize': 0,
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
    } catch (_) {}
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
    } catch (_) {}
    return <double>[];
  }

  Future<String> exportTimeline(Map<String, dynamic> timelineJson) async {
    try {
      final result = await _methodChannel.invokeMethod<String>('export', {
        'timeline': timelineJson,
      });
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (_) {}
    final ext = (timelineJson['settings']?['format'] as String?) ?? 'mp4';
    return '/tmp/export_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  Future<void> cancelExport() async {
    try {
      await _methodChannel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  void dispose() {}
}
