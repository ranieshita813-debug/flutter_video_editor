import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';
import 'package:flutter_video_editor/features/effects/services/effect_download_service.dart';
import 'package:flutter_video_editor/features/effects/services/shader_effect_service.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_card.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_parameter_panel.dart';
import 'package:flutter_video_editor/features/effects/widgets/effect_preview_widget.dart';

class EffectsLibraryPage extends StatefulWidget {
  const EffectsLibraryPage({
    super.key,
    this.onApplyEffect,
    this.selectedClipTime = Duration.zero,
  });

  final void Function(ShaderEffect effect, ShaderEffectClip clip)? onApplyEffect;
  final Duration selectedClipTime;

  @override
  State<EffectsLibraryPage> createState() => _EffectsLibraryPageState();
}

class _EffectsLibraryPageState extends State<EffectsLibraryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ShaderEffectService _effectService = ShaderEffectService();
  final EffectDownloadService _downloadService = EffectDownloadService.instance;

  ShaderEffect? _selectedEffect;
  ShaderEffectClip? _previewClip;
  bool _isEditingParameters = false;
  String _selectedCategoryTag = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {
      if (_tabController.index == 0) {
        _effectService.toggleFavoritesFilter();
        if (_effectService.showFavoritesOnly) _effectService.toggleFavoritesFilter();
        if (_effectService.showDownloadedOnly) _effectService.toggleDownloadedFilter();
      } else if (_tabController.index == 1) {
        if (!_effectService.showDownloadedOnly) _effectService.toggleDownloadedFilter();
      } else if (_tabController.index == 2) {
        if (!_effectService.showFavoritesOnly) _effectService.toggleFavoritesFilter();
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _effectService.dispose();
    super.dispose();
  }

  void _selectEffect(ShaderEffect effect) {
    setState(() {
      _selectedEffect = effect;
      _previewClip = _effectService.createClipFromEffect(
        effect,
        start: Duration.zero,
        duration: const Duration(seconds: 5),
      );
      _isEditingParameters = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _effectService,
      builder: (context, _) {
        final filteredList = _effectService.filteredEffects;

        if (_selectedEffect == null && filteredList.isNotEmpty) {
          _selectedEffect = filteredList.first;
          _previewClip = _effectService.createClipFromEffect(
            _selectedEffect!,
            start: Duration.zero,
            duration: const Duration(seconds: 5),
          );
        }

        return Scaffold(
          backgroundColor: EditorTokens.bg,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                ToolSearchHeader(
                  onSearchChanged: (q) => _effectService.setSearchQuery(q),
                  onTagSelected: (tag) {
                    setState(() => _selectedCategoryTag = tag);
                    final cat = _mapTagToCategory(tag);
                    _effectService.selectCategory(cat);
                  },
                  selectedTag: _selectedCategoryTag,
                  placeholder: 'Search shader effects...',
                ),
                _buildTabs(),
                if (_selectedEffect != null && _previewClip != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: SizedBox(
                      height: 140,
                      child: EffectPreviewWidget(
                        effect: _selectedEffect!,
                        clip: _previewClip!,
                        playheadTime: widget.selectedClipTime,
                      ),
                    ),
                  ),
                Expanded(
                  child: _isEditingParameters && _selectedEffect != null && _previewClip != null
                      ? EffectParameterPanel(
                          effect: _selectedEffect!,
                          clip: _previewClip!,
                          playheadTime: widget.selectedClipTime,
                          onParameterChanged: (paramId, newValue) {
                            setState(() {
                              _previewClip!.parameterValues[paramId] = newValue;
                            });
                          },
                          onAddKeyframe: (paramId, value, easing) {
                            setState(() {
                              final relativeTime = widget.selectedClipTime - _previewClip!.start;
                              final newKf = ShaderKeyframe(
                                id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
                                time: relativeTime,
                                value: value,
                                easing: easing,
                              );
                              final index = _previewClip!.keyframeAnimations.indexWhere(
                                (a) => a.parameterId == paramId,
                              );
                              if (index != -1) {
                                final existing = _previewClip!.keyframeAnimations[index];
                                final updatedKfs = List<ShaderKeyframe>.from(existing.keyframes)
                                  ..removeWhere((k) => (k.time - relativeTime).abs() < const Duration(milliseconds: 50))
                                  ..add(newKf);
                                _previewClip!.keyframeAnimations[index] = existing.copyWith(keyframes: updatedKfs);
                              } else {
                                _previewClip!.keyframeAnimations.add(KeyframeAnimation(
                                  id: 'anim_${DateTime.now().millisecondsSinceEpoch}',
                                  parameterId: paramId,
                                  keyframes: [newKf],
                                ));
                              }
                            });
                          },
                          onRemoveKeyframe: (paramId, kfId) {
                            setState(() {
                              final index = _previewClip!.keyframeAnimations.indexWhere(
                                (a) => a.parameterId == paramId,
                              );
                              if (index != -1) {
                                final existing = _previewClip!.keyframeAnimations[index];
                                final updatedKfs = List<ShaderKeyframe>.from(existing.keyframes)
                                  ..removeWhere((k) => k.id == kfId);
                                _previewClip!.keyframeAnimations[index] = existing.copyWith(keyframes: updatedKfs);
                              }
                            });
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.9,
                          ),
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final effect = filteredList[index];
                            final isSelected = _selectedEffect?.id == effect.id;
                            final isDownloading = _downloadService.isDownloading(effect.id);
                            final progress = _downloadService.getDownloadProgress(effect.id);

                            return EffectCard(
                              effect: effect,
                              isSelected: isSelected,
                              downloadProgress: isDownloading ? progress : null,
                              onTap: () => _selectEffect(effect),
                              onToggleFavorite: () async {
                                await _effectService.toggleFavorite(effect.id);
                              },
                              onDownload: () async {
                                await _downloadService.downloadEffect(effect);
                                setState(() {});
                              },
                            );
                          },
                        ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: EditorTokens.surface,
      child: Row(
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedMagicWand01,
            color: EditorTokens.text,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Shader Effects Library',
              style: TextStyle(
                color: EditorTokens.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              color: EditorTokens.text,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: EditorTokens.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: EditorTokens.text,
        labelColor: EditorTokens.text,
        unselectedLabelColor: EditorTokens.muted,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'Poppins',
        ),
        tabs: const [
          Tab(text: 'ALL EFFECTS'),
          Tab(text: 'DOWNLOADED'),
          Tab(text: 'FAVORITES'),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: EditorTokens.surface,
        border: Border(top: BorderSide(color: EditorTokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: EditorTokens.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                setState(() => _isEditingParameters = !_isEditingParameters);
              },
              icon: HugeIcon(
                icon: _isEditingParameters
                    ? HugeIcons.strokeRoundedGridView
                    : HugeIcons.strokeRoundedFilter,
                color: EditorTokens.text,
                size: 18,
              ),
              label: Text(
                _isEditingParameters ? 'BROWSE' : 'CONTROLS',
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: EditorTokens.text,
                foregroundColor: EditorTokens.bg,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: (_selectedEffect != null && _previewClip != null)
                  ? () {
                      if (widget.onApplyEffect != null) {
                        widget.onApplyEffect!(_selectedEffect!, _previewClip!);
                      }
                      Navigator.of(context).pop(_previewClip);
                    }
                  : null,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedTick01,
                color: EditorTokens.bg,
                size: 18,
              ),
              label: const Text(
                'APPLY EFFECT',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ShaderEffectCategory _mapTagToCategory(String tag) {
    switch (tag.toLowerCase()) {
      case 'glow':
      case 'neon':
        return ShaderEffectCategory.glow;
      case 'blur':
        return ShaderEffectCategory.blur;
      case 'cinematic':
        return ShaderEffectCategory.cinematic;
      case 'retro':
      case 'vintage':
        return ShaderEffectCategory.vintage;
      case 'noir':
        return ShaderEffectCategory.noir;
      case 'glitch':
        return ShaderEffectCategory.glitch;
      case 'bloom':
        return ShaderEffectCategory.bloom;
      case 'light leak':
        return ShaderEffectCategory.lightLeak;
      case 'distortion':
        return ShaderEffectCategory.distortion;
      case 'color':
        return ShaderEffectCategory.colorStyle;
      default:
        return ShaderEffectCategory.all;
    }
  }
}
