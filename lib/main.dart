import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_video_editor/app.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/editor/widgets/fx_shader.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await FxShaders.preload();

    // Wire real video thumbnail generator and real audio waveform decoder
    thumbGenerator = (String path, int timeMs, int maxWidth) async {
      try {
        final bytes = await ExportService().frameAt(path, timeMs, maxHeight: maxWidth);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}
      return null;
    };

    waveformDecoder = (String path, int bars) async {
      try {
        return await ExportService().waveform(path, bars);
      } catch (e) {
        AppLogger.warning('Waveform decoding failed for $path: $e');
        return <double>[];
      }
    };

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      AppLogger.error(
        details.exceptionAsString(),
        tag: 'FlutterError',
        error: details.exception,
        stackTrace: details.stack,
      );
    };

    runApp(const VideoEditorApp());
  }, (Object error, StackTrace stackTrace) {
    AppLogger.error(
      'Unhandled zoned error',
      tag: 'MainZone',
      error: error,
      stackTrace: stackTrace,
    );
  });
}
