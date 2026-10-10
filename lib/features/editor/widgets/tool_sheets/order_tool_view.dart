import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

/// Body of the toolbar's "Order" tool. Plug it into ToolPanel for
/// `EditorTool.order`. Moves the lane of the selected overlay clip (text,
/// sticker, drawing) up or down the layer stack.
class OrderToolView extends StatelessWidget {
  const OrderToolView({super.key});

  @override
  Widget build(BuildContext context) {
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final e = context.read<EditorController>();

    final bool overlay = clip != null &&
        clip.clipType != ClipType.video &&
        clip.clipType != ClipType.image &&
        clip.clipType != ClipType.audio;

    if (!overlay) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Select a text, sticker, or drawing clip to change its order',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      );
    }

    final bool canUp = e.canMoveClipLayer(clip.id, up: true);
    final bool canDown = e.canMoveClipLayer(clip.id, up: false);

    Widget item(IconData icon, String label, bool enabled, VoidCallback onTap) {
      return Expanded(
        child: Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled
                  ? () {
                      tapFeedback();
                      onTap();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(height: 6),
                    Text(label,
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: <Widget>[
          item(Icons.vertical_align_top_rounded, 'To front', canUp,
              () => e.moveClipLayer(clip.id, up: true, toEdge: true)),
          item(Icons.arrow_upward_rounded, 'Forward', canUp,
              () => e.moveClipLayer(clip.id, up: true)),
          item(Icons.arrow_downward_rounded, 'Backward', canDown,
              () => e.moveClipLayer(clip.id, up: false)),
          item(Icons.vertical_align_bottom_rounded, 'To back', canDown,
              () => e.moveClipLayer(clip.id, up: false, toEdge: true)),
        ],
      ),
    );
  }
}