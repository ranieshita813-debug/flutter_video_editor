import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/plugins/plugin_interface.dart';
import 'package:flutter_video_editor/core/plugins/plugin_manager.dart';

const Color _sheet = Color(0xFF0E0E11);
const Color _card = Color(0xFF1A1A1F);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);

class PluginsSheet extends StatefulWidget {
  const PluginsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PluginsSheet(),
    );
  }

  @override
  State<PluginsSheet> createState() => _PluginsSheetState();
}

class _PluginsSheetState extends State<PluginsSheet> {
  PluginCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<PluginManager>();
    final allPlugins = manager.plugins;

    final filtered = _selectedCategory == null
        ? allPlugins
        : allPlugins.where((p) => p.category == _selectedCategory).toList();

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text(
                  'Plug-in Manager',
                  style: TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  _categoryChip('All', _selectedCategory == null, () {
                    setState(() => _selectedCategory = null);
                  }),
                  for (final cat in PluginCategory.values)
                    _categoryChip(
                      cat.label,
                      _selectedCategory == cat,
                      () => setState(() => _selectedCategory = cat),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final plugin = filtered[index];
                  return _PluginCard(plugin: plugin, manager: manager);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : _card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : _text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin, required this.manager});

  final EditorPlugin plugin;
  final PluginManager manager;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: plugin.isEnabled ? Colors.white38 : Colors.transparent,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _track,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.extension_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          plugin.name,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _track,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v${plugin.version}',
                            style: const TextStyle(
                                color: _muted, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plugin.category.label}  ·  By ${plugin.author}',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: plugin.isEnabled,
                onChanged: (_) => manager.togglePlugin(plugin.id),
                activeThumbColor: Colors.black,
                activeTrackColor: Colors.white,
                inactiveThumbColor: _muted,
                inactiveTrackColor: _track,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plugin.description,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.3),
          ),
        ],
      ),
    );
  }
}
