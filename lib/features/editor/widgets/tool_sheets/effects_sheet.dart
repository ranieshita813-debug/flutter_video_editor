import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';
import 'package:flutter_video_editor/features/effects/pages/effects_library_page.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_timeline_chip.dart';

class EffectsSheet extends StatefulWidget {
  const EffectsSheet({super.key, required this.isFilterMode});
  final bool isFilterMode;

  @override
  State<EffectsSheet> createState() => _EffectsSheetState();
}

class _EffectsSheetState extends State<EffectsSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';

  void _openEffectsLibrary(BuildContext context, EditorController editor) async {
    final clip = editor.selectedClip;
    final result = await Navigator.of(context).push<ShaderEffectClip>(
      MaterialPageRoute(
        builder: (_) => EffectsLibraryPage(
          selectedClipTime: editor.playhead,
          onApplyEffect: (effect, shaderClip) {
            if (clip != null) {
              editor.addShaderEffectToSelectedClip(shaderClip);
            }
          },
        ),
      ),
    );

    if (result != null && clip != null) {
      editor.addShaderEffectToSelectedClip(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedClip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final editor = context.read<EditorController>();
    final currentEffect = selectedClip?.effect ?? VideoEffect.none;
    final appliedShaderEffects = selectedClip?.shaderEffects ?? const <ShaderEffectClip>[];

    final filtered = VideoEffect.values.where((fx) {
      final nameMatches = fx.name.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!nameMatches) return false;
      if (_selectedTag == 'All') return true;
      if (_selectedTag == 'Cinematic') return fx == VideoEffect.cinematic || fx == VideoEffect.noir;
      if (_selectedTag == 'Retro') return fx == VideoEffect.vintage || fx == VideoEffect.retro;
      if (_selectedTag == 'Glitch') return fx == VideoEffect.glitch || fx == VideoEffect.matrix;
      return true;
    }).toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EditorTokens.elevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: EditorTokens.border),
          ),
          child: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedMagicWand01,
                color: EditorTokens.text,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shader Effects Store',
                      style: TextStyle(
                        color: EditorTokens.text,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'Browse CapCut-style shader effects & keyframes',
                      style: TextStyle(
                        color: EditorTokens.muted,
                        fontSize: 10,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTokens.text,
                  foregroundColor: EditorTokens.bg,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onPressed: () => _openEffectsLibrary(context, editor),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedAdd01,
                  color: EditorTokens.bg,
                  size: 14,
                ),
                label: const Text(
                  'BROWSE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (appliedShaderEffects.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: appliedShaderEffects.map((fx) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: EffectTimelineChip(
                        effectClip: fx,
                        isSelected: true,
                        onToggleEnabled: () => editor.toggleShaderEffectEnabled(fx.id),
                        onRemove: () => editor.removeShaderEffectFromSelectedClip(fx.id),
                        onTap: () => _openEffectsLibrary(context, editor),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: widget.isFilterMode ? 'Search filters...' : 'Search visual effects...',
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.6,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final fx = filtered[index];
              final isSelected = fx == currentEffect;
              return GestureDetector(
                onTap: () => editor.applyEffect(fx),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? EditorTokens.text : EditorTokens.elevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? EditorTokens.text : EditorTokens.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    fx.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? EditorTokens.bg : EditorTokens.text,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
