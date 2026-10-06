import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class ToolSearchHeader extends StatefulWidget {
  const ToolSearchHeader({
    super.key,
    required this.onSearchChanged,
    required this.onTagSelected,
    this.selectedTag = 'All',
    this.tags = const [
      'All',
      'Popular',
      'Trending',
      'Cinematic',
      'Retro',
      '3D',
      'Glitch',
      'Neon',
      'Abstract',
      'Vlog',
    ],
    this.placeholder = 'Search...',
  });

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTagSelected;
  final String selectedTag;
  final List<String> tags;
  final String placeholder;

  @override
  State<ToolSearchHeader> createState() => _ToolSearchHeaderState();
}

class _ToolSearchHeaderState extends State<ToolSearchHeader> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Input Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 40,
          decoration: BoxDecoration(
            color: EditorTokens.elevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: EditorTokens.border, width: 1),
          ),
          child: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                color: EditorTokens.muted,
                size: 18.0,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: widget.onSearchChanged,
                  style: const TextStyle(
                    color: EditorTokens.text,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                  decoration: InputDecoration(
                    hintText: widget.placeholder,
                    hintStyle: const TextStyle(
                      color: EditorTokens.muted,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_controller.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _controller.clear();
                    widget.onSearchChanged('');
                    setState(() {});
                  },
                  child: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    color: EditorTokens.muted,
                    size: 16.0,
                  ),
                ),
            ],
          ),
        ),
        // Tag Filter Chips
        if (widget.tags.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.tags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tag = widget.tags[index];
                final isSelected = tag.toLowerCase() == widget.selectedTag.toLowerCase();
                return ChoiceChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (_) => widget.onTagSelected(tag),
                  selectedColor: EditorTokens.text,
                  backgroundColor: EditorTokens.elevated,
                  elevation: 0,
                  pressElevation: 0,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  labelStyle: TextStyle(
                    color: isSelected ? EditorTokens.bg : EditorTokens.text,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: 'Poppins',
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? EditorTokens.text : EditorTokens.border,
                      width: 1,
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
