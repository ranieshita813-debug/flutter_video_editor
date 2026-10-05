import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/error/app_exceptions.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';

class ErrorHandler {
  ErrorHandler._();

  static void handleError(
    Object error, {
    StackTrace? stackTrace,
    String tag = 'ErrorHandler',
    BuildContext? context,
  }) {
    AppLogger.error(
      error.toString(),
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );

    if (context != null && context.mounted) {
      final message = getUserFriendlyMessage(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static String getUserFriendlyMessage(Object error) {
    if (error is AppException) {
      return error.message;
    } else if (error is FormatException) {
      return 'Invalid data format encountered.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }
}
