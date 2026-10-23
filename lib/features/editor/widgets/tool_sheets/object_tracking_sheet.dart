import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/object_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/object_tracking_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

class _FxDef {
  const _FxDef(this.label, this.icon, this.type);
  final String label;
  final PhosphorIconData icon;
  final ObjectEffectType type;
}

class ObjectTrackingSheet extends StatefulWidget {
  const ObjectTrackingSheet({super.key});

  @override
  State<ObjectTrackingSheet> createState() => _ObjectTrackingSheetState();
}

class _ObjectTrackingSheetState extends State<ObjectTrackingSheet>
    with SingleTickerProviderStateMixin {
  bool _isAnalyzing = false;
  double _progress = 0.0;
  String _statusText = '';

  String? _selectedObjectId;
  bool _mergeMode = false;
  final Set<String> _selectedForMerge = {};

  int _textRevision = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const List<String> _stickerOptions = [
    '🎯', '⚡', '🔥', '✨', '🚗', '🐱', '📱', '☕',
  ];

  static const List<String> _textPresets = ['Target', 'Object', 'Tracked', 'Focus'];

  static const List<Color> _palette = [
    Color(0xFF00E5FF),
    Color(0xFFFF2A6D),
    Color(0xFFFFC300),
    Color(0xFF05FFA1),
    Color(0xFFB537F2),
    Color(0xFFFF7034),
  ];

  static final List<_FxDef> _fxDefs = [
    const _FxDef('None', PhosphorIconsRegular.prohibit, ObjectEffectType.none),
    const _FxDef('Highlight', PhosphorIconsRegular.boundingBox, ObjectEffectType.boxHighlight),
    const _FxDef('Blur', PhosphorIconsRegular.dropHalf, ObjectEffectType.blur),
    const _FxDef('Mosaic', PhosphorIconsRegular.gridFour, ObjectEffectType.mosaic),
    const _FxDef('Text', PhosphorIconsRegular.textAa, ObjectEffectType.text),
    const _FxDef('Sticker', PhosphorIconsRegular.smiley, ObjectEffectType.sticker),
  ];

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _startTracking(EditorController editor) async {
    _pulse.repeat(reverse: true);
    setState(() {
      _isAnalyzing = true;
      _progress = 0.0;
      _statusText = 'Initializing object tracking...';
      _mergeMode = false;
      _selectedForMerge.clear();
    });

    try {
      final ObjectTrackingData? result =
          await editor.runObjectTrackingOnSelectedClip(
        stepDelays: false,
        onProgress: (p, status) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusText = status;
            });
          }
        },
      );

      if (mounted && result != null && result.objects.isNotEmpty) {
        setState(() => _selectedObjectId = result.objects.first.id);
      }
    } finally {
      _pulse.stop();
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  ObjectEffect _defaultEffect(ObjectEffectType type, TrackedObject obj) {
    switch (type) {
      case ObjectEffectType.none:
        return const ObjectEffect(type: ObjectEffectType.none);
      case ObjectEffectType.boxHighlight:
        return const ObjectEffect(type: ObjectEffectType.boxHighlight);
      case ObjectEffectType.blur:
        return const ObjectEffect(type: ObjectEffectType.blur, intensity: 10.0);
      case ObjectEffectType.mosaic:
        return const ObjectEffect(type: ObjectEffectType.mosaic, intensity: 16.0);
      case ObjectEffectType.text:
        return ObjectEffect(type: ObjectEffectType.text, text: obj.label);
      case ObjectEffectType.sticker:
        return const ObjectEffect(type: ObjectEffectType.sticker, stickerAsset: '🎯');
    }
  }

  void _applyToAll(EditorController editor, List<TrackedObject> objects, ObjectEffect fx) {
    for (final o in objects) {
      final ObjectEffect next = fx.type == ObjectEffectType.text
          ? fx.copyWith(text: o.label)
          : fx;
      editor.updateObjectEffect(o.id, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final TimelineClip? clip = editor.selectedClip;

    if (clip == null) return _buildNoClip();
    if (_isAnalyzing) return _buildScanning();

    final ObjectTrackingData tracking = clip.objectTrackingData;
    if (!tracking.isProcessed || tracking.objects.isEmpty) {
      return _buildIntro(editor);
    }

    return _buildEditor(editor, tracking);
  }

  Widget _buildNoClip() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: cardToken,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: PhosphorIcon(PhosphorIconsRegular.crosshair,
                    size: 30, color: mutedToken),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No clip selected',
              style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap a video or image clip on the timeline to use object tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedToken, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro(EditorController editor) {
    Widget feature(PhosphorIconData icon, String title, String sub) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cardToken,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: PhosphorIcon(icon, size: 18, color: accentToken)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(sub,
                      style: const TextStyle(color: mutedToken, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentToken.withValues(alpha: 0.35),
                  accentToken.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(color: accentToken.withValues(alpha: 0.5)),
            ),
            child: const Center(
              child: PhosphorIcon(PhosphorIconsRegular.crosshair,
                  size: 40, color: accentToken),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Multi-Object Detection & Tracking',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Track vehicles, pets, gadgets, and items automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedToken, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          feature(PhosphorIconsRegular.scan, 'Multi-category detection',
              'Identifies vehicles, pets, persons, gadgets and items'),
          feature(PhosphorIconsRegular.path, 'SORT Trajectory',
              'Maintains continuous spatial motion tracking'),
          feature(PhosphorIconsRegular.boundingBox, 'Interactive overlay',
              'Apply bounding highlight, blur, mosaic or stickers'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentToken,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: () {
                tapFeedback();
                _startTracking(editor);
              },
              icon: const PhosphorIcon(PhosphorIconsBold.scan, size: 18),
              label: const Text('Scan & Track Objects',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    final stages = <String>['Sampling frames', 'Detecting objects', 'Tracking trajectories'];
    int active = 0;
    if (_progress >= 0.75) {
      active = 2;
    } else if (_progress >= 0.33) {
      active = 1;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 128,
              height: 128,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentToken.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: _progress.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: cardToken,
                      color: accentToken,
                    ),
                  ),
                  Text(
                    '${(_progress * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(stages.length, (i) {
                final bool done = i < active;
                final bool now = i == active;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: now
                        ? accentToken.withValues(alpha: 0.18)
                        : cardToken,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: now ? accentToken : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (done)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.check_rounded,
                              size: 12, color: accentToken),
                        ),
                      Text(
                        stages[i],
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: (done || now) ? Colors.white : mutedToken,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(EditorController editor, ObjectTrackingData tracking) {
    final List<TrackedObject> objects = tracking.objects;

    if (_selectedObjectId == null ||
        !objects.any((o) => o.id == _selectedObjectId)) {
      _selectedObjectId = objects.first.id;
    }
    _selectedForMerge.removeWhere((id) => !objects.any((o) => o.id == id));

    final int activeIndex = objects.indexWhere((o) => o.id == _selectedObjectId);
    final TrackedObject activeObject = objects[activeIndex];
    final Color activeColor = _palette[activeIndex % _palette.length];
    final ObjectEffect currentFx = activeObject.effects.isNotEmpty
        ? activeObject.effects.first
        : const ObjectEffect();

    return Column(
      children: [
        _buildHeader(editor, objects.length),
        _buildObjectStrip(objects),
        const Divider(height: 1, color: dividerToken),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            children: [
              _buildObjectInfo(editor, activeObject, activeColor),
              const SizedBox(height: 14),
              _buildEffectRow(editor, activeObject, currentFx),
              const SizedBox(height: 14),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey('${activeObject.id}_${currentFx.type}'),
                    child: _buildParams(editor, activeObject, currentFx),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBottomBar(editor, objects, currentFx),
      ],
    );
  }

  Widget _buildHeader(EditorController editor, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Text(
            '$count Objects Tracked',
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (_mergeMode) ...[
            TextButton(
              onPressed: () {
                tapFeedback();
                setState(() {
                  _mergeMode = false;
                  _selectedForMerge.clear();
                });
              },
              style: TextButton.styleFrom(foregroundColor: mutedToken),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentToken,
                foregroundColor: Colors.black,
                disabledBackgroundColor: cardToken,
                disabledForegroundColor: mutedToken,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: _selectedForMerge.length >= 2
                  ? () {
                      tapFeedback();
                      editor.mergeSelectedObjects(_selectedForMerge.toList());
                      setState(() {
                        _selectedForMerge.clear();
                        _mergeMode = false;
                      });
                    }
                  : null,
              icon: const PhosphorIcon(PhosphorIconsRegular.gitMerge, size: 16),
              label: Text('Merge (${_selectedForMerge.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
          ] else ...[
            if (count > 1)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () {
                  tapFeedback();
                  setState(() => _mergeMode = true);
                },
                icon: const PhosphorIcon(PhosphorIconsRegular.gitMerge, size: 16),
                label: const Text('Merge', style: TextStyle(fontSize: 12)),
              ),
            IconButton(
              tooltip: 'Re-scan',
              icon: const PhosphorIcon(PhosphorIconsRegular.arrowsClockwise,
                  color: mutedToken, size: 20),
              onPressed: () {
                tapFeedback();
                _startTracking(editor);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildObjectStrip(List<TrackedObject> objects) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: objects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, idx) {
          final TrackedObject o = objects[idx];
          final Color color = _palette[idx % _palette.length];
          final bool isSelected = o.id == _selectedObjectId;
          final bool isMerge = _selectedForMerge.contains(o.id);
          final bool hasFx =
              o.effects.isNotEmpty && o.effects.first.type != ObjectEffectType.none;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapFeedback();
              setState(() {
                if (_mergeMode) {
                  isMerge
                      ? _selectedForMerge.remove(o.id)
                      : _selectedForMerge.add(o.id);
                } else {
                  _selectedObjectId = o.id;
                }
              });
            },
            onLongPress: () {
              tapFeedback();
              setState(() {
                _mergeMode = true;
                _selectedForMerge.add(o.id);
              });
            },
            child: SizedBox(
              width: 60,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 54,
                        height: 54,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isMerge
                                ? Colors.amber
                                : (isSelected && !_mergeMode
                                    ? color
                                    : Colors.transparent),
                            width: 2.5,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color.withValues(alpha: 0.45),
                                color.withValues(alpha: 0.12),
                              ],
                            ),
                          ),
                          child: Center(
                            child: PhosphorIcon(_categoryIcon(o.category),
                                size: 22, color: Colors.white),
                          ),
                        ),
                      ),
                      if (isMerge)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: _badge(Colors.amber, Icons.check_rounded),
                        )
                      else if (hasFx)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: _badge(color, Icons.auto_awesome),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected && !_mergeMode
                          ? Colors.white
                          : mutedToken,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  PhosphorIconData _categoryIcon(String cat) {
    switch (cat) {
      case 'vehicle':
        return PhosphorIconsRegular.car;
      case 'pet':
        return PhosphorIconsRegular.cat;
      case 'phone':
        return PhosphorIconsRegular.deviceMobile;
      case 'cup':
        return PhosphorIconsRegular.coffee;
      case 'person':
        return PhosphorIconsRegular.user;
      default:
        return PhosphorIconsRegular.cube;
    }
  }

  Widget _badge(Color color, IconData icon) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: surfaceToken, width: 2),
      ),
      child: Icon(icon, size: 10, color: Colors.black),
    );
  }

  Widget _buildObjectInfo(
      EditorController editor, TrackedObject object, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${object.label} Effect',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '${object.tracks.length} ${object.tracks.length == 1 ? 'track' : 'tracks'}',
          style: const TextStyle(color: mutedToken, fontSize: 11.5),
        ),
        if (object.tracks.length > 1) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              tapFeedback();
              editor.splitObjectTrack(object.id, object.tracks.last.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cardToken,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                children: [
                  PhosphorIcon(PhosphorIconsRegular.arrowsSplit,
                      size: 13, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Split',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEffectRow(
      EditorController editor, TrackedObject object, ObjectEffect currentFx) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: _fxDefs.map((fx) {
          final bool selected = currentFx.type == fx.type;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                tapFeedback();
                if (selected) return;
                editor.updateObjectEffect(
                    object.id, _defaultEffect(fx.type, object));
                setState(() => _textRevision++);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected
                          ? accentToken.withValues(alpha: 0.16)
                          : cardToken,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? accentToken : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: PhosphorIcon(
                        fx.icon,
                        size: 20,
                        color: selected ? accentToken : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fx.label,
                    style: TextStyle(
                      color: selected ? accentToken : mutedToken,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardToken.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _buildParams(
      EditorController editor, TrackedObject object, ObjectEffect fx) {
    switch (fx.type) {
      case ObjectEffectType.none:
        return _panel(
          child: const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: mutedToken),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pick an effect above to apply to this tracked object.',
                  style: TextStyle(color: mutedToken, fontSize: 12),
                ),
              ),
            ],
          ),
        );

      case ObjectEffectType.boxHighlight:
        return _panel(
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 16, color: accentToken),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Highlight box overlay enabled for object tracking.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        );

      case ObjectEffectType.blur:
      case ObjectEffectType.mosaic:
        final bool isBlur = fx.type == ObjectEffectType.blur;
        final double base = isBlur ? 10.0 : 16.0;
        final double value = fx.intensity.clamp(2.0, 50.0);
        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    isBlur ? 'Blur radius' : 'Tile size',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: surfaceToken,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      value.round().toString(),
                      style: const TextStyle(
                          color: accentToken,
                          fontSize: 12,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      tapFeedback();
                      editor.updateObjectEffect(
                          object.id, fx.copyWith(intensity: base));
                    },
                    child: const Icon(Icons.restart_alt_rounded,
                        size: 18, color: mutedToken),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: accentToken,
                  inactiveTrackColor: surfaceToken,
                  thumbColor: Colors.white,
                  overlayColor: accentToken.withValues(alpha: 0.15),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 9),
                ),
                child: Slider(
                  value: value,
                  min: 2.0,
                  max: 50.0,
                  onChanged: (val) => editor.updateObjectEffect(
                      object.id, fx.copyWith(intensity: val)),
                ),
              ),
            ],
          ),
        );

      case ObjectEffectType.text:
        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Label',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _ObjectLabelField(
                key: ValueKey('${object.id}_$_textRevision'),
                initialText: fx.text,
                onChanged: (val) => editor.updateObjectEffect(
                    object.id, fx.copyWith(text: val)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [object.label, ..._textPresets].map((t) {
                  return GestureDetector(
                    onTap: () {
                      tapFeedback();
                      editor.updateObjectEffect(
                          object.id, fx.copyWith(text: t));
                      setState(() => _textRevision++);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: fx.text == t
                            ? accentToken.withValues(alpha: 0.18)
                            : surfaceToken,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: fx.text == t
                              ? accentToken
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          color: fx.text == t ? accentToken : Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );

      case ObjectEffectType.sticker:
        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sticker',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _stickerOptions.map((st) {
                  final bool selected = fx.stickerAsset == st;
                  return GestureDetector(
                    onTap: () {
                      tapFeedback();
                      editor.updateObjectEffect(
                          object.id, fx.copyWith(stickerAsset: st));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected
                            ? accentToken.withValues(alpha: 0.18)
                            : surfaceToken,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? accentToken : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(st, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildBottomBar(
      EditorController editor, List<TrackedObject> objects, ObjectEffect fx) {
    final bool canApplyAll = objects.length > 1 && fx.type != ObjectEffectType.none;

    return Container(
      decoration: const BoxDecoration(
        color: surfaceToken,
        border: Border(top: BorderSide(color: dividerToken)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: mutedToken,
                      side: const BorderSide(color: dividerToken),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: canApplyAll
                        ? () {
                            tapFeedback();
                            _applyToAll(editor, objects, fx);
                          }
                        : null,
                    icon: const PhosphorIcon(PhosphorIconsRegular.cube, size: 16),
                    label: const Text('Apply to all objects',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObjectLabelField extends StatefulWidget {
  const _ObjectLabelField({super.key, required this.initialText, required this.onChanged});

  final String initialText;
  final ValueChanged<String> onChanged;

  @override
  State<_ObjectLabelField> createState() => _ObjectLabelFieldState();
}

class _ObjectLabelFieldState extends State<_ObjectLabelField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      maxLength: 24,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      cursorColor: accentToken,
      decoration: InputDecoration(
        counterText: '',
        hintText: 'Type object label…',
        hintStyle: const TextStyle(color: mutedToken, fontSize: 13),
        filled: true,
        fillColor: surfaceToken,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentToken, width: 1.5),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
