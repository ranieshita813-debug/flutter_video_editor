import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';

class ShaderDatabaseService {
  ShaderDatabaseService._internal();
  static final ShaderDatabaseService instance = ShaderDatabaseService._internal();

  final Map<String, ShaderEffect> _effectsRegistry = <String, ShaderEffect>{};
  final Map<String, String> _shaderCodeCache = <String, String>{};
  bool _isInitialized = false;
  File? _registryFile;
  Directory? _cacheDir;

  bool get isInitialized => _isInitialized;

  Future<void> initialize({List<ShaderEffect>? seeds}) async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDocDir.path}/effects_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      _registryFile = File('${appDocDir.path}/effects_registry.json');
      if (await _registryFile!.exists()) {
        final content = await _registryFile!.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
          for (final item in jsonList) {
            final effect = ShaderEffect.fromJson(Map<String, dynamic>.from(item as Map));
            _effectsRegistry[effect.id] = effect;
          }
        }
      }

      if (seeds != null) {
        for (final seed in seeds) {
          if (!_effectsRegistry.containsKey(seed.id)) {
            _effectsRegistry[seed.id] = seed;
          } else {
            final existing = _effectsRegistry[seed.id]!;
            _effectsRegistry[seed.id] = seed.copyWith(
              isFavorite: existing.isFavorite,
              isDownloaded: existing.isDownloaded || seed.isDownloaded,
              localCachePath: existing.localCachePath ?? seed.localCachePath,
            );
          }

          if (seed.shaderSource.isNotEmpty) {
            _shaderCodeCache[seed.id] = seed.shaderSource;
          }
        }
      }

      await _saveRegistry();
      _isInitialized = true;
      AppLogger.info('ShaderDatabaseService initialized with ${_effectsRegistry.length} effects',
          tag: 'ShaderDatabaseService');
    } catch (e, stack) {
      AppLogger.error('Failed to initialize ShaderDatabaseService',
          tag: 'ShaderDatabaseService', error: e, stackTrace: stack);
      if (seeds != null) {
        for (final seed in seeds) {
          _effectsRegistry[seed.id] = seed;
        }
      }
      _isInitialized = true;
    }
  }

  Future<void> _saveRegistry() async {
    try {
      if (_registryFile == null) return;
      final list = _effectsRegistry.values.map((e) => e.toJson()).toList();
      await _registryFile!.writeAsString(jsonEncode(list));
    } catch (e, stack) {
      AppLogger.error('Failed to save effects registry',
          tag: 'ShaderDatabaseService', error: e, stackTrace: stack);
    }
  }

  List<ShaderEffect> fetchAllEffects() {
    return _effectsRegistry.values.toList();
  }

  List<ShaderEffect> fetchByCategory(ShaderEffectCategory category) {
    if (category == ShaderEffectCategory.all) {
      return fetchAllEffects();
    }
    return _effectsRegistry.values
        .where((e) => e.category == category)
        .toList();
  }

  List<ShaderEffect> fetchFavorites() {
    return _effectsRegistry.values
        .where((e) => e.isFavorite)
        .toList();
  }

  List<ShaderEffect> fetchDownloaded() {
    return _effectsRegistry.values
        .where((e) => e.isDownloaded)
        .toList();
  }

  ShaderEffect? getEffectById(String id) {
    return _effectsRegistry[id];
  }

  Future<ShaderEffect?> toggleFavorite(String effectId) async {
    final effect = _effectsRegistry[effectId];
    if (effect == null) return null;

    final updated = effect.copyWith(isFavorite: !effect.isFavorite);
    _effectsRegistry[effectId] = updated;
    await _saveRegistry();
    return updated;
  }

  Future<String> cacheShaderFile(String effectId, String shaderSource) async {
    _shaderCodeCache[effectId] = shaderSource;

    if (_cacheDir != null) {
      final file = File('${_cacheDir!.path}/$effectId.glsl');
      await file.writeAsString(shaderSource);
      return file.path;
    }
    return '';
  }

  Future<String> getShaderSource(String effectId) async {
    if (_shaderCodeCache.containsKey(effectId)) {
      return _shaderCodeCache[effectId]!;
    }

    final effect = _effectsRegistry[effectId];
    if (effect != null && effect.shaderSource.isNotEmpty) {
      _shaderCodeCache[effectId] = effect.shaderSource;
      return effect.shaderSource;
    }

    if (_cacheDir != null) {
      final file = File('${_cacheDir!.path}/$effectId.glsl');
      if (await file.exists()) {
        final code = await file.readAsString();
        _shaderCodeCache[effectId] = code;
        return code;
      }
    }

    return '';
  }

  Future<ShaderEffect> saveDownloadedEffect(ShaderEffect effect, String shaderSource) async {
    final filePath = await cacheShaderFile(effect.id, shaderSource);

    final updated = effect.copyWith(
      isDownloaded: true,
      localCachePath: filePath.isNotEmpty ? filePath : effect.localCachePath,
      shaderSource: shaderSource,
      updatedAt: DateTime.now(),
    );

    _effectsRegistry[effect.id] = updated;
    await _saveRegistry();
    AppLogger.info('Downloaded and saved effect ${effect.name} (${effect.id})',
        tag: 'ShaderDatabaseService');
    return updated;
  }

  Future<bool> removeDownloadedEffect(String effectId) async {
    final effect = _effectsRegistry[effectId];
    if (effect == null) return false;

    if (effect.type == EffectType.builtIn) {
      final updated = effect.copyWith(isDownloaded: false);
      _effectsRegistry[effectId] = updated;
      await _saveRegistry();
      return true;
    }

    if (effect.localCachePath != null && effect.localCachePath!.isNotEmpty) {
      try {
        final file = File(effect.localCachePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _effectsRegistry.remove(effectId);
    _shaderCodeCache.remove(effectId);
    await _saveRegistry();
    return true;
  }

  void resetMemoryRegistry() {
    _effectsRegistry.clear();
    _shaderCodeCache.clear();
    _isInitialized = false;
  }
}
