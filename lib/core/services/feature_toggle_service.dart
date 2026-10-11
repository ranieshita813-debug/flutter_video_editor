import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/services/firebase_service.dart';

class FeatureToggleService extends ChangeNotifier {
  FeatureToggleService._internal() {
    _init();
  }
  static final FeatureToggleService instance = FeatureToggleService._internal();

  final Map<String, bool> _featureFlags = <String, bool>{
    'effects': true,
    'filters': true,
    'chroma_key': true,
    'auto_captions': true,
    'elements': true,
    'stickers': true,
    'draw': true,
    'speed': true,
    'adjust': true,
    'track': true,
  };

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  Map<String, bool> get featureFlags => Map<String, bool>.unmodifiable(_featureFlags);

  FirebaseFirestore? get _db {
    if (FirebaseService.instance.isInitialized) {
      try {
        return FirebaseFirestore.instance;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<File> get _configFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/feature_flags.json');
  }

  Future<void> _init() async {
    await _loadLocal();
    await _syncRemote();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _loadLocal() async {
    try {
      final file = await _configFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        json.forEach((key, val) {
          if (val is bool) {
            _featureFlags[key] = val;
          }
        });
      }
    } catch (e) {
      AppLogger.warning('Failed loading local feature flags: $e', tag: 'FeatureToggleService');
    }
  }

  Future<void> _saveLocal() async {
    try {
      final file = await _configFile;
      await file.writeAsString(jsonEncode(_featureFlags));
    } catch (e) {
      AppLogger.error('Failed saving local feature flags: $e', tag: 'FeatureToggleService');
    }
  }

  Future<void> _syncRemote() async {
    final firestore = _db;
    if (firestore == null) return;

    try {
      final doc = await firestore.collection('settings').doc('feature_flags').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        data.forEach((key, val) {
          if (val is bool) {
            _featureFlags[key] = val;
          }
        });
        await _saveLocal();
        AppLogger.info('Feature flags synced with Firebase Cloud', tag: 'FeatureToggleService');
      }
    } catch (e) {
      AppLogger.warning('Remote feature flag sync error: $e', tag: 'FeatureToggleService');
    }
  }

  bool isFeatureEnabled(String featureId) {
    return _featureFlags[featureId] ?? true;
  }

  Future<void> setFeatureEnabled(String featureId, bool enabled) async {
    _featureFlags[featureId] = enabled;
    notifyListeners();
    await _saveLocal();

    final firestore = _db;
    if (firestore != null) {
      try {
        await firestore.collection('settings').doc('feature_flags').set(
          <String, dynamic>{featureId: enabled},
          SetOptions(merge: true),
        );
      } catch (e) {
        AppLogger.warning('Failed to push feature flag to Firestore: $e', tag: 'FeatureToggleService');
      }
    }
  }

  Future<void> resetToDefaults() async {
    _featureFlags.updateAll((key, val) => true);
    notifyListeners();
    await _saveLocal();
  }
}
