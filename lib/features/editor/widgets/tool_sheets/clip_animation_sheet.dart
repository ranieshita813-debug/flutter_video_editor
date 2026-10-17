import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
    ClipAnimation.rotateIn,
    ClipAnimation.flipHorizontal,
    ClipAnimation.flipVertical,
    ClipAnimation.elasticBounce,
    ClipAnimation.blurFade,
    ClipAnimation.shakeSlide,
    ClipAnimation.zoomRotate,
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
    final editor = context.read<EditorController>();
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    if (clip == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text(
          'Select a clip to apply animations',
          style: TextStyle(color: EditorTokens.muted, fontFamily: 'Ubuntu'),
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
            fontFamily: 'Ubuntu',
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
        childAspectRatio: 0.85,
      ),
      itemCount: options.length,
      itemBuilder: (context, index) {
        final anim = options[index];
        final isSelected = currentAnim == anim;
        final name = _getAnimationName(anim);
        return GestureDetector(
          onTap: () {
            editor.updateSelectedClipAnimation(
              anim,
              isInAnimation: isInMode,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: EditorTokens.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? EditorTokens.text : EditorTokens.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: EditorTokens.elevated,
                    child: Center(
                      child: PhosphorIcon(
                        _getAnimationIcon(anim),
                        color: isSelected ? EditorTokens.text : EditorTokens.text.withValues(alpha: 0.8),
                        size: 22.0,
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  color: isSelected ? EditorTokens.text : EditorTokens.surface,
                  alignment: Alignment.center,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? EditorTokens.bg : EditorTokens.text,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Ubuntu',
                    ),
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
      case ClipAnimation.rotateIn:
        return 'Rotate In';
      case ClipAnimation.flipHorizontal:
        return 'Flip H';
      case ClipAnimation.flipVertical:
        return 'Flip V';
      case ClipAnimation.elasticBounce:
        return 'Elastic';
      case ClipAnimation.blurFade:
        return 'Blur Fade';
      case ClipAnimation.shakeSlide:
        return 'Shake Slide';
      case ClipAnimation.zoomRotate:
        return 'Zoom Rotate';
    }
  }

  PhosphorIconData _getAnimationIcon(ClipAnimation anim) {
    switch (anim) {
      case ClipAnimation.none:
        return PhosphorIconsRegular.prohibit;
      case ClipAnimation.fadeIn:
      case ClipAnimation.fadeOut:
        return PhosphorIconsRegular.circle;
      case ClipAnimation.slideLeft:
        return PhosphorIconsRegular.arrowLeft;
      case ClipAnimation.slideRight:
        return PhosphorIconsRegular.arrowRight;
      case ClipAnimation.zoomIn:
        return PhosphorIconsRegular.magnifyingGlassPlus;
      case ClipAnimation.zoomOut:
        return PhosphorIconsRegular.magnifyingGlassMinus;
      case ClipAnimation.bounce:
        return PhosphorIconsRegular.play;
      case ClipAnimation.spin:
        return PhosphorIconsRegular.arrowsClockwise;
      case ClipAnimation.glitch:
        return PhosphorIconsRegular.magicWand;
      case ClipAnimation.rotateIn:
        return PhosphorIconsRegular.arrowClockwise;
      case ClipAnimation.flipHorizontal:
      case ClipAnimation.flipVertical:
        return PhosphorIconsRegular.repeat;
      case ClipAnimation.elasticBounce:
        return PhosphorIconsRegular.lightning;
      case ClipAnimation.blurFade:
        return PhosphorIconsRegular.funnel;
      case ClipAnimation.shakeSlide:
        return PhosphorIconsRegular.sliders;
      case ClipAnimation.zoomRotate:
        return PhosphorIconsRegular.magnifyingGlassPlus;
    }
  }
}
