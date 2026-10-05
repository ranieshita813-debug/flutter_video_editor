import 'package:flutter_video_editor/core/plugins/plugin_interface.dart';

class VintageFilmPlugin extends EditorPlugin {
  @override
  String get id => 'com.motiongr.plugin.vintage_film';

  @override
  String get name => 'Vintage Film FX';

  @override
  String get version => '1.2.0';

  @override
  String get author => 'motionGr Labs';

  @override
  String get description =>
      'Adds 16mm/35mm film grain, sepia tones, light leaks, and dust scratches.';

  @override
  PluginCategory get category => PluginCategory.filter;

  final Map<String, dynamic> _settings = <String, dynamic>{
    'grainIntensity': 0.65,
    'sepiaTone': 0.40,
    'lightLeaks': true,
    'scratchFrequency': 0.30,
  };

  @override
  Map<String, dynamic> get settings => _settings;

  @override
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    notifyListeners();
  }

  @override
  void onEnable() {}

  @override
  void onDisable() {}
}

class GlitchFxPlugin extends EditorPlugin {
  @override
  String get id => 'com.motiongr.plugin.glitch_fx';

  @override
  String get name => 'Glitch FX Pro';

  @override
  String get version => '2.0.1';

  @override
  String get author => 'motionGr Labs';

  @override
  String get description =>
      'Digital signal corruption, RGB displacement, scanlines, and VHS distortions.';

  @override
  PluginCategory get category => PluginCategory.effect;

  final Map<String, dynamic> _settings = <String, dynamic>{
    'displacement': 0.50,
    'rgbSplit': 0.80,
    'scanlines': true,
    'vhsNoise': 0.40,
  };

  @override
  Map<String, dynamic> get settings => _settings;

  @override
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    notifyListeners();
  }

  @override
  void onEnable() {}

  @override
  void onDisable() {}
}

class AiCaptionPlugin extends EditorPlugin {
  @override
  String get id => 'com.motiongr.plugin.ai_caption';

  @override
  String get name => 'AI Auto Captioning';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'motionGr AI';

  @override
  String get description =>
      'Automatic speech recognition, speech-to-text generation, and animated subtitle cues.';

  @override
  PluginCategory get category => PluginCategory.tool;

  final Map<String, dynamic> _settings = <String, dynamic>{
    'language': 'Auto-detect',
    'fontSize': 16.0,
    'highlightWords': true,
  };

  @override
  Map<String, dynamic> get settings => _settings;

  @override
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    notifyListeners();
  }

  @override
  void onEnable() {}

  @override
  void onDisable() {}
}

class AudioEqProPlugin extends EditorPlugin {
  @override
  String get id => 'com.motiongr.plugin.audio_eq';

  @override
  String get name => 'Audio Equalizer Pro';

  @override
  String get version => '1.5.0';

  @override
  String get author => 'Sound FX Team';

  @override
  String get description =>
      '10-band parametric equalizer, bass boost, vocal clarity, and noise reduction filters.';

  @override
  PluginCategory get category => PluginCategory.audio;

  final Map<String, dynamic> _settings = <String, dynamic>{
    'preset': 'Bass Boost',
    'noiseReduction': 0.70,
    'vocalEnhancer': true,
  };

  @override
  Map<String, dynamic> get settings => _settings;

  @override
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    notifyListeners();
  }

  @override
  void onEnable() {}

  @override
  void onDisable() {}
}

class Camera3dPlugin extends EditorPlugin {
  @override
  String get id => 'com.motiongr.plugin.camera_3d';

  @override
  String get name => '3D Camera FX Engine';

  @override
  String get version => '2.1.0';

  @override
  String get author => 'Motion3D Lab';

  @override
  String get description =>
      '3D spatial camera tracking, depth of field, tilt-shift, and smooth virtual dolly motions.';

  @override
  PluginCategory get category => PluginCategory.camera;

  final Map<String, dynamic> _settings = <String, dynamic>{
    'fov': 60.0,
    'focalLength': 35.0,
    'depthOfField': true,
    'motionBlur': 0.50,
  };

  @override
  Map<String, dynamic> get settings => _settings;

  @override
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    notifyListeners();
  }

  @override
  void onEnable() {}

  @override
  void onDisable() {}
}
