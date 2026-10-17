import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/core/widgets/loading_wave.dart';

// ───────────────────────── Models ─────────────────────────

enum AiMediaType { image, video }

enum AiCapability { imageInput, audio, editing, fast, textRendering }

const _capabilityLabels = <AiCapability, String>{
  AiCapability.imageInput: 'Image input',
  AiCapability.audio: 'Audio',
  AiCapability.editing: 'Editing',
  AiCapability.fast: 'Fast',
  AiCapability.textRendering: 'Text',
};

/// One selectable AI model. `id` is what you send to your backend.
class AiModelOption {
  const AiModelOption({
    required this.id,
    required this.name,
    required this.provider,
    required this.description,
    required this.type,
    required this.creditsPerUnit,
    this.capabilities = const [],
    this.supportsNegativePrompt = false,
    this.supportsSeed = true,
    this.durations = const [],
    this.badge,
  });

  final String id;
  final String name;
  final String provider;
  final String description;
  final AiMediaType type;

  /// Credits per image, or per second of video (your own pricing).
  final int creditsPerUnit;
  final List<AiCapability> capabilities;
  final bool supportsNegativePrompt;
  final bool supportsSeed;

  /// Allowed clip lengths in seconds (video only).
  final List<int> durations;
  final String? badge;

  bool get supportsReference => capabilities.contains(AiCapability.imageInput);
}

/// Starter catalog. Ids, durations and credit costs are placeholders:
/// map them to what your provider or aggregator actually exposes.
class AiModelCatalog {
  static const defaults = <AiModelOption>[
    // Video
    AiModelOption(
      id: 'veo-3.1',
      name: 'Veo 3.1',
      provider: 'Google',
      description: 'Cinematic video with native audio',
      type: AiMediaType.video,
      creditsPerUnit: 8,
      capabilities: [AiCapability.imageInput, AiCapability.audio],
      durations: [4, 6, 8],
      badge: 'Top quality',
    ),
    AiModelOption(
      id: 'grok-imagine-video',
      name: 'Grok Imagine',
      provider: 'xAI',
      description: 'Great value, longer clips',
      type: AiMediaType.video,
      creditsPerUnit: 5,
      capabilities: [AiCapability.imageInput, AiCapability.editing],
      durations: [5, 10, 15],
      badge: 'Best value',
    ),
    AiModelOption(
      id: 'kling-2.5-pro',
      name: 'Kling 2.5 Pro',
      provider: 'Kuaishou',
      description: 'Consistent characters and scenes',
      type: AiMediaType.video,
      creditsPerUnit: 6,
      capabilities: [AiCapability.imageInput],
      durations: [5, 10],
    ),
    AiModelOption(
      id: 'seedance-1.5-pro',
      name: 'Seedance 1.5 Pro',
      provider: 'ByteDance',
      description: 'Fast multi-shot iteration',
      type: AiMediaType.video,
      creditsPerUnit: 4,
      capabilities: [AiCapability.imageInput, AiCapability.fast],
      durations: [5, 10],
    ),
    AiModelOption(
      id: 'runway-gen-4.5',
      name: 'Gen-4.5',
      provider: 'Runway',
      description: 'Creative control and editing tools',
      type: AiMediaType.video,
      creditsPerUnit: 7,
      capabilities: [AiCapability.imageInput, AiCapability.editing],
      durations: [5, 10],
    ),
    AiModelOption(
      id: 'hailuo-02',
      name: 'Hailuo 02',
      provider: 'MiniMax',
      description: 'Quick, eye-catching clips',
      type: AiMediaType.video,
      creditsPerUnit: 3,
      capabilities: [AiCapability.imageInput, AiCapability.fast],
      durations: [6, 10],
    ),
    AiModelOption(
      id: 'luma-ray-2',
      name: 'Ray 2',
      provider: 'Luma',
      description: 'Physics-accurate motion',
      type: AiMediaType.video,
      creditsPerUnit: 5,
      capabilities: [AiCapability.imageInput],
      durations: [5, 9],
    ),
    AiModelOption(
      id: 'wan-2.5',
      name: 'Wan 2.5',
      provider: 'Alibaba',
      description: 'Open-weight, low cost',
      type: AiMediaType.video,
      creditsPerUnit: 2,
      capabilities: [AiCapability.imageInput, AiCapability.audio],
      durations: [5, 10],
      supportsNegativePrompt: true,
    ),

    // Image
    AiModelOption(
      id: 'gpt-image-2',
      name: 'GPT Image 2',
      provider: 'OpenAI',
      description: 'Best prompt following and edits',
      type: AiMediaType.image,
      creditsPerUnit: 6,
      capabilities: [AiCapability.imageInput, AiCapability.editing, AiCapability.textRendering],
      supportsSeed: false,
      badge: 'Top quality',
    ),
    AiModelOption(
      id: 'nano-banana-2',
      name: 'Nano Banana 2',
      provider: 'Google',
      description: 'Fast, versatile, strong edits',
      type: AiMediaType.image,
      creditsPerUnit: 3,
      capabilities: [AiCapability.imageInput, AiCapability.editing, AiCapability.fast],
      supportsSeed: false,
      badge: 'Popular',
    ),
    AiModelOption(
      id: 'imagen-4',
      name: 'Imagen 4',
      provider: 'Google',
      description: 'Photorealistic with crisp detail',
      type: AiMediaType.image,
      creditsPerUnit: 3,
      capabilities: [AiCapability.textRendering],
    ),
    AiModelOption(
      id: 'flux-2-max',
      name: 'FLUX.2 Max',
      provider: 'Black Forest Labs',
      description: 'Top FLUX quality and edits',
      type: AiMediaType.image,
      creditsPerUnit: 4,
      capabilities: [AiCapability.imageInput, AiCapability.editing],
    ),
    AiModelOption(
      id: 'grok-imagine-image',
      name: 'Grok Imagine',
      provider: 'xAI',
      description: 'Fast and cheap',
      type: AiMediaType.image,
      creditsPerUnit: 1,
      capabilities: [AiCapability.imageInput, AiCapability.editing, AiCapability.fast],
    ),
    AiModelOption(
      id: 'seedream-4',
      name: 'Seedream 4',
      provider: 'ByteDance',
      description: 'Budget quality',
      type: AiMediaType.image,
      creditsPerUnit: 2,
      capabilities: [AiCapability.imageInput, AiCapability.editing],
    ),
    AiModelOption(
      id: 'ideogram-3',
      name: 'Ideogram 3',
      provider: 'Ideogram',
      description: 'Posters, logos, text in images',
      type: AiMediaType.image,
      creditsPerUnit: 3,
      capabilities: [AiCapability.textRendering],
    ),
    AiModelOption(
      id: 'sd-3.5',
      name: 'Stable Diffusion 3.5',
      provider: 'Stability AI',
      description: 'Full control, negative prompts',
      type: AiMediaType.image,
      creditsPerUnit: 1,
      supportsNegativePrompt: true,
    ),
  ];
}

