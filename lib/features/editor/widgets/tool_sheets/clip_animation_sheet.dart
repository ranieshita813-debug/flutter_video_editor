import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';

class ClipAnimationSheet extends StatefulWidget {
  const ClipAnimationSheet({super.key});

  @override
  State<ClipAnimationSheet> createState() => _ClipAnimationSheetState();
}

class _ClipAnimationSheetState extends State<ClipAnimationSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String _selectedTag = 'All';

  final List<ClipAnimation> _animations = const [
    ClipAnimation.none,
    ClipAnimation.fadeIn,
    ClipAnimation.fadeOut,
    ClipAnimation.slideLeft,
    ClipAnimation.slideRight,
    ClipAnimation.zoomIn,
    ClipAnimation.zoomOut,
    ClipAnimation.bounce,
    ClipAnimation.spin,
    ClipAnimation.glitch,
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
    final clip = editor.selectedClip;
    if (clip == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text(
          'Select a clip to apply animations',
          style: TextStyle(color: EditorTokens.muted, fontFamily: 'Poppins'),
        ),
      );
    }

    final filtered = _animations.where((anim) {
      final name = _getAnimationName(anim).toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: EditorTokens.text,
          labelColor: EditorTokens.text,
          unselectedLabelColor: EditorTokens.muted,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            fontFamily: 'Poppins',
          ),
          tabs: const [
            Tab(text: 'In Animation'),
            Tab(text: 'Out Animation'),
          ],
        ),
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: 'Search animation styles...',
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAnimationGrid(
                context,
                editor,
                clip,
                filtered,
                isInMode: true,
              ),
              _buildAnimationGrid(
                context,
                editor,
                clip,
                filtered,
                isInMode: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimationGrid(
    BuildContext context,
    EditorController editor,
    TimelineClip clip,
    List<ClipAnimation> options, {
    required bool isInMode,
  }) {
    final currentAnim = isInMode ? clip.inAnimation : clip.outAnimation;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      itemCount: options.length,
      itemBuilder: (context, index) {
        final anim = options[index];
        final isSelected = currentAnim == anim;
        return GestureDetector(
          onTap: () {
            editor.updateSelectedClipAnimation(
              anim,
              isInAnimation: isInMode,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? EditorTokens.text : EditorTokens.elevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? EditorTokens.text : EditorTokens.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HugeIcon(
                  icon: _getAnimationIcon(anim),
                  color: isSelected ? EditorTokens.bg : EditorTokens.text,
                  size: 24.0,
                ),
                const SizedBox(height: 6),
                Text(
                  _getAnimationName(anim),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? EditorTokens.bg : EditorTokens.text,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getAnimationName(ClipAnimation anim) {
    switch (anim) {
      case ClipAnimation.none:
        return 'None';
      case ClipAnimation.fadeIn:
        return 'Fade In';
      case ClipAnimation.fadeOut:
        return 'Fade Out';
      case ClipAnimation.slideLeft:
        return 'Slide Left';
      case ClipAnimation.slideRight:
        return 'Slide Right';
      case ClipAnimation.zoomIn:
        return 'Zoom In';
      case ClipAnimation.zoomOut:
        return 'Zoom Out';
      case ClipAnimation.bounce:
        return 'Bounce';
      case ClipAnimation.spin:
        return 'Spin';
      case ClipAnimation.glitch:
        return 'Glitch';
    }
  }

  dynamic _getAnimationIcon(ClipAnimation anim) {
    switch (anim) {
      case ClipAnimation.none:
        return HugeIcons.strokeRoundedCancel01;
      case ClipAnimation.fadeIn:
      case ClipAnimation.fadeOut:
        return HugeIcons.strokeRoundedCircle;
      case ClipAnimation.slideLeft:
        return HugeIcons.strokeRoundedArrowLeft01;
      case ClipAnimation.slideRight:
        return HugeIcons.strokeRoundedArrowRight01;
      case ClipAnimation.zoomIn:
        return HugeIcons.strokeRoundedZoomIn;
      case ClipAnimation.zoomOut:
        return HugeIcons.strokeRoundedZoomOut;
      case ClipAnimation.bounce:
        return HugeIcons.strokeRoundedPlay;
      case ClipAnimation.spin:
        return HugeIcons.strokeRoundedLoading01;
      case ClipAnimation.glitch:
        return HugeIcons.strokeRoundedMagicWand01;
    }
  }
}
