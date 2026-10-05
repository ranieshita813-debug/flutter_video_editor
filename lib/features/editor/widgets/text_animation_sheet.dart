import 'package:hugeicons/hugeicons.dart';
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

class TextAnimationSheet extends StatefulWidget {
  const TextAnimationSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
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
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
                  'Text, Fonts & Animation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: _text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              style: const TextStyle(color: _text, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Text Content',
                labelStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _card,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _track),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Text Animation Preset',
                style: TextStyle(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TextAnimationStyle.values.map((anim) {
                final isSelected = selectedAnimation == anim;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => selectedAnimation = anim);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _track),
                    ),
                    child: Text(
                      anim.name.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.black : _text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Text('Typography & Custom Fonts',
                    style: TextStyle(
                        color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 16, color: _text),
                  label: const Text('Add Font',
                      style: TextStyle(color: _text, fontSize: 12)),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: _sheet,
                        title: const Text('Add Custom Font',
                            style: TextStyle(color: _text)),
                        content: TextField(
                          controller: _customFontController,
                          style: const TextStyle(color: _text),
                          decoration: const InputDecoration(
                            hintText: 'Enter font name',
                            hintStyle: TextStyle(color: _muted),
                          ),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel',
                                style: TextStyle(color: _muted)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () {
                              if (_customFontController.text.trim().isNotEmpty) {
                                controller.uploadCustomFont(
                                    _customFontController.text.trim());
                                setState(() {
                                  selectedFont =
                                      _customFontController.text.trim();
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
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fonts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final font = fonts[index];
                  final isSelected = selectedFont == font;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => selectedFont = font);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _track),
                      ),
                      child: Text(
                        font,
                        style: TextStyle(
                          color: isSelected ? Colors.black : _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
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
              child: const Text('Apply Text Layer',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
