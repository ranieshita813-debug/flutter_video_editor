import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';

class StickersSheet extends StatefulWidget {
  const StickersSheet({super.key});

  @override
  State<StickersSheet> createState() => _StickersSheetState();
}

class _StickersSheetState extends State<StickersSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';

  static const List<Map<String, String>> _stickers = [
    {'emoji': '🔥', 'tag': 'Popular'},
    {'emoji': '✨', 'tag': 'Popular'},
    {'emoji': '⚡', 'tag': 'Trending'},
    {'emoji': '🎉', 'tag': 'Popular'},
    {'emoji': '❤️', 'tag': 'Popular'},
    {'emoji': '🌟', 'tag': 'Trending'},
    {'emoji': '🎬', 'tag': 'Cinematic'},
    {'emoji': '👏', 'tag': 'Popular'},
    {'emoji': '🚀', 'tag': 'Trending'},
    {'emoji': '💯', 'tag': 'Trending'},
    {'emoji': '💥', 'tag': 'Glitch'},
    {'emoji': '⭐', 'tag': 'Popular'},
    {'emoji': '🎈', 'tag': 'Popular'},
    {'emoji': '🏆', 'tag': 'Trending'},
    {'emoji': '💎', 'tag': 'Trending'},
  ];

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    final filtered = _stickers.where((s) {
      if (_selectedTag != 'All' && s['tag'] != _selectedTag) return false;
      if (_searchQuery.isNotEmpty && !s['emoji']!.contains(_searchQuery)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: 'Search stickers & emojis...',
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final emoji = filtered[index]['emoji']!;
              return GestureDetector(
                onTap: () => editor.addTextOverlay(emoji, fontFamily: 'Poppins'),
                child: Container(
                  decoration: BoxDecoration(
                    color: EditorTokens.elevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: EditorTokens.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
