import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _sheet = Color(0xFF0E0E11);
const Color _card = Color(0xFF1A1A1F);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);

class StickersSheet extends StatelessWidget {
  const StickersSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const StickersSheet(),
    );
  }

  static const List<String> stickers = <String>[
    '🔥', '✨', '⚡', '❤️', '🎬', '🌟', '🎉', '💯', '🚀', '⭐'
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  'Stickers & Emojis',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: stickers.length,
              itemBuilder: (context, index) {
                final sticker = stickers[index];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.addClip(
                      TimelineClip(
                        id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
                        label: sticker,
                        start: controller.playhead,
                        end: controller.playhead + const Duration(seconds: 3),
                        clipType: ClipType.sticker,
                        layerIndex: 3,
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _track),
                    ),
                    child: Center(
                      child: Text(sticker, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
