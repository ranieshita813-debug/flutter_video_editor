import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/effects/pages/effects_library_page.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_timeline_chip.dart';

const _font = 'Ubuntu Sans';
const _tabs = ['All', 'Cinematic', 'Retro', 'Glitch'];

class EffectsSheet extends StatefulWidget {
  const EffectsSheet({super.key, required this.isFilterMode});
  final bool isFilterMode;

  @override
  State<EffectsSheet> createState() => _EffectsSheetState();
}

class _EffectsSheetState extends State<EffectsSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';
  bool _searching = false;
  VideoEffect? _configuringFx;

  void _openEffectsLibrary(BuildContext context, EditorController editor) async {
    final clip = editor.selectedClip;
    bool appliedViaCallback = false;
    final result = await Navigator.of(context).push<ShaderEffectClip>(
      MaterialPageRoute(
        builder: (_) => EffectsLibraryPage(
          selectedClipTime: editor.playhead,
          onApplyEffect: (effect, shaderClip) {
            if (clip != null) {
              appliedViaCallback = true;
              editor.addShaderEffectToSelectedClip(shaderClip);
            }
          },
        ),
      ),
    );

    if (result != null && clip != null && !appliedViaCallback) {
      editor.addShaderEffectToSelectedClip(result);
    }
  }

  bool _matchesTab(VideoEffect fx) {
    switch (_selectedTag) {
      case 'Cinematic':
        return fx == VideoEffect.cinematic ||
            fx == VideoEffect.noir ||
            fx == VideoEffect.cinematicVignette;
      case 'Retro':
        return fx == VideoEffect.vintage || fx == VideoEffect.retro || fx == VideoEffect.vhs;
      case 'Glitch':
        return fx == VideoEffect.glitch || fx == VideoEffect.matrix;
      default:
        return true;
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

    final q = _searchQuery.toLowerCase();
    final filtered = VideoEffect.values
        .where((fx) => fx.name.toLowerCase().contains(q) && _matchesTab(fx))
        .toList();

    return Column(
      children: [
        _buildTopBar(context, editor, currentEffect),
        if (appliedShaderEffects.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              scrollDirection: Axis.horizontal,
              itemCount: appliedShaderEffects.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final fx = appliedShaderEffects[i];
                return EffectTimelineChip(
                  effectClip: fx,
                  isSelected: true,
                  onToggleEnabled: () => editor.toggleShaderEffectEnabled(fx.id),
                  onRemove: () => editor.removeShaderEffectFromSelectedClip(fx.id),
                  onTap: () => _openEffectsLibrary(context, editor),
                );
              },
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No effects found',
                    style: TextStyle(color: EditorTokens.muted, fontSize: 13, fontFamily: _font),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final fx = filtered[index];
                    final isSelected = fx == currentEffect;
                    return _EffectTile(
                      fx: fx,
                      isSelected: isSelected,
                      onTap: () {
                        if (isSelected && fx != VideoEffect.none) {
                          setState(() => _configuringFx = fx);
                        } else {
                          editor.applyEffect(fx);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, EditorController editor, VideoEffect current) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTokens.border, width: 0.5)),
      ),
      child: _searching
          ? Row(
              children: [
                const SizedBox(width: 14),
                const PhosphorIcon(PhosphorIconsRegular.magnifyingGlass,
                    color: EditorTokens.muted, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    cursorColor: EditorTokens.text,
                    style: const TextStyle(
                        color: EditorTokens.text, fontSize: 14, fontFamily: _font),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: widget.isFilterMode ? 'Search filters' : 'Search effects',
                      hintStyle: const TextStyle(
                          color: EditorTokens.muted, fontSize: 14, fontFamily: _font),
                    ),
                  ),
                ),
                IconButton(
                  icon: const PhosphorIcon(PhosphorIconsRegular.x,
                      color: EditorTokens.text, size: 18),
                  onPressed: () => setState(() {
                    _searching = false;
                    _searchQuery = '';
                  }),
                ),
              ],
            )
          : Row(
              children: [
                IconButton(
                  tooltip: 'Effects store',
                  icon: const PhosphorIcon(PhosphorIconsRegular.storefront,
                      color: EditorTokens.text, size: 20),
                  onPressed: () => _openEffectsLibrary(context, editor),
                ),
                Container(width: 1, height: 16, color: EditorTokens.border),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: _tabs.length,
                    itemBuilder: (_, i) {
                      final tab = _tabs[i];
                      final active = tab == _selectedTag;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selectedTag = tab),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                tab,
                                style: TextStyle(
                                  color: active ? EditorTokens.text : EditorTokens.muted,
                                  fontSize: 14,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                  fontFamily: _font,
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: 2,
                                width: active ? 16 : 0,
                                decoration: BoxDecoration(
                                  color: EditorTokens.text,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (current != VideoEffect.none)
                  IconButton(
                    tooltip: 'Adjust',
                    icon: const PhosphorIcon(PhosphorIconsRegular.slidersHorizontal,
                        color: EditorTokens.text, size: 20),
                    onPressed: () => setState(() => _configuringFx = current),
                  ),
                IconButton(
                  icon: const PhosphorIcon(PhosphorIconsRegular.magnifyingGlass,
                      color: EditorTokens.text, size: 20),
                  onPressed: () => setState(() => _searching = true),
                ),
              ],
            ),
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({required this.fx, required this.isSelected, required this.onTap});
  final VideoEffect fx;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isNone = fx == VideoEffect.none;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? EditorTokens.text : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: EdgeInsets.all(isSelected ? 2 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isNone ? EditorTokens.elevated : null,
                    gradient: isNone
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _gradientFor(fx),
                          ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PhosphorIcon(
                        _iconFor(fx),
                        color: isNone ? EditorTokens.muted : Colors.white,
                        size: isNone ? 22 : 24,
                      ),
                      if (isSelected && !isNone)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: EditorTokens.text,
                              borderRadius: BorderRadius.only(topLeft: Radius.circular(6)),
                            ),
                            child: const PhosphorIcon(
                              PhosphorIconsBold.slidersHorizontal,
                              color: EditorTokens.bg,
                              size: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            isNone ? 'None' : _prettyName(fx.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? EditorTokens.text : EditorTokens.muted,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontFamily: _font,
            ),
          ),
        ],
      ),
    );
  }
}

