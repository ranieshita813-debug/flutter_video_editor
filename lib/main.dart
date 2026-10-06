import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_video_editor/app.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/features/editor/pages/editor_page.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Wire real video thumbnail generator and real audio waveform decoder
    thumbGenerator = (String path, int timeMs, int maxWidth) async {
      try {
        final thumbs = await ExportService().thumbnails(path, 1, maxWidth);
        if (thumbs.isNotEmpty) {
          final file = File(thumbs.first);
          if (await file.exists()) {
            return await file.readAsBytes();
          }
        }
      } catch (_) {}
      return null;
    };

    waveformDecoder = (String path, int bars) async {
      return await ExportService().waveform(path, bars);
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
