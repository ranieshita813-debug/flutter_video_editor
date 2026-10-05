import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

class TextAnimationSheet extends StatefulWidget {
  const TextAnimationSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const TextAnimationSheet(),
    );
  }

  @override
  State<TextAnimationSheet> createState() => _TextAnimationSheetState();
}

class _TextAnimationSheetState extends State<TextAnimationSheet> {
  late TextEditingController _textController;
  late TextEditingController _customFontController;
  String selectedFont = 'Poppins';
  TextAnimationStyle selectedAnimation = TextAnimationStyle.fadeIn;

  @override
  void initState() {
    super.initState();
    final controller = context.read<EditorController>();
    final currentClip = controller.selectedClip;

    if (currentClip != null && currentClip.clipType == ClipType.text) {
      _textController = TextEditingController(text: currentClip.label);
      selectedFont = currentClip.fontFamily;
      selectedAnimation = currentClip.textAnimationStyle;
    } else {
      _textController = TextEditingController(text: 'Animated Title Text');
    }
    _customFontController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _customFontController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EditorController>();
    final fonts = controller.project.customFonts;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Text, Fonts & Animation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Text Content',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF1F2937),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Text Animation Preset', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TextAnimationStyle.values.map((anim) {
                final isSelected = selectedAnimation == anim;
                return ChoiceChip(
                  label: Text(anim.name.toUpperCase()),
                  selected: isSelected,
                  selectedColor: const Color(0xFF8B5CF6),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        selectedAnimation = anim;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('Typography & Custom Fonts', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Font'),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF111827),
                        title: const Text('Add Custom Font', style: TextStyle(color: Colors.white)),
                        content: TextField(
                          controller: _customFontController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Enter font name',
                            hintStyle: TextStyle(color: Colors.white38),
                          ),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (_customFontController.text.trim().isNotEmpty) {
                                controller.uploadCustomFont(_customFontController.text.trim());
                                setState(() {
                                  selectedFont = _customFontController.text.trim();
                                });
                              }
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Add Font'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fonts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final font = fonts[index];
                  final isSelected = selectedFont == font;
                  return ChoiceChip(
                    label: Text(font),
                    selected: isSelected,
                    selectedColor: const Color(0xFF8B5CF6),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          selectedFont = font;
                        });
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Apply Text Layer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final current = controller.selectedClip;
                  if (current != null && current.clipType == ClipType.text) {
                    controller.updateSelectedTextProperties(
                      text: _textController.text.trim(),
                      fontFamily: selectedFont,
                      textAnimationStyle: selectedAnimation,
                    );
                  } else {
                    controller.addTextOverlay(
                      _textController.text.trim(),
                      fontFamily: selectedFont,
                      animationStyle: selectedAnimation,
                    );
                  }
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