class AiGenerationRequest {
  const AiGenerationRequest({
    required this.type,
    required this.modelId,
    required this.prompt,
    required this.aspectRatio,
    required this.count,
    required this.guidance,
    required this.steps,
    this.negativePrompt,
    this.style,
    this.seed,
    this.durationSeconds,
    this.motionStrength,
    this.referenceImagePath,
  });

  final AiMediaType type;
  final String modelId;
  final String prompt;
  final String? negativePrompt;
  final String? style;
  final String aspectRatio;
  final int count;
  final double guidance;
  final int steps;
  final int? seed;
  final int? durationSeconds;
  final double? motionStrength;
  final String? referenceImagePath;
}

class _Ratio {
  const _Ratio(this.label, this.hint);
  final String label;
  final String hint;
}

// ───────────────────────── Entry point ─────────────────────────

/// Opens the generator as a drag-resizable bottom sheet (starts at ~55% height).
Future<void> showAiGenerateSheet(
  BuildContext context, {
  required Future<void> Function(AiGenerationRequest request) onGenerate,
  List<AiModelOption> models = AiModelCatalog.defaults,
  AiMediaType initialType = AiMediaType.video,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: EditorTokens.bg,
    constraints: const BoxConstraints(maxWidth: 760),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, controller) => AiGenerateSheet(
        scrollController: controller,
        onGenerate: onGenerate,
        models: models,
        initialType: initialType,
      ),
    ),
  );
}

// ───────────────────────── Sheet ─────────────────────────

