import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/toolbar/editor_toolbar.dart';

class ToolPanel extends StatelessWidget {
  const ToolPanel({
    super.key,
    required this.tool,
    required this.height,
    required this.onClose,
    required this.onResize,
    required this.onDrag,
  });

  final EditorTool tool;
  final double height;
  final VoidCallback onClose;
  final ValueChanged<double> onResize;
  final ValueChanged<bool> onDrag;

  void _tap() => HapticFeedback.selectionClick();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EditorTokens.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: EditorTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: <Widget>[
              // Grabber header
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => onDrag(true),
                onVerticalDragUpdate: (d) => onResize(d.delta.dy),
                onVerticalDragEnd: (_) => onDrag(false),
                onVerticalDragCancel: () => onDrag(false),
                child: SizedBox(
                  height: 48,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: EditorTokens.faint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 16),
                            Icon(tool.icon, color: EditorTokens.text, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              tool.title,
                              style: const TextStyle(
                                color: EditorTokens.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Done',
                              icon: const Icon(Icons.check_rounded, color: EditorTokens.text, size: 22),
                              onPressed: () {
                                _tap();
                                onClose();
                              },
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: EditorTokens.border),
              Expanded(
                child: ClipRect(
                  child: Material(type: MaterialType.transparency, child: tool.body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
