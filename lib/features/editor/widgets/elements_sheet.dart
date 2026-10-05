import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

const Color _sheet = Color(0xFF0E0E11);
const Color _card = Color(0xFF1A1A1F);
const Color _track = Color(0xFF2B2B31);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF9A9AA3);

class ElementsSheet extends StatefulWidget {
  const ElementsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ElementsSheet(),
    );
  }

  @override
  State<ElementsSheet> createState() => _ElementsSheetState();
}

class _ElementsSheetState extends State<ElementsSheet> {
  ElementShape selectedShape = ElementShape.rectangle;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditorController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
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
                  'Elements & Overlay Objects',
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
            const SizedBox(height: 14),
            const Text(
              'Vector Shapes',
              style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _shapesGrid(c),
            const SizedBox(height: 20),
            const Text(
              'Import Media / Overlay',
              style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _text,
                side: const BorderSide(color: _track),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: const Text('Add Overlay Video or Photo'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed('/media_picker');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _shapesGrid(EditorController c) {
    final shapes = <(ElementShape, String, IconData)>[
      (ElementShape.rectangle, 'Rectangle', Icons.crop_square_rounded),
      (ElementShape.circle, 'Circle', Icons.circle_outlined),
      (ElementShape.star, 'Star', Icons.star_border_rounded),
      (ElementShape.triangle, 'Triangle', Icons.change_history_rounded),
      (ElementShape.arrow, 'Arrow', Icons.arrow_forward_rounded),
      (ElementShape.line, 'Line', Icons.remove_rounded),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemCount: shapes.length,
      itemBuilder: (context, i) {
        final item = shapes[i];
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            c.addElementClip(item.$1, label: item.$2);
            Navigator.of(context).pop();
          },
          child: Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _track),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(item.$3, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
