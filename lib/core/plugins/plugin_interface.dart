import 'package:flutter/foundation.dart';

enum PluginCategory {
  effect('Effects'),
  transition('Transitions'),
  filter('Filters'),
  audio('Audio Tools'),
  camera('3D Camera'),
  tool('Tools');

  const PluginCategory(this.label);
  final String label;
}

abstract class EditorPlugin extends ChangeNotifier {
  String get id;
  String get name;
  String get version;
  String get author;
  String get description;
  PluginCategory get category;

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;

  void setEnabled(bool enabled) {
    if (_isEnabled != enabled) {
      _isEnabled = enabled;
      if (_isEnabled) {
        onEnable();
      } else {
        onDisable();
      }
      notifyListeners();
    }
  }

  void onEnable();
  void onDisable();

  Map<String, dynamic> get settings;
  void updateSetting(String key, dynamic value);
}
