import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_video_editor/app.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

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
