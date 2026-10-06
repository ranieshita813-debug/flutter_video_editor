import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';

class ElementsSheet extends StatefulWidget {
  const ElementsSheet({super.key});

  @override
  State<ElementsSheet> createState() => _ElementsSheetState();
}

class _ElementsSheetState extends State<ElementsSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();

    final filtered = ElementShape.values.where((shape) {
      return shape.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: 'Search shape elements...',
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.5,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final shape = filtered[index];
              return GestureDetector(
                onTap: () => editor.addElementClip(shape),
                child: Container(
                  decoration: BoxDecoration(
                    color: EditorTokens.elevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: EditorTokens.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    shape.name.toUpperCase(),
                    style: const TextStyle(
                      color: EditorTokens.text,
                      fontSize: 12,
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
