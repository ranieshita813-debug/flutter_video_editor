import 'package:flutter/foundation.dart';
import 'package:flutter_video_editor/core/plugins/builtin_plugins.dart';
import 'package:flutter_video_editor/core/plugins/plugin_interface.dart';

class PluginManager extends ChangeNotifier {
  PluginManager() {
    _registerBuiltins();
  }

  final List<EditorPlugin> _plugins = <EditorPlugin>[];

  List<EditorPlugin> get plugins => List<EditorPlugin>.unmodifiable(_plugins);

  List<EditorPlugin> get activePlugins =>
      _plugins.where((p) => p.isEnabled).toList();

  void _registerBuiltins() {
    registerPlugin(VintageFilmPlugin());
    registerPlugin(GlitchFxPlugin());
    registerPlugin(AiCaptionPlugin());
    registerPlugin(AudioEqProPlugin());
    registerPlugin(Camera3dPlugin());
  }

  void registerPlugin(EditorPlugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) return;
    _plugins.add(plugin);
    plugin.addListener(notifyListeners);
    notifyListeners();
  }

  void unregisterPlugin(String id) {
    final idx = _plugins.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final plugin = _plugins.removeAt(idx);
      plugin.removeListener(notifyListeners);
      notifyListeners();
    }
  }

  void togglePlugin(String id) {
    final plugin = _plugins.firstWhere((p) => p.id == id);
    plugin.setEnabled(!plugin.isEnabled);
    notifyListeners();
  }

  EditorPlugin? getPlugin(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
