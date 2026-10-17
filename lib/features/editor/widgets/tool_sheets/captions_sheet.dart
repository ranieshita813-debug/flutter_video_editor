import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

class CaptionsSheet extends StatefulWidget {
  const CaptionsSheet({super.key});

  @override
  State<CaptionsSheet> createState() => _CaptionsSheetState();
}

class _CaptionsSheetState extends State<CaptionsSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGenerating = false;

  static const List<Color> _presetColors = <Color>[
    Color(0xFFFFD700), // Gold / Yellow
    Color(0xFF00E5FF), // Cyan
    Color(0xFF00FF66), // Emerald
    Color(0xFFFF007F), // Neon Pink
    Color(0xFFFF6600), // Bright Orange
    Color(0xFFFFFFFF), // White
    Color(0xFFA855F7), // Purple
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final captions = editor.project.captions;
    final selectedClip = editor.selectedClip;

    return Column(
      children: [
        // Top Action Bar & Tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: EditorTokens.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isGenerating
                          ? null
                          : () async {
                              setState(() => _isGenerating = true);
                              tapFeedback();
                              try {
                                await editor.generateWhisperCaptions();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Captions generated with OpenAI Whisper Large!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isGenerating = false);
                              }
                            },
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const PhosphorIcon(PhosphorIconsRegular.sparkle, size: 18),
                      label: Text(
                        _isGenerating ? 'Transcribing...' : 'Whisper Auto Caption',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Ubuntu Sans', fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: EditorTokens.border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      tapFeedback();
                      final count = await editor.importCaptionFile();
                      if (context.mounted && count > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Imported $count caption cues!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const PhosphorIcon(PhosphorIconsRegular.fileArrowUp, size: 18),
                    label: const Text('Import .SRT/.VTT', style: TextStyle(fontFamily: 'Ubuntu Sans', fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                indicatorColor: EditorTokens.accent,
                labelColor: Colors.white,
                unselectedLabelColor: EditorTokens.muted,
                tabs: const [
                  Tab(text: 'Edit Captions'),
                  Tab(text: 'Highlight & Style'),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Edit Captions List
              _buildCaptionListTab(context, editor, captions, selectedClip),

              // Tab 2: Highlight & Style
              _buildHighlightStyleTab(context, editor, selectedClip),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaptionListTab(
    BuildContext context,
    EditorController editor,
    List<CaptionCue> captions,
    TimelineClip? selectedClip,
  ) {
    if (captions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PhosphorIcon(PhosphorIconsRegular.closedCaptioning, size: 48, color: EditorTokens.muted),
            const SizedBox(height: 12),
            const Text(
              'No captions in project yet',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Ubuntu Sans'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use OpenAI Whisper Auto Caption or import a file',
              style: TextStyle(color: EditorTokens.muted, fontSize: 13, fontFamily: 'Ubuntu Sans'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: EditorTokens.accent, foregroundColor: Colors.black),
              onPressed: () => editor.addCaptionCue(
                CaptionCue(
                  id: 'cue_${DateTime.now().millisecondsSinceEpoch}',
                  start: editor.playhead,
                  end: editor.playhead + const Duration(seconds: 3),
                  text: 'New Caption',
                ),
              ),
              icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 16),
              label: const Text('Add Manual Caption', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: captions.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == captions.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: EditorTokens.border)),
                onPressed: () => editor.addCaptionCue(
                  CaptionCue(
                    id: 'cue_${DateTime.now().millisecondsSinceEpoch}',
                    start: editor.playhead,
                    end: editor.playhead + const Duration(seconds: 3),
                    text: 'New Caption Cue',
                  ),
                ),
                icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 16),
                label: const Text('Add Cue at Playhead'),
              ),
            ),
          );
        }

        final cue = captions[index];
        final bool isSelected = selectedClip != null &&
            selectedClip.clipType == ClipType.caption &&
            (selectedClip.id == cue.id || selectedClip.id == 'caption_${cue.id}');

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? EditorTokens.elevated : EditorTokens.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? EditorTokens.accent : EditorTokens.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      tapFeedback();
                      seekPlayhead(editor, secondsOf(cue.start));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: EditorTokens.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const PhosphorIcon(PhosphorIconsRegular.play, size: 12, color: EditorTokens.accent),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatDuration(cue.start)} -> ${_formatDuration(cue.end)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Ubuntu Sans', fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const PhosphorIcon(PhosphorIconsRegular.scissors, size: 16, color: Colors.white70),
                    tooltip: 'Split Cue',
                    onPressed: () => editor.splitSelectedClip(),
                  ),
                  IconButton(
                    icon: const PhosphorIcon(PhosphorIconsRegular.arrowLineDown, size: 16, color: Colors.white70),
                    tooltip: 'Merge Next',
                    onPressed: () => editor.mergeNextCaptionClip(),
                  ),
                  IconButton(
                    icon: const PhosphorIcon(PhosphorIconsRegular.trash, size: 16, color: Colors.redAccent),
                    tooltip: 'Delete Cue',
                    onPressed: () => editor.deleteCaptionCue(cue.id),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: cue.text,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Ubuntu Sans'),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderSide: BorderSide(color: EditorTokens.border)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: EditorTokens.accent)),
                ),
                onChanged: (newText) {
                  editor.updateCaptionCue(cue.copyWith(text: newText));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHighlightStyleTab(
    BuildContext context,
    EditorController editor,
    TimelineClip? selectedClip,
  ) {
    final style = selectedClip?.textStyle ?? const TextStyleProperties();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Enable Word-level Highlight Toggle
        SwitchListTile(
          value: style.enableHighlight,
          title: const Text('Word-by-Word Highlight (Karaoke)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: const Text('Highlights active spoken words in real time', style: TextStyle(color: EditorTokens.muted, fontSize: 12)),
          activeThumbColor: EditorTokens.accent,
          onChanged: (val) {
            final updated = style.copyWith(enableHighlight: val);
            editor.updateSelectedClipTextStyle(updated);
          },
        ),

        const Divider(color: EditorTokens.border, height: 24),

        // Highlight Text Color
        const Text('Highlight Text Color', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _presetColors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final color = _presetColors[i];
              final isSelected = style.highlightColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () {
                  tapFeedback();
                  editor.updateSelectedClipTextStyle(style.copyWith(highlightColor: color));
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // Highlight Background Badge Color
        const Text('Highlight Background Badge', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _presetColors.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                final isNone = style.highlightBackgroundColor == Colors.transparent;
                return GestureDetector(
                  onTap: () {
                    tapFeedback();
                    editor.updateSelectedClipTextStyle(style.copyWith(highlightBackgroundColor: Colors.transparent));
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: isNone ? EditorTokens.accent : EditorTokens.border, width: 2),
                    ),
                    child: const Center(child: Text('None', style: TextStyle(color: Colors.white, fontSize: 10))),
                  ),
                );
              }
              final color = _presetColors[i - 1];
              final isSelected = style.highlightBackgroundColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () {
                  tapFeedback();
                  editor.updateSelectedClipTextStyle(style.copyWith(highlightBackgroundColor: color));
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // Highlight Animation Style
        const Text('Highlight Style Effect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _styleChip(editor, style, 'color', 'Color Shift'),
            _styleChip(editor, style, 'badge', 'Background Badge'),
            _styleChip(editor, style, 'scale', 'Scale Pop'),
            _styleChip(editor, style, 'outline', 'Outline Glow'),
          ],
        ),

        const Divider(color: EditorTokens.border, height: 24),

        // Font Size Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Font Size', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text('${style.fontSize.round()} px', style: const TextStyle(color: EditorTokens.muted, fontSize: 12)),
          ],
        ),
        Slider(
          value: style.fontSize,
          min: 14,
          max: 60,
          activeColor: EditorTokens.accent,
          inactiveColor: EditorTokens.border,
          onChanged: (val) => editor.updateSelectedClipTextStyle(style.copyWith(fontSize: val)),
        ),

        const SizedBox(height: 16),

        // Apply Style to All Captions Button
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: EditorTokens.elevated,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: EditorTokens.border),
              ),
            ),
            onPressed: () {
              tapFeedback();
              editor.applyCaptionStyleToAll(style);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Applied caption style to all project captions!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const PhosphorIcon(PhosphorIconsRegular.checks, size: 18),
            label: const Text('Apply Style to All Captions', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Ubuntu Sans')),
          ),
        ),
      ],
    );
  }

  Widget _styleChip(EditorController editor, TextStyleProperties currentStyle, String value, String label) {
    final bool isSelected = currentStyle.highlightStyle == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 12)),
      selected: isSelected,
      selectedColor: EditorTokens.accent,
      backgroundColor: EditorTokens.elevated,
      onSelected: (_) {
        tapFeedback();
        editor.updateSelectedClipTextStyle(currentStyle.copyWith(highlightStyle: value));
      },
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$min:$sec.$ms';
  }
}
