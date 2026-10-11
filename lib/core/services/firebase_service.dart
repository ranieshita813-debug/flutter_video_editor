import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';

class FirebaseService {
  FirebaseService._internal();
  static final FirebaseService instance = FirebaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (Firebase.apps.isNotEmpty) {
        _isInitialized = true;
        AppLogger.info('Firebase already initialized.', tag: 'FirebaseService');
        return true;
      }

      await Firebase.initializeApp();
      _isInitialized = true;
      AppLogger.info('Firebase initialized successfully.', tag: 'FirebaseService');
      return true;
    } catch (e, stack) {
      _isInitialized = false;
      AppLogger.warning(
        'Firebase initialization skipped or failed: $e. Operating in local/fallback mode.',
        tag: 'FirebaseService',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }
}