class AiGenerateSheet extends StatefulWidget {
  const AiGenerateSheet({
    super.key,
    required this.onGenerate,
    this.models = AiModelCatalog.defaults,
    this.initialType = AiMediaType.video,
    this.scrollController,
  });

  final Future<void> Function(AiGenerationRequest request) onGenerate;
  final List<AiModelOption> models;
  final AiMediaType initialType;
  final ScrollController? scrollController;

  @override
  State<AiGenerateSheet> createState() => _AiGenerateSheetState();
}

class _AiGenerateSheetState extends State<AiGenerateSheet> {
  static const _ratios = <_Ratio>[
    _Ratio('9:16', 'Vertical'),
    _Ratio('1:1', 'Square'),
    _Ratio('16:9', 'Wide'),
    _Ratio('4:3', 'Classic'),
    _Ratio('3:4', 'Portrait'),
  ];
  static const _styles = ['None', 'Cinematic', 'Anime', '3D render', 'Photo', 'Watercolor'];

  final _promptCtl = TextEditingController();
  final _negCtl = TextEditingController();
  final _seedCtl = TextEditingController();

  late AiMediaType _type = widget.initialType;
  late String _modelId = _modelsOf(widget.initialType).first.id;
  int _ratioIndex = 0;
  int _count = 1;
  int? _duration;
  double _guidance = 7.5;
  int _steps = 30;
  double _motion = 0.5;
  String _style = 'None';
  String? _refPath;
  bool _busy = false;
  String? _promptError;

  List<AiModelOption> _modelsOf(AiMediaType t) =>
      widget.models.where((m) => m.type == t).toList();

  AiModelOption get _model {
    final list = _modelsOf(_type);
    return list.firstWhere((m) => m.id == _modelId, orElse: () => list.first);
  }

  bool get _isVideo => _type == AiMediaType.video;

  int get _credits => _model.creditsPerUnit *
      (_isVideo ? (_duration ?? (_model.durations.isEmpty ? 5 : _model.durations.first)) : _count);

  @override
  void initState() {
    super.initState();
    _syncDuration();
  }

  @override
  void dispose() {
    _promptCtl.dispose();
    _negCtl.dispose();
    _seedCtl.dispose();
    super.dispose();
  }

  void _syncDuration() {
    if (_isVideo && _model.durations.isNotEmpty) {
      _duration = _model.durations.contains(_duration) ? _duration : _model.durations.first;
    } else {
      _duration = null;
    }
  }

