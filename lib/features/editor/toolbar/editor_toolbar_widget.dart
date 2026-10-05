import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/toolbar/editor_toolbar.dart';

class EditorToolbarWidget extends StatefulWidget {
  const EditorToolbarWidget({super.key, required this.onOpenTool});
  final ValueChanged<EditorTool> onOpenTool;

  @override
  State<EditorToolbarWidget> createState() => _EditorToolbarWidgetState();
}

class _EditorToolbarWidgetState extends State<EditorToolbarWidget> {
  ToolCategory _selectedCategory = ToolCategory.edit;

  void _tap() => HapticFeedback.selectionClick();

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final sel = editor.selectedClip;
    final bool canSplit = sel != null && editor.playhead > sel.start && editor.playhead < sel.end;

    return Container(
      color: EditorTokens.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Category segmented tabs
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: ToolCategory.values.map((cat) {
                  final bool active = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        _categoryName(cat),
                        style: TextStyle(
                          fontSize: EditorTokens.minFontSize,
                          color: active ? EditorTokens.bg : EditorTokens.text,
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: active,
                      selectedColor: EditorTokens.text,
                      backgroundColor: EditorTokens.elevated,
                      onSelected: (val) {
                        if (val) {
                          _tap();
                          setState(() => _selectedCategory = cat);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: EditorTokens.border),
            // Tools list
            SizedBox(
              height: 60,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: <Widget>[
                    if (sel != null) ...<Widget>[
                      _actionItem(Icons.content_cut_rounded, 'Split', canSplit ? editor.splitSelectedClip : null),
                      _actionItem(Icons.delete_outline_rounded, 'Delete', () {
                        editor.deleteSelectedClip();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Deleted clip'),
                            action: SnackBarAction(
                              label: 'Undo',
                              textColor: EditorTokens.text,
                              onPressed: editor.undo,
                            ),
                          ),
                        );
                      }),
                      _actionItem(Icons.copy_rounded, 'Duplicate', editor.duplicateSelectedClip),
                      _actionItem(Icons.content_copy_rounded, 'Copy', editor.copySelectedClip),
                      _actionItem(Icons.content_paste_rounded, 'Paste', editor.pasteClip),
                      _actionItem(Icons.ac_unit_rounded, 'Freeze', editor.freezeFrame),
                      _actionItem(Icons.replay_rounded, 'Reverse', editor.toggleReverse),
                      Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 4), color: EditorTokens.border),
                    ],
                    for (final tool in EditorTool.values.where((t) => t.category == _selectedCategory))
                      _toolItem(tool),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryName(ToolCategory cat) {
    switch (cat) {
      case ToolCategory.edit:
        return 'Edit';
      case ToolCategory.audio:
        return 'Audio';
      case ToolCategory.textAndStickers:
        return 'Text & Stickers';
      case ToolCategory.effects:
        return 'Effects';
      case ToolCategory.adjust:
        return 'Adjust';
      case ToolCategory.ai:
        return 'AI Tools';
    }
  }

  Widget _actionItem(IconData icon, String label, VoidCallback? onTap) {
    final bool enabled = onTap != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkWell(
          onTap: enabled
              ? () {
                  _tap();
                  onTap();
                }
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 20, color: enabled ? EditorTokens.text : EditorTokens.faint),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? EditorTokens.text : EditorTokens.faint,
                    fontSize: EditorTokens.minFontSize - 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolItem(EditorTool tool) {
    return _actionItem(tool.icon, tool.title, () => widget.onOpenTool(tool));
  }
}