String _prettyName(String camel) {
  final spaced = camel.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

const Map<VideoEffect, List<Color>> _gradients = {
  VideoEffect.warm: [Color(0xFFFF7E5F), Color(0xFFFEB47B)],
  VideoEffect.cinematic: [Color(0xFF003366), Color(0xFF336699)],
  VideoEffect.noir: [Color(0xFF434343), Color(0xFF000000)],
  VideoEffect.vibrant: [Color(0xFFFF007F), Color(0xFF7F00FF)],
  VideoEffect.vintage: [Color(0xFFC94B4C), Color(0xFF4D13D1)],
  VideoEffect.glitch: [Color(0xFF00E5FF), Color(0xFFFF0055)],
  VideoEffect.blur: [Color(0xFF3A6073), Color(0xFF16222A)],
  VideoEffect.glow: [Color(0xFFFF00CC), Color(0xFF333399)],
  VideoEffect.retro: [Color(0xFFF7971E), Color(0xFFFFD200)],
  VideoEffect.matrix: [Color(0xFF00FF87), Color(0xFF60EFFF)],
  VideoEffect.flame: [Color(0xFFF857A6), Color(0xFFFF5858)],
  VideoEffect.vhs: [Color(0xFF8A2387), Color(0xFFE94057)],
  VideoEffect.vhsTape: [Color(0xFF8A2387), Color(0xFFE94057)],
  VideoEffect.wave: [Color(0xFF42275A), Color(0xFF734B6D)],
  VideoEffect.liquidWave: [Color(0xFF42275A), Color(0xFF734B6D)],
  VideoEffect.vignette: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
  VideoEffect.cinematicVignette: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
  VideoEffect.chromaticAberration: [Color(0xFF11998E), Color(0xFF38EF7D)],
  VideoEffect.filmGrain: [Color(0xFF3E5151), Color(0xFFDECBA4)],
  VideoEffect.dreamBloom: [Color(0xFFFF512F), Color(0xFFDD2476)],
  VideoEffect.mosaicPixelate: [Color(0xFF4568DC), Color(0xFFB06AB3)],
  VideoEffect.crispSharpen: [Color(0xFF136A8A), Color(0xFF267871)],
  VideoEffect.lensDistortion: [Color(0xFF00B4DB), Color(0xFF0083B0)],
  VideoEffect.convexScreenPro: [Color(0xFF302B63), Color(0xFF24243E)],
  VideoEffect.speedZoomBlur: [Color(0xFF833AB4), Color(0xFFFD1D1D)],
  VideoEffect.lightLeak: [Color(0xFFFF9966), Color(0xFFFF5E62)],
};

List<Color> _gradientFor(VideoEffect fx) =>
    _gradients[fx] ?? const [Color(0xFF2A2A30), Color(0xFF1B1B20)];

PhosphorIconData _iconFor(VideoEffect fx) {
  switch (fx) {
    case VideoEffect.none:
      return PhosphorIconsRegular.prohibit;
    case VideoEffect.warm:
    case VideoEffect.lightLeak:
      return PhosphorIconsRegular.sun;
    case VideoEffect.cinematic:
      return PhosphorIconsRegular.videoCamera;
    case VideoEffect.noir:
      return PhosphorIconsRegular.moon;
    case VideoEffect.vibrant:
    case VideoEffect.speedZoomBlur:
      return PhosphorIconsRegular.lightning;
    case VideoEffect.vintage:
      return PhosphorIconsRegular.clock;
    case VideoEffect.glitch:
    case VideoEffect.chromaticAberration:
      return PhosphorIconsRegular.sliders;
    case VideoEffect.blur:
      return PhosphorIconsRegular.funnel;
    case VideoEffect.glow:
    case VideoEffect.dreamBloom:
      return PhosphorIconsRegular.magicWand;
    case VideoEffect.retro:
    case VideoEffect.filmGrain:
      return PhosphorIconsRegular.filmStrip;
    case VideoEffect.matrix:
      return PhosphorIconsRegular.code;
    case VideoEffect.flame:
      return PhosphorIconsRegular.fire;
    case VideoEffect.vhs:
    case VideoEffect.vhsTape:
    case VideoEffect.convexScreenPro:
      return PhosphorIconsRegular.television;
    case VideoEffect.wave:
    case VideoEffect.liquidWave:
      return PhosphorIconsRegular.drop;
    case VideoEffect.vignette:
    case VideoEffect.cinematicVignette:
      return PhosphorIconsRegular.circle;
    case VideoEffect.mosaicPixelate:
      return PhosphorIconsRegular.gridFour;
    case VideoEffect.crispSharpen:
      return PhosphorIconsRegular.eye;
    case VideoEffect.lensDistortion:
      return PhosphorIconsRegular.crosshair;
  }
}

class _P {
  const _P(this.id, this.label, this.min, this.max, this.def);
  final String id;
  final String label;
  final double min;
  final double max;
  final double def;
}

List<_P> _specsFor(VideoEffect effect) {
  switch (effect) {
    case VideoEffect.glitch:
      return const [
        _P('amount', 'Distortion', 0.0, 1.0, 0.7),
        _P('speed', 'Speed', 0.2, 4.0, 1.5),
      ];
    case VideoEffect.blur:
      return const [_P('blurAmount', 'Strength', 0.0, 5.0, 1.5)];
    case VideoEffect.glow:
    case VideoEffect.dreamBloom:
      return const [
        _P('intensity', 'Intensity', 0.0, 1.0, 0.5),
        _P('threshold', 'Threshold', 0.2, 0.95, 0.6),
        _P('radius', 'Radius', 0.1, 1.0, 0.5),
      ];
    case VideoEffect.vhs:
      return const [
        _P('distortion', 'Distortion', 0.0, 2.0, 1.0),
        _P('scanlines', 'Scanlines', 0.0, 1.0, 0.5),
        _P('noise', 'Noise', 0.0, 1.0, 0.5),
      ];
    case VideoEffect.vhsTape:
      return const [
        _P('amount', 'Distortion', 0.0, 1.0, 0.7),
        _P('speed', 'Flicker speed', 0.2, 4.0, 1.0),
      ];
    case VideoEffect.wave:
      return const [
        _P('frequency', 'Frequency', 1.0, 30.0, 10.0),
        _P('amplitude', 'Amplitude', 0.0, 5.0, 1.0),
      ];
    case VideoEffect.liquidWave:
      return const [
        _P('amount', 'Amount', 0.0, 2.0, 1.0),
        _P('freq', 'Frequency', 0.5, 6.0, 2.0),
        _P('speed', 'Flow speed', 0.2, 4.0, 1.0),
      ];
    case VideoEffect.vignette:
      return const [
        _P('radius', 'Radius', 0.0, 1.0, 0.8),
        _P('softness', 'Softness', 0.0, 1.0, 0.5),
      ];
    case VideoEffect.cinematicVignette:
      return const [
        _P('strength', 'Strength', 0.0, 1.0, 0.6),
        _P('softness', 'Softness', 0.0, 1.0, 0.6),
      ];
    case VideoEffect.chromaticAberration:
      return const [_P('amount', 'Color shift', 0.0, 1.0, 0.5)];
    case VideoEffect.filmGrain:
      return const [
        _P('amount', 'Intensity', 0.0, 1.0, 0.5),
        _P('sizePx', 'Particle size', 1.0, 4.0, 1.5),
      ];
    case VideoEffect.mosaicPixelate:
      return const [_P('sizePx', 'Pixel size', 2.0, 64.0, 12.0)];
    case VideoEffect.crispSharpen:
      return const [_P('amount', 'Strength', 0.0, 1.0, 0.5)];
    case VideoEffect.lensDistortion:
      return const [_P('amount', 'Distortion', -1.0, 1.0, 0.4)];
    case VideoEffect.convexScreenPro:
      return const [
        _P('strength', 'Curvature', 0.0, 1.0, 0.5),
        _P('radius', 'Radius', 0.2, 1.5, 0.8),
      ];
    case VideoEffect.speedZoomBlur:
      return const [_P('amount', 'Amount', 0.0, 1.0, 0.5)];
    case VideoEffect.lightLeak:
      return const [
        _P('intensity', 'Intensity', 0.0, 1.0, 0.6),
        _P('speed', 'Speed', 0.2, 3.0, 1.0),
      ];
    case VideoEffect.warm:
      return const [
        _P('warmth', 'Warmth', 0.0, 1.0, 0.5),
        _P('intensity', 'Intensity', 0.0, 1.0, 0.5),
      ];
    case VideoEffect.cinematic:
      return const [
        _P('contrast', 'Contrast', 0.5, 2.0, 1.2),
        _P('tealShift', 'Teal & orange', 0.0, 1.0, 0.6),
      ];
    case VideoEffect.noir:
      return const [
        _P('contrast', 'Contrast', 0.5, 2.5, 1.5),
        _P('grain', 'Grain', 0.0, 1.0, 0.3),
      ];
    case VideoEffect.vibrant:
      return const [
        _P('saturation', 'Saturation', 0.5, 2.0, 1.3),
        _P('boost', 'Vibrance', 0.0, 1.0, 0.5),
      ];
    case VideoEffect.vintage:
      return const [
        _P('sepia', 'Sepia', 0.0, 1.0, 0.7),
        _P('fade', 'Fade', 0.0, 1.0, 0.4),
      ];
    case VideoEffect.retro:
      return const [
        _P('grain', 'Grain', 0.0, 1.0, 0.5),
        _P('warmth', 'Warmth', 0.0, 1.0, 0.6),
      ];
    case VideoEffect.matrix:
      return const [
        _P('density', 'Density', 0.0, 1.0, 0.7),
        _P('speed', 'Speed', 0.2, 3.0, 1.0),
      ];
    case VideoEffect.flame:
      return const [
        _P('heat', 'Heat', 0.0, 1.0, 0.7),
        _P('speed', 'Speed', 0.2, 3.0, 1.0),
      ];
    case VideoEffect.none:
      return const [];
  }
}

class _EffectConfigView extends StatelessWidget {
  const _EffectConfigView({required this.fx, required this.clip, required this.onBack});

  final VideoEffect fx;
  final TimelineClip? clip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final specs = _specsFor(fx);
    final currentParams = clip?.effectParameters ?? const <String, double>{};

    return Column(
      children: [
        SizedBox(
          height: 46,
          child: Row(
            children: [
              IconButton(
                icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft,
                    color: EditorTokens.text, size: 20),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  _prettyName(fx.name),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: EditorTokens.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: _font,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Reset',
                icon: const PhosphorIcon(PhosphorIconsRegular.arrowCounterClockwise,
                    color: EditorTokens.text, size: 20),
                onPressed: () => editor.updateEffectParameters({
                  for (final s in specs) s.id: s.def,
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: specs.isEmpty
              ? const Center(
                  child: Text(
                    'No adjustable settings for this effect',
                    style: TextStyle(color: EditorTokens.muted, fontSize: 13, fontFamily: _font),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: specs.length,
                  itemBuilder: (context, index) {
                    final spec = specs[index];
                    final val = (currentParams[spec.id] ?? spec.def).clamp(spec.min, spec.max);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              spec.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: EditorTokens.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                fontFamily: _font,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8, elevation: 2),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                activeTrackColor: EditorTokens.text,
                                inactiveTrackColor: EditorTokens.border,
                                thumbColor: EditorTokens.text,
                                overlayColor: EditorTokens.text.withValues(alpha: 0.12),
                              ),
                              child: Slider(
                                value: val.toDouble(),
                                min: spec.min,
                                max: spec.max,
                                onChanged: (v) => editor.updateEffectParameter(spec.id, v),
                              ),
                            ),
                          ),
                          Container(
                            width: 44,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: EditorTokens.elevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              val.toStringAsFixed(val.abs() >= 10 ? 0 : 2),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: EditorTokens.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: _font,
                              ),
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