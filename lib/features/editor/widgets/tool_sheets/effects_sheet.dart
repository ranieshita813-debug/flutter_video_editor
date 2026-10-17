import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
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
  VideoEffect? _configuringFx;

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

    if (_configuringFx != null) {
      return _EffectConfigView(
        fx: _configuringFx!,
        clip: selectedClip,
        onBack: () => setState(() => _configuringFx = null),
      );
    }

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
              const PhosphorIcon(
                PhosphorIconsRegular.magicWand,
                color: EditorTokens.text,
                size: 18,
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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Ubuntu Sans',
                      ),
                    ),
                    Text(
                      'Browse CapCut-style shader effects & keyframes',
                      style: TextStyle(
                        color: EditorTokens.muted,
                        fontSize: 11,
                        fontFamily: 'Ubuntu Sans',
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
                icon: const PhosphorIcon(
                  PhosphorIconsRegular.plus,
                  color: EditorTokens.bg,
                  size: 14,
                ),
                label: const Text(
                  'BROWSE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Ubuntu Sans',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (currentEffect != VideoEffect.none) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: EditorTokens.elevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EditorTokens.border),
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  _getEffectIcon(currentEffect),
                  color: EditorTokens.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Active: ${currentEffect.name.toUpperCase()}',
                  style: const TextStyle(
                    color: EditorTokens.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Ubuntu Sans',
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _configuringFx = currentEffect),
                  icon: const PhosphorIcon(PhosphorIconsRegular.slidersHorizontal, size: 14, color: EditorTokens.accent),
                  label: const Text(
                    'CONFIGURE',
                    style: TextStyle(color: EditorTokens.accent, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Ubuntu Sans'),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                onTap: () {
                  editor.applyEffect(fx);
                  if (fx != VideoEffect.none) {
                    setState(() => _configuringFx = fx);
                  }
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
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _getEffectGradient(fx),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: PhosphorIcon(
                                  _getEffectIcon(fx),
                                  color: isSelected ? EditorTokens.text : Colors.white70,
                                  size: 24,
                                ),
                              ),
                              if (fx != VideoEffect.none)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () {
                                      editor.applyEffect(fx);
                                      setState(() => _configuringFx = fx);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const PhosphorIcon(
                                        PhosphorIconsRegular.slidersHorizontal,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Ubuntu Sans',
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
      case VideoEffect.vhsTape:
        return const [Color(0xFF8A2387), Color(0xFFE94057)];
      case VideoEffect.wave:
      case VideoEffect.liquidWave:
        return const [Color(0xFF42275A), Color(0xFF734B6D)];
      case VideoEffect.vignette:
      case VideoEffect.cinematicVignette:
        return const [Color(0xFF1F1C2C), Color(0xFF928DAB)];
      case VideoEffect.chromaticAberration:
        return const [Color(0xFF11998E), Color(0xFF38EF7D)];
      case VideoEffect.filmGrain:
        return const [Color(0xFF3E5151), Color(0xFFDECBA4)];
      case VideoEffect.dreamBloom:
        return const [Color(0xFFFF512F), Color(0xFFDD2476)];
      case VideoEffect.mosaicPixelate:
        return const [Color(0xFF4568DC), Color(0xFFB06AB3)];
      case VideoEffect.crispSharpen:
        return const [Color(0xFF136A8A), Color(0xFF267871)];
      case VideoEffect.lensDistortion:
        return const [Color(0xFF00B4DB), Color(0xFF0083B0)];
      case VideoEffect.convexScreenPro:
        return const [Color(0xFF302B63), Color(0xFF24243E)];
      case VideoEffect.speedZoomBlur:
        return const [Color(0xFF833AB4), Color(0xFFFD1D1D)];
      case VideoEffect.lightLeak:
        return const [Color(0xFFFF9966), Color(0xFFFF5E62)];
    }
  }

  PhosphorIconData _getEffectIcon(VideoEffect fx) {
    switch (fx) {
      case VideoEffect.none:
        return PhosphorIconsRegular.prohibit;
      case VideoEffect.warm:
        return PhosphorIconsRegular.sun;
      case VideoEffect.cinematic:
        return PhosphorIconsRegular.videoCamera;
      case VideoEffect.noir:
        return PhosphorIconsRegular.moon;
      case VideoEffect.vibrant:
        return PhosphorIconsRegular.lightning;
      case VideoEffect.vintage:
        return PhosphorIconsRegular.clock;
      case VideoEffect.glitch:
        return PhosphorIconsRegular.sliders;
      case VideoEffect.blur:
        return PhosphorIconsRegular.funnel;
      case VideoEffect.glow:
        return PhosphorIconsRegular.magicWand;
      case VideoEffect.retro:
        return PhosphorIconsRegular.filmStrip;
      case VideoEffect.matrix:
        return PhosphorIconsRegular.code;
      case VideoEffect.flame:
        return PhosphorIconsRegular.fire;
      case VideoEffect.vhs:
      case VideoEffect.vhsTape:
        return PhosphorIconsRegular.television;
      case VideoEffect.wave:
      case VideoEffect.liquidWave:
        return PhosphorIconsRegular.drop;
      case VideoEffect.vignette:
      case VideoEffect.cinematicVignette:
        return PhosphorIconsRegular.circle;
      case VideoEffect.chromaticAberration:
        return PhosphorIconsRegular.sliders;
      case VideoEffect.filmGrain:
        return PhosphorIconsRegular.filmStrip;
      case VideoEffect.dreamBloom:
        return PhosphorIconsRegular.magicWand;
      case VideoEffect.mosaicPixelate:
        return PhosphorIconsRegular.gridFour;
      case VideoEffect.crispSharpen:
        return PhosphorIconsRegular.eye;
      case VideoEffect.lensDistortion:
        return PhosphorIconsRegular.crosshair;
      case VideoEffect.convexScreenPro:
        return PhosphorIconsRegular.television;
      case VideoEffect.speedZoomBlur:
        return PhosphorIconsRegular.lightning;
      case VideoEffect.lightLeak:
        return PhosphorIconsRegular.sun;
    }
  }
}

class _EffectParamSpec {
  const _EffectParamSpec({
    required this.id,
    required this.label,
    required this.min,
    required this.max,
    required this.def,
  });

  final String id;
  final String label;
  final double min;
  final double max;
  final double def;
}

class _EffectConfigView extends StatelessWidget {
  const _EffectConfigView({
    required this.fx,
    required this.clip,
    required this.onBack,
  });

  final VideoEffect fx;
  final TimelineClip? clip;
  final VoidCallback onBack;

  List<_EffectParamSpec> _getSpecsForEffect(VideoEffect effect) {
    switch (effect) {
      case VideoEffect.glitch:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Distortion Amount', min: 0.0, max: 1.0, def: 0.7),
          _EffectParamSpec(id: 'speed', label: 'Glitch Speed', min: 0.2, max: 4.0, def: 1.5),
        ];
      case VideoEffect.blur:
        return const [
          _EffectParamSpec(id: 'blurAmount', label: 'Blur Strength', min: 0.0, max: 5.0, def: 1.5),
        ];
      case VideoEffect.glow:
      case VideoEffect.dreamBloom:
        return const [
          _EffectParamSpec(id: 'intensity', label: 'Bloom Intensity', min: 0.0, max: 1.0, def: 0.5),
          _EffectParamSpec(id: 'threshold', label: 'Luminance Threshold', min: 0.2, max: 0.95, def: 0.6),
          _EffectParamSpec(id: 'radius', label: 'Bloom Radius', min: 0.1, max: 1.0, def: 0.5),
        ];
      case VideoEffect.vhs:
        return const [
          _EffectParamSpec(id: 'distortion', label: 'VHS Distortion', min: 0.0, max: 2.0, def: 1.0),
          _EffectParamSpec(id: 'scanlines', label: 'Scanline Intensity', min: 0.0, max: 1.0, def: 0.5),
          _EffectParamSpec(id: 'noise', label: 'Tape Noise', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.vhsTape:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Tape Distortion', min: 0.0, max: 1.0, def: 0.7),
          _EffectParamSpec(id: 'speed', label: 'Flicker Speed', min: 0.2, max: 4.0, def: 1.0),
        ];
      case VideoEffect.wave:
        return const [
          _EffectParamSpec(id: 'frequency', label: 'Wave Frequency', min: 1.0, max: 30.0, def: 10.0),
          _EffectParamSpec(id: 'amplitude', label: 'Wave Amplitude', min: 0.0, max: 5.0, def: 1.0),
        ];
      case VideoEffect.liquidWave:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Liquid Amount', min: 0.0, max: 2.0, def: 1.0),
          _EffectParamSpec(id: 'freq', label: 'Frequency', min: 0.5, max: 6.0, def: 2.0),
          _EffectParamSpec(id: 'speed', label: 'Flow Speed', min: 0.2, max: 4.0, def: 1.0),
        ];
      case VideoEffect.vignette:
        return const [
          _EffectParamSpec(id: 'radius', label: 'Vignette Radius', min: 0.0, max: 1.0, def: 0.8),
          _EffectParamSpec(id: 'softness', label: 'Edge Softness', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.cinematicVignette:
        return const [
          _EffectParamSpec(id: 'strength', label: 'Darkening Strength', min: 0.0, max: 1.0, def: 0.6),
          _EffectParamSpec(id: 'softness', label: 'Falloff Softness', min: 0.0, max: 1.0, def: 0.6),
        ];
      case VideoEffect.chromaticAberration:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Color Shift Amount', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.filmGrain:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Grain Intensity', min: 0.0, max: 1.0, def: 0.5),
          _EffectParamSpec(id: 'sizePx', label: 'Particle Size', min: 1.0, max: 4.0, def: 1.5),
        ];
      case VideoEffect.mosaicPixelate:
        return const [
          _EffectParamSpec(id: 'sizePx', label: 'Pixel Size (px)', min: 2.0, max: 64.0, def: 12.0),
        ];
      case VideoEffect.crispSharpen:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Sharpen Strength', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.lensDistortion:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Distortion (-1 to 1)', min: -1.0, max: 1.0, def: 0.4),
        ];
      case VideoEffect.convexScreenPro:
        return const [
          _EffectParamSpec(id: 'strength', label: 'Curvature Strength', min: 0.0, max: 1.0, def: 0.5),
          _EffectParamSpec(id: 'radius', label: 'Screen Radius', min: 0.2, max: 1.5, def: 0.8),
        ];
      case VideoEffect.speedZoomBlur:
        return const [
          _EffectParamSpec(id: 'amount', label: 'Zoom Blur Amount', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.lightLeak:
        return const [
          _EffectParamSpec(id: 'intensity', label: 'Leak Intensity', min: 0.0, max: 1.0, def: 0.6),
          _EffectParamSpec(id: 'speed', label: 'Animation Speed', min: 0.2, max: 3.0, def: 1.0),
        ];
      case VideoEffect.warm:
        return const [
          _EffectParamSpec(id: 'warmth', label: 'Warmth Shift', min: 0.0, max: 1.0, def: 0.5),
          _EffectParamSpec(id: 'intensity', label: 'Color Intensity', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.cinematic:
        return const [
          _EffectParamSpec(id: 'contrast', label: 'Cinematic Contrast', min: 0.5, max: 2.0, def: 1.2),
          _EffectParamSpec(id: 'tealShift', label: 'Teal/Orange Boost', min: 0.0, max: 1.0, def: 0.6),
        ];
      case VideoEffect.noir:
        return const [
          _EffectParamSpec(id: 'contrast', label: 'B&W Contrast', min: 0.5, max: 2.5, def: 1.5),
          _EffectParamSpec(id: 'grain', label: 'Film Grain', min: 0.0, max: 1.0, def: 0.3),
        ];
      case VideoEffect.vibrant:
        return const [
          _EffectParamSpec(id: 'saturation', label: 'Color Saturation', min: 0.5, max: 2.0, def: 1.3),
          _EffectParamSpec(id: 'boost', label: 'Vibrance Boost', min: 0.0, max: 1.0, def: 0.5),
        ];
      case VideoEffect.vintage:
        return const [
          _EffectParamSpec(id: 'sepia', label: 'Sepia Tone', min: 0.0, max: 1.0, def: 0.7),
          _EffectParamSpec(id: 'fade', label: 'Fading Amount', min: 0.0, max: 1.0, def: 0.4),
        ];
      case VideoEffect.retro:
        return const [
          _EffectParamSpec(id: 'grain', label: 'Retro Grain', min: 0.0, max: 1.0, def: 0.5),
          _EffectParamSpec(id: 'warmth', label: 'Warmth', min: 0.0, max: 1.0, def: 0.6),
        ];
      case VideoEffect.matrix:
        return const [
          _EffectParamSpec(id: 'density', label: 'Matrix Density', min: 0.0, max: 1.0, def: 0.7),
          _EffectParamSpec(id: 'speed', label: 'Code Speed', min: 0.2, max: 3.0, def: 1.0),
        ];
      case VideoEffect.flame:
        return const [
          _EffectParamSpec(id: 'heat', label: 'Fire Heat', min: 0.0, max: 1.0, def: 0.7),
          _EffectParamSpec(id: 'speed', label: 'Flame Speed', min: 0.2, max: 3.0, def: 1.0),
        ];
      case VideoEffect.none:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final specs = _getSpecsForEffect(fx);
    final currentParams = clip?.effectParameters ?? const <String, double>{};

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: EditorTokens.border)),
          ),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const PhosphorIcon(PhosphorIconsRegular.arrowLeft, color: EditorTokens.text, size: 20),
                onPressed: onBack,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Configure ${fx.name.toUpperCase()}',
                  style: const TextStyle(
                    color: EditorTokens.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Ubuntu Sans',
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final Map<String, double> defaults = {};
                  for (final s in specs) {
                    defaults[s.id] = s.def;
                  }
                  editor.updateEffectParameters(defaults);
                },
                child: const Text('RESET', style: TextStyle(color: EditorTokens.muted, fontSize: 11, fontFamily: 'Ubuntu Sans')),
              ),
            ],
          ),
        ),
        Expanded(
          child: specs.isEmpty
              ? const Center(
                  child: Text(
                    'No configurable parameters for this effect.',
                    style: TextStyle(color: EditorTokens.muted, fontSize: 13, fontFamily: 'Ubuntu Sans'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: specs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final spec = specs[index];
                    final double val = currentParams[spec.id] ?? spec.def;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: EditorTokens.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: EditorTokens.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  spec.label,
                                  style: const TextStyle(
                                    color: EditorTokens.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Ubuntu Sans',
                                  ),
                                ),
                              ),
                              Text(
                                val.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: EditorTokens.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Ubuntu Sans',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SliderTheme(
                            data: const SliderThemeData(
                              trackHeight: 3,
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: EditorTokens.text,
                              inactiveTrackColor: EditorTokens.border,
                              thumbColor: EditorTokens.text,
                            ),
                            child: Slider(
                              value: val.clamp(spec.min, spec.max),
                              min: spec.min,
                              max: spec.max,
                              onChanged: (newVal) {
                                editor.updateEffectParameter(spec.id, newVal);
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
