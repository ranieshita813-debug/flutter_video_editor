import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/plugins/builtin_plugins.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';

void main() {
  group('PluginManager Unit Tests', () {
    late PluginManager manager;

    setUp(() {
      manager = PluginManager();
    });

    test('Initializes with default built-in plugins', () {
      expect(manager.plugins.length, greaterThanOrEqualTo(5));
      expect(manager.activePlugins.length, equals(manager.plugins.length));
    });

    test('Toggle plugin updates active state', () {
      final plugin = manager.plugins.first;
      final initialId = plugin.id;

      expect(plugin.isEnabled, isTrue);
      manager.togglePlugin(initialId);
      expect(plugin.isEnabled, isFalse);

      manager.togglePlugin(initialId);
      expect(plugin.isEnabled, isTrue);
    });

    test('Registers and unregisters custom plugin', () {
      final customPlugin = VintageFilmPlugin();
      final count = manager.plugins.length;

      manager.unregisterPlugin(customPlugin.id);
      expect(manager.plugins.length, equals(count - 1));

      manager.registerPlugin(customPlugin);
      expect(manager.plugins.length, equals(count));
    });
  });
}
