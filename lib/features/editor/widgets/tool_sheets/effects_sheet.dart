import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';

class EffectsSheet extends StatefulWidget {
  const EffectsSheet({super.key, required this.isFilterMode});
  final bool isFilterMode;

  @override
  State<EffectsSheet> createState() => _EffectsSheetState();
}

class _EffectsSheetState extends State<EffectsSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final currentEffect = editor.selectedClip?.effect ?? VideoEffect.none;

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