  void _setType(AiMediaType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _modelId = _modelsOf(t).first.id;
      if (!_model.supportsReference) _refPath = null;
      _syncDuration();
    });
  }

  void _setModel(AiModelOption m) {
    setState(() {
      _modelId = m.id;
      if (!m.supportsReference) _refPath = null;
      _syncDuration();
    });
  }

  Future<void> _openModelPicker() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<AiModelOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: EditorTokens.bg,
      constraints: const BoxConstraints(maxWidth: 760),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ModelPicker(models: _modelsOf(_type), selectedId: _model.id),
    );
    if (picked != null) _setModel(picked);
  }

  Future<void> _pickReference() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = res?.files.single.path;
      if (path != null) setState(() => _refPath = path);
    } catch (_) {
      _toast('Could not open that image');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Future<void> _generate() async {
    final prompt = _promptCtl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _promptError = 'Describe what you want to create');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await widget.onGenerate(
        AiGenerationRequest(
          type: _type,
          modelId: _model.id,
          prompt: prompt,
          negativePrompt: _model.supportsNegativePrompt && _negCtl.text.trim().isNotEmpty
              ? _negCtl.text.trim()
              : null,
          style: _style == 'None' ? null : _style,
          aspectRatio: _ratios[_ratioIndex].label,
          count: _isVideo ? 1 : _count,
          guidance: _guidance,
          steps: _steps,
          seed: _model.supportsSeed ? int.tryParse(_seedCtl.text.trim()) : null,
          durationSeconds: _duration,
          motionStrength: _isVideo ? _motion : null,
          referenceImagePath: _refPath,
        ),
      );
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      _toast('Generation failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Sections ──

  Widget _header() => Row(
        children: [
          Expanded(child: _TypeToggle(type: _type, onChanged: _setType)),
          const SizedBox(width: 8),
          _IconBtn(
            icon: PhosphorIconsRegular.x,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      );

  Widget _promptField() => TextField(
        controller: _promptCtl,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        style: _fieldStyle,
        onChanged: (_) {
          if (_promptError != null) setState(() => _promptError = null);
        },
        decoration: _decoration(
          _isVideo
              ? 'A drone shot over a misty forest at sunrise'
              : 'A neon-lit street in the rain, reflections on the road',
        ).copyWith(errorText: _promptError, counterText: ''),
      );

  Widget _modelRow() => _ModelRow(model: _model, onTap: _openModelPicker);

  Widget _pills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Pill<int>(
          icon: PhosphorIconsRegular.frameCorners,
          label: _ratios[_ratioIndex].label,
          items: List.generate(_ratios.length, (i) => i),
          labelOf: (i) => '${_ratios[i].label}  ·  ${_ratios[i].hint}',
          onSelected: (i) => setState(() => _ratioIndex = i),
        ),
        if (_isVideo && _model.durations.isNotEmpty)
          _Pill<int>(
            icon: PhosphorIconsRegular.timer,
            label: '${_duration ?? _model.durations.first}s',
            items: _model.durations,
            labelOf: (d) => '$d seconds',
            onSelected: (d) => setState(() => _duration = d),
          )
        else if (!_isVideo)
          _Pill<int>(
            icon: PhosphorIconsRegular.images,
            label: '$_count ${_count == 1 ? 'image' : 'images'}',
            items: const [1, 2, 3, 4],
            labelOf: (n) => '$n ${n == 1 ? 'image' : 'images'}',
            onSelected: (n) => setState(() => _count = n),
          ),
        _Pill<String>(
          icon: PhosphorIconsRegular.paintBrush,
          label: _style == 'None' ? 'Style' : _style,
          items: _styles,
          labelOf: (s) => s,
          onSelected: (s) => setState(() => _style = s),
        ),
        if (_model.supportsReference)
          _RefPill(
            path: _refPath,
            label: _isVideo ? 'Start frame' : 'Reference',
            onPick: _pickReference,
            onClear: () => setState(() => _refPath = null),
          ),
      ],
    );
  }

  Widget _advanced() => _Advanced(
        children: [
          if (_model.supportsNegativePrompt) ...[
            TextField(
              controller: _negCtl,
              minLines: 1,
              maxLines: 2,
              style: _fieldStyle,
              decoration: _decoration('Negative prompt: blurry, low quality'),
            ),
            const SizedBox(height: 8),
          ],
          _LabeledSlider(
            label: 'Prompt strength',
            valueLabel: _guidance.toStringAsFixed(1),
            value: _guidance,
            min: 1,
            max: 20,
            onChanged: (v) => setState(() => _guidance = (v * 2).round() / 2),
          ),
          _LabeledSlider(
            label: 'Quality steps',
            valueLabel: '$_steps',
            value: _steps.toDouble(),
            min: 10,
            max: 60,
            onChanged: (v) => setState(() => _steps = v.round()),
          ),
          if (_isVideo)
            _LabeledSlider(
              label: 'Motion strength',
              valueLabel: '${(_motion * 100).round()}%',
              value: _motion,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _motion = v),
            ),
          if (_model.supportsSeed)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _seedCtl,
                    keyboardType: TextInputType.number,
                    style: _fieldStyle,
                    decoration: _decoration('Seed (random)'),
                  ),
                ),
                const SizedBox(width: 8),
                _IconBtn(
                  icon: PhosphorIconsRegular.diceFive,
                  onTap: () => setState(() => _seedCtl.text =
                      (DateTime.now().microsecondsSinceEpoch % 4294967296).toString()),
                ),
              ],
            ),
        ],
      );

  Widget _generateBar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: EditorTokens.text,
                foregroundColor: EditorTokens.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const TextShimmerWave(
                      'Generating…',
                      style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Ubuntu'),
                      baseColor: Colors.black45,
                      waveColor: Colors.black,
                    )
                  : const PhosphorIcon(PhosphorIconsRegular.sparkle, size: 18),
              label: _busy
                  ? const SizedBox.shrink()
                  : Text(
                      'Generate · $_credits credits',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Ubuntu'),
                    ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboard),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            decoration: BoxDecoration(
              color: EditorTokens.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 640;
                final body = wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [_promptField(), const SizedBox(height: 4), _pills()],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                _modelRow(),
                                const SizedBox(height: 10),
                                _advanced(),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _promptField(),
                          const SizedBox(height: 4),
                          _modelRow(),
                          const SizedBox(height: 10),
                          _pills(),
                          const SizedBox(height: 10),
                          _advanced(),
                        ],
                      );

                return ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  children: [_header(), const SizedBox(height: 12), body],
                );
              },
            ),
          ),
          _generateBar(),
        ],
      ),
    );
  }
}

