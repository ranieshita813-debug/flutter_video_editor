import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/widgets/caption_widgets.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

class CaptionTranslationSheet extends StatefulWidget {
  const CaptionTranslationSheet({super.key});

  @override
  State<CaptionTranslationSheet> createState() => _CaptionTranslationSheetState();
}

class _CaptionTranslationSheetState extends State<CaptionTranslationSheet> {
  bool _applyToAll = true;
  String _selectedLanguage = 'Bengali';
  bool _isTranslating = false;

  static const List<Map<String, String>> _languages = [
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা'},
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'es', 'name': 'Spanish', 'native': 'Español'},
    {'code': 'fr', 'name': 'French', 'native': 'Français'},
    {'code': 'de', 'name': 'German', 'native': 'Deutsch'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी'},
    {'code': 'ja', 'name': 'Japanese', 'native': '日本語'},
    {'code': 'ar', 'name': 'Arabic', 'native': 'العربية'},
    {'code': 'zh', 'name': 'Chinese', 'native': '中文'},
    {'code': 'ru', 'name': 'Russian', 'native': 'Русский'},
  ];

  Future<void> _performTranslation(EditorController editor) async {
    tapFeedback();
    setState(() => _isTranslating = true);

    try {
      await editor.translateCaptions(
        targetLanguage: _selectedLanguage,
        allCaptions: _applyToAll,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Captions translated to $_selectedLanguage',
              style: const TextStyle(fontFamily: 'Ubuntu Sans'),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Translation failed: $e',
              style: const TextStyle(fontFamily: 'Ubuntu Sans'),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final sel = editor.selectedClip;
    final hasCaptionSelected = sel != null && sel.clipType == ClipType.caption;

    return Container(
      color: EditorTokens.surface,
      child: Column(
        children: [
          const MonoSheetHeader(
            title: 'Translate Captions',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                const MonoLabel('Apply to'),
                MonoSegmented<bool>(
                  options: const {true: 'All captions', false: 'Selected'},
                  value: _applyToAll,
                  onChanged: (v) {
                    if (!v && !hasCaptionSelected) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                          content: Text('Select a caption on the timeline first'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ));
                      return;
                    }
                    tapFeedback();
                    setState(() => _applyToAll = v);
                  },
                ),
                const SizedBox(height: 22),
                const MonoLabel('Target Language'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 3.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _languages.length,
                  itemBuilder: (context, index) {
                    final lang = _languages[index];
                    final isSelected = _selectedLanguage == lang['name'];

                    return GestureDetector(
                      onTap: () {
                        tapFeedback();
                        setState(() => _selectedLanguage = lang['name']!);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? EditorTokens.text : EditorTokens.elevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? EditorTokens.text : EditorTokens.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            PhosphorIcon(
                              PhosphorIconsRegular.translate,
                              size: 18,
                              color: isSelected ? EditorTokens.bg : EditorTokens.text,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    lang['name']!,
                                    style: TextStyle(
                                      color: isSelected ? EditorTokens.bg : EditorTokens.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      fontFamily: 'Ubuntu Sans',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    lang['native']!,
                                    style: TextStyle(
                                      color: isSelected
                                          ? EditorTokens.bg.withValues(alpha: 0.7)
                                          : EditorTokens.muted,
                                      fontSize: 10,
                                      fontFamily: 'Ubuntu Sans',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EditorTokens.text,
                      foregroundColor: EditorTokens.bg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isTranslating ? null : () => _performTranslation(editor),
                    icon: _isTranslating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: EditorTokens.bg,
                            ),
                          )
                        : const PhosphorIcon(PhosphorIconsRegular.translate, size: 20),
                    label: Text(
                      _isTranslating ? 'Translating…' : 'Translate to $_selectedLanguage',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Ubuntu Sans',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
