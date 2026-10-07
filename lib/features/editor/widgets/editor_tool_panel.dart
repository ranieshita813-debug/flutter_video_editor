import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

const Color _editorPanelSurface = Color(0xFF101014);
const Color _editorPanelDivider = Color(0xFF1E1E22);

class EditorToolPanel extends StatelessWidget {
  const EditorToolPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    this.height,
    this.docked = false,
    this.onClose,
    this.onResize,
    this.onDrag,
  });

  final String title;
  final dynamic icon;
  final Widget body;
  final double? height;
  final bool docked;
  final VoidCallback? onClose;
  final ValueChanged<double>? onResize;
  final ValueChanged<bool>? onDrag;

  Widget _header() => Row(
        children: <Widget>[
          const SizedBox(width: 16),
          HugeIcon(icon: icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Done',
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedTick01,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                onClose!();
              },
            ),
          const SizedBox(width: 4),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final Widget content = Expanded(
      child: ClipRect(
        child: Material(type: MaterialType.transparency, child: body),
      ),
    );

    if (docked) {
      return Container(
        decoration: const BoxDecoration(
          color: _editorPanelSurface,
          border: Border(left: BorderSide(color: _editorPanelDivider)),
        ),
        child: SafeArea(
          left: false,
          child: Column(
            children: <Widget>[
              SizedBox(height: 52, child: _header()),
              const Divider(height: 1, thickness: 0.5, color: _editorPanelDivider),
              content,
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: _editorPanelSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: _editorPanelDivider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => onDrag?.call(true),
                onVerticalDragUpdate: (d) => onResize?.call(d.delta.dy),
                onVerticalDragEnd: (_) => onDrag?.call(false),
                onVerticalDragCancel: () => onDrag?.call(false),
                child: SizedBox(
                  height: 52,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(child: _header()),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: _editorPanelDivider),
              content,
            ],
          ),
        ),
      ),
    );
  }
}