// ───────────────────────── Model picker ─────────────────────────

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.selectedId});
  final List<AiModelOption> models;
  final String selectedId;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  final _search = TextEditingController();
  String? _provider;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = widget.models.map((m) => m.provider).toSet().toList()..sort();
    final q = _search.text.trim().toLowerCase();
    final filtered = widget.models.where((m) {
      final okProvider = _provider == null || m.provider == _provider;
      final okQuery = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.provider.toLowerCase().contains(q) ||
          m.description.toLowerCase().contains(q);
      return okProvider && okQuery;
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: EditorTokens.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                style: _fieldStyle,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Search models').copyWith(
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: PhosphorIcon(
                      PhosphorIconsRegular.magnifyingGlass,
                      size: 16,
                      color: EditorTokens.muted,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _Chip(
                    label: 'All',
                    selected: _provider == null,
                    onTap: () => setState(() => _provider = null),
                  ),
                  for (final p in providers) ...[
                    const SizedBox(width: 8),
                    _Chip(
                      label: p,
                      selected: _provider == p,
                      onTap: () => setState(() => _provider = p),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No models match your search',
                        style: TextStyle(
                          color: EditorTokens.muted,
                          fontSize: 12,
                          fontFamily: 'Ubuntu',
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final m = filtered[i];
                        return _ModelTile(
                          model: m,
                          selected: m.id == widget.selectedId,
                          onTap: () => Navigator.of(context).pop(m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.selected, required this.onTap});
  final AiModelOption model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: EditorTokens.elevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? EditorTokens.text : EditorTokens.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(model.provider),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        model.name,
                        style: const TextStyle(
                          color: EditorTokens.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Ubuntu',
                        ),
                      ),
                      if (model.badge != null) _Badge(model.badge!),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${model.provider} · ${model.description}',
                    style: const TextStyle(
                      color: EditorTokens.muted,
                      fontSize: 11,
                      fontFamily: 'Ubuntu',
                    ),
                  ),
                  if (model.capabilities.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final c in model.capabilities) _Tag(_capabilityLabels[c]!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${model.creditsPerUnit}/${model.type == AiMediaType.video ? 's' : 'img'}',
                  style: const TextStyle(
                    color: EditorTokens.muted,
                    fontSize: 11,
                    fontFamily: 'Ubuntu',
                  ),
                ),
                if (selected) ...[
                  const SizedBox(height: 6),
                  const PhosphorIcon(
                    PhosphorIconsRegular.check,
                    size: 16,
                    color: EditorTokens.text,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.onTap});
  final AiModelOption model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: EditorTokens.elevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EditorTokens.border),
        ),
        child: Row(
          children: [
            _Avatar(model.provider, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: EditorTokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Ubuntu',
                    ),
                  ),
                  Text(
                    model.provider,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: EditorTokens.muted,
                      fontSize: 11,
                      fontFamily: 'Ubuntu',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Change',
              style: TextStyle(
                color: EditorTokens.muted,
                fontSize: 11,
                fontFamily: 'Ubuntu',
              ),
            ),
            const SizedBox(width: 4),
            const PhosphorIcon(
              PhosphorIconsRegular.caretRight,
              size: 14,
              color: EditorTokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Small components ─────────────────────────

const _fieldStyle = TextStyle(
  color: EditorTokens.text,
  fontSize: 13,
  fontFamily: 'Ubuntu',
);

InputDecoration _decoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: EditorTokens.muted, fontSize: 13, fontFamily: 'Ubuntu'),
      filled: true,
      fillColor: EditorTokens.elevated,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: EditorTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: EditorTokens.text),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );

class _Avatar extends StatelessWidget {
  const _Avatar(this.provider, {this.size = 36});
  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EditorTokens.bg,
          border: Border.all(color: EditorTokens.border),
        ),
        alignment: Alignment.center,
        child: Text(
          provider.isEmpty ? '?' : provider[0].toUpperCase(),
          style: TextStyle(
            color: EditorTokens.text,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            fontFamily: 'Ubuntu',
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: EditorTokens.text,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: EditorTokens.bg,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'Ubuntu',
          ),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: EditorTokens.border),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: EditorTokens.muted,
            fontSize: 10,
            fontFamily: 'Ubuntu',
          ),
        ),
      );
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});
  final AiMediaType type;
  final ValueChanged<AiMediaType> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(AiMediaType t, String label, PhosphorIconData icon) {
      final on = t == type;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            decoration: BoxDecoration(
              color: on ? EditorTokens.text : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(icon, size: 16, color: on ? EditorTokens.bg : EditorTokens.text),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: on ? EditorTokens.bg : EditorTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Ubuntu',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EditorTokens.border),
      ),
      child: Row(
        children: [
          seg(AiMediaType.video, 'Video', PhosphorIconsRegular.videoCamera),
          seg(AiMediaType.image, 'Image', PhosphorIconsRegular.image),
        ],
      ),
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({required this.icon, required this.label});
  final PhosphorIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: EditorTokens.elevated,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: EditorTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 14, color: EditorTokens.text),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: EditorTokens.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Ubuntu',
              ),
            ),
            const SizedBox(width: 4),
            const PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 11,
              color: EditorTokens.muted,
            ),
          ],
        ),
      );
}

