import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
    final editor = context.read<EditorController>();
    final selectedClip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
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
              const FaIcon(
                FontAwesomeIcons.wandMagicSparkles,
                color: EditorTokens.text,
                size: 16,
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
                icon: const FaIcon(
                  FontAwesomeIcons.plus,
                  color: EditorTokens.bg,
                  size: 12,
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
              childAspectRatio: 0.85,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final fx = filtered[index];
              final isSelected = fx == currentEffect;
              return GestureDetector(
                onTap: () => editor.applyEffect(fx),
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
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _getEffectGradient(fx),
                            ),
                          ),
                          child: Center(
                            child: FaIcon(
                              _getEffectIcon(fx),
                              color: isSelected ? EditorTokens.text : Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        color: isSelected ? EditorTokens.text : EditorTokens.elevated,
                        alignment: Alignment.center,
                        child: Text(
                          fx.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? EditorTokens.bg : EditorTokens.text,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Color> _getEffectGradient(VideoEffect fx) {
    switch (fx) {
      case VideoEffect.none:
        return const [Color(0xFF2A2A30), Color(0xFF1B1B20)];
      case VideoEffect.warm:
        return const [Color(0xFFFF7E5F), Color(0xFFFEB47B)];
      case VideoEffect.cinematic:
        return const [Color(0xFF003366), Color(0xFF336699)];
      case VideoEffect.noir:
        return const [Color(0xFF434343), Color(0xFF000000)];
      case VideoEffect.vibrant:
        return const [Color(0xFFFF007F), Color(0xFF7F00FF)];
      case VideoEffect.vintage:
        return const [Color(0xFFC94B4C), Color(0xFF4D13D1)];
      case VideoEffect.glitch:
        return const [Color(0xFF00E5FF), Color(0xFFFF0055)];
      case VideoEffect.blur:
        return const [Color(0xFF3A6073), Color(0xFF16222A)];
      case VideoEffect.glow:
        return const [Color(0xFFFF00CC), Color(0xFF333399)];
      case VideoEffect.retro:
        return const [Color(0xFFF7971E), Color(0xFFFFD200)];
      case VideoEffect.matrix:
        return const [Color(0xFF00FF87), Color(0xFF60EFFF)];
      case VideoEffect.flame:
        return const [Color(0xFFF857A6), Color(0xFFFF5858)];
      case VideoEffect.vhs:
        return const [Color(0xFF8A2387), Color(0xFFE94057)];
      case VideoEffect.wave:
        return const [Color(0xFF42275A), Color(0xFF734B6D)];
      case VideoEffect.vignette:
        return const [Color(0xFF1F1C2C), Color(0xFF928DAB)];
    }
  }

  FaIconData _getEffectIcon(VideoEffect fx) {
    switch (fx) {
      case VideoEffect.none:
        return FontAwesomeIcons.ban;
      case VideoEffect.warm:
        return FontAwesomeIcons.sun;
      case VideoEffect.cinematic:
        return FontAwesomeIcons.video;
      case VideoEffect.noir:
        return FontAwesomeIcons.moon;
      case VideoEffect.vibrant:
        return FontAwesomeIcons.bolt;
      case VideoEffect.vintage:
        return FontAwesomeIcons.clock;
      case VideoEffect.glitch:
        return FontAwesomeIcons.sliders;
      case VideoEffect.blur:
        return FontAwesomeIcons.filter;
      case VideoEffect.glow:
        return FontAwesomeIcons.wandMagicSparkles;
      case VideoEffect.retro:
        return FontAwesomeIcons.film;
      case VideoEffect.matrix:
        return FontAwesomeIcons.code;
      case VideoEffect.flame:
        return FontAwesomeIcons.fire;
      case VideoEffect.vhs:
        return FontAwesomeIcons.tv;
      case VideoEffect.wave:
        return FontAwesomeIcons.water;
      case VideoEffect.vignette:
        return FontAwesomeIcons.circle;
    }
  }
}