class _Pill<T> extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.items,
    required this.labelOf,
    required this.onSelected,
  });
  final PhosphorIconData icon;
  final String label;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: '',
        color: EditorTokens.elevated,
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final i in items)
            PopupMenuItem<T>(
              value: i,
              height: 40,
              child: Text(
                labelOf(i),
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 13,
                  fontFamily: 'Ubuntu',
                ),
              ),
            ),
        ],
        child: _PillBody(icon: icon, label: label),
      );
}

class _RefPill extends StatelessWidget {
  const _RefPill({
    required this.path,
    required this.label,
    required this.onPick,
    required this.onClear,
  });
  final String? path;
  final String label;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final has = path != null;
    return GestureDetector(
      onTap: has ? onClear : onPick,
      child: Container(
        height: 34,
        padding: const EdgeInsets.fromLTRB(5, 0, 10, 0),
        decoration: BoxDecoration(
          color: EditorTokens.elevated,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: has ? EditorTokens.text : EditorTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 24,
                height: 24,
                child: has
                    ? Image.file(File(path!), fit: BoxFit.cover)
                    : const ColoredBox(
                        color: EditorTokens.bg,
                        child: Center(
                          child: PhosphorIcon(
                            PhosphorIconsRegular.plus,
                            size: 12,
                            color: EditorTokens.text,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: EditorTokens.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Ubuntu',
              ),
            ),
            if (has) ...[
              const SizedBox(width: 6),
              const PhosphorIcon(PhosphorIconsRegular.x, size: 12, color: EditorTokens.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? EditorTokens.text : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? EditorTokens.text : EditorTokens.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? EditorTokens.bg : EditorTokens.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Ubuntu',
            ),
          ),
        ),
      );
}

class _Advanced extends StatelessWidget {
  const _Advanced({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: EditorTokens.elevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EditorTokens.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            iconColor: EditorTokens.text,
            collapsedIconColor: EditorTokens.text,
            leading: const PhosphorIcon(
              PhosphorIconsRegular.slidersHorizontal,
              size: 16,
              color: EditorTokens.text,
            ),
            title: const Text(
              'Advanced',
              style: TextStyle(
                color: EditorTokens.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Ubuntu',
              ),
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: EditorTokens.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Ubuntu',
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: EditorTokens.muted,
                  fontSize: 12,
                  fontFamily: 'Ubuntu',
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: EditorTokens.text,
              inactiveTrackColor: EditorTokens.border,
              thumbColor: EditorTokens.text,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final PhosphorIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: EditorTokens.border),
          ),
          child: Center(child: PhosphorIcon(icon, size: 18, color: EditorTokens.text)),
        ),
      );
}